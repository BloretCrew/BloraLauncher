import 'dart:io';

import 'package:path/path.dart' as path;

// Made with Google Gemini
class JavaConfig {
  static const Map<String, Map<String, Map<String, String>>> versions = {
    "25": {
      "Windows": {
        "x64":
            "https://cdn.azul.com/zulu/bin/zulu25.30.17-ca-jdk25.0.1-win_x64.msi",
      },
    },
    "24": {
      "Windows": {
        "x64":
            "https://cdn.azul.com/zulu/bin/zulu24.32.13-ca-jdk24.0.2-win_x64.msi",
      },
    },
    "21": {
      "Windows": {
        "x64":
            "https://cdn.azul.com/zulu/bin/zulu21.44.17-ca-jdk21.0.8-win_x64.msi",
      },
    },
    "17": {
      "Windows": {
        "x64":
            "https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-win_x64.msi",
      },
    },
    "11": {
      "Windows": {
        "x64":
            "https://cdn.azul.com/zulu/bin/zulu11.82.19-ca-jdk11.0.28-win_x64.msi",
      },
    },
    "8": {
      "Windows": {
        "x64":
            "https://cdn.azul.com/zulu/bin/zulu8.88.0.19-ca-jdk8.0.462-win_x64.msi",
      },
    },
  };

  static List<String> get versionList =>
      versions.keys.toList()
        ..sort((a, b) => int.parse(b).compareTo(int.parse(a)));

  static int getRecommendedJavaVersion(String mcVersion) {
    if (mcVersion.isEmpty) return 8;

    // Handle Snapshots (e.g., 24w33a, 24w14a)
    final snapshotMatch = RegExp(r'^(\d{2})w(\d{2})').firstMatch(mcVersion);
    if (snapshotMatch != null) {
      final year = int.parse(snapshotMatch.group(1)!);
      final week = int.parse(snapshotMatch.group(2)!);

      if (year >= 24 && week >= 33) return 23; // 24w33a+ needs Java 23
      if (year >= 24 && week >= 14) return 21; // 24w14a+ needs Java 21
      if (year >= 24 || (year == 23 && week >= 40)) {
        return 21; // 1.20.5 snapshots
      }
      if (year >= 21) return 17; // 1.18+ snapshots
      return 8;
    }

    final versionParts = mcVersion.split('.');
    if (versionParts.length < 2) return 8;

    final int major = int.tryParse(versionParts[0]) ?? 0;
    final int minor = int.tryParse(versionParts[1]) ?? 0;
    int patch = 0;
    if (versionParts.length >= 3) {
      patch = int.tryParse(versionParts[2]) ?? 0;
    }

    if (major == 1) {
      if (minor >= 21) return 21;
      if (minor == 20 && patch >= 5) return 21; // 1.20.5+
      if (minor >= 18) return 17; // 1.18 - 1.20.4
      if (minor == 17) return 16; // 1.17
    } else if (major > 1) {
      return 21; // 2.x versions (theoretical)
    }

    return 8; // 1.16.5 and below
  }

  static String getRecommendedJavaName(String mcVersion) {
    return "Java ${getRecommendedJavaVersion(mcVersion)}";
  }

