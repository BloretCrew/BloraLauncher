import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:archive/archive_io.dart';
import 'package:bloret_launcher/core/source_decoder.dart';
import 'package:bloret_launcher/services/notice_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../tools/isolate.dart';
import 'config_service.dart';

const currentVersion = "0.0.4";

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
      noticeManager.show(null, message: "检查更新失败: $e", icon: Icons.error);
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

  Future<bool> checkAndApplyUpdate({BuildContext? context, Function(double)? onProgress}) async {
    final update = await checkUpdate();
    if (update == null) return false;
    
    if (context?.mounted == true) noticeManager.show(context, message: "正在下载新版本 ${update.version}...", icon: Icons.download);

    final decoder = SourceDecoder(_source, null);
    decoder.runtimeValues['shareId'] = update.id;

    try {
      final dynamic fileResult = await decoder.runFlow("file_parse");
      if (fileResult.toString() == "https://developer2.lanrar.com/file/0") {
        if (context?.mounted == true) noticeManager.show(context, message: "无法获取下载链接", icon: Icons.error);
        return false;
      }
      String? downloadUrl;
      
      if (fileResult is Map) {
        downloadUrl = fileResult['url']?.toString();
      } else if (fileResult is String) {
        downloadUrl = fileResult;
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        if (context?.mounted == true) noticeManager.show(context, message: "无法获取下载链接", icon: Icons.error);
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
          if (context?.mounted == true) noticeManager.show(context, message: "下载失败：网盘链路已失效或需要验证", icon: Icons.error);
        } else {
          if (context?.mounted == true) noticeManager.show(context, message: "文件校验失败：Hash 不匹配", icon: Icons.error);
        }
        return false;
      }

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
          if (context?.mounted == true) noticeManager.show(context, message: "解压失败: $e", icon: Icons.error);
          return false;
        }
      } else {
        await file.writeAsBytes(bytes);
      }
      
      await _saveLocalVersion(update.version);
      if (context?.mounted == true) noticeManager.show(context, message: "热更新补丁 ${update.version} 已应用，重启生效", icon: Icons.check_circle);
      return true;
    } catch (e) {
      if (context?.mounted == true) noticeManager.show(context, message: "执行更新失败: $e", icon: Icons.error);
      return false;
    }
  }

  bool _shouldUpdate(String localVersion, String remoteVersion) {
    return _compareVersion(remoteVersion, localVersion) > 0;
  }

  Future<String> getLocalVersion() async {
    try {
      final supportDir = await getSupportData();
      final file = File(p.join(supportDir.path, 'data', 'version.txt'));
      if (await file.exists()) return await file.readAsString();
    } catch (_) {}
    return currentVersion;
  }

  Future<void> _saveLocalVersion(String version) async {
    final supportDir = await getSupportData();
    final file = File(p.join(supportDir.path, 'data', 'version.txt'));
    await file.parent.create(recursive: true);
    await file.writeAsString(version);
  }
}
