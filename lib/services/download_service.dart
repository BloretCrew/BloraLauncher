import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/i18n.dart';
import '../core/java_config.dart';
import 'config_service.dart';
import 'launch_service.dart';

class MavenArtifact {
  final String name;
  final String url;
  final String path;
  final String? sha1;

  MavenArtifact({
    required this.name,
    required this.url,
    required this.path,
    this.sha1,
  });
}

enum LoaderType { vanilla, fabric, forge, neoforge, quilt }

// {"id": "26.3-snapshot-6",
// "type": "snapshot",
// "url": "https://piston-meta.mojang.com/v1/packages/0d633dfe790a7638af3f1682a93e374890a56e96/26.3-snapshot-6.json",
// "time": "2026-08-04T11:33:25+00:00",
// "releaseTime": "2026-07-28T12:25:51+00:00",
// "sha1": "0d633dfe790a7638af3f1682a93e374890a56e96",
// "complianceLevel": 1}
class MinecraftVersion {
  final String id;
  final String type;
  final String url;
  final String sha1;
  final int complianceLevel;
  final DateTime time;
  final DateTime releaseTime;

  MinecraftVersion({
    required this.id,
    required this.type,
    required this.url,
    required this.time,
    required this.releaseTime,
    required this.sha1,
    required this.complianceLevel,
  });

  factory MinecraftVersion.fromJson(Map<String, dynamic> json) {
    return MinecraftVersion(
      id: json['id'],
      type: json['type'],
      url: json['url'],
      time: DateTime.parse(json['time']),
      releaseTime: DateTime.parse(json['releaseTime']),
      sha1: json['sha1'],
      complianceLevel: (json['complianceLevel'] as num?)?.toInt() ?? -1,
    );
  }
}

class DownloadItem {
  final String id;
  final String url;
  final String savePath;
  final String? sha1;

  DownloadItem({
    required this.id,
    required this.url,
    required this.savePath,
    this.sha1,
  });
}

class DownloadTask extends ChangeNotifier {
  final String id;
  double progress = 0.0;
  String status = "Ready...";
  bool isDownloading = false;
  int receivedBytes = 0;
  int totalBytes = 0;
  double speed = 0.0; // bytes per second
  DateTime lastUpdate = DateTime.now();
  int lastReceived = 0;

  DownloadTask(this.id);

  void update(double p, String s, {int? received, int? total}) {
    progress = p;
    status = s;
    if (received != null) {
      final now = DateTime.now();
      final duration = now.difference(lastUpdate).inMilliseconds;
      if (duration > 500) {
        // Update speed every 0.5s
        speed = (received - lastReceived) / (duration / 1000.0);
        lastUpdate = now;
        lastReceived = received;
      }
      receivedBytes = received;
    }
    if (total != null) totalBytes = total;
    notifyListeners();
  }
}

class DownloadService extends ChangeNotifier {
  static final DownloadService instance = DownloadService._();
  DownloadService._();

  final Map<String, DownloadTask> _tasks = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final Dio _dio = Dio(
    BaseOptions(
      headers: {
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        "Referer": "https://gitcode.com/",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
      },
    ),
  );

  List<DownloadTask> getTasks() => _tasks.values.toList();
  List<DownloadTask> get activeTasks =>
      _tasks.values.where((t) => t.isDownloading).toList();
  int get remainingTasks => _tasks.values
      .where((t) => t.progress < 1.0 && !t.status.contains("已取消"))
      .length;

  double get totalProgress {
    final active = activeTasks;
    if (active.isEmpty) return 0.0;
    return active.fold(0.0, (sum, t) => sum + t.progress) / active.length;
  }

  double get totalSpeed {
    return activeTasks.fold(0.0, (sum, t) => sum + t.speed);
  }

  String formatSpeed(double speed) {
    if (speed < 1024) return "${speed.toStringAsFixed(1)} B/s";
    if (speed < 1024 * 1024) return "${(speed / 1024).toStringAsFixed(1)} KB/s";
    return "${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s";
  }

  DownloadTask getTask(String id) {
    return _tasks.putIfAbsent(id, () {
      final task = DownloadTask(id);
      task.addListener(notifyListeners);
      return task;
    });
  }

  void cancelTask(String id) {
    _cancelTokens[id]?.cancel("User cancelled");
    _cancelTokens.remove(id);
    final task = _tasks[id];
    if (task != null) {
      task.update(0.0, "Canceled");
      task.isDownloading = false;
    }
  }

