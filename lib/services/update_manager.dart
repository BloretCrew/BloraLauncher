import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:archive/archive_io.dart';
import 'package:bloret_launcher/core/source_decoder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/i18n.dart';
import '../main.dart';
import '../tools/isolate.dart';
import 'config_service.dart';

const currentVersion = "0.1.0";

class UpdateInfo {
  final String version;
  final String? hash;
  final String? id;
  final String? name;

  UpdateInfo({required this.version, this.hash, this.id, this.name});
}

class UpdateManager {
  static final UpdateManager instance = UpdateManager._();
  late dynamic _source;
  UpdateManager._();

  final String shareId = "b00tcosk3i";
  final String password = "axor";

  static Future<Map<String, dynamic>> decodeJson(String raw) async {
    return jsonDecode(raw);
  }

  Future<UpdateManager> init() async {
    final supportDir = await getSupportData();
    final file1 = File(p.join(supportDir.path, "source_api.json"));
    late final String sourceFileData;
    if (!await file1.exists()) {
      sourceFileData = await rootBundle.loadString("assets/source_api.json");
    } else {
      sourceFileData = await file1.readAsString();
    }
    _source = await runIsolate(decodeJson, sourceFileData);
    return this;
  }

  Future<UpdateInfo?> checkUpdate() async {
    final decoder = SourceDecoder(_source, null);
    decoder.runtimeValues['shareId'] = shareId;
    decoder.runtimeValues['password'] = password;

    try {
      final dynamic flowResult = await decoder.runFlow("folder_parse");
      
      List files = [];
      if (flowResult is Map && flowResult.containsKey('text')) {
        files = flowResult['text'] is List ? flowResult['text'] : [];
      } else if (flowResult is List) {
        files = flowResult;
      }

      final List<UpdateInfo> updates = [];
      for (var f in files) {
        dynamic file = f;
        String? name;
        String? id;

        if (file is Map) {
          name = (file['name_all'] ?? file['name'])?.toString();
          id = file['id']?.toString();
        } else if (file is List && file.length >= 2) {
          id = file[0]?.toString();
          name = file[1]?.toString();
        }

        if (name != null && name.endsWith('.zip')) {
          if (Platform.isLinux && !name.startsWith('linux_patch_')) continue;
          
          final info = _extractInfo(name);
          updates.add(UpdateInfo(
            version: info['version']!,
            hash: info['hash'],
            id: id,
            name: name,
          ));
        }
      }

      if (updates.isEmpty) return null;

      updates.sort((a, b) => _compareVersion(b.version, a.version));

      final latest = updates.first;
      final localVersion = await getLocalVersion();

      if (_shouldUpdate(localVersion, latest.version)) {
        return latest;
      }
    } catch (e) {
      noticeManager.show(null, message: "${"Check Update Failed".tl}: $e", icon: Icons.error);
    }
    return null;
  }

  Map<String, String?> _extractInfo(String filename) {
    final versionMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(filename);
    final hashMatch = RegExp(r'_([a-fA-F0-9]{8,64})').firstMatch(filename);
    
    return {
      'version': versionMatch?.group(1) ?? currentVersion,
      'hash': hashMatch?.group(1),
    };
  }

  int _compareVersion(String v1, String v2) {
    final list1 = v1.split('.').map(int.parse).toList();
    final list2 = v2.split('.').map(int.parse).toList();
    for (int i = 0; i < 3; i++) {
      if (list1[i] > list2[i]) return 1;
      if (list1[i] < list2[i]) return -1;
    }
    return 0;
  }

  bool _verifyHash(List<int> bytes, String? expectedHash) {
    if (expectedHash == null || expectedHash.isEmpty) return true; 
    final actualHash = sha256.convert(bytes).toString();
    return actualHash.startsWith(expectedHash.toLowerCase());
  }

  bool _isMajorUpdate(String local, String remote) {
    final l = local.split('.').map(int.parse).toList();
    final r = remote.split('.').map(int.parse).toList();
    if (r[0] > l[0]) return true;
    if (r[1] > l[1]) return true;
    return false;
  }

