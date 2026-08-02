import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'package:archive/archive_io.dart';

class MavenArtifact {
  final String name;
  final String url;
  final String path;
  final String? sha1;

  MavenArtifact({required this.name, required this.url, required this.path, this.sha1});
}

class DownloadItem {
  final String id;
  final String url;
  final String savePath;
  final String? sha1;

  DownloadItem({required this.id, required this.url, required this.savePath, this.sha1});
}

class DownloadTask extends ChangeNotifier {
  final String id;
  double progress = 0.0;
  String status = "准备中...";
  bool isDownloading = false;

  DownloadTask(this.id);

  void update(double p, String s) {
    progress = p;
    status = s;
    notifyListeners();
  }
}

class DownloadService extends ChangeNotifier {
  static final DownloadService instance = DownloadService._();
  DownloadService._();

  final Map<String, DownloadTask> _tasks = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final Dio _dio = Dio(BaseOptions(
    headers: {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
      "Referer": "https://gitcode.com/",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    },
  ));

  List<DownloadTask> getTasks() => _tasks.values.toList();

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
      task.update(0.0, "已取消");
      task.isDownloading = false;
    }
  }

  Future<bool> downloadLibrary(String id, MavenArtifact artifact, Directory librariesDir) async {
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
      await _dio.download(artifact.url, savePath, onReceiveProgress: (count, total) {
        if (total != -1) task.update(count / total, "下载库: ${(count / total * 100).toInt()}%");
      });
      return true;
    } catch (e) {
      debugPrint("下载库失败 $id: $e");
      return false;
    } finally {
      task.isDownloading = false;
    }
  }

  Future<void> downloadBatch(List<DownloadItem> items, Directory baseDir) async {
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

  Future<bool> extractNative(File archive, Directory nativesDir, List<String> excludes) async {
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
        if (!p.isWithin(destination.path, targetPath) && p.normalize(targetPath) != destination.path) {
          throw Exception("检测到路径穿越: $filename");
        }

        if (file.isFile) {
          final outFile = File(targetPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(targetPath).create(recursive: true);
        }
      }
      debugPrint("Native 已成功解压到: ${nativesDir.path}");
      return true;
    } catch (e) {
      debugPrint("解压 native 失败: $e");
      return false;
    }
  }

  Future<String?> getJavaPath() async {
    final candidates = ['java'];
    for (final java in candidates) {
      try {
        final result = await Process.run(java, ['-version']);
        if (result.exitCode == 0) {
          debugPrint("找到 Java: $java");
          return java;
        }
      } catch (e) {
        continue;
      }
    }
    return null;
  }

  String getMavenArtifactPath(String name, {String? classifier, String extension = "jar"}) {
    final parts = name.split(":");
    final group = parts[0].replaceAll(".", "/");
    final artifact = parts[1];
    final version = parts[2];
    final filename = "$artifact-$version${classifier != null ? '-$classifier' : ''}.$extension";
    return "$group/$artifact/$version/$filename";
  }

  Map<String, dynamic> mergeVersionData(Map<String, dynamic> base, Map<String, dynamic> loader, String targetId) {
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

  Future<void> downloadFile(
    String id, 
    String url, 
    String fileName, 
    Future<bool> Function(String path, Function(String) updateStatus) onComplete
  ) async {
    final task = getTask(id);
    if (task.isDownloading) return;
    
    final cancelToken = CancelToken();
    _cancelTokens[id] = cancelToken;
    
    task.isDownloading = true;
    task.update(0.0, "正在下载...");

    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = p.join(tempDir.path, fileName);

      await _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (count, total) {
          if (total != -1) {
            task.update(count / total, "下载中: ${(count / total * 100).toInt()}%");
          }
        },
      );
      
      final success = await onComplete(savePath, (newStatus) {
        task.update(1.0, newStatus);
      });
      
      task.update(1.0, success ? "安装完成" : "安装失败");
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        task.update(0.0, "已取消");
      } else {
        task.update(0.0, "下载失败: $e");
      }
    } finally {
      _cancelTokens.remove(id);
      task.isDownloading = false;
    }
  }

  Future<bool> installMinecraftVersion(String versionId, String targetDir) async {
    debugPrint("正在安装 Minecraft $versionId 到 $targetDir");
    try {
      debugPrint("安装流程初始化完成...");
      return true;
    } catch (e) {
      debugPrint("安装失败: $e");
      return false;
    }
  }
}