  Future<bool> downloadLibrary(
    String id,
    MavenArtifact artifact,
    Directory librariesDir,
  ) async {
    final savePath = p.join(librariesDir.path, artifact.path);
    final file = File(savePath);

    if (await file.exists()) {
      if (artifact.sha1 == null) return true;
      final bytes = await file.readAsBytes();
      final hash = sha1.convert(bytes).toString();
      if (hash == artifact.sha1) return true;
    }

    await file.parent.create(recursive: true);
    final task = getTask(id);
    task.isDownloading = true;

    try {
      await _dio.download(
        artifact.url,
        savePath,
        onReceiveProgress: (count, total) {
          if (total != -1) {
            task.update(
              count / total,
              "Transferring...".tl,
              received: count,
              total: total,
            );
          }
        },
      );
      return true;
    } catch (e) {
      debugPrint("Download Lib Failed $id: $e");
      return false;
    } finally {
      task.isDownloading = false;
    }
  }

  Future<void> downloadBatch(
    List<DownloadItem> items,
    Directory baseDir,
  ) async {
    final queue = List.from(items);
    final List<Future<void>> futures = [];
    for (int i = 0; i < 6 && queue.isNotEmpty; i++) {
      futures.add(_processQueue(queue, baseDir));
    }
    await Future.wait(futures);
  }

  Future<void> _processQueue(List queue, Directory baseDir) async {
    while (queue.isNotEmpty) {
      final item = queue.removeAt(0);
      final artifact = MavenArtifact(
        name: item.id,
        url: item.url,
        path: item.savePath,
        sha1: item.sha1,
      );
      await downloadLibrary(item.id, artifact, baseDir);
    }
  }

