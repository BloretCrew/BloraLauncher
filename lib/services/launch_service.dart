import 'dart:io';
import 'package:path/path.dart' as p;

class LaunchService {
  static final LaunchService instance = LaunchService._();
  LaunchService._();

  Future<String> buildClasspath(String minecraftDir) async {
    final librariesDir = Directory(p.join(minecraftDir, 'libraries'));
    
    if (!await librariesDir.exists()) {
      throw Exception("Libraries 目录不存在: ${librariesDir.path}");
    }

    final List<String> cpEntries = [];

    await for (final entity in librariesDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.jar')) {
        if (entity.path.endsWith('-sources.jar')) continue;
        
        cpEntries.add(entity.absolute.path);
      }
    }

    return cpEntries.join(Platform.isWindows ? ';' : ':');
  }

  Future<Process> runMinecraft(
    String version, 
    String minecraftDir, 
    String javaPath,
    {String username = "BloretPlayer"}
  ) async {
    final cp = await buildClasspath(minecraftDir);
    final clientJar = p.join(minecraftDir, 'versions', version, '$version.jar');
    
    if (!await File(clientJar).exists()) {
      throw Exception("客户端 JAR 不存在: $clientJar");
    }

    final cpString = '$clientJar${Platform.isWindows ? ';' : ':'}$cp';
    
    final args = [
      '-cp', cpString,
      'net.minecraft.client.main.Main',
      '--username', username,
      '--version', version,
      '--gameDir', minecraftDir,
      '--assetsDir', p.join(minecraftDir, 'assets'),
      '--assetIndex', version,
      '--uuid', '00000000-0000-0000-0000-000000000000',
      '--accessToken', '0',
    ];

    return await Process.start(javaPath, args, workingDirectory: minecraftDir);
  }
}
