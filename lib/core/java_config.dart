import 'dart:io';
import 'package:path/path.dart' as path;

class JavaConfig {
  static const Map<String, Map<String, Map<String, String>>> versions = {
    "25": {"Windows": {"x64": "https://cdn.azul.com/zulu/bin/zulu25.30.17-ca-jdk25.0.1-win_x64.msi"}},
    "24": {"Windows": {"x64": "https://cdn.azul.com/zulu/bin/zulu24.32.13-ca-jdk24.0.2-win_x64.msi"}},
    "21": {"Windows": {"x64": "https://cdn.azul.com/zulu/bin/zulu21.44.17-ca-jdk21.0.8-win_x64.msi"}},
    "17": {"Windows": {"x64": "https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-win_x64.msi"}},
    "11": {"Windows": {"x64": "https://cdn.azul.com/zulu/bin/zulu11.82.19-ca-jdk11.0.28-win_x64.msi"}},
    "8": {"Windows": {"x64": "https://cdn.azul.com/zulu/bin/zulu8.88.0.19-ca-jdk8.0.462-win_x64.msi"}},
  };

  static List<String> get versionList => versions.keys.toList()..sort((a, b) => int.parse(b).compareTo(int.parse(a)));

  static Stream<Map<String, String>> detectJava({bool includeDetails = true}) async* {
    if (Platform.isAndroid) {
      yield {"version": "Android Runtime", "path": "internal", "detail": "Built-in Android OpenJDK"};
      return;
    }

    final Set<String> seenPaths = {};

    Map<String, String> createCandidate(String javaPath) {
      final normalized = path.normalize(javaPath);
      String vendor = "Java";
      final lowerPath = normalized.toLowerCase();
      
      if (lowerPath.contains("zulu")) {
        vendor = "Zulu OpenJDK";
      } else if (lowerPath.contains("adopt") || lowerPath.contains("temurin")) {
        vendor = "Eclipse Temurin";
      } else if (lowerPath.contains("microsoft")) {
        vendor = "Microsoft OpenJDK";
      } else if (lowerPath.contains("corretto")) {
        vendor = "Amazon Corretto";
      } else if (lowerPath.contains("jbr") || lowerPath.contains("jetbrains") || lowerPath.contains("android studio") || lowerPath.contains("clion")) {
        vendor = "JetBrains Runtime";
      } else if (lowerPath.contains("openjdk")) {
        vendor = "OpenJDK";
      } else if (lowerPath.contains("jdk")) {
        vendor = "JDK";
      } else if (lowerPath.contains("jre")) {
        vendor = "JRE";
      }

      final version = _getJavaVersion(normalized);
      return {
        "version": version,
        "path": normalized,
        "vendor": vendor,
        "detail": "$vendor $version"
      };
    }

    Future<Map<String, String>> refineCandidate(Map<String, String> candidate) async {
      final executable = path.join(candidate['path']!, 'bin', Platform.isWindows ? 'java.exe' : 'java');
      try {
        final result = await Process.run(executable, ['-version']);
        final output = result.stderr.toString() + result.stdout.toString();
        final firstLine = output.split('\n').first.trim();
        if (firstLine.isNotEmpty) {
          final match = RegExp(r'version "([^"]+)"').firstMatch(firstLine);
          final ver = match?.group(1) ?? candidate['version'];
          return {...candidate, 'detail': "${candidate['vendor']} $ver"};
        }
      } catch (_) {}
      return candidate;
    }

    final List<String> searchRoots = [];
    if (Platform.isWindows) {
      for (int i = 67; i <= 90; i++) {
        final drive = "${String.fromCharCode(i)}:\\";
        try {
          if (Directory(drive).existsSync()) searchRoots.add(drive);
        } catch (_) {}
      }

      final envVars = ['JAVA_HOME', 'JDK_HOME', 'PROGRAMFILES', 'PROGRAMFILES(X86)'];
      for (var env in envVars) {
        final value = Platform.environment[env];
        if (value != null && value.isNotEmpty && Directory(value).existsSync()) {
          if (!searchRoots.contains(value)) searchRoots.add(value);
        }
      }

      final commonSubDirs = [
        r'Program Files\Java',
        r'Program Files (x86)\Java',
        r'Program Files\Eclipse Adoptium',
        r'Program Files\Zulu',
        r'Program Files\Microsoft',
        r'Program Files\Amazon Corretto',
        r'Program Files\JetBrains',
        r'AppData\Local\JetBrains',
        r'.minecraft\runtime',
        r'.jdks',
      ];

      for (var root in List.from(searchRoots)) {
        for (var sub in commonSubDirs) {
          final p = path.join(root, sub);
          if (Directory(p).existsSync()) {
            if (!searchRoots.contains(p)) searchRoots.add(p);
          }
        }
      }
    } else if (Platform.isLinux) {
      searchRoots.addAll(['/usr/lib/jvm', '/usr/lib64/jvm', '/usr/java', '/opt']);
      final home = Platform.environment['HOME'];
      if (home != null) {
        searchRoots.add(path.join(home, '.jdks'));
        searchRoots.add(path.join(home, '.sdkman', 'candidates', 'java'));
      }
    }

    // Path scanning
    for (var root in searchRoots) {
      final rootDir = Directory(root);
      if (!rootDir.existsSync()) continue;
      
      final queue = [rootDir];
      int processedDepth = 0;
      
      while (queue.isNotEmpty && processedDepth < 100) { // Limit total iterations instead of depth for simplicity in async*
        final current = queue.removeAt(0);
        processedDepth++;
        
        try {
          await for (final entity in current.list(recursive: false, followLinks: false)) {
            if (entity is Directory) {
              final binJava = File(path.join(entity.path, 'bin', Platform.isWindows ? 'java.exe' : 'java'));
              if (binJava.existsSync()) {
                final normalized = path.normalize(entity.path);
                if (!seenPaths.contains(normalized)) {
                  seenPaths.add(normalized);
                  var cand = createCandidate(normalized);
                  if (includeDetails) cand = await refineCandidate(cand);
                  yield cand;
                }
              } else if (processedDepth < 10) { // Shallow recursion
                queue.add(entity);
              }
            }
          }
        } catch (_) {}
      }
    }

    // Fallback command
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', ['java']);
      if (result.exitCode == 0) {
        for (var line in result.stdout.toString().split(Platform.isWindows ? '\r\n' : '\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && File(trimmed).existsSync()) {
            final candPath = path.normalize(Directory(trimmed).parent.parent.path);
            if (!seenPaths.contains(candPath)) {
              seenPaths.add(candPath);
              var cand = createCandidate(candPath);
              if (includeDetails) cand = await refineCandidate(cand);
              yield cand;
            }
          }
        }
      }
    } catch (_) {}
  }

  static String _getJavaVersion(String candidate) {
    final name = path.basename(candidate);
    final match = RegExp(r'(\d+)').firstMatch(name);
    return match?.group(1) ?? "?";
  }
}