  static Map<String, String>? findBestJavaMatch(
    String mcVersion,
    List<Map<String, String>> detectedJavas,
  ) {
    if (detectedJavas.isEmpty) return null;

    final targetVersion = getRecommendedJavaVersion(mcVersion);

    // 1. Precise Match (Always best)
    for (var java in detectedJavas) {
      final ver = int.tryParse(java['version'] ?? "") ?? 0;
      if (ver == targetVersion) return java;
    }

    // 2. Compatibility Logic for Modern Versions (17+)
    if (targetVersion >= 17) {
      List<Map<String, String>> compatibles = detectedJavas.where((java) {
        final ver = int.tryParse(java['version'] ?? "") ?? 0;
        // Java 17, 21, 23 etc. are generally backward compatible for MC
        return ver >= targetVersion;
      }).toList();

      if (compatibles.isNotEmpty) {
        // Prefer the version closest to target
        compatibles.sort(
          (a, b) => (int.tryParse(a['version'] ?? "") ?? 0).compareTo(
            int.tryParse(b['version'] ?? "") ?? 0,
          ),
        );
        return compatibles.first;
      }
    }

    // 3. Fallback for 1.17 (Java 16 usually works on 17)
    if (targetVersion == 16) {
      for (var java in detectedJavas) {
        final ver = int.tryParse(java['version'] ?? "") ?? 0;
        if (ver == 17) return java;
      }
    }

    // 4. Strict Lock for Java 8 (Older versions are very sensitive to Java version)
    if (targetVersion == 8) {
      for (var java in detectedJavas) {
        final ver = int.tryParse(java['version'] ?? "") ?? 0;
        if (ver == 8) return java;
      }
    }

    // 5. Emergency Fallback: Find anything that might work
    // If we can't find exact, but have something newer than target, try it
    for (var java in detectedJavas) {
      final ver = int.tryParse(java['version'] ?? "") ?? 0;
      if (ver > targetVersion) return java;
    }

    // Return the first one if absolutely no match found
    return detectedJavas.first;
  }

  static Stream<Map<String, String>> detectJava({
    bool includeDetails = true,
  }) async* {
    if (Platform.isAndroid) {
      yield {
        "version": "Android Runtime",
        "path": "internal",
        "detail": "Built-in Android OpenJDK",
      };
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
      } else if (lowerPath.contains("jbr") ||
          lowerPath.contains("jetbrains") ||
          lowerPath.contains("android studio") ||
          lowerPath.contains("clion")) {
        vendor = "JetBrains Runtime";
      } else if (lowerPath.contains("graal")) {
        vendor = "GraalVM";
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
        "detail": "$vendor $version",
      };
    }

    Future<Map<String, String>> refineCandidate(
      Map<String, String> candidate,
    ) async {
      final executable = path.join(
        candidate['path']!,
        'bin',
        Platform.isWindows ? 'java.exe' : 'java',
      );
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

      final envVars = [
        'JAVA_HOME',
        'JDK_HOME',
        'PROGRAMFILES',
        'PROGRAMFILES(X86)',
      ];
      for (var env in envVars) {
        final value = Platform.environment[env];
        if (value != null &&
            value.isNotEmpty &&
            Directory(value).existsSync()) {
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
      searchRoots.addAll([
        '/usr/lib/jvm',
        '/usr/lib64/jvm',
        '/usr/java',
        '/opt',
      ]);
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

      while (queue.isNotEmpty && processedDepth < 100) {
        // Limit total iterations instead of depth for simplicity in async*
        final current = queue.removeAt(0);
        processedDepth++;

        try {
          await for (final entity in current.list(
            recursive: false,
            followLinks: false,
          )) {
            if (entity is Directory) {
              final binJava = File(
                path.join(
                  entity.path,
                  'bin',
                  Platform.isWindows ? 'java.exe' : 'java',
                ),
              );
              if (binJava.existsSync()) {
                final normalized = path.normalize(entity.path);
                if (!seenPaths.contains(normalized)) {
                  seenPaths.add(normalized);
                  var cand = createCandidate(normalized);
                  if (includeDetails) cand = await refineCandidate(cand);
                  yield cand;
                }
              } else if (processedDepth < 10) {
                // Shallow recursion
                queue.add(entity);
              }
            }
          }
        } catch (_) {}
      }
    }

    // Fallback command
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        'java',
      ]);
      if (result.exitCode == 0) {
        for (var line in result.stdout.toString().split(
          Platform.isWindows ? '\r\n' : '\n',
        )) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && File(trimmed).existsSync()) {
            final candPath = path.normalize(
              Directory(trimmed).parent.parent.path,
            );
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
    final name = path.basename(candidate).toLowerCase();

    // Handle 1.8 -> 8 pattern
    final legacyMatch = RegExp(r'1\.(\d+)').firstMatch(name);
    if (legacyMatch != null) return legacyMatch.group(1)!;

    final match = RegExp(r'(\d+)').firstMatch(name);
    return match?.group(1) ?? "?";
  }
}
