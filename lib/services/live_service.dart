import 'dart:async';
import 'dart:convert';
import 'package:bloret_launcher/core/logger.dart';
import 'package:bloret_launcher/main.dart';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../core/i18n.dart';
class LiveService {
  static String get _baseUrl => "http://bloret.net:21111";

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

  static Future<List<dynamic>> fetchSpaceList({BuildContext? context}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/live/list'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return jsonDecode(response.body);
      
      logger.error("[LiveService] Failed to fetch space list: ${response.statusCode}", LogSource.network);
    } catch (e) {
      logger.error("[LiveService] fetchSpaceList network error: $e", LogSource.network);
    }
    return [];
  }

  static Future<Map<String, dynamic>?> createSpace(String name, {BuildContext? context}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/live/create'),
        headers: _getHeaders(),
        body: jsonEncode({"name": name}),
      ).timeout(const Duration(seconds: 15));
      
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (context != null && context.mounted) noticeManager.showSuccess(context, "Live space created successfully".tl);
        return data;
      }
      
      if (context != null && context.mounted) noticeManager.showWarning(context, (data['message'] as String? ?? "Failed to create space").tl);
      return {"success": false, "message": data['message'] ?? "Server error ${response.statusCode}"};
    } catch (e) {
      logger.error("[LiveService] createSpace error: $e", LogSource.network);
      if (context != null && context.mounted) noticeManager.showError(context, "Network error while creating space".tl);
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<Map<String, dynamic>> verifyPassword(String spaceId, String password, {BuildContext? context}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/live/verify-password/$spaceId'),
        headers: _getHeaders(),
        body: jsonEncode({"password": password}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        if (context != null && context.mounted) noticeManager.showSuccess(context, "Password verified".tl);
      } else if (context != null && context.mounted) {
        noticeManager.showWarning(context, "Incorrect password".tl);
      }
      return data;
    } catch (e) {
      logger.error("[LiveService] verifyPassword error: $e", LogSource.network);
      if (context != null && context.mounted) noticeManager.showError(context, "Network error while verifying password".tl);
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
      logger.info("[LiveService] sendSignal: $logStr", LogSource.network);
      await dio.Dio().post(
        '$_baseUrl/api/live/signal/$spaceId',
        options: dio.Options(
          headers: _getHeaders(),
        ),
        data: jsonEncode(signalData),
      );
    } catch (e) {
      logger.error("[LiveService] sendSignal error: $e", LogSource.network);
    }
  }

  static Stream<Map<String, dynamic>> subscribeEvents(String spaceId) {
    final client = http.Client();
    final controller = StreamController<Map<String, dynamic>>();
    
    logger.info("[LiveService] Starting SSE connection for space: $spaceId", LogSource.network);
    
    _runSSE(client, controller, spaceId);
    
    return controller.stream;
  }

  static Future<void> _runSSE(http.Client client, StreamController<Map<String, dynamic>> controller, String spaceId) async {
    bool isCancelled = false;
    int retryCount = 0;
    const maxRetries = 3;
    
    controller.onCancel = () {
      logger.info("[LiveService] Stream cancelled by listener, closing SSE...", LogSource.network);
      isCancelled = true;
      client.close();
      if (!controller.isClosed) controller.close();
    };

    while (!isCancelled && retryCount < maxRetries) {
      try {
        final request = http.Request('GET', Uri.parse('$_baseUrl/api/live/events/$spaceId'));
        request.headers.addAll(_getHeaders());
        request.headers['Connection'] = 'keep-alive';
        request.headers['Accept'] = 'text/event-stream';
        request.headers['Cache-Control'] = 'no-cache';

        final response = await client.send(request).timeout(const Duration(seconds: 30));
        
        if (response.statusCode != 200) {
          logger.error("[LiveService] SSE connection failed with status: ${response.statusCode}", LogSource.network);
          if (response.statusCode == 404 || response.statusCode == 403) {
             break;
          }
          throw Exception("Status ${response.statusCode}");
        }

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
                  logger.error("[LiveService] JSON Parse Error: $e, content: $dataBuffer", LogSource.network);
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
        
        if (!isCancelled) {
          logger.warning("[LiveService] SSE stream ended unexpectedly, retrying...", LogSource.network);
          throw Exception("Stream ended");
        }

      } catch (e) {
        if (isCancelled) break;
        retryCount++;
        logger.error("[LiveService] SSE connection error (Attempt $retryCount/$maxRetries): $e", LogSource.network);
        
        if (retryCount >= maxRetries) {
          if (!controller.isClosed) controller.addError(e);
          break;
        }
        
        await Future.delayed(Duration(seconds: 2 * retryCount));
      }
    }

    client.close();
    if (!controller.isClosed) controller.close();
    logger.info("[LiveService] SSE resources released / connection closed", LogSource.network);
  }

  static Future<Map<String, dynamic>?> fetchUserProfile(String username) async {
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
        _userProfileCache[username] = data;
        return data;
      }
      logger.error("[LiveService] fetchUserProfile failed: ${response.statusCode}", LogSource.network);
    } catch (e) {
      logger.error("[LiveService] fetchUserProfile error: $e", LogSource.network);
    }
    return null;
  }

  static Future<Map<String, dynamic>?> uploadImage(Uint8List bytes, String filename, {BuildContext? context}) async {
    try {
      final dioClient = dio.Dio();
      final headers = _getHeaders();
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
        if (context != null && context.mounted) noticeManager.showSuccess(context, "Image uploaded successfully".tl);
        return response.data;
      }
      
      if (context != null && context.mounted) noticeManager.showWarning(context, "Upload failed with status: ${response.statusCode}".tl);
    } catch (e) {
      logger.error("[LiveService] uploadImage error: $e", LogSource.network);
      if (context != null && context.mounted) noticeManager.showError(context, "Network error while uploading image".tl);
    }
    return null;
  }

  // EasyTier Actions
  static Future<bool> startEasyTier(String spaceId, {BuildContext? context}) async {
    try {
      final resp = await http.post(Uri.parse('$_baseUrl/api/live/easytier/start/$spaceId'), headers: _getHeaders());
      if (resp.statusCode == 200) {
        if (context != null && context.mounted) noticeManager.showSuccess(context, "EasyTier service started".tl);
        return true;
      }
      if (context != null && context.mounted) noticeManager.showWarning(context, "Failed to start EasyTier".tl);
    } catch (e) {
      logger.error("[LiveService] startEasyTier error: $e", LogSource.network);
      if (context != null && context.mounted) noticeManager.showError(context, "Network error starting EasyTier".tl);
    }
    return false;
  }

  static Future<bool> stopEasyTier(String spaceId, {BuildContext? context}) async {
    try {
      final resp = await http.post(Uri.parse('$_baseUrl/api/live/easytier/stop/$spaceId'), headers: _getHeaders());
      if (resp.statusCode == 200) {
        if (context != null && context.mounted) noticeManager.showSuccess(context, "EasyTier service stopped".tl);
        return true;
      }
    } catch (e) {
      logger.error("[LiveService] stopEasyTier error: $e", LogSource.network);
    }
    return false;
  }

  static Future<bool> publishEndpoint(String spaceId, String ip, int port, {BuildContext? context}) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/live/easytier/publish/$spaceId'),
        headers: _getHeaders(),
        body: jsonEncode({"hostVirtualIp": ip, "gamePort": port}),
      );
      if (resp.statusCode == 200) {
        if (context != null && context.mounted) noticeManager.showSuccess(context, "Endpoint published to space".tl);
        return true;
      }
      if (context != null && context.mounted) noticeManager.showWarning(context, "Failed to publish endpoint".tl);
    } catch (e) {
      logger.error("[LiveService] publishEndpoint error: $e", LogSource.network);
      if (context != null && context.mounted) noticeManager.showError(context, "Network error publishing endpoint".tl);
    }
    return false;
  }
}
