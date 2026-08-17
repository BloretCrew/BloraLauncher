import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/i18n.dart';
import '../core/logger.dart';
import '../main.dart';
import 'download_service.dart';
import 'launch_service.dart';

class ModpackService {
  static Future<void> importMrpack(
    File mrpackFile,
    String minecraftDir, {
    Function(String status, double progress)? onProgress,
  }) async {
    try {
      onProgress?.call("Reading modpack manifest...".tl, 0.05);
      final bytes = await mrpackFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final indexFile = archive.findFile('modrinth.index.json');
      if (indexFile == null) {
        throw Exception("modrinth.index.json not found in mrpack");
      }
      final indexData =
          jsonDecode(utf8.decode(indexFile.content)) as Map<String, dynamic>;

      if (indexData['game'] != 'minecraft') {
        throw Exception("Unsupported game type: ${indexData['game']}");
      }

      final String name =
          indexData['name'] ?? p.basenameWithoutExtension(mrpackFile.path);
      final String mcVersion = indexData['dependencies']['minecraft'];

      String? loaderType;
      String? loaderVersion;
      if (indexData['dependencies'].containsKey('fabric-loader')) {
        loaderType = 'fabric';
        loaderVersion = indexData['dependencies']['fabric-loader'];
      } else if (indexData['dependencies'].containsKey('forge')) {
        loaderType = 'forge';
        loaderVersion = indexData['dependencies']['forge'];
      } else if (indexData['dependencies'].containsKey('neoforge')) {
        loaderType = 'neoforge';
        loaderVersion = indexData['dependencies']['neoforge'];
      } else if (indexData['dependencies'].containsKey('quilt-loader')) {
        loaderType = 'quilt';
        loaderVersion = indexData['dependencies']['quilt-loader'];
      }

      String instanceName = name
          .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
          .replaceAll(' ', '_');
      if (instanceName.isEmpty) instanceName = "ImportedModpack";

      String uniqueName = instanceName;
      int count = 1;
      while (Directory(
        p.join(minecraftDir, "versions", uniqueName),
      ).existsSync()) {
        uniqueName = "${instanceName}_${count++}";
      }
      final instanceDir = Directory(
        p.join(minecraftDir, "versions", uniqueName),
      );
      await instanceDir.create(recursive: true);

      onProgress?.call("Installing Minecraft $mcVersion...".tl, 0.1);
      final versions = await DownloadService.instance.fetchAllVanillaVersions();
      final mcInfo = versions.firstWhere(
        (v) => v.id == mcVersion,
        orElse: () => throw Exception(
          "Minecraft version $mcVersion not found in manifest",
        ),
      );

      await DownloadService.instance.installVanilla(
        uniqueName,
        mcInfo.url,
        Directory(minecraftDir),
      );

      if (loaderType != null && loaderVersion != null) {
        onProgress?.call("Installing $loaderType $loaderVersion...".tl, 0.3);
        LoaderType type = LoaderType.vanilla;
        if (loaderType == 'fabric') {
          type = LoaderType.fabric;
        } else if (loaderType == 'forge') {
          type = LoaderType.forge;
        } else if (loaderType == 'neoforge') {
          type = LoaderType.neoforge;
        } else if (loaderType == 'quilt') {
          type = LoaderType.quilt;
        }

        await DownloadService.instance.installLoader(
          mcVersion,
          loaderVersion,
          type,
          Directory(minecraftDir),
          customVersionId: uniqueName,
        );
      }

      final files = indexData['files'] as List;
      if (files.isNotEmpty) {
        onProgress?.call(
          "Downloading ${files.length} modpack files...".tl,
          0.5,
        );
        final List<DownloadItem> downloadItems = [];
        for (var file in files) {
          final path = file['path'] as String;
          final downloads = file['downloads'] as List;
          if (downloads.isEmpty) continue;

          final url = downloads.first as String;
          final hashes = file['hashes'] as Map<String, dynamic>;
          final sha1 = hashes['sha1'];

          downloadItems.add(
            DownloadItem(
              id: p.basename(path),
              url: url,
              savePath: path,
              sha1: sha1,
            ),
          );
        }
        await DownloadService.instance.downloadBatch(
          downloadItems,
          instanceDir,
        );
      }

      // 5. Extract overrides
      onProgress?.call("Extracting overrides...".tl, 0.8);
      for (final file in archive) {
        String fileName = file.name.replaceAll('\\', '/');
        String? relPath;

        if (fileName.startsWith('overrides/')) {
          relPath = fileName.substring('overrides/'.length);
        } else if (fileName.startsWith('client-overrides/')) {
          relPath = fileName.substring('client-overrides/'.length);
        } else if (fileName.startsWith('files/')) {
          relPath = fileName.substring('files/'.length);
        }

        if (relPath != null && relPath.isNotEmpty && !fileName.endsWith('/')) {
          final targetFile = File(p.join(instanceDir.path, relPath));
          await targetFile.parent.create(recursive: true);
          await targetFile.writeAsBytes(file.content as List<int>);
        }
      }

      // 6. Write meta data
      final meta = {
        "source": "mrpack",
        "pack_name": name,
        "pack_version": indexData['versionId'],
        "minecraft": mcVersion,
        "loader": loaderType,
        "loader_version": loaderVersion,
        "imported_at": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "mrpack_file": p.basename(mrpackFile.path),
      };
      await File(
        p.join(instanceDir.path, "bloret-mrpack-meta.json"),
      ).writeAsString(jsonEncode(meta));

      // 7. Update .BLF.json
      await LaunchService.instance.updateBlJson(
        minecraftDir,
        uniqueName,
        fabricLoader: loaderType == 'fabric',
      );

      onProgress?.call("Import completed successfully!".tl, 1.0);
    } catch (e) {
      logger.error("Failed to import mrpack: $e", LogSource.system);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getMrpackMetadata(File mrpackFile) async {
    try {
      final bytes = await mrpackFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final indexFile = archive.findFile('modrinth.index.json');
      if (indexFile == null) return {};

      final indexData =
          jsonDecode(utf8.decode(indexFile.content)) as Map<String, dynamic>;

      // Try to extract icon
      String? iconPath;
      final iconFile =
          archive.findFile('icon.png') ??
          archive.findFile('icon.jpg') ??
          archive.findFile('overrides/icon.png');
      if (iconFile != null) {
        try {
          final tempDir = await getTemporaryDirectory();
          final localIcon = File(
            p.join(
              tempDir.path,
              'mrpack_icon_${DateTime.now().millisecondsSinceEpoch}.png',
            ),
          );
          await localIcon.writeAsBytes(iconFile.content as List<int>);
          iconPath = localIcon.path;
        } catch (_) {}
      }

      final List<String> mods = [];
      final List<String> resourcePacks = [];
      final List<String> shaderPacks = [];

      // 1. Files to be downloaded
      final files = indexData['files'] as List? ?? [];
      for (var file in files) {
        final path = (file['path'] as String? ?? "").replaceAll('\\', '/');
        final fileName = p.basename(path);
        if (path.startsWith('mods/')) {
          mods.add(fileName);
        } else if (path.startsWith('resourcepacks/')) {
          resourcePacks.add(fileName);
        } else if (path.startsWith('shaderpacks/')) {
          shaderPacks.add(fileName);
        }
      }

      // 2. Overrides (bundled files)
      for (final file in archive) {
        final path = file.name.replaceAll('\\', '/');
        if (path.endsWith('/')) continue;

        String? relPath;
        if (path.startsWith('overrides/')) {
          relPath = path.substring('overrides/'.length);
        } else if (path.startsWith('client-overrides/')) {
          relPath = path.substring('client-overrides/'.length);
        }

        if (relPath != null) {
          final fileName = p.basename(relPath);
          if (relPath.startsWith('mods/')) {
            mods.add(fileName);
          } else if (relPath.startsWith('resourcepacks/')) {
            resourcePacks.add(fileName);
          } else if (relPath.startsWith('shaderpacks/')) {
            shaderPacks.add(fileName);
          }
        }
      }

      return {
        'name': indexData['name'],
        'versionId': indexData['versionId'],
        'summary': indexData['summary'],
        'minecraft': indexData['dependencies']?['minecraft'],
        'iconPath': iconPath,
        'mods': mods.toSet().toList()..sort(),
        'resourcePacks': resourcePacks.toSet().toList()..sort(),
        'shaderPacks': shaderPacks.toSet().toList()..sort(),
      };
    } catch (e) {
      return {};
    }
  }
}
