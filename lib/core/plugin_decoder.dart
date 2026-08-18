import 'dart:math';
import 'package:bloret_launcher/core/grammer_candy.dart';
import 'package:dio/dio.dart';
import 'package:bloret_launcher/core/global.dart';
import '../main.dart';
import 'logger.dart';
import '../models/plugin.dart';

class PluginDecoder {
  final BloretPlugin plugin;
  final Map<String, dynamic> source;
  final Map<String, dynamic> runtimeValues = {};
  final Dio dio = Dio();
  final _random = Random();
  int _iterationCount = 0;

  PluginDecoder(this.plugin, this.source);

  bool _checkPermission(String permission) {
    if (!plugin.hasPermission(permission)) {
      showError("Plugin ${plugin.id} does not have permission: $permission");
      logger.error("[PluginDecoder] Plugin ${plugin.id} does not have permission: $permission", LogSource.system);
      return false;
    }
    return true;
  }

  Future<dynamic> request(Map<String, dynamic> rule, {dynamic input}) async {
    if (rule.containsKey('way')) {
      return _executeMethod(rule, source, input: input);
    }

    if (!_checkPermission("net.http")) throw Exception("Permission denied: net.http");;

    final urlStr = rule['url']?.toString() ?? "";
    dynamic currentData = input;

    if (urlStr.isNotEmpty) {
      final url = _resolveValue(urlStr, source, input: input);
      final method = (rule['method'] ?? 'GET').toString().toUpperCase();
      final headers = _decodeHeaderOrData(rule, isHeader: true);
      final data = _decodeHeaderOrData(rule, isHeader: false, bodyKey: 'data');

      await Future.delayed(Duration(milliseconds: 50 + _random.nextInt(101)));

      try {
        Response response;
        if (method == 'POST') {
          response = await dio.post(url, data: data, options: Options(headers: headers, contentType: Headers.formUrlEncodedContentType));
        } else {
          response = await dio.get(url, queryParameters: data, options: Options(headers: headers));
        }
        currentData = response.data;
      } catch (e) {
        logger.error("[PluginDecoder] Request Error (${plugin.id}): $e", LogSource.network);
        return null;
      }
    }

    if (rule.containsKey('parse')) {
      return _resolveValue(rule['parse'], source, input: currentData);
    }
    return currentData;
  }

  Map<String, String> _decodeHeaderOrData(Map<String, dynamic> json, {bool isHeader = true, String bodyKey = ""}) {
    final key = isHeader ? 'header' : bodyKey;
    if (json[key] == null) return {};
    var raw = Map<String, dynamic>.from(json[key]);
    Map<String, String> resolved = {};
    raw.forEach((k, v) => resolved[k] = _resolveValue(v, json).toString());
    return resolved;
  }

  dynamic _resolveValue(dynamic value, Map<String, dynamic> json, {dynamic input = ""}) {
    if (_iterationCount++ > 1000) throw Exception("Too many iterations in PluginDecoder!");
    if (value == null) return "";

    if (value is String && RegExp(r'^\$[a-zA-Z0-9_]+$').hasMatch(value)) {
      final key = value.substring(1);
      return runtimeValues[key] ?? value;
    }

    if (value.toString() == "@input") return input;
    if (value is Map) return _executeMethod(value as Map<String, dynamic>, json, input: input);

    String str = value.toString();
    if (str.contains('*') || str.contains(r'$') || str.contains('@') || str.contains('&')) {
      return str.replaceAllMapped(RegExp(r'([*&$@])([a-zA-Z0-9_]+)'), (match) {
        final prefix = match.group(1);
        final key = match.group(2)!;
        if (prefix == '@' && key == "input") return input.toString();
        switch (prefix) {
          case '&': return _getConstants(key);
          case r'$': return runtimeValues[key]?.toString() ?? match.group(0)!;
          case '@': return json[key]?.toString() ?? match.group(0)!;
          case '*': 
            if (key == "pluginId") return plugin.id;
            if (key == "pluginVersion") return plugin.version;
            return match.group(0)!;
          default: return match.group(0)!;
        }
      });
    }
    return str;
  }

  String _getConstants(String key) {
    return switch (key) {
      "ua_bl" => "BloraLauncher Plugin Engine",
      "ua" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      "time" => DateTime.now().millisecondsSinceEpoch.toString(),
      _ => ""
    };
  }

  dynamic _executeMethod(Map<String, dynamic> method, Map<String, dynamic> json, {dynamic input = ""}) {
    final way = method['way'] as String;
    if (way.isEmpty) return input;
    final cmd = way.startsWith('#') ? way.substring(1) : way;

    switch (cmd) {
      case "input": return _resolveValue(method['value'], json, input: input);
      case "json_extract":
        if (input is Map) return input[method['key']];
        if (input is List && method['index'] != null) return input[method['index']];
        return input;
      case "regex_extract":
        var match = RegExp(method['regex'].toString(), dotAll: true).firstMatch(input.toString());
        return match?.group(method['group'] ?? 1) ?? "";
      case "stringMerge":
        return (method['values'] as List).map((v) => _resolveValue(v, json, input: input)).join("");
      case "show_notification":
        _checkPermission("notify.send");
        final msg = _resolveValue(method['value'], json, input: input);
        noticeManager.showInfo(globalShellContext, msg.toString());
        return input;
      default: return input;
    }
  }

  Future<dynamic> runFlow(List<dynamic> steps, {dynamic input}) async {
    _iterationCount = 0;
    dynamic result = input;
    try {
      for (final step in steps) {
        if (step is! Map) continue;

        if (step['condition'] != null) {
          final cond = step['condition'];
          if (cond['contains'] != null && !result.toString().contains(cond['contains'])) continue;
        }

        if (step['rule'] != null) {
          final rule = source[step['rule']];
          if (rule != null) {
            result = await request(rule, input: result);
          }
        }

        if (step['save'] != null) {
          runtimeValues[step['save']] = result;
        }
      }
    } catch (e) {
      showError("Run flow error: ${e.toString().split(":")[1]}");
      logger.error("[PluginDecoder] Run flow error: $e", LogSource.system);
    }
    return result;
  }
}
