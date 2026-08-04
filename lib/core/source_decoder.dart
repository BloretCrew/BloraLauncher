import 'dart:math';
import 'package:dio/dio.dart';
import 'logger.dart';

class SourceDecoder {
  final time = DateTime.now().millisecondsSinceEpoch.toString();
  final dynamic source;
  late final Map<String, dynamic> extra = source["extra"] ?? {};
  final Map<String, dynamic> runtimeValues = {};
  final Dio dio = Dio();
  final _random = Random();
  int i = 0;

  SourceDecoder(this.source, _);

  Future<dynamic> request(Map<String, dynamic> rule, {dynamic input}) async {
    final urlStr = rule['url']?.toString() ?? "";
    dynamic currentData = input;
    if (urlStr.isNotEmpty) {
      final url = _resolveValue(urlStr, source, input: input);
      final method = (rule['method'] ?? 'GET').toString().toUpperCase();
      final headers = decodeHeaderOrData(rule, isHeader: true);
      final data = decodeHeaderOrData(rule, isHeader: false, bodyKey: 'data');

      await Future.delayed(Duration(milliseconds: 100 + _random.nextInt(201)));

      try {
        Response response;
        if (method == 'POST') {
          response = await dio.post(url, data: data, options: Options(headers: headers, contentType: Headers.formUrlEncodedContentType));
        } else {
          response = await dio.get(url, queryParameters: data, options: Options(headers: headers));
        }
        final setCookies = response.headers.map['set-cookie'];
        if (setCookies != null) {
          var current = dio.options.headers["cookie"]?.toString() ?? "";
          for (var c in setCookies) {
            final cookiePair = c.split(';').first;
            if (!current.contains(cookiePair.split('=').first)) {
              if (current.isNotEmpty && !current.endsWith(";")) current += "; ";
              current += cookiePair;
            }
          }
          dio.options.headers["cookie"] = current;
        }
        currentData = response.data;
      } catch (e) { 
        final l = await AppLogger.getInstance();
        l.log("Request Error: $e", source: LogSource.network, level: LogLevel.error); 
        return null; 
      }
    }
    if (rule.containsKey('parse')) return _resolveValue(rule['parse'], source, input: currentData);
    return currentData;
  }

  Future<dynamic> runFlow(String name, [void Function(String)? onStep]) async {
    i = 0;
    final steps = source['flows'][name];

    dynamic result;

    for (final step in steps) {
      if (step['condition'] != null) {
        final cond = step['condition'];

        if (cond['contains'] != null) {
          if (!result.toString().contains(cond['contains'])) {
            continue;
          }
        }
      }

      if (step['flow'] != null) {
        result = await runFlow(step['flow']);
        continue;
      }

      final rule = source[step['rule']];

      result = await executeRule(
        rule,
        input: result,
        onStep: onStep
      );

      if (step['save'] != null) {
        saveValue(step, result);
      }
    }

    return result;
  }

  Future<dynamic> executeDslFlow(
      List steps, {
        dynamic input,
      }) async {

    dynamic current = input;
    final originalInput = input;

    for (final step in steps) {
      switch (step["action"]) {
        case "extract":
          final match=RegExp(
            step["regex"],
            dotAll:true,
          ).firstMatch(
              originalInput.toString()
          );
          current=match?.group(1) ?? "";
          runtimeValues[step["save"]]=current;
          break;

        case "execute":
          final method = {
            "way": step["way"],
            "values": step["values"],
            "input": step["input"],
          };

          current = _executeMethod(
            method,
            source,
            input: current,
          );

          runtimeValues[step["save"]] = current;
          break;

        case "cookie":
          final value = _resolveValue(
            step["value"],
            source,
            input: current,
          );
          dio.options.headers["cookie"] =
              value.toString();
          current = value;
          break;
      }
    }

    return current;
  }

  void saveValue(
      Map<String,dynamic> step,
      dynamic value
      ){
    if (step["save"] is List){
      final keys = step["save"] as List;
      final list = step["split"] != null
          ? value.toString().split(step["split"])
          : [];

      for(int i=0;i<keys.length;i++){
        runtimeValues[keys[i]] =
        i < list.length ? list[i] : "";
      }

    } else {
      runtimeValues[step["save"]] = value;
    }

    if (step["result"] != null){
      runtimeValues[step["result"]] = value;
    }
  }

  Future<dynamic> executeRule(
      Map<String, dynamic> rule, {
        dynamic input, void Function(String)? onStep
      }) async {

    if (rule["url"].toString().contains("shareId") && rule["parse"] == null) {
      onStep?.call("Checking safety challenge...");
    } else if (rule["url"].toString().contains("shareId")) {
      onStep?.call("Fetching share page...");
    } else if (rule["url"].toString().contains("iframePath")) {
      onStep?.call("Parsing redirect...");
    } else if (rule["url"].toString().contains("ajaxm")) {
      onStep?.call("Solving parameters...");
    }

    if (rule.containsKey("flow")) {
      return await executeDslFlow(
        rule["flow"],
        input: input,
      );
    }

    return await request(
      rule,
      input: input,
    );
  }

