import 'dart:async';
import 'dart:convert';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LiveService {
  static String get _baseUrl => "http://bloret.net:21111";

  // 全局用户信息缓存
  static final Map<String, Map<String, dynamic>> _userProfileCache = {};

  static Map<String, String> _getHeaders() {
    final session = ConfigService.get('Bloret_PassPort_BBBS_Session') ?? '';
    final sig = ConfigService.get('Bloret_PassPort_BBBS_Session.sig') ?? '';
    List<String> cookies = [];
    if (session.isNotEmpty) cookies.add('session=$session');
    if (sig.isNotEmpty) cookies.add('session.sig=$sig');
    
    return {
      'Content-Type': 'application/json',
      if (cookies.isNotEmpty) 'Cookie': cookies.join('; '),
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

  static Future<void> publishAiStats(String spaceId) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/api/live/ai/$spaceId/stats'),
        headers: _getHeaders(),
        body: jsonEncode({"extractCount": 0, "messageCount": 0, "recordCount": 0, "hasSummary": false}),
      );
    } catch (e) {
      // Ignore 304 or other errors for stats
    }
  }

  static Future<void> sendSignal(String spaceId, Map<String, dynamic> signalData) async {
    try {
      final signalStr = signalData.toString();
      final logLimit = signalStr.length < 50 ? signalStr.length : 50;
      final logStr = signalStr.substring(0, logLimit);
      print("[LiveService] sendSignal: $logStr");
      await dio.Dio().post(
        '$_baseUrl/api/live/signal/$spaceId',
        options: dio.Options(
          headers: _getHeaders(),
        ),
        data: jsonEncode(signalData),
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
    int retryCount = 0;
    const maxRetries = 3;
    
    controller.onCancel = () {
      debugPrint("[LiveService] Stream cancelled by listener, closing SSE...");
      isCancelled = true;
      client.close();
      if (!controller.isClosed) controller.close();
    };

    while (!isCancelled && retryCount < maxRetries) {
      try {
        final request = http.Request('GET', Uri.parse('$_baseUrl/api/live/events/$spaceId'));
        request.headers.addAll(_getHeaders());
        // Force keep-alive and other headers that might help with some proxies
        request.headers['Connection'] = 'keep-alive';
        request.headers['Accept'] = 'text/event-stream';
        request.headers['Cache-Control'] = 'no-cache';

        final response = await client.send(request).timeout(const Duration(seconds: 30));
        debugPrint("[LiveService] SSE response status: ${response.statusCode}");
        
        if (response.statusCode != 200) {
          debugPrint("[LiveService] SSE connection failed with status: ${response.statusCode}");
          if (response.statusCode == 404 || response.statusCode == 403) {
             // Permanent failures
             break;
          }
          throw Exception("Status ${response.statusCode}");
        }

        // Reset retry count on successful connection
        retryCount = 0;

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
        
        // If the stream ends naturally but not cancelled, it might be a timeout or server-side close
        if (!isCancelled) {
          debugPrint("[LiveService] SSE stream ended unexpectedly, retrying...");
          throw Exception("Stream ended");
        }

      } catch (e) {
        if (isCancelled) break;
        retryCount++;
        debugPrint("[LiveService] SSE 连接异常 (尝试 $retryCount/$maxRetries): $e");
        
        if (retryCount >= maxRetries) {
          if (!controller.isClosed) controller.addError(e);
          break;
        }
        
        // Exponential backoff or simple delay
        await Future.delayed(Duration(seconds: 2 * retryCount));
      }
    }

    client.close();
    if (!controller.isClosed) controller.close();
    debugPrint("[LiveService] SSE 资源已回收/连接关闭");
  }

  static Future<Map<String, dynamic>?> fetchUserProfile(String username) async {
    // 优先返回缓存
    if (_userProfileCache.containsKey(username)) {
      return _userProfileCache[username];
    }
    try {
      final response = await http.get(
        Uri.parse('https://bbs.bloret.net/api/user/profile/$username'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _userProfileCache[username] = data; // 存入缓存
        return data;
      }
    } catch (e) {
      debugPrint("[LiveService] fetchUserProfile error: $e");
    }
    return null;
  }

  static Future<Map<String, dynamic>?> uploadImage(Uint8List bytes, String filename) async {
    try {
      final dioClient = dio.Dio();
      final headers = _getHeaders();
      // Dio 会自动处理 Content-Type: multipart/form-data
      headers.remove('Content-Type');
      
      final formData = dio.FormData.fromMap({
        'image': dio.MultipartFile.fromBytes(bytes, filename: filename),
      });

      final response = await dioClient.post(
        'https://bbs.bloret.net/api/upload-proxy',
        data: formData,
        options: dio.Options(headers: headers),
      );

      if (response.statusCode == 200) {
        return response.data;
      }
    } catch (e) {
      debugPrint("[LiveService] uploadImage error: $e");
    }
    return null;
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