  Future<bool> extractNative(
    File archive,
    Directory nativesDir,
    List<String> excludes,
  ) async {
    try {
      final destination = nativesDir.absolute;
      await destination.create(recursive: true);

      final bytes = await archive.readAsBytes();
      final zipDecoder = ZipDecoder();
      final archiveFile = zipDecoder.decodeBytes(bytes);

      for (final file in archiveFile) {
        final filename = file.name.replaceAll('\\', '/');
        if (excludes.any((ex) => filename.startsWith(ex))) continue;

        final targetPath = p.join(destination.path, filename);
        if (!p.isWithin(destination.path, targetPath) &&
            p.normalize(targetPath) != destination.path) {
          throw Exception("File path traversal protection failed: $filename");
        }

        if (file.isFile) {
          final outFile = File(targetPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(targetPath).create(recursive: true);
        }
      }
      debugPrint("Native decompression succeeded: ${nativesDir.path}");
      return true;
    } catch (e) {
      debugPrint("Decompression failed: $e");
      return false;
    }
  }

  Future<bool> extractZip(
    File archive,
    Directory destination, {
    bool stripRoot = false,
  }) async {
    try {
      if (!await destination.exists()) {
        await destination.create(recursive: true);
      }

      final bytes = await archive.readAsBytes();
      final zipDecoder = ZipDecoder();
      final archiveFile = zipDecoder.decodeBytes(bytes);

      String? rootFolder;
      if (stripRoot && archiveFile.isNotEmpty) {
        final firstPath = archiveFile.first.name.replaceAll('\\', '/');
        final segments = firstPath.split('/');
        if (segments.length > 1 ||
            (segments.length == 1 && !archiveFile.first.isFile)) {
          final potentialRoot = segments[0];
          bool allMatch = true;
          for (final file in archiveFile) {
            final name = file.name.replaceAll('\\', '/');
            if (name == potentialRoot) continue; // Folder entry itself
            if (!name.startsWith('$potentialRoot/')) {
              allMatch = false;
              break;
            }
          }
          if (allMatch) rootFolder = potentialRoot;
        }
      }

      for (final file in archiveFile) {
        String filename = file.name.replaceAll('\\', '/');
        if (rootFolder != null && filename.startsWith('$rootFolder/')) {
          filename = filename.substring(rootFolder.length + 1);
        } else if (rootFolder != null && filename == rootFolder) {
          continue; // Skip root folder entry
        }

        if (filename.isEmpty) continue;

        final targetPath = p.join(destination.path, filename);
        if (!p.isWithin(destination.path, targetPath) &&
            p.normalize(targetPath) != destination.path) {
          continue; // Path traversal protection
        }

        if (file.isFile) {
          final outFile = File(targetPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(targetPath).create(recursive: true);
        }
      }
      return true;
    } catch (e) {
      debugPrint("Zip extraction failed: $e");
      return false;
    }
  }

  Future<String?> getJavaPath() async {
    final candidates = ['java'];
    for (final java in candidates) {
      try {
        final result = await Process.run(java, ['-version']);
        if (result.exitCode == 0) {
          debugPrint("Found Java: $java");
          return java;
        }
      } catch (e) {
        continue;
      }
    }
    return null;
  }

  String getMavenArtifactPath(
    String name, {
    String? classifier,
    String extension = "jar",
  }) {
    final parts = name.split(":");
    final group = parts[0].replaceAll(".", "/");
    final artifact = parts[1];
    final version = parts[2];
    final filename =
        "$artifact-$version${classifier != null ? '-$classifier' : ''}.$extension";
    return "$group/$artifact/$version/$filename";
  }

  Map<String, dynamic> mergeVersionData(
    Map<String, dynamic> base,
    Map<String, dynamic> loader,
    String targetId,
  ) {
    final merged = Map<String, dynamic>.from(base);
    merged.addAll(loader);
    final baseLibs = (base['libraries'] as List? ?? []);
    final loaderLibs = (loader['libraries'] as List? ?? []);
    final Set<String> seen = {};
    final List<Map<String, dynamic>> libraries = [];
    for (var lib in [...loaderLibs, ...baseLibs]) {
      final name = lib['name'] ?? "";
      if (name != "" && seen.contains(name)) continue;
      if (name != "") seen.add(name);
      libraries.add(Map<String, dynamic>.from(lib));
    }
    merged['libraries'] = libraries;
    merged['id'] = targetId;
    merged.remove('inheritsFrom');
    return merged;
  }

  bool isLibraryAllowed(Map<String, dynamic> lib) {
    final rules = lib['rules'] as List?;
    if (rules == null) return true;
    bool allowed = false;
    for (var rule in rules) {
      final action = rule['action'] ?? 'disallow';
      final os = rule['os'];
      if (os == null) {
        allowed = action == 'allow';
      } else {
        if (os['name'] == (Platform.isWindows ? 'windows' : 'osx')) {
          allowed = action == 'allow';
        }
      }
    }
    return allowed;
  }

  List<MinecraftVersion> _cachedVanillaVersions = [];
  bool _isVersionsUpdating = false;
  double _versionsUpdateProgress = 0.0;
  String _versionsUpdateStatus = "";

  List<MinecraftVersion> get cachedVanillaVersions => _cachedVanillaVersions;
  bool get isVersionsUpdating => _isVersionsUpdating;
  double get versionsUpdateProgress => _versionsUpdateProgress;
  String get versionsUpdateStatus => _versionsUpdateStatus;

  Future<void> _saveVersionsToDisk(List<dynamic> versions) async {
    try {
      final dir = await getSupportData();
      final file = File(p.join(dir.path, "mc_versions.json"));
      await file.writeAsString(jsonEncode(versions));
    } catch (e) {
      debugPrint("Failed to save versions to disk: $e");
    }
  }

  Future<List<MinecraftVersion>> _loadVersionsFromDisk() async {
    try {
      final dir = await getSupportData();
      final file = File(p.join(dir.path, "mc_versions.json"));
      if (await file.exists()) {
        final List<dynamic> data = jsonDecode(await file.readAsString());
        return data.map((v) => MinecraftVersion.fromJson(v)).toList();
      }
    } catch (e) {
      debugPrint("Failed to load versions from disk: $e");
    }
    return <MinecraftVersion>[];
  }

  Future<List<MinecraftVersion>> fetchAllVanillaVersions({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedVanillaVersions.isNotEmpty) {
      return _cachedVanillaVersions;
    }

    // Load from disk first if not in memory
    if (_cachedVanillaVersions.isEmpty) {
      _cachedVanillaVersions = await _loadVersionsFromDisk();
      if (_cachedVanillaVersions.isNotEmpty) notifyListeners();
    }

    // If we have data and not forcing refresh, return it and update in background
    if (_cachedVanillaVersions.isNotEmpty && !forceRefresh) {
      _updateVersionsInBackground();
      return _cachedVanillaVersions;
    }

    return await _performVersionsUpdate();
  }

  Future<List<MinecraftVersion>> _performVersionsUpdate({
    int retries = 3,
  }) async {
    _isVersionsUpdating = true;
    _versionsUpdateProgress = 0.0;
    _versionsUpdateStatus = "Connecting to manifest server...".tl;
    notifyListeners();

    int attempts = 0;
    while (attempts <= retries) {
      try {
        final response = await _dio.get(
          "https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json",
          onReceiveProgress: (count, total) {
            if (total != -1) {
              _versionsUpdateProgress = count / total;
              _versionsUpdateStatus = "Downloading version manifest...".tl;
              notifyListeners();
            }
          },
        );

        if (response.statusCode == 200) {
          final List<dynamic> versions = response.data is String
              ? jsonDecode(response.data)['versions']
              : response.data['versions'];

          _cachedVanillaVersions = versions
              .map((v) => MinecraftVersion.fromJson(v))
              .toList();
          await _saveVersionsToDisk(versions);

          _versionsUpdateStatus = "Manifest updated".tl;
          _versionsUpdateProgress = 1.0;
          _isVersionsUpdating = false;
          notifyListeners();
          return _cachedVanillaVersions;
        }
      } on DioException catch (e) {
        attempts++;
        if (attempts <= retries) {
          _versionsUpdateStatus = "Retry $attempts/$retries...".tl;
          notifyListeners();
          await Future.delayed(Duration(seconds: 2 * attempts));
          continue;
        }
        _versionsUpdateStatus = "Update failed: ${e.message}".tl;
      } catch (e) {
        _versionsUpdateStatus = "Update error".tl;
        break;
      }
    }

    _isVersionsUpdating = false;
    notifyListeners();
    return _cachedVanillaVersions;
  }

  void _updateVersionsInBackground() async {
    if (_isVersionsUpdating) return;
    await _performVersionsUpdate();
  }

  Future<List<Map<String, dynamic>>> fetchLoaderVersions(
    String mcVersion,
    LoaderType type,
  ) async {
    try {
      String url = "";
      switch (type) {
        case LoaderType.fabric:
          url =
              "https://bmclapi2.bangbang93.com/fabric-meta/v2/versions/loader/$mcVersion";
          break;
        case LoaderType.forge:
          url = "https://bmclapi2.bangbang93.com/forge/minecraft/$mcVersion";
          break;
        case LoaderType.neoforge:
          url = "https://bmclapi2.bangbang93.com/neoforge/list/$mcVersion";
          break;
        case LoaderType.quilt:
          url = "https://meta.quiltmc.org/v3/versions/loader/$mcVersion";
          break;
        default:
          return <Map<String, dynamic>>[];
      }

      final response = await _dio.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data is String
            ? jsonDecode(response.data)
            : response.data;

        if (type == LoaderType.fabric || type == LoaderType.quilt) {
          return data.map<Map<String, dynamic>>((e) {
            if (e is Map) {
              final loader = e['loader'] ?? e;
              return {
                'version': loader['version'].toString(),
                'stable': loader['stable'] ?? true,
                'type': (loader['stable'] ?? true) ? 'Stable' : 'Snapshot',
              };
            }
            return {'version': e.toString(), 'stable': true, 'type': 'Stable'};
          }).toList();
        } else if (type == LoaderType.forge || type == LoaderType.neoforge) {
          return data.map<Map<String, dynamic>>((e) {
            if (e is Map) {
              return {
                'version': e['version'].toString(),
                'stable': true,
                'type': 'Stable',
                'time': e['time'],
              };
            }
            return {'version': e.toString(), 'stable': true, 'type': 'Stable'};
          }).toList();
        }
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        debugPrint("Loader versions not found (404) for $mcVersion ($type)");
      } else {
        debugPrint(
          "Dio error fetching loader versions ($type) for $mcVersion: ${e.message}",
        );
      }
    } catch (e) {
      debugPrint("Failed to fetch loader versions ($type) for $mcVersion: $e");
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> installVanilla(
    String versionId,
    String url,
    Directory targetDir,
  ) async {
    final task = getTask("Install_$versionId");
    task.isDownloading = true;
    task.update(0.0, "Fetching metadata...".tl);

    try {
      final response = await _dio.get(url);
      if (response.statusCode != 200) {
        throw Exception("Failed to get version metadata");
      }

      final versionData = response.data;
      final versionPath = p.join(targetDir.path, "versions", versionId);
      final jsonFile = File(p.join(versionPath, "$versionId.json"));

      await jsonFile.parent.create(recursive: true);
      await jsonFile.writeAsString(jsonEncode(versionData));

      task.update(0.3, "Completing game files...".tl);
      await LaunchService.instance.downloadMissingFiles(
        targetDir.path,
        versionId,
        onStatus: (status, p) {
          task.update(0.3 + p * 0.6, status);
        },
      );

      task.update(1.0, "Installation Complete".tl);
    } catch (e) {
      task.update(0.0, "Installation Failed: $e".tl);
    } finally {
      task.isDownloading = false;
    }
  }

  Future<void> installLoader(
    String mcVersion,
    String loaderVersion,
    LoaderType type,
    Directory targetDir, {
    String? customVersionId,
  }) async {
    final String versionId =
        customVersionId ?? "$mcVersion-${type.name}-$loaderVersion";
    final task = getTask("Install_$versionId");
    task.isDownloading = true;
    task.update(0.0, "Preparing installation...".tl);

    try {
      final versionPath = p.join(targetDir.path, "versions", versionId);
      final jsonFile = File(p.join(versionPath, "$versionId.json"));
      await jsonFile.parent.create(recursive: true);

      Map<String, dynamic> loaderJson = {};

      if (type == LoaderType.fabric) {
        task.update(0.2, "Fetching Fabric JSON...".tl);
        final res = await _dio.get(
          "https://bmclapi2.bangbang93.com/fabric-meta/v2/versions/loader/$mcVersion/$loaderVersion/json",
        );
        loaderJson = res.data;
      } else if (type == LoaderType.forge) {
        task.update(0.2, "Fetching Forge JSON...".tl);
        final res = await _dio.get(
          "https://bmclapi2.bangbang93.com/forge/download/$mcVersion-$loaderVersion/json",
        );
        loaderJson = res.data;
      } else if (type == LoaderType.neoforge) {
        task.update(0.2, "Fetching NeoForge JSON...".tl);
        final res = await _dio.get(
          "https://bmclapi2.bangbang93.com/neoforge/version/$loaderVersion/json",
        );
        loaderJson = res.data;
      } else if (type == LoaderType.quilt) {
        task.update(0.2, "Fetching Quilt JSON...".tl);
        final res = await _dio.get(
          "https://meta.quiltmc.org/v3/versions/loader/$mcVersion/$loaderVersion/profile/json",
        );
        loaderJson = res.data;
      }

      await jsonFile.writeAsString(jsonEncode(loaderJson));

      task.update(0.5, "Completing dependencies...".tl);
      await LaunchService.instance.downloadMissingFiles(
        targetDir.path,
        versionId,
        onStatus: (status, p) {
          task.update(0.5 + p * 0.4, status);
        },
      );

      task.update(1.0, "Installation Complete");
    } catch (e) {
      task.update(0.0, "Installation Failed: $e");
      debugPrint("Install Loader Error: $e");
    } finally {
      task.isDownloading = false;
    }
  }

  Future<void> downloadFile(
    String id,
    String url,
    String fileName,
    Future<bool> Function(String path, Function(String) updateStatus)
    onComplete,
  ) async {
    final task = getTask(id);
    if (task.isDownloading) return;

    final cancelToken = CancelToken();
    _cancelTokens[id] = cancelToken;

    task.isDownloading = true;
    task.update(0.0, "Downloading...");

    try {
      final tempDir = await getApplicationCacheDirectory();
      final savePath = p.join(tempDir.path, fileName);

      await _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (count, total) {
          if (total != -1) {
            task.update(
              count / total,
              "Downloading...".tl,
              received: count,
              total: total,
            );
          }
        },
      );

      final success = await onComplete(savePath, (newStatus) {
        task.update(1.0, newStatus);
      });

      task.update(
        1.0,
        success ? "Installation Complete" : "Installation Failed",
      );
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        task.update(0.0, "Canceled");
      } else {
        task.update(0.0, "Download Failed: $e");
      }
    } finally {
      _cancelTokens.remove(id);
      task.isDownloading = false;
    }
  }

  Future<String?> findExistingJava(String version) async {
    await for (final java in JavaConfig.detectJava(includeDetails: false)) {
      if (java['version'] == version ||
          (java['version'] != null && java['version']!.startsWith(version))) {
        return java['path'];
      }
    }
    return null;
  }
}
