import 'package:http/http.dart' as http;

enum GraalVersion {
  java17,
  java21,
  java25,
  java25_2,
}

extension GraalVersionExtension on GraalVersion {
  String get label => switch (this) {
    GraalVersion.java17 => 'Java 17',
    GraalVersion.java21 => 'Java 21',
    GraalVersion.java25 => 'Java 25.0',
    GraalVersion.java25_2 => 'Java 25.2',
  };

  int get javaVersion => switch (this) {
    GraalVersion.java17 => 17,
    GraalVersion.java21 => 21,
    GraalVersion.java25 => 25,
    GraalVersion.java25_2 => 25,
  };

  String get release => switch (this) {
    GraalVersion.java17 => '17',
    GraalVersion.java21 => '21',
    GraalVersion.java25 => '25',
    GraalVersion.java25_2 => '25i2',
  };

  bool get useGds => this == GraalVersion.java25_2;
}

enum GraalPlatform {
  linuxX64,
  linuxAarch64,
  macosAarch64,
  windowsX64,
}

extension GraalPlatformExtension on GraalPlatform {
  String get label => switch (this) {
    GraalPlatform.linuxX64 => 'Linux x64',
    GraalPlatform.linuxAarch64 => 'Linux AArch64',
    GraalPlatform.macosAarch64 => 'macOS AArch64',
    GraalPlatform.windowsX64 => 'Windows x64',
  };

  String get platform => switch (this) {
    GraalPlatform.linuxX64 => 'linux-x64',
    GraalPlatform.linuxAarch64 => 'linux-aarch64',
    GraalPlatform.macosAarch64 => 'macos-aarch64',
    GraalPlatform.windowsX64 => 'windows-x64',
  };

  String get extension => switch (this) {
    GraalPlatform.windowsX64 => 'zip',
    _ => 'tar.gz',
  };
}

class GraalPackage {
  final GraalVersion version;
  final GraalPlatform platform;
  final String downloadUrl;

  const GraalPackage({
    required this.version,
    required this.platform,
    required this.downloadUrl,
  });
}

class GraalVMApi {
  final http.Client client;

  GraalVMApi({http.Client? client})
      : client = client ?? http.Client();

  String buildUrl(
      GraalVersion version,
      GraalPlatform platform,
      ) {
    if (version.useGds) {
      return 'https://gds.oracle.com/download/graal/'
          '${version.release}/latest/'
          'graalvm-jdk-${version.release}-${version.javaVersion}'
          '_${platform.platform}_bin.${platform.extension}';
    }

    return 'https://download.oracle.com/graalvm/'
        '${version.release}/latest/'
        'graalvm-jdk-${version.javaVersion}'
        '_${platform.platform}_bin.${platform.extension}';
  }

  Stream<GraalPackage> getPackages() async* {
    for (final version in GraalVersion.values) {
      for (final platform in GraalPlatform.values) {
        final url = buildUrl(version, platform);

        try {
          final response = await client.head(
            Uri.parse(url),
          );

          if (response.statusCode >= 200 &&
              response.statusCode < 300) {
            yield GraalPackage(
              version: version,
              platform: platform,
              downloadUrl: url,
            );
          }
        } catch (_) {}
      }
    }
  }

  Future<List<GraalPackage>> getAllPackages() async {
    final result = <GraalPackage>[];

    await for (final package in getPackages()) {
      result.add(package);
    }

    return result;
  }

  void dispose() {
    client.close();
  }
}