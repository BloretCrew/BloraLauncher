import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';

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
      throw Exception("版本继承循环: $versionId");
    }
    seen.add(versionId);

    final versionJsonPath = p.join(minecraftDir, "versions", versionId, "$versionId.json");
    final file = File(versionJsonPath);
    if (!await file.exists()) {
      throw Exception("找不到版本 JSON: $versionJsonPath");
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
      } else if (k == "assetIndex" && v is Map && v['id'] == null && merged['assetIndex'] != null) {
        // Keep parent's complete assetIndex if child's is partial
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
        
        // Match Mojang architecture tags
        if (arch == "x86" && currentArch == "x64") {
           // On 64-bit Windows, we can often run x86 but Mojang JSONs usually have separate rules.
           // However, if the rule ONLY specifies x86, we might allow it depending on the library.
           // To be safe and match Python's logic:
           // return false if they don't match exactly.
           return false;
        }
        if (arch != currentArch) return false;
      }
      final versionRegex = osRule['version'] as String?;
      if (versionRegex != null) {
        // Dart's Platform.version is usually "version (date) on "os""
        // Mojang's version rule is for the OS version. 
        // We skip it for now or return true if we can't reliably check OS version.
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
    final name = lib['name'] as String?;
    if (name == null) return "";
    final parts = name.split(':');
    if (parts.length < 3) return "";
    final group = parts[0].replaceAll('.', p.separator);
    final artifact = parts[1];
    final version = parts[2];
    
    String extension = "jar";
    String? classifier;
    final natives = lib['natives'] as Map<String, dynamic>?;
    if (natives != null) {
      final currentOs = Platform.isWindows ? "windows" : (Platform.isMacOS ? "osx" : "linux");
      classifier = natives[currentOs]?.replaceAll("\${arch}", "64");
    }

    final filename = "$artifact-$version${classifier != null ? "-$classifier" : ""}.$extension";
    return p.join(minecraftDir, 'libraries', group, artifact, version, filename);
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
      stderr.writeln("提取原生库失败 ($zipPath): $e");
    }
  }

  Future<Process> launch({
    required String version,
    required String minecraftDir,
    Function(String status, double progress)? onStatus,
  }) async {
    onStatus?.call("正在加载版本配置...", 0.05);
    final versionData = await loadMergedVersionJson(minecraftDir, version);
    
    onStatus?.call("正在校验 Java 环境...", 0.1);
    String? javaPath = ConfigService.get('java_path');
    if (javaPath == null || javaPath.isEmpty) {
      throw Exception("未配置 Java 路径，请在设置中选择或自动检测。");
    }
    
    String javaExe = p.join(javaPath, 'bin', Platform.isWindows ? 'java.exe' : 'java');
    if (!await File(javaExe).exists()) {
      if (await File(javaPath).exists() && (javaPath.toLowerCase().endsWith("java.exe") || javaPath.toLowerCase().endsWith("java"))) {
        javaExe = javaPath;
      } else {
        throw Exception("Java 执行文件不存在: $javaExe\n请确保设置中的 Java 路径是正确的 JDK/JRE 根目录或直接指向 java 可执行文件。");
      }
    }

    final String javaVersionStr = ConfigService.get("java_version") ?? "8";
    final int javaVersion = int.tryParse(javaVersionStr) ?? 8;

    onStatus?.call("正在加载账户信息...", 0.15);
    final List<dynamic> accountListRaw = ConfigService.get("MinecraftAccountList") ?? [];
    final int chosenIndex = ConfigService.get("MinecraftAccount_Chosen") ?? 0;
    
    if (accountListRaw.isEmpty || chosenIndex >= accountListRaw.length) {
      throw Exception("未找到有效的账户，请先登录。");
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

    onStatus?.call("正在扫描库文件...", 0.2);
    final cp = await buildClasspath(minecraftDir, versionData, onProgress: (p) {
      onStatus?.call("正在扫描库文件 ($version)...", 0.2 + (p * 0.3));
    });

    final clientJarName = versionData['jar'] ?? version;
    final clientJar = p.join(minecraftDir, 'versions', clientJarName, '$clientJarName.jar');
    if (!await File(clientJar).exists()) {
      throw Exception("找不到游戏核心 JAR: $clientJar\n请检查该版本是否已完整安装。");
    }

    final fullClasspath = '$clientJar${Platform.isWindows ? ';' : ':'}$cp';
    final nativesDir = p.join(minecraftDir, "versions", version, "$version-natives");
    if (!await Directory(nativesDir).exists()) {
      await Directory(nativesDir).create(recursive: true);
    }

    onStatus?.call("正在准备原生库...", 0.55);
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

    onStatus?.call("正在启动 Minecraft...", 0.95);
    return await Process.start(javaExe, args, workingDirectory: variables['game_directory']);
  }
}
