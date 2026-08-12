import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bloret_launcher/core/i18n.dart';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/services/download_service.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';

import '../core/java_config.dart';
import '../core/logger.dart';
import '../main.dart';

class RunningCore {
  final String id;
  final String version;
  final String loader;
  final String userName;
  final String? avatar;
  final String accountType;
  final String identityName;
  final List<String> logs = [];
  final List<double> cpuUsage = List.generate(30, (_) => 0.0);
  final List<double> memUsage = List.generate(30, (_) => 0.0);
  final Process process;
  final DateTime startTime = DateTime.now();
  int? exitCode;
  bool isManuallyTerminated = false;

  bool isSuspended = false;
  bool isEfficiencyMode = false;

  int lastCpuTime = 0;
  DateTime lastCpuTimestamp = DateTime.now();

  RunningCore({
    required this.id,
    required this.version,
    required this.loader,
    required this.userName,
    this.avatar,
    required this.accountType,
    required this.identityName,
    required this.process,
    this.exitCode,
  });
}

class CoreManager {
  static final CoreManager instance = CoreManager._();
  CoreManager._();

  final List<RunningCore> _runningCores = [];
  final StreamController<List<RunningCore>> _coresController = StreamController<List<RunningCore>>.broadcast();

  List<RunningCore> get runningCores => List.unmodifiable(_runningCores);
  Stream<List<RunningCore>> get coresStream => _coresController.stream;

  void addCore(RunningCore core) {
    _runningCores.add(core);
    _coresController.add(runningCores);
  }

  void removeCore(RunningCore core) {
    _runningCores.remove(core);
    _coresController.add(runningCores);
  }

  void update() {
    _coresController.add(runningCores);
  }
}

class LaunchService {
  static final LaunchService instance = LaunchService._();
  LaunchService._();

  Future<void> updateBlJson(String minecraftDir, String versionId, {bool fabricLoader = false, String? iconPath}) async {
    try {
      final blJsonPath = p.join(minecraftDir, "versions", ".BLF.json");
      final file = File(blJsonPath);
      Map<String, dynamic> blData = {"versions": {}};

      if (await file.exists()) {
        try {
          blData = jsonDecode(await file.readAsString());
        } catch (e) {
          blData = {"versions": {}};
        }
      }

      if (blData["versions"] == null || blData["versions"] is! Map) {
        blData["versions"] = {};
      }

      final baseVersion = versionId.contains("-") ? versionId.split("-")[0] : versionId;

      final versionEntry = {
        "Fabric": fabricLoader,
        "client": true,
        "version": baseVersion,
        "setup_time": DateTime.now().millisecondsSinceEpoch ~/ 1000,
      };

      if (iconPath != null) {
        versionEntry["icon"] = iconPath;
      }

      (blData["versions"] as Map<String, dynamic>)[versionId] = versionEntry;

      await Directory(p.dirname(blJsonPath)).create(recursive: true);
      await file.writeAsString(JsonEncoder.withIndent("    ").convert(blData));
    } catch (e) {
      stderr.writeln("Failed to update .BLF.json: $e");
    }
  }

  Future<void> repairBlJson(String minecraftDir) async {
    try {
      final versionsPath = p.join(minecraftDir, "versions");
      if (!await Directory(versionsPath).exists()) return;

      final blJsonPath = p.join(versionsPath, ".BLF.json");
      Map<String, dynamic> blData = {"versions": {}};

      if (await File(blJsonPath).exists()) {
        try {
          blData = jsonDecode(await File(blJsonPath).readAsString());
        } catch (e) {
          blData = {"versions": {}};
        }
      }

      if (blData["versions"] == null || blData["versions"] is! Map) {
        blData["versions"] = {};
      }

      final versionsMap = Map<String, dynamic>.from(blData["versions"] as Map);
      bool changed = false;

      final List<FileSystemEntity> entities = await Directory(versionsPath).list().toList();
      for (var entity in entities) {
        if (entity is Directory) {
          final id = p.basename(entity.path);
          if (id == ".BLF.json") continue;

          if (!versionsMap.containsKey(id)) {
            final isFabric = id.toLowerCase().contains("fabric");
            final baseVersion = id.contains("-") ? id.split("-")[0] : id;

            versionsMap[id] = {
              "Fabric": isFabric,
              "client": true,
              "version": baseVersion,
              "setup_time": DateTime.now().millisecondsSinceEpoch ~/ 1000,
            };
            changed = true;
          }
        }
      }

      if (changed) {
        blData["versions"] = versionsMap;
        await File(blJsonPath).writeAsString(JsonEncoder.withIndent("    ").convert(blData));
      }
    } catch (e) {
      stderr.writeln("Failed to repair .BLF.json: $e");
    }
  }