  Map<String, String> decodeHeaderOrData(Map<String, dynamic> json, {bool isHeader = true, String bodyKey = ""}) {
    final key = isHeader ? 'header' : bodyKey;
    if (json[key] == null) return {};
    var raw = Map<String, dynamic>.from(json[key]);
    Map<String, String> resolved = {};
    raw.forEach((k, v) => resolved[k] = _resolveValue(v, json).toString());
    return resolved;
  }

  dynamic _resolveValue(dynamic value, Map<String, dynamic> json, {dynamic input = ""}) {
    if (i++ > 1000) throw Exception("Too many iterations!");
    if (value == null) return "";
    if (value is String &&
        RegExp(r'^\$[a-zA-Z0-9_]+$').hasMatch(value)) {

      final key = value.substring(1);

      return runtimeValues[key] ?? value;
    }
    if (value.toString() == "@input") return input;
    if (value is Map) return _executeMethod(value as Map<String, dynamic>, json, input: input);
    if (value is List) {
      if (value.isNotEmpty && value.first is Map) return _executeMethodGroup(value.cast<Map<String, dynamic>>(), json, input: input);
      return value.first.toString();
    }
    String str = value.toString();
    if (str.contains('*') || str.contains(r'$') || str.contains('@') || str.contains('&')) {
      return str.replaceAllMapped(RegExp(r'([*&$@])([a-zA-Z0-9_]+)'), (match) {
        final prefix = match.group(1);
        final key = match.group(2)!;
        if (prefix == '@' && key == "input") return input.toString();
        switch (prefix) {
          case '*': return extra[key]?.toString() ?? match.group(0)!;
          case '&': return _getConstants(key);
          case r'$':
            final value = runtimeValues[key];

            if (value == null) {
              return match.group(0)!;
            }

            return value.toString();
          case '@': return json[key]?.toString() ?? match.group(0)!;
          default: return match.group(0)!;
        }
      });
    }
    return str;
  }

  dynamic _executeMethodGroup(List<Map<String, dynamic>> steps, Map<String, dynamic> json, {dynamic input}) {
    dynamic current = input;
    for (var step in steps) {
      current = _executeMethod(step, json, input: current);
    }
    return current;
  }

  String _getConstants(String key) {
    return switch (key) {
      "ua" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      "time" => time,
      _ => ""
    };
  }

  dynamic _executeMethod(Map<String, dynamic> method, Map<String, dynamic> json, {dynamic input = ""}) {
    final way = method['way'] as String;
    if (way.isEmpty) return input;
    final cmd = way.substring(1);
    switch (cmd) {
      case "input": return _resolveValue(method['value'], json, input: input);
      case "stringMerge":
        return (method['values'] as List).map((v) => _resolveValue(v, json, input: input)).join("");
      case "add_cookie":
        var current = dio.options.headers["cookie"]?.toString() ?? "";
        if (current.isNotEmpty && !current.endsWith(";")) current += "; ";
        dio.options.headers["cookie"] = "$current${input.toString()}";
        return input;
      case "regex_extract":
        var match = RegExp(method['regex'].toString(), dotAll: true).firstMatch(input.toString());
        return match?.group(method['group'] ?? 1) ?? "";
      case "json_extract":
        if (input is Map) return input[method['key']];
        return input;
      case "lanzou_folder_parse":
        if (input is! List) return [];
        final domain = extra['domain'] ?? "";
        return input
            .where((item) => item is Map && item['icon'] == "zip")
            .map((item) => "$domain/${(item as Map)['id']}")
            .toList();

      case "regex_variable_extract":
        final html = input.toString();
        final nameRegex = RegExp(method['nameRegex']);
        final name = nameRegex.firstMatch(html)?.group(1);

        if(name == null) return "";

        final valueRegex = RegExp(
            "var\\s+$name\\s*=\\s*'([^']+)'"
        );

        return valueRegex.firstMatch(html)?.group(1) ?? "";

      case "parse_number_array":
        final str = input.toString().trim();

        if (str.isEmpty) return [];

        return str
            .split(',')
            .where((e)=>e.trim().isNotEmpty)
            .map((e) {
          e = e.trim();

          if (e.startsWith("0x")) {
            return int.parse(
              e.substring(2),
              radix: 16,
            );
          }

          return int.parse(
            e,
            radix: 10,
          );
        })
            .toList();

      case "array_reorder":
        final values = method['values'] as List;

        final arg1 = _resolveValue(
          values[0],
          json,
          input: input,
        ).toString();

        final m = _resolveValue(
          values[1],
          json,
          input: input,
        ) as List;

        final q = List<String>.filled(m.length, '');

        for (int x = 0; x < arg1.length; x++) {
          for (int z = 0; z < m.length; z++) {
            if (m[z] == x + 1) {
              q[z] = arg1[x];
              break;
            }
          }
        }

        return q.join();
      case "xor_hex":
        final values = method['values'] as List;

        final inputHex =
        _resolveValue(values[0], json, input: input)
            .toString();

        final key =
        values[1].toString();


        final result = StringBuffer();


        for (int i=0;i<inputHex.length && i<key.length;i+=2){

          final a = int.parse(
              inputHex.substring(i,i+2),
              radix:16
          );

          final b = int.parse(
              key.substring(i,i+2),
              radix:16
          );

          result.write(
              (a ^ b)
                  .toRadixString(16)
                  .padLeft(2,'0')
          );
        }
        return result.toString();
      default: return input;
    }
  }
}