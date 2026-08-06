import 'dart:convert';
import 'dart:io';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:path/path.dart' as p;

class LaunchService {
  static final LaunchService instance = LaunchService._();
  LaunchService._();

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
        for (var lib in parentLibs) {
          final name = lib['name'];
          if (name != null) allLibsMap[name] = lib;
        }
        for (var lib in childLibs) {
          final name = lib['name'];
          if (name != null) allLibsMap[name] = lib;
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
      final arch = osRule['arch'];
      if (arch != null) {
        final currentArch = Platform.isAndroid ? "arm" : "x86";
        if (arch != currentArch) return false;
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
    final javaExe = p.join(javaPath, 'bin', Platform.isWindows ? 'java.exe' : 'java');
    if (!await File(javaExe).exists()) {
      throw Exception("Java 执行文件不存在: $javaExe");
    }

    final String javaVersionStr = ConfigService.get("java_version") ?? "8";
    final int javaVersion = int.tryParse(javaVersionStr) ?? 8;

    onStatus?.call("正在加载账户信息...", 0.15);
    final List<dynamic> accountListRaw = ConfigService.get("MinecraftAccountList") ?? [];
    final int chosenIndex = ConfigService.get("MinecraftAccount_Chosen") ?? 0;
    
    if (accountListRaw.isEmpty || chosenIndex >= accountListRaw.length) {
      throw Exception("未找到有效的账户，请先登录。");
    }

    final Map<String, dynamic> account = jsonDecode(accountListRaw[chosenIndex]);
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

    final clientJar = p.join(minecraftDir, 'versions', version, '$version.jar');
    if (!await File(clientJar).exists()) {
      throw Exception("客户端 JAR 不存在: $clientJar");
    }

    final fullClasspath = '$clientJar${Platform.isWindows ? ';' : ':'}$cp';
    final nativesDir = p.join(minecraftDir, "versions", version, "$version-natives");
    if (!await Directory(nativesDir).exists()) {
      await Directory(nativesDir).create(recursive: true);
    }

    final Map<String, String> variables = {
      "natives_directory": nativesDir,
      "launcher_name": "Bloret-Launcher",
      "launcher_version": "361",
      "classpath": fullClasspath,
      "classpath_separator": Platform.isWindows ? ";" : ":",
      "library_directory": p.join(minecraftDir, "libraries"),
      "auth_player_name": username,
      "version_name": version,
      "game_directory": p.join(minecraftDir, "versions", version), // 版本隔离
      "assets_root": p.join(minecraftDir, "assets"),
      "assets_index_name": (versionData['assetIndex']?['id'] ?? version).toString(),
      "auth_uuid": uuid,
      "auth_access_token": isMicrosoft ? accessToken : "00000000000000000000000000000000",
      "user_type": isMicrosoft ? "msa" : "legacy",
      "version_type": "Bloret-Launcher",
      "clientid": clientId,
      "auth_xuid": xuid,
    };

    final List<String> args = [];

    // JVM Args
    final int minMem = ConfigService.get('java_min_memory') ?? 512;
    final int maxMem = ConfigService.get('java_max_memory') ?? 4096;
    args.addAll(["-Xms${minMem}M", "-Xmx${maxMem}M"]);

    if (Platform.isMacOS) {
      args.add("-XstartOnFirstThread");
    }

    // Default launcher properties from launch.py
    args.addAll([
      "-Dio.netty.tryReflectionSetAccessible=true",
      "-Dio.netty.native.skipTryReflectionSetAccessible=true",
      "-Dlog4j2.formatMsgNoLookups=true",
      "-Dfile.encoding=UTF-8",
      "-Dsun.jnu.encoding=UTF-8",
      "-XX:-OmitStackTraceInFastThrow",
      "-Dfml.ignoreInvalidMinecraftCertificates=True",
      "-Dfml.ignorePatchDiscrepancies=True",
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

    onStatus?.call("正在启动 Minecraft...", 0.95);
    return await Process.start(javaExe, args, workingDirectory: variables['game_directory']);
  }
}