  Future<void> _ensureLauncherProfile(String minecraftDir) async {
    try {
      final profilePath = p.join(minecraftDir, "launcher_profiles.json");
      final file = File(profilePath);
      if (await file.exists()) return;

      final defaultProfile = {
        "profiles": {
          "BloretLauncher": {
            "name": "BloretLauncher",
            "type": "custom",
            "created": "1970-01-01T00:00:00.000Z",
            "lastUsed": "1970-01-01T00:00:00.000Z",
            "gameDir": minecraftDir
          }
        },
        "selectedProfile": "BloretLauncher",
        "clientToken": "00000000000000000000000000000000"
      };

      await Directory(p.dirname(profilePath)).create(recursive: true);
      await file.writeAsString(JsonEncoder.withIndent("    ").convert(defaultProfile));
    } catch (e) {
      stderr.writeln("Failed to create launcher_profiles.json: $e");
    }
  }

  int _compareVersions(String v1, String v2) {
    final p1 = v1.split(RegExp(r'[.-]'));
    final p2 = v2.split(RegExp(r'[.-]'));
    for (int i = 0; i < p1.length && i < p2.length; i++) {
      final i1 = int.tryParse(p1[i]);
      final i2 = int.tryParse(p2[i]);
      if (i1 != null && i2 != null) {
        if (i1 != i2) return i1.compareTo(i2);
      } else {
        final c = p1[i].compareTo(p2[i]);
        if (c != 0) return c;
      }
    }
    return p1.length.compareTo(p2.length);
  }

  Future<Map<String, dynamic>> loadMergedVersionJson(String minecraftDir, String versionId, [Set<String>? seen]) async {
    seen ??= {};
    if (seen.contains(versionId)) {
      throw Exception("Version inheritance loop: $versionId");
    }
    seen.add(versionId);

    final versionJsonPath = p.join(minecraftDir, "versions", versionId, "$versionId.json");
    final file = File(versionJsonPath);
    if (!await file.exists()) {
      throw Exception("Version JSON not found: $versionJsonPath");
    }

    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final parentId = data['inheritsFrom'];
    if (parentId == null) {
      return data;
    }

    final parentData = await loadMergedVersionJson(minecraftDir, parentId, seen);

    final merged = Map<String, dynamic>.from(parentData);
    data.forEach((k, v) {
      if (k == "libraries") {
        final childLibs = v as List;
        final parentLibs = parentData['libraries'] as List? ?? [];
        final Map<String, dynamic> allLibsMap = {};
        
        for (var lib in [...parentLibs, ...childLibs]) {
          final name = lib['name'] as String?;
          if (name == null) continue;
          
          final parts = name.split(':');
          if (parts.length < 3) {
            allLibsMap[name] = lib;
            continue;
          }
          
          final artifactId = "${parts[0]}:${parts[1]}";
          final version = parts[2];
          
          final existing = allLibsMap[artifactId];
          if (existing == null) {
            allLibsMap[artifactId] = lib;
          } else {
            final existingVersion = (existing['name'] as String).split(':')[2];
            if (_compareVersions(version, existingVersion) > 0) {
              allLibsMap[artifactId] = lib;
            }
          }
        }
        merged['libraries'] = allLibsMap.values.toList();
      } else if (k == "arguments") {
        final parentArgs = parentData['arguments'] as Map<String, dynamic>? ?? {};
        final childArgs = v as Map<String, dynamic>;
        final Map<String, dynamic> mergedArgs = {};
        for (var field in ["game", "jvm"]) {
          final pList = parentArgs[field] as List? ?? [];
          final cList = childArgs[field] as List? ?? [];
          mergedArgs[field] = [...pList, ...cList];
        }
        merged['arguments'] = mergedArgs;
      } else {
        merged[k] = v;
      }
    });
    return merged;
  }

