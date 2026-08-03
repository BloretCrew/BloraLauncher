import 'dart:async';
import 'dart:convert';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LiveService {
  static String get _baseUrl => "http://bloret.net:21111";

  static Map<String, String> _getHeaders() {
    final session = ConfigService.get('Bloret_PassPort_BBBS_Session') ?? '';
    final sig = ConfigService.get('Bloret_PassPort_BBBS_Session.sig') ?? '';
    List<String> cookies = [];
    if (session.isNotEmpty) cookies.add('session=$session');
    if (sig.isNotEmpty) cookies.add('session.sig=$sig');
    
    return {
      'Content-Type': 'application/json',
      if (cookies.isNotEmpty) 'cookie': cookies.join('; '),
    };
  }

  static Future<List<dynamic>> fetchSpaceList() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/live/list'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (e) {
      print("[LiveService] fetchSpaceList error: $e");
    }
    return [];
  }

  static Future<Map<String, dynamic>?> createSpace(String name) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/live/create'),
        headers: _getHeaders(),
        body: jsonEncode({"name": name}),
      ).timeout(const Duration(seconds: 15));
      
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) return data;
      return {"success": false, "message": data['message'] ?? "Server error ${response.statusCode}"};
    } catch (e) {
      print("[LiveService] createSpace error: $e");
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<Map<String, dynamic>> verifyPassword(String spaceId, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/live/verify-password/$spaceId'),
        headers: _getHeaders(),
        body: jsonEncode({"password": password}),
      ).timeout(const Duration(seconds: 15));

      return jsonDecode(response.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<void> sendSignal(String spaceId, Map<String, dynamic> signalData) async {
    try {
      print("[LiveService] sendSignal: $signalData");
      await http.post(
        Uri.parse('$_baseUrl/api/live/signal/$spaceId'),
        headers: _getHeaders(),
        body: jsonEncode(signalData),
      );
    } catch (e) {
      print("[LiveService] sendSignal error: $e");
    }
  }

  static Stream<Map<String, dynamic>> subscribeEvents(String spaceId) {
    final client = http.Client();
    final controller = StreamController<Map<String, dynamic>>();
    
    debugPrint("[LiveService] Starting SSE connection for space: $spaceId");
    
    _runSSE(client, controller, spaceId);
    
    return controller.stream;
  }

  static Future<void> _runSSE(http.Client client, StreamController<Map<String, dynamic>> controller, String spaceId) async {
    bool isCancelled = false;
    
    controller.onCancel = () {
      debugPrint("[LiveService] Stream cancelled by listener, closing SSE...");
      isCancelled = true;
      client.close();
      if (!controller.isClosed) controller.close();
    };

    try {
      final request = http.Request('GET', Uri.parse('$_baseUrl/api/live/events/$spaceId'));
      request.headers.addAll(_getHeaders());

      final response = await client.send(request);
      debugPrint("[LiveService] SSE response status: ${response.statusCode}");
      
      if (response.statusCode != 200) {
        if (!controller.isClosed) controller.close();
        client.close();
        return;
      }

      String buffer = "";
      String dataBuffer = "";
      String? currentEventType;

      await for (var chunk in response.stream.transform(utf8.decoder)) {
        if (isCancelled) break;
        
        buffer += chunk;
        while (buffer.contains('\n')) {
          int index = buffer.indexOf('\n');
          String line = buffer.substring(0, index).trim();
          buffer = buffer.substring(index + 1);

          if (line.isEmpty) {
            if (dataBuffer.isNotEmpty) {
              try {
                final Map<String, dynamic> payload = jsonDecode(dataBuffer);
                if (currentEventType != null) payload['type'] = currentEventType;
                debugPrint("[LiveService] SSE Event Parsed: Type=$currentEventType, From=${payload['from'] ?? payload['user']}");
                if (!controller.isClosed) controller.add(payload);
              } catch (e) {
                debugPrint("[LiveService] JSON解析失败: $e\n数据内容: $dataBuffer");
              }
              dataBuffer = "";
              currentEventType = null;
            }
          } else if (line.startsWith('event: ')) {
            currentEventType = line.substring(7).trim();
          } else if (line.startsWith('data: ')) {
            dataBuffer += line.substring(6);
          } else if (line.startsWith(':')) {
            // Heartbeat
          } else {
            if (dataBuffer.isNotEmpty) dataBuffer += line;
          }
        }
      }
    } catch (e) {
      if (!isCancelled) {
        debugPrint("[LiveService] SSE 连接异常: $e");
        if (!controller.isClosed) controller.addError(e);
      }
    } finally {
      client.close();
      if (!controller.isClosed) controller.close();
      debugPrint("[LiveService] SSE 资源已回收/连接关闭");
    }
  }

  // EasyTier Actions
  static Future<bool> startEasyTier(String spaceId) async {
    final resp = await http.post(Uri.parse('$_baseUrl/api/live/easytier/start/$spaceId'), headers: _getHeaders());
    return resp.statusCode == 200;
  }

  static Future<bool> stopEasyTier(String spaceId) async {
    final resp = await http.post(Uri.parse('$_baseUrl/api/live/easytier/stop/$spaceId'), headers: _getHeaders());
    return resp.statusCode == 200;
  }

  static Future<bool> publishEndpoint(String spaceId, String ip, int port) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/api/live/easytier/publish/$spaceId'),
      headers: _getHeaders(),
      body: jsonEncode({"hostVirtualIp": ip, "gamePort": port}),
    );
    return resp.statusCode == 200;
  }
}
