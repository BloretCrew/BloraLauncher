import 'dart:async';
import 'dart:convert';
import 'package:bloret_launcher/services/config_service.dart';
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
      await http.post(
        Uri.parse('$_baseUrl/api/live/signal/$spaceId'),
        headers: _getHeaders(),
        body: jsonEncode(signalData),
      );
    } catch (e) {
      print("[LiveService] sendSignal error: $e");
    }
  }

  static Stream<Map<String, dynamic>> subscribeEvents(String spaceId) async* {
    final request = http.Request('GET', Uri.parse('$_baseUrl/api/live/events/$spaceId'));
    request.headers.addAll(_getHeaders());

    final client = http.Client();
    try {
      final response = await client.send(request);
      if (response.statusCode != 200) return;

      String buffer = "";
      await for (var chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        print("[LiveService] SSE chunk: $chunk");
        while (buffer.contains('\n\n')) {
          final parts = buffer.split('\n\n');
          final eventString = parts.removeAt(0);
          buffer = parts.join('\n\n');

          Map<String, dynamic> payload = {};
          String? eventType;
          
          for (var line in eventString.split('\n')) {
            if (line.startsWith('event: ')) {
              eventType = line.substring(7).trim();
            } else if (line.startsWith('data: ')) {
              final dataPart = line.substring(6).trim();
              try {
                payload = jsonDecode(dataPart);
              } catch (e) {
                print("[LiveService] JSON decode error: $e, Raw: $dataPart");
              }
            }
          }
          if (eventType != null) payload['type'] = eventType;
          yield payload;
        }
      }
    } catch (e) {
      print("[LiveService] SSE error: $e");
    } finally {
      client.close();
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