  bool _matchRule(Map<String, dynamic> rule) {
    final osRule = rule['os'] as Map<String, dynamic>?;
    if (osRule != null) {
      final name = osRule['name'];
      if (name != null) {
        final currentOs = Platform.isWindows ? "windows" : (Platform.isMacOS ? "osx" : "linux");
        if (name != currentOs) return false;
      }
      final arch = osRule['arch'] as String?;
      if (arch != null) {
        String currentArch = "x86";
        final v = Platform.version.toLowerCase();
        if (v.contains("x64") || v.contains("amd64")) {
          currentArch = "x64";
        } else if (v.contains("arm64") || v.contains("aarch64")) {
          currentArch = "arm64";
        } else if (Platform.isAndroid) {
          currentArch = "arm";
        }

        if (arch == "x86" && currentArch == "x64") {
           return false;
        }
        if (arch != currentArch) return false;
      }
      final versionRegex = osRule['version'] as String?;
      if (versionRegex != null) {
      }
    }
    
    final features = rule['features'] as Map<String, dynamic>?;
    if (features != null) {
      for (var required in features.values) {
        if (required == true) return false;
      }
    }
    
    return true;
  }

  bool _rulesAllow(List? rules) {
    if (rules == null || rules.isEmpty) return true;
    bool allowed = false;
    for (var rule in rules) {
      if (_matchRule(rule as Map<String, dynamic>)) {
        allowed = rule['action'] == 'allow';
      }
    }
    return allowed;
  }

  String _getLibraryPath(String minecraftDir, Map<String, dynamic> lib) {
    final relPath = _getLibraryRelativePath(lib);
    if (relPath.isEmpty) return "";
    return p.join(minecraftDir, relPath);
  }

  Future<String> buildClasspath(String minecraftDir, Map<String, dynamic> versionData, {Function(double)? onProgress}) async {
    final libraries = versionData['libraries'] as List? ?? [];
    final List<String> cpEntries = [];
    
    int processed = 0;
    for (var lib in libraries) {
      if (!_rulesAllow(lib['rules'])) continue;
      
      final libPath = _getLibraryPath(minecraftDir, lib as Map<String, dynamic>);
      if (libPath.isNotEmpty && await File(libPath).exists()) {
        cpEntries.add(libPath);
      }
      
      processed++;
      if (onProgress != null && libraries.isNotEmpty) {
        onProgress(processed / libraries.length);
      }
    }

    return cpEntries.join(Platform.isWindows ? ';' : ':');
  }

  String _replaceVariables(String value, Map<String, String> variables) {
    variables.forEach((k, v) {
      value = value.replaceAll("\${$k}", v);
    });
    return value;
  }

  List<String> _splitArguments(String commandLine) {
    final List<String> result = [];
    bool inQuotes = false;
    StringBuffer current = StringBuffer();
    for (int i = 0; i < commandLine.length; i++) {
      String char = commandLine[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ' ' && !inQuotes) {
        if (current.isNotEmpty) {
          result.add(current.toString());
          current.clear();
        }
      } else {
        current.write(char);
      }
    }
    if (current.isNotEmpty) {
      result.add(current.toString());
    }
    return result;
  }

  Future<void> _extractNatives(String zipPath, String extractTo, List<dynamic>? excludes) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final excludeList = excludes?.map((e) => e.toString().replaceAll('\\', '/')).toList() ?? [];
      