  Future<bool> checkAndApplyUpdate({BuildContext? context, Function(double)? onProgress}) async {
    final update = await checkUpdate();
    if (update == null) return false;
    
    final localVersion = await getLocalVersion();
    final isMajor = _isMajorUpdate(localVersion, update.version);

    if (context?.mounted == true) {
      noticeManager.show(context, 
        message: "${"Downloading".tl}${isMajor ? "Version".tl : "Patch".tl}${"Update".tl} ${update.version}...",
        icon: Icons.download
      );
    }

    final decoder = SourceDecoder(_source, null);
    decoder.runtimeValues['shareId'] = update.id;

    try {
      final dynamic fileResult = await decoder.runFlow("file_parse");
      if (fileResult.toString() == "https://developer2.lanrar.com/file/0") {
        if (context?.mounted == true) noticeManager.show(context, message: "Cannot get download link".tl, icon: Icons.error);
        return false;
      }
      String? downloadUrl;
      
      if (fileResult is Map) {
        downloadUrl = fileResult['url']?.toString();
      } else if (fileResult is String) {
        downloadUrl = fileResult;
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        if (context?.mounted == true) noticeManager.show(context, message: "Cannot get download link".tl, icon: Icons.error);
        return false;
      }

      final dio = Dio();
      final options = Options(
        headers: {
          "user-agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36 Edg/150.0.0.0",
          "accept": "*/*",
          "accept-language": "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6",
          "referer": "https://wwbug.lanzn.com/",
        },
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 5),
        responseType: ResponseType.bytes,
      );

      final response = await dio.get(
        downloadUrl, 
        options: options,
        onReceiveProgress: (count, total) {
          if (total != -1) {
            onProgress?.call(count / total);
          } else {
            onProgress?.call(1.0 + (count / (1024 * 1024)));
          }
        },
      );
      
      final List<int> bytes = response.data;

      if (!_verifyHash(bytes, update.hash)) {
        final header = String.fromCharCodes(bytes.take(20));
        if (header.contains("<!DOCTYPE") || header.contains("<html")) {
          if (context?.mounted == true) noticeManager.show(context, message: "Download Failed: WebRTC link unavailable or need auth".tl, icon: Icons.error);
        } else {
          if (context?.mounted == true) noticeManager.show(context, message: "File check failed: Hash is not match".tl, icon: Icons.error);
        }
        return false;
      }

      if (isMajor) {
        if (Platform.isWindows) {
          if (!context!.mounted) return false;
          return await _applyMajorUpdateWindows(bytes, update, context);
        } else if (Platform.isLinux) {
          if (!context!.mounted) return false;
          return await _applyMajorUpdateLinux(bytes, update, context);
        }
      }

      final appExePath = Platform.resolvedExecutable;
      final appDir = p.dirname(appExePath);

      if (Platform.isLinux) {
        // Linux 热更新逻辑
        final targetPath = p.join(appDir, 'lib', 'libapp.so');
        final file = File(targetPath);
        await file.parent.create(recursive: true);

        if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
          try {
            final archive = ZipDecoder().decodeBytes(bytes);
            final soFile = archive.findFile('libapp.so') ?? archive.files.first;
            await file.writeAsBytes(soFile.content as List<int>);
          } catch (e) {
            if (context?.mounted == true) noticeManager.show(context, message: "Unzip failed: $e", icon: Icons.error);
            return false;
          }
        } else {
          await file.writeAsBytes(bytes);
        }
      } else {
        final supportDir = await getSupportData();
        final targetPath = p.join(supportDir.parent.path, 'data', 'app.so');
        
        final file = File(targetPath);
        await file.parent.create(recursive: true);

        if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
          try {
            final archive = ZipDecoder().decodeBytes(bytes);
            final soFile = archive.findFile('app.so') ?? archive.files.first;
            await file.writeAsBytes(soFile.content as List<int>);
          } catch (e) {
            if (context?.mounted == true) noticeManager.show(context, message: "Unzip failed: $e", icon: Icons.error);
            return false;
          }
        } else {
          await file.writeAsBytes(bytes);
        }
      }
      
      if (context?.mounted == true) noticeManager.show(context, message: "${"Hot Update Patch".tl} ${update.version} ${"Applied, restart to take effect".tl}", icon: Icons.check_circle);
      return true;
    } catch (e) {
      if (context?.mounted == true) noticeManager.show(context, message: "${"Update failed".tl}: $e", icon: Icons.error);
      return false;
    }
  }

  Future<bool> _applyMajorUpdateWindows(List<int> bytes, UpdateInfo update, BuildContext? context) async {
    try {
      final appExePath = Platform.resolvedExecutable;
      final appDir = p.dirname(appExePath);
      final stagingDir = Directory(p.join(appDir, 'update_staging'));
      
      if (await stagingDir.exists()) await stagingDir.delete(recursive: true);
      await stagingDir.create(recursive: true);

      final archive = ZipDecoder().decodeBytes(bytes);
      final List<String> filesToDelete = [];

      for (final file in archive) {
        final filename = file.name;
        if (filename.endsWith('/')) {
          await Directory(p.join(stagingDir.path, filename)).create(recursive: true);
          continue;
        }
        
        final data = file.content as List<int>;
        if (filename.endsWith('.deleted')) {
          final targetToRemove = filename.substring(0, filename.length - 8);
          filesToDelete.add(targetToRemove);
          continue; 
        }

        final outFile = File(p.join(stagingDir.path, filename));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(data);
      }

      final batchFile = File(p.join(appDir, 'updater.bat'));
      final exeName = p.basename(appExePath);
      
      final StringBuffer script = StringBuffer();
      script.writeln('@echo off');
      script.writeln('setlocal');
      script.writeln('echo Waiting for application to exit...');
      script.writeln(':wait_loop');
      script.writeln('tasklist /FI "IMAGENAME eq $exeName" 2>NUL | find /I /N "$exeName">NUL');
      script.writeln('if "%ERRORLEVEL%"=="0" (');
      script.writeln('    timeout /t 1 /nobreak >nul');
      script.writeln('    goto wait_loop');
      script.writeln(')');

      script.writeln('echo Applying updates...');
      for (final f in filesToDelete) {
        script.writeln('if exist "$f" del /f /q "$f"');
      }

      script.writeln('xcopy /s /e /y /q "update_staging\\*" "."');
      script.writeln('rmdir /s /q "update_staging"');
      script.writeln('start "" "$exeName"');
      script.writeln('del "%~f0" & exit');

      await batchFile.writeAsString(script.toString(), encoding: const Utf8Codec(allowMalformed: true));

      if (context?.mounted == true) {
        showDialog(
          context: context!,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text("Update ready".tl),
            content: Text("${"Main app update".tl} ${update.version} ${"Ready".tl}。\n${"Click 'Restart Now' to close the app and completed installation".tl}"),
            actions: [
              TextButton(
                onPressed: () {
                  Process.run('cmd', ['/c', 'start', '', batchFile.path], workingDirectory: appDir);
                  exit(0);
                }, 
                child: Text("Restart Now".tl)
              ),
            ],
          ),
        );
      }
      return true;
    } catch (e) {
      if (context?.mounted == true) noticeManager.show(context, message: "${"Main app update failed".tl}: $e", icon: Icons.error);
      return false;
    }
  }

  Future<bool> _applyMajorUpdateLinux(List<int> bytes, UpdateInfo update, BuildContext? context) async {
    try {
      final appExePath = Platform.resolvedExecutable;
      final appDir = p.dirname(appExePath);
      final stagingDir = Directory(p.join(appDir, 'update_staging'));
      
      if (await stagingDir.exists()) await stagingDir.delete(recursive: true);
      await stagingDir.create(recursive: true);

      final archive = ZipDecoder().decodeBytes(bytes);
      final List<String> filesToDelete = [];

      for (final file in archive) {
        final filename = file.name;
        if (filename.endsWith('/')) {
          await Directory(p.join(stagingDir.path, filename)).create(recursive: true);
          continue;
        }
        
        final data = file.content as List<int>;
        if (filename.endsWith('.deleted')) {
          final targetToRemove = filename.substring(0, filename.length - 8);
          filesToDelete.add(targetToRemove);
          continue; 
        }

        final outFile = File(p.join(stagingDir.path, filename));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(data);
      }

      final shellScript = File(p.join(appDir, 'updater.sh'));
      final exeName = p.basename(appExePath);
      
      final StringBuffer script = StringBuffer();
      script.writeln('#!/bin/bash');
      script.writeln('echo "Waiting for $exeName to exit..."');
      script.writeln('while pgrep -x "$exeName" > /dev/null; do sleep 1; done');

      script.writeln('echo "Applying updates..."');
      for (final f in filesToDelete) {
        script.writeln('rm -f "$f"');
      }

      script.writeln('cp -r update_staging/* .');
      script.writeln('rm -rf update_staging');
      script.writeln('chmod +x "$exeName"');
      script.writeln('nohup "./$exeName" > /dev/null 2>&1 &');
      script.writeln('rm -- "\$0"');

      await shellScript.writeAsString(script.toString());
      await Process.run('chmod', ['+x', shellScript.path]);

      if (context?.mounted == true) {
        showDialog(
          context: context!,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text("Update ready".tl),
            content: Text("${"Linux Main app update".tl} ${update.version} ${"Ready".tl}。\n${"Click 'Restart Now' to close the app and completed installation".tl}"),
            actions: [
              TextButton(
                onPressed: () {
                  Process.start('sh', [shellScript.path], workingDirectory: appDir, mode: ProcessStartMode.detached);
                  exit(0);
                }, 
                child: Text("Restart Now".tl)
              ),
            ],
          ),
        );
      }
      return true;
    } catch (e) {
      if (context?.mounted == true) noticeManager.show(context, message: "${"Linux Main app update failed".tl}: $e", icon: Icons.error);
      return false;
    }
  }

  bool _shouldUpdate(String localVersion, String remoteVersion) {
    return _compareVersion(remoteVersion, localVersion) > 0;
  }

  Future<String> getLocalVersion() async {
    return currentVersion;
  }
}
