import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:bloret_launcher/core/global.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher_string.dart';
import '../main.dart';
import 'logger.dart';
import '../models/plugin.dart';
import '../services/config_service.dart';

class PluginDecoder {
  final BloretPlugin plugin;
  final Map<String, dynamic> source;
  final Map<String, dynamic> runtimeValues;
  final Dio dio = Dio();
  final _random = Random();
  int _iterationCount = 0;

  PluginDecoder(this.plugin, this.source) : runtimeValues = plugin.runtimeValues;

  bool _checkPermission(String permission) {
    if (!plugin.hasPermission(permission)) {
      if (globalShellContext != null) {
        noticeManager.showError(globalShellContext, "Plugin ${plugin.id} does not have permission: $permission");
      }
      logger.error("[PluginDecoder] Plugin ${plugin.id} does not have permission: $permission", LogSource.system);
      return false;
    }
    return true;
  }

  Future<dynamic> request(Map<String, dynamic> rule, {dynamic input}) async {
    if (rule.containsKey('way')) {
      return _executeMethod(rule, source, input: input);
    }

    if (rule.containsKey('flow')) {
      return await runFlow(rule['flow'] as List, input: input);
    }

    if (!_checkPermission("net.http")) throw Exception("Permission denied: net.http");

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

  // Hello, guys.
  // This is DSL's core.
  // The most important part is the FEC(Format Explain Character)
  /// Format Explain Character (FEC) usage
  ///
  /// `$` is used to access runtime values
  ///
  /// `%` is used to access persistent values
  ///
  /// `~` is used to access global values
  ///
  /// `*` is used to access extra values
  ///
  /// `@` is used to access input
  ///
  /// `^` is used to ignore the resolvation
  dynamic _resolveValue(dynamic value, Map<String, dynamic> json, {dynamic input = ""}) {
    if (_iterationCount++ > 1000) throw Exception("Too many iterations in PluginDecoder!");
    if (value == null) return "";

    if (value is String && value.startsWith('^')) {
      return value.substring(1);
    }

    if (value is String && RegExp(r'^[*&$@%~][a-zA-Z0-9_\.\[\]]+$').hasMatch(value)) {
      final prefix = value[0];
      final path = value.substring(1);
      
      dynamic base;
      switch (prefix) {
        case r'$': base = runtimeValues; break;
        case '%': base = plugin.persistentValues; break;
        case '~': base = pluginRuntimeGlobalStore; break;
        case '>': base = plugin.pluginSettingsValues; break;
        case '&': return _getConstants(path);
        case '*': base = source['extra'] ?? {}; break;
        case '@': base = input; break;
      }

      if (path.isEmpty) return base;

      final firstPartEnd = _getFirstPartEnd(path);
      if (firstPartEnd == -1) {
        if (base is Map) return base[path] ?? value;
        return _extractJsonByPath(base, path) ?? value;
      } else {
        final varName = path.substring(0, firstPartEnd);
        final subPath = path.substring(firstPartEnd).startsWith('.') ? path.substring(firstPartEnd + 1) : path.substring(firstPartEnd);
        final baseValue = (base is Map) ? base[varName] : base;
        return _extractJsonByPath(baseValue, subPath) ?? value;
      }
    }

    if (value.toString() == "@input") return input;
    if (value is Map) return _executeMethod(value as Map<String, dynamic>, json, input: input);

    String str = value.toString();
    if (str.contains('*') || str.contains(r'$') || str.contains('@') || str.contains('&') || str.contains('%') || str.contains('~') || str.contains('>')) {
      return str.replaceAllMapped(RegExp(r'([*&$@%~>])([a-zA-Z0-9_\.\[\]]+( [a-zA-Z0-9_\.\[\]]+)*)'), (match) {
        final prefix = match.group(1);
        final path = match.group(2)!;
        if (prefix == '@' && path == "input") return input.toString();

        dynamic base;
        switch (prefix) {
          case '&': return _getConstants(path).toString();
          case r'$': base = runtimeValues; break;
          case '%': base = plugin.persistentValues; break;
          case '~': base = pluginRuntimeGlobalStore; break;
          case '>': base = plugin.pluginSettingsValues; break;
          case '*': base = source['extra'] ?? {}; break;
          case '@': base = input; break;
          default: return match.group(0)!;
        }

        final firstPartEnd = _getFirstPartEnd(path);
        if (firstPartEnd == -1) {
          if (base is Map) return base[path]?.toString() ?? match.group(0)!;
          return _extractJsonByPath(base, path)?.toString() ?? match.group(0)!;
        }
        final varName = path.substring(0, firstPartEnd);
        final subPath = path.substring(firstPartEnd).startsWith('.') ? path.substring(firstPartEnd + 1) : path.substring(firstPartEnd);
        final baseValue = (base is Map) ? base[varName] : base;
        return _extractJsonByPath(baseValue, subPath)?.toString() ?? match.group(0)!;
      });
    }
    return str;
  }

  int _getFirstPartEnd(String path) {
    final dot = path.indexOf('.');
    final bracket = path.indexOf('[');
    if (dot == -1 && bracket == -1) return -1;
    if (dot != -1 && bracket != -1) return min(dot, bracket);
    return max(dot, bracket);
  }

  String _getConstants(String key) {
    return switch (key) {
      "ua_bl" => "BloraLauncher Plugin Engine",
      "ua" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      "time" => DateTime.now().millisecondsSinceEpoch.toString(),
      _ => ""
    };
  }

  Future<Directory> _getPluginWorkplaceDir() async {
    final supportDir = await getSupportData();
    final dir = Directory(p.join(supportDir.path, 'plugins', plugin.id, 'workplace'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _getPluginCacheDir() async {
    final supportDir = await getSupportData();
    final dir = Directory(p.join(supportDir.path, 'plugins', plugin.id, 'cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  int _parseToInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    final str = value.toString();
    final d = double.tryParse(str);
    return d?.toInt() ?? int.tryParse(str) ?? 0;
  }

  dynamic _executeMethod(Map<String, dynamic> method, Map<String, dynamic> json, {dynamic input = ""}) {
    final way = method['way'] as String;
    if (way.isEmpty) return input;
    final cmd = way.startsWith('#') ? way.substring(1) : way;

    dynamic targetInput = input;
    if (method.containsKey('input')) {
      targetInput = _resolveValue(method['input'], json, input: input);
    }
    
    if (targetInput is String && (targetInput.startsWith('{') || targetInput.startsWith('['))) {
      try {
        targetInput = jsonDecode(targetInput);
      } catch (_) {}
    }

    switch (cmd) {
      case "input": return _resolveValue(method['value'], json, input: targetInput);
      case "json_extract":
        final path = _resolveValue(method['key'] ?? method['path'], json, input: targetInput).toString();
        return _extractJsonByPath(targetInput, path);
      case "json_decode":
        if (targetInput is String) {
          try { return jsonDecode(targetInput); } catch (_) { return targetInput; }
        }
        return targetInput;
      case "regex_extract":
        var match = RegExp(method['regex'].toString(), dotAll: true).firstMatch(targetInput.toString());
        return match?.group(method['group'] ?? 1) ?? "";
      case "stringMerge":
        return (method['values'] as List).map((v) => _resolveValue(v, json, input: targetInput)).join("");
      case "show_notification":
        _checkPermission("notify.send");
        final msg = _resolveValue(method['value'], json, input: targetInput);
        noticeManager.showInfo(globalShellContext, msg.toString());
        return targetInput;
      case "log":
        final msg = _resolveValue(method['value'], json, input: targetInput);
        logger.info("[Plugin:${plugin.id}] $msg", LogSource.tool);
        return targetInput;
      case "open_url":
        final url = _resolveValue(method['value'] ?? method['url'], json, input: targetInput).toString();
        if (url.isNotEmpty) launchUrlString(url);
        return targetInput;
      case "write_file":
        if (_checkPermission("fs.datapath")) {
          _writeFileAction(method, json, targetInput, isCache: false);
        }
        return targetInput;
      case "read_file":
        if (_checkPermission("fs.datapath")) {
          return _readFileAction(method, json, targetInput, isCache: false);
        }
        return null;
      case "write_cache":
        _writeFileAction(method, json, targetInput, isCache: true);
        return targetInput;
      case "read_cache":
        return _readFileAction(method, json, targetInput, isCache: true);
      case "set_value":
      case "set_persistent":
      case "set_global":
        final rawKey = _resolveValue(method['key'], json, input: targetInput).toString();
        dynamic value = _resolveValue(method['value'], json, input: targetInput);
        
        Map<String, dynamic> store = runtimeValues;
        String key = rawKey;
        if (cmd == "set_persistent" || rawKey.startsWith('%')) {
          store = plugin.persistentValues;
          if (key.startsWith('%')) key = key.substring(1);
        } else if (cmd == "set_global" || rawKey.startsWith('~')) {
          store = pluginRuntimeGlobalStore;
          if (key.startsWith('~')) key = key.substring(1);
        } else if (rawKey.startsWith(r'$')) {
          key = key.substring(1);
        }
        
        if (value is num || (value is String && double.tryParse(value) != null)) {
          double val = double.tryParse(value.toString()) ?? 0.0;
          if (method.containsKey('min')) val = max(val, double.tryParse(_resolveValue(method['min'], json, input: targetInput).toString()) ?? -double.infinity);
          if (method.containsKey('max')) val = min(val, double.tryParse(_resolveValue(method['max'], json, input: targetInput).toString()) ?? double.infinity);
          value = val;
        }

        store[key] = value;
        return value;
      case "add":
        final rawKey = _resolveValue(method['key'], json, input: targetInput).toString();
        final amount = double.tryParse(_resolveValue(method['value'], json, input: targetInput).toString()) ?? 1.0;
        
        Map<String, dynamic> targetStore = runtimeValues;
        String key = rawKey;
        if (rawKey.startsWith('%')) { targetStore = plugin.persistentValues; key = rawKey.substring(1); }
        else if (rawKey.startsWith('~')) { targetStore = pluginRuntimeGlobalStore; key = rawKey.substring(1); }
        else if (rawKey.startsWith('>')) { targetStore = plugin.pluginSettingsValues; key = rawKey.substring(1); }
        else if (rawKey.startsWith(r'$')) { key = rawKey.substring(1); }

        double current = double.tryParse(targetStore[key]?.toString() ?? "0") ?? 0.0;
        double result = current + amount;

        if (method.containsKey('min')) result = max(result, double.tryParse(_resolveValue(method['min'], json, input: targetInput).toString()) ?? -double.infinity);
        if (method.containsKey('max')) result = min(result, double.tryParse(_resolveValue(method['max'], json, input: targetInput).toString()) ?? double.infinity);

        targetStore[key] = result;
        return targetStore[key];
      case "json_map":
        final items = targetInput is List ? targetInput : [];
        final limit = _parseToInt(_resolveValue(method['limit'], json, input: targetInput));
        final template = method['template'] as Map<String, dynamic>;
        
        final resultList = [];
        final actualLimit = limit > 0 ? limit : items.length;
        for (var i = 0; i < items.length && i < actualLimit; i++) {
          final item = items[i];
          final mappedItem = {};
          template.forEach((k, v) {
            mappedItem[k] = _resolveValue(v, json, input: item);
          });
          resultList.add(mappedItem);
        }
        return resultList;
      case "sub_list":
        if (targetInput is! List) return [];
        int start = _parseToInt(_resolveValue(method['start'] ?? 0, json, input: targetInput));
        int? endVal = method.containsKey('end') ? _parseToInt(_resolveValue(method['end'], json, input: targetInput)) : null;
        int? length = method.containsKey('length') ? _parseToInt(_resolveValue(method['length'], json, input: targetInput)) : null;
        
        int total = targetInput.length;
        if (total == 0) return [];

        start = start.clamp(0, total);
        int end = total;
        if (length != null) {
          end = (start + length).clamp(0, total);
        } else if (endVal != null) {
          end = endVal.clamp(start, total);
        }

        return targetInput.sublist(start, end);
      case "get_length":
        if (targetInput is List) return targetInput.length;
        if (targetInput is Map) return targetInput.length;
        if (targetInput is String) return targetInput.length;
        return 0;
      case "modulo":
        final val = double.tryParse(_resolveValue(method['value'], json, input: targetInput).toString()) ?? 0.0;
        final mod = double.tryParse(_resolveValue(method['mod'], json, input: targetInput).toString()) ?? 1.0;
        return val % mod;
      case "math":
        final expression = _resolveValue(method['value'], json, input: targetInput).toString();
        if (expression.contains('-')) {
          final parts = expression.split('-').map((e) => double.tryParse(e.trim()) ?? 0.0).toList();
          if (parts.length == 2) return parts[0] - parts[1];
        }
        if (expression.contains('+')) {
          final parts = expression.split('+').map((e) => double.tryParse(e.trim()) ?? 0.0).toList();
          if (parts.length == 2) return parts[0] + parts[1];
        }
        return 0.0;
      default: return targetInput;
    }
  }

  dynamic _extractJsonByPath(dynamic data, String path) {
    if (path.isEmpty || data == null) return data;
    final parts = path.split('.');
    dynamic current = data;
    for (var part in parts) {
      if (current == null) return null;

      if (part.contains('[') && part.endsWith(']')) {
        final bracketIdx = part.indexOf('[');
        final key = part.substring(0, bracketIdx);
        final indexStr = part.substring(bracketIdx + 1, part.length - 1);

        int index = _parseToInt(indexStr);
        
        if (key.isNotEmpty) {
          if (current is Map) {
            current = current[key];
          } else {
            return null;
          }
        }
        
        if (current is List) {
          if (current.isEmpty) return null;
          index = index % current.length;
          if (index < 0) index += current.length;
          current = current[index];
        } else {
          return null;
        }
      } else {
        if (current is Map) {
          current = current[part];
        } else {
          return null;
        }
      }
    }
    return current;
  }

  Future<void> _writeFileAction(Map<String, dynamic> method, Map<String, dynamic> json, dynamic input, {required bool isCache}) async {
    final fileName = _resolveValue(method['file'] ?? method['name'], json, input: input).toString();
    final content = _resolveValue(method['value'] ?? method['content'], json, input: input);
    if (fileName.isEmpty) return;
    
    final dir = isCache ? await _getPluginCacheDir() : await _getPluginWorkplaceDir();
    final file = File(p.join(dir.path, fileName));
    String stringContent = content is Map || content is List ? jsonEncode(content) : content.toString();
    await file.writeAsString(stringContent);
  }

  Future<dynamic> _readFileAction(Map<String, dynamic> method, Map<String, dynamic> json, dynamic input, {required bool isCache}) async {
    final fileName = _resolveValue(method['file'] ?? method['name'], json, input: input).toString();
    if (fileName.isEmpty) return null;

    final dir = isCache ? await _getPluginCacheDir() : await _getPluginWorkplaceDir();
    final file = File(p.join(dir.path, fileName));
    if (!await file.exists()) return null;

    final content = await file.readAsString();
    try {
      return jsonDecode(content);
    } catch (_) {
      return content;
    }
  }

  Future<dynamic> runFlow(List<dynamic> steps, {dynamic input}) async {
    _iterationCount = 0;
    dynamic result = input;
    try {
      for (final step in steps) {
        if (step is! Map) continue;
        final stepMap = Map<String, dynamic>.from(step);

        if (stepMap['condition'] != null) {
          final cond = stepMap['condition'];
          if (cond['contains'] != null && !result.toString().contains(cond['contains'])) continue;
        }

        if (stepMap.containsKey('way')) {
          result = await _executeMethod(stepMap, source, input: result);
        } else if (stepMap['rule'] != null) {
          final ruleName = stepMap['rule'].toString();
          dynamic rule = source[ruleName] ?? source['flows']?[ruleName];
          
          if (rule != null) {
            if (rule is List) {
              result = await runFlow(rule, input: result);
            } else if (rule is Map<String, dynamic>) {
              result = await request(rule, input: result);
            }
          } else {
            logger.warning("[PluginDecoder] Rule not found: $ruleName");
          }
        }

        if (stepMap['save'] != null) {
          runtimeValues[stepMap['save']] = result;
        }
      }
    } catch (e) {
      if (globalShellContext != null) {
        noticeManager.showError(globalShellContext, "Run flow error: ${e.toString().split(":")[1]}");
      }
      logger.error("[PluginDecoder] Run flow error: $e", LogSource.system);
    }
    return result;
  }
}