      for (final file in archive) {
        if (file.isFile) {
          final fileName = file.name.replaceAll('\\', '/');
          bool isExcluded = false;
          for (final ex in excludeList) {
            if (fileName.startsWith(ex)) {
              isExcluded = true;
              break;
            }
          }
          if (isExcluded) continue;

          final name = p.basename(file.name);
          if (name.endsWith(".dll") || name.endsWith(".so") || name.endsWith(".dylib") || name.contains("lwjgl")) {
            final data = file.content as List<int>;
            final outFile = File(p.join(extractTo, name));
            await outFile.create(recursive: true);
            await outFile.writeAsBytes(data);
          }
        }
      }
    } catch (e) {
      stderr.writeln("Failed to extract native library ($zipPath): $e");
    }
  }

  String getPreferredDownloadDir() {
    final List<dynamic> dirs = ConfigService.get('minecraft_dirs') ?? [];
    if (dirs.isNotEmpty) {
      return dirs.first.toString();
    }
    if (Platform.isWindows) {
      return p.join(Platform.environment['APPDATA']!, ".minecraft");
    }
    return p.join(Directory.systemTemp.path, ".minecraft");
  }

  Future<List<String>> getAvailableVersions(String minecraftDir, {String? query}) async {
    final versionsDir = Directory(p.join(minecraftDir, "versions"));
    if (!await versionsDir.exists()) return [];

    final List<String> versions = [];
    try {
      final List<FileSystemEntity> entities = await versionsDir.list().toList();
      for (var entity in entities) {
        if (entity is Directory) {
          final id = p.basename(entity.path);
          final jsonFile = File(p.join(entity.path, "$id.json"));
          if (await jsonFile.exists()) {
            if (query == null || query.isEmpty || id.toLowerCase().contains(query.toLowerCase())) {
              versions.add(id);
            }
          }
        }
      }
    } catch (e) {
      stderr.writeln("Failed to scan versions directory: $e");
    }
    return versions;
  }

  Future<List<Map<String, String>>> getAllAvailableVersions({String? query}) async {
    final List<dynamic> dirsRaw = ConfigService.get('minecraft_dirs') ?? [];
    final List<String> dirs = List<String>.from(dirsRaw);
    final List<Map<String, String>> allVersions = [];
    for (var dir in dirs) {
      final versions = await getAvailableVersions(dir, query: query);
      for (var v in versions) {
        allVersions.add({
          "id": v,
          "directory": dir,
        });
      }
    }
    return allVersions;
  }

  Future<List<Map<String, dynamic>>> getMissingFiles(String minecraftDir, String versionId) async {
    final versionData = await loadMergedVersionJson(minecraftDir, versionId);
    final List<Map<String, dynamic>> missing = [];

    // 1. Client JAR
    final clientJarName = versionData['jar'] ?? versionId;
    final relativeJarPath = p.join('versions', versionId, '$versionId.jar');
    final clientJar = p.join(minecraftDir, relativeJarPath);
    
    final downloads = versionData['downloads'] as Map<String, dynamic>?;
    final clientInfo = downloads?['client'] as Map<String, dynamic>?;
    
    if (!await File(clientJar).exists()) {
      missing.add({
        "type": "jar",
        "id": clientJarName,
        "path": clientJar,
        "relativePath": relativeJarPath,
        "url": clientInfo?['url'],
        "sha1": clientInfo?['sha1'],
        "size": clientInfo?['size'],
      });
    }

    // 2. Libraries and Natives
    final libraries = versionData['libraries'] as List? ?? [];
    for (var lib in libraries) {
      final libData = lib as Map<String, dynamic>;
      if (!_rulesAllow(libData['rules'])) continue;
      
      final libName = libData['name'] as String?;
      if (libName == null) continue;
      
      final relPath = _getLibraryRelativePath(libData);
      final libPath = p.join(minecraftDir, relPath);
      final libDownloads = libData['downloads'] as Map<String, dynamic>?;
      final artifact = libDownloads?['artifact'] as Map<String, dynamic>?;

      if (!await File(libPath).exists()) {
        missing.add({
          "type": "library",
          "id": libName,
          "path": libPath,
          "relativePath": relPath,
          "url": artifact?['url'] ?? (libData['url'] != null ? "${libData['url']}${relPath.replaceAll(p.separator, '/')}" : null),
          "sha1": artifact?['sha1'],
          "size": artifact?['size'],
        });
      }
      
      // Natives Classifier
      final currentOs = Platform.isWindows ? "windows" : (Platform.isMacOS ? "osx" : "linux");
      final natives = libData['natives'] as Map<String, dynamic>?;
      if (natives != null && natives.containsKey(currentOs)) {
        final classifier = natives[currentOs].replaceAll("\${arch}", "64");
        final classifiers = libDownloads?['classifiers'] as Map<String, dynamic>?;
        final nativeArtifact = classifiers?[classifier] as Map<String, dynamic>?;
        
        if (nativeArtifact != null) {
          final nativeRelPath = nativeArtifact['path'] ?? _getMavenArtifactPath(libName, classifier: classifier);
          final nativePath = p.join(minecraftDir, nativeRelPath);
          if (!await File(nativePath).exists()) {
            missing.add({
              "type": "library",
              "id": "$libName-$classifier",
              "path": nativePath,
              "relativePath": nativeRelPath,
              "url": nativeArtifact['url'],
              "sha1": nativeArtifact['sha1'],
              "size": nativeArtifact['size'],
              "isNative": true,
            });
          }
        }
      }
    }

    // 3. Asset Index
    final assetIndex = versionData['assetIndex'];
    if (assetIndex != null && assetIndex['id'] != null) {
      final assetIndexId = assetIndex['id'];
      final relativeIndexPath = p.join("assets", "indexes", "$assetIndexId.json");
      final assetIndexPath = p.join(minecraftDir, relativeIndexPath);
      
      if (!await File(assetIndexPath).exists()) {
        missing.add({
          "type": "asset_index",
          "id": assetIndexId,
          "path": assetIndexPath,
          "relativePath": relativeIndexPath,
          "url": assetIndex['url'],
          "sha1": assetIndex['sha1'],
          "size": assetIndex['size'],
        });
      } else {
        // 4. Asset Objects
        try {
          final indexContent = await File(assetIndexPath).readAsString();
          final indexData = jsonDecode(indexContent);
          final objects = indexData['objects'] as Map<String, dynamic>? ?? {};
          
          for (var entry in objects.entries) {
            final assetMeta = entry.value as Map<String, dynamic>;
            final hash = assetMeta['hash'] as String?;
            if (hash == null) continue;
            
            final relObjPath = p.join("assets", "objects", hash.substring(0, 2), hash);
            final objPath = p.join(minecraftDir, relObjPath);
            
            if (!await File(objPath).exists()) {
              missing.add({
                "type": "asset_object",
                "id": entry.key,
                "path": objPath,
                "relativePath": relObjPath,
                "url": "https://resources.download.minecraft.net/${hash.substring(0, 2)}/$hash",
                "sha1": hash,
                "size": assetMeta['size'],
              });
            }
          }
        } catch (e) {
          stderr.writeln("Failed to check asset objects: $e");
        }
      }
    }

    return missing;
  }

  String _getLibraryRelativePath(Map<String, dynamic> lib) {
    final name = lib['name'] as String?;
    if (name == null) return "";

    final downloads = lib['downloads'] as Map<String, dynamic>?;
    final artifact = downloads?['artifact'] as Map<String, dynamic>?;
    if (artifact != null && artifact['path'] != null) {
      return artifact['path'];
    }

    return _getMavenArtifactPath(name);
  }

  String _getMavenArtifactPath(String name, {String? classifier, String extension = "jar"}) {
    final parts = name.split(":");
    if (parts.length < 3) return "";
    final group = parts[0].replaceAll(".", p.separator);
    final artifact = parts[1];
    final version = parts[2];
    final filename = "$artifact-$version${classifier != null ? "-$classifier" : ""}.$extension";
    return p.join("libraries", group, artifact, version, filename);
  }

  Future<void> downloadMissingFiles(String minecraftDir, String versionId, {Function(String status, double progress)? onStatus}) async {
    List<Map<String, dynamic>> missing = await getMissingFiles(minecraftDir, versionId);
    if (missing.isEmpty) {
      onStatus?.call("All files are complete".tl, 1.0);
      return;
    }

    bool indexDownloaded = false;
    int totalDownloaded = 0;
    
    while (missing.isNotEmpty) {
      onStatus?.call("Completing files (${missing.length} pending)...".tl, 0.0);
      
      final List<DownloadItem> items = [];
      for (var m in missing) {
        if (m['url'] == null) continue;
        items.add(DownloadItem(
          id: m['id'],
          url: m['url'],
          savePath: m['relativePath'],
          sha1: m['sha1'],
        ));
        if (m['type'] == 'asset_index') indexDownloaded = true;
      }

      if (items.isEmpty) break;
      
      await DownloadService.instance.downloadBatch(items, Directory(minecraftDir));
      totalDownloaded += items.length;
      
      // If index was downloaded, need to re-scan objects
      if (indexDownloaded) {
        indexDownloaded = false; 
        missing = await getMissingFiles(minecraftDir, versionId);
      } else {
        break; 
      }
    }
    
    onStatus?.call("Completed $totalDownloaded files".tl, 1.0);
  }

  Future<Process> launch({
    required String version,
    required String minecraftDir,
    Function(String status, double progress)? onStatus,
  }) async {
    // 1. Repair metadata and configuration files
    onStatus?.call("Checking version metadata...".tl, 0.0);
    await repairBlJson(minecraftDir);
    await _ensureLauncherProfile(minecraftDir);

    // 2. Complete missing files
    onStatus?.call("Checking game integrity...".tl, 0.02);
    await downloadMissingFiles(minecraftDir, version, onStatus: (s, p) => onStatus?.call(s, 0.02 + p * 0.03));

    onStatus?.call("Loading version configuration...".tl, 0.05);
    final versionData = await loadMergedVersionJson(minecraftDir, version);
    
    onStatus?.call("Verifying Java environment...".tl, 0.1);
    String? javaPath;
    String javaVersionStr = ConfigService.get("java_version") ?? "8";

    final String selectionMode = ConfigService.get('java_selection_mode') ?? "auto";
    
    if (selectionMode == "auto") {
      final String? cachedJava = ConfigService.get('detected_java_list');
      if (cachedJava != null) {
        try {
          final List<Map<String, String>> detectedJavas = (jsonDecode(cachedJava) as List)
              .map((e) => Map<String, String>.from(e))
              .toList();
          final bestMatch = JavaConfig.findBestJavaMatch(version, detectedJavas);
          if (bestMatch != null) {
            javaPath = bestMatch['path'];
            javaVersionStr = bestMatch['version'] ?? "8";
            logger.info("Auto-selected Java for $version: ${bestMatch['detail']} at $javaPath", LogSource.system);
          }
        } catch (e) {
          logger.error("Auto Java selection failed: $e", LogSource.system);
        }
      }
    }

    if (javaPath == null || javaPath.isEmpty) {
      javaPath = ConfigService.get('java_path');
      javaVersionStr = ConfigService.get("java_version") ?? "8";
    }

    if (javaPath == null || javaPath.isEmpty) {
      throw Exception("Java path not configured, please select or auto-detect in settings.");
    }
    
    String javaExe = p.join(javaPath, 'bin', Platform.isWindows ? 'java.exe' : 'java');
    if (!await File(javaExe).exists()) {
      if (await File(javaPath).exists() && (javaPath.toLowerCase().endsWith("java.exe") || javaPath.toLowerCase().endsWith("java"))) {
        javaExe = javaPath;
      } else {
        throw Exception("Java executable does not exist: $javaExe\nPlease ensure the Java path in settings is a correct JDK/JRE root directory or points directly to the java executable.");
      }
    }

    final int javaVersion = int.tryParse(javaVersionStr) ?? 8;

    onStatus?.call("Loading account information...".tl, 0.15);
    final List<dynamic> accountListRaw = ConfigService.get("MinecraftAccountList") ?? [];
    final int chosenIndex = ConfigService.get("MinecraftAccount_Chosen") ?? 0;
    
    if (accountListRaw.isEmpty || chosenIndex >= accountListRaw.length) {
      throw Exception("No valid account found, please log in first.");
    }

    final Map<String, dynamic> account = accountListRaw[chosenIndex] is String 
        ? jsonDecode(accountListRaw[chosenIndex]) 
        : accountListRaw[chosenIndex];
    final String username = account['username'] ?? "BloretPlayer";
    final String uuid = account['uuid'] ?? "00000000000000000000000000000000";
    final String accessToken = account['access_token'] ?? "0";
    final String xuid = account['xuid'] ?? "";
    final String clientId = account['clientId'] ?? "";
    final bool isMicrosoft = account['type'] == "Microsoft";

    onStatus?.call("Scanning library files...".tl, 0.2);
    final cp = await buildClasspath(minecraftDir, versionData, onProgress: (p) {
      onStatus?.call("Scanning library files ($version)...".tl, 0.2 + (p * 0.3));
    });

    final clientJarName = versionData['jar'] ?? version;
    final clientJar = p.join(minecraftDir, 'versions', clientJarName, '$clientJarName.jar');
    if (!await File(clientJar).exists()) {
      throw Exception("Game core JAR not found: $clientJar\nPlease check if this version is fully installed.");
    }

    final fullClasspath = '$clientJar${Platform.isWindows ? ';' : ':'}$cp';
    final nativesDir = p.join(minecraftDir, "versions", version, "$version-natives");
    if (!await Directory(nativesDir).exists()) {
      await Directory(nativesDir).create(recursive: true);
    }

    onStatus?.call("Preparing native libraries...".tl, 0.55);
    final libraries = versionData['libraries'] as List? ?? [];
    for (var lib in libraries) {
      if (!_rulesAllow(lib['rules'])) continue;
      if (lib['natives'] != null || lib['extract'] != null) {
        final libPath = _getLibraryPath(minecraftDir, lib as Map<String, dynamic>);
        if (libPath.isNotEmpty && await File(libPath).exists()) {
          final excludes = lib['extract']?['exclude'] as List<dynamic>?;
          await _extractNatives(libPath, nativesDir, excludes);
        }
      }
    }

    final tempDir = p.join(Directory.systemTemp.path, "BloraLauncherTemp");
    if (!await Directory(tempDir).exists()) {
      await Directory(tempDir).create(recursive: true);
    }

    final Map<String, String> variables = {
      "natives_directory": nativesDir,
      "launcher_name": "BloraLauncher-Flutter",
      "launcher_version": "361",
      "classpath": fullClasspath,
      "classpath_separator": Platform.isWindows ? ";" : ":",
      "library_directory": p.join(minecraftDir, "libraries"),
      "auth_player_name": username,
      "version_name": version,
      "game_directory": p.join(minecraftDir, "versions", version),
      "assets_root": p.join(minecraftDir, "assets"),
      "assets_index_name": (versionData['assetIndex']?['id'] ?? version).toString(),
      "auth_uuid": uuid,
      "auth_access_token": isMicrosoft ? accessToken : "00000000000000000000000000000000",
      "user_type": isMicrosoft ? "msa" : "legacy",
      "version_type": "BloraLauncher-Flutter",
      "clientid": clientId,
      "auth_xuid": xuid,
      "user_properties": "{}",
    };

    final List<String> args = [];

    // JVM Args
    final int minMem = ConfigService.get('java_min_memory') ?? 512;
    final int maxMem = ConfigService.get('java_max_memory') ?? 4096;
    args.addAll(["-Xms${minMem}M", "-Xmx${maxMem}M"]);

    if (Platform.isMacOS) {
      args.add("-XstartOnFirstThread");
    }

    // Matching launch.py's launcher_jvm_args
    args.addAll([
      "-Djava.library.path=$nativesDir",
      "-Djna.tmpdir=$nativesDir",
      "-Dorg.lwjgl.system.SharedLibraryExtractPath=$nativesDir",
      "-Dio.netty.native.workdir=$nativesDir",
      "-Dminecraft.launcher.brand=BloraLauncher-Flutter",
      "-Dminecraft.launcher.version=361",
      "-Doolloo.jlw.tmpdir=$tempDir",
      "-Djava.io.tmpdir=$tempDir",
      "-Dio.netty.tryReflectionSetAccessible=true",
      "-Dio.netty.native.skipTryReflectionSetAccessible=true",
      "-Dlog4j2.formatMsgNoLookups=true",
      "-Dfile.encoding=UTF-8",
      "-Dsun.jnu.encoding=UTF-8",
      "-XX:-OmitStackTraceInFastThrow",
      "-Dfml.ignoreInvalidMinecraftCertificates=True",
      "-Dfml.ignorePatchDiscrepancies=True",
      "-XX:HeapDumpPath=MojangTricksIntelDriversForPerformance_javaw.exe_minecraft.exe.heapdump",
      "-Djava.rmi.server.useCodebaseOnly=true",
      "-Djna.nosys=true",
      "-Djnidispatch.preserve=true",
      "-Dorg.lwjgl.util.Debug=false",
      "-Dorg.lwjgl.util.noload=true",
      "-Djava.awt.headless=false",
      "-Dsun.java2d.noddraw=true",
      "-Dsun.java2d.d3d=false",
      "-Dsun.java2d.opengl=false",
      "-Dsun.java2d.pmoffscreen=false",
      "-Dsun.java2d.accthreshold=0",
      "-XX:ErrorFile=hs_err_pid%p.log",
    ]);

    if (javaVersion >= 9) {
      args.addAll([
        "--add-modules=jdk.unsupported",
        "--add-opens=java.base/java.lang=ALL-UNNAMED",
        "--add-opens=java.base/java.util=ALL-UNNAMED",
        "--add-opens=java.base/sun.nio.ch=ALL-UNNAMED",
        "--add-opens=java.base/jdk.internal.misc=ALL-UNNAMED",
        "--add-opens=java.base/jdk.internal.ref=ALL-UNNAMED",
        "--add-opens=java.base/jdk.internal.loader=ALL-UNNAMED",
        "--add-opens=java.base/java.net=ALL-UNNAMED",
        "--add-opens=java.base/java.security=ALL-UNNAMED",
        "--add-exports=java.base/sun.nio.ch=ALL-UNNAMED",
        "--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED",
        "--add-exports=java.base/jdk.internal.ref=ALL-UNNAMED",
        "-Djdk.attach.allowAttachSelf=true",
        "-Djdk.module.IllegalAccess.silent=true",
      ]);
    }
    if (javaVersion >= 17) {
      args.add("--enable-native-access=ALL-UNNAMED");
    }

    final jvmArguments = versionData['arguments']?['jvm'] as List?;
    if (jvmArguments != null) {
      for (final entry in jvmArguments) {
        if (entry is String) {
          args.add(_replaceVariables(entry, variables));
        } else if (entry is Map<String, dynamic>) {
          if (_rulesAllow(entry['rules'])) {
            final value = entry['value'];
            if (value is String) {
              args.add(_replaceVariables(value, variables));
            } else if (value is List) {
              for (final v in value) {
                args.add(_replaceVariables(v.toString(), variables));
              }
            }
          }
        }
      }
    } else {
      args.add("-Djava.library.path=${variables['natives_directory']}");
      args.add("-cp");
      args.add(variables['classpath']!);
    }

    // Fabric / Forge support
    final libraryNames = (versionData['libraries'] as List? ?? []).map((e) => e['name'].toString().toLowerCase()).toList();
    final bool isFabric = version.toLowerCase().contains("fabric") || libraryNames.any((name) => name.contains("fabric"));
    final bool isForge = version.toLowerCase().contains("forge") || libraryNames.any((name) => name.contains("forge") || name.contains("neoforged"));

    if (isFabric) {
      args.add("-DFabricMcEmu=net.minecraft.client.main.Main");
      final modsDir = p.join(minecraftDir, "versions", version, "mods");
      if (await Directory(modsDir).exists()) {
        args.add("-Dfabric.addMods=$modsDir");
      }
    } else if (isForge) {
      // Forge usually handles itself via its own main class and libraries
    }

    // Main Class
    final mainClass = versionData['mainClass'] ?? "net.minecraft.client.main.Main";
    args.add(mainClass);

    // Game Args
    final gameArguments = versionData['arguments']?['game'] as List?;
    String templateText = jsonEncode(gameArguments ?? versionData['minecraftArguments'] ?? "");
    
    if (gameArguments != null) {
      for (final entry in gameArguments) {
        if (entry is String) {
          args.add(_replaceVariables(entry, variables));
        } else if (entry is Map<String, dynamic>) {
          if (_rulesAllow(entry['rules'])) {
            final value = entry['value'];
            if (value is String) {
              args.add(_replaceVariables(value, variables));
            } else if (value is List) {
              for (final v in value) {
                args.add(_replaceVariables(v.toString(), variables));
              }
            }
          }
        }
      }
    } else {
      final String minecraftArguments = versionData['minecraftArguments'] ?? "";
      if (minecraftArguments.isNotEmpty) {
        final expanded = _replaceVariables(minecraftArguments, variables);
        args.addAll(_splitArguments(expanded));
      }
    }

    // Explicitly add clientId/xuid if needed (matching launch.py)
    if (isMicrosoft) {
      if (templateText.contains("\${clientid}") && clientId.isNotEmpty && !args.contains("--clientId")) {
        args.addAll(["--clientId", clientId]);
      }
      if (templateText.contains("\${auth_xuid}") && xuid.isNotEmpty && !args.contains("--xuid")) {
        args.addAll(["--xuid", xuid]);
      }
    }

    onStatus?.call("Launching Minecraft...".tl, 0.95);
    return await Process.start(javaExe, args, workingDirectory: variables['game_directory']);
  }

  Future<bool> isVersionComplete(String minecraftDir, String versionId) async {
    final missing = await getMissingFiles(minecraftDir, versionId);
    return missing.isEmpty;
  }
}
