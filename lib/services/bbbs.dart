import 'dart:convert';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:http/http.dart' as http;

class BbbsService {
  static String _getBaseUrl() {
    return "https://bbs.bloret.net";
  }

  static Map<String, String> _getSessionCookie() {
    final session = ConfigService.get('Bloret_PassPort_BBBS_Session') ?? '';
    final sig = ConfigService.get('Bloret_PassPort_BBBS_Session.sig') ?? '';
    List<String> cookies = [];
    if (session.isNotEmpty) cookies.add('session=$session');
    if (sig.isNotEmpty) cookies.add('session.sig=$sig');
    
    if (cookies.isNotEmpty) {
      return {'Cookie': cookies.join('; ')};
    }
    return {};
  }

  static bool isAuthenticated() {
    final session = ConfigService.get('Bloret_PassPort_BBBS_Session') ?? '';
    return session.isNotEmpty;
  }

  static Future<dynamic> fetchSummary() async {
    final url = Uri.parse('${_getBaseUrl()}/api/summary');
    try {
      final response = await http.get(
        url,
        headers: _getSessionCookie(),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print("[BBBS] 获取每日摘要失败，状态码: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("[BBBS] 获取每日摘要网络错误: $e");
      return null;
    }
  }

  static Future<List<dynamic>> fetchLeaderboardPosts() async {
    final url = Uri.parse('${_getBaseUrl()}/api/leaderboard/posts');
    try {
      final response = await http.get(
        url,
        headers: _getSessionCookie(),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data;
        return [];
      } else {
        print("[BBBS] 获取热帖排行失败，状态码: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("[BBBS] 获取热帖排行网络错误: $e");
      return [];
    }
  }

  static Future<List<dynamic>> fetchAllPosts() async {
    final url = Uri.parse('${_getBaseUrl()}/api/all-posts');
    try {
      final response = await http.get(
        url,
        headers: _getSessionCookie(),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data;
        return [];
      } else {
        print("[BBBS] 获取最新帖子失败，状态码: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("[BBBS] 获取最新帖子网络错误: $e");
      return [];
    }
  }

  static Future<Map<String, dynamic>?> fetchTodayFeed() async {
    final url = Uri.parse('${_getBaseUrl()}/api/feed/today');
    try {
      final response = await http.get(
        url,
        headers: _getSessionCookie(),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("[BBBS] 获取今日推荐失败: $e");
    }
    return null;
  }

  static Future<Map<String, dynamic>?> fetchPostDetail(String filename) async {
    final url = Uri.parse('${_getBaseUrl()}/api/post/$filename');
    try {
      final response = await http.get(
        url,
        headers: _getSessionCookie(),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("[BBBS] 获取帖子详情失败: $e");
    }
    return null;
  }

  static Future<List<dynamic>> fetchPostsByBoard(String board, String section) async {
    final url = Uri.parse('${_getBaseUrl()}/api/posts')
        .replace(queryParameters: {'board': board, 'section': section});
    try {
      final response = await http.get(
        url,
        headers: _getSessionCookie(),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("[BBBS] 获取板块帖子列表失败: $e");
    }
    return [];
  }

  static Future<void> recordView(String filename) async {
    final url = Uri.parse('${_getBaseUrl()}/api/post/view');
    try {
      await http.post(
        url,
        headers: _getSessionCookie()..addAll({'Content-Type': 'application/json'}),
        body: jsonEncode({"filename": filename}),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> fetchCurrentUser() async {
    final url = Uri.parse('${_getBaseUrl()}/api/user/me');
    try {
      final response = await http.get(
        url,
        headers: _getSessionCookie(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("[BBBS] 获取用户信息失败: $e");
    }
    return null;
  }

  // Post Interactions
  static Future<Map<String, dynamic>> likePost({
    required String board,
    required String section,
    required String filename,
  }) async {
    final url = Uri.parse('${_getBaseUrl()}/api/post/like');
    final headers = _getSessionCookie()..addAll({'Content-Type': 'application/json'});
    final body = jsonEncode({
      "board": board,
      "section": section,
      "filename": filename,
    });
    try {
      final resp = await http.post(url, headers: headers, body: body);
      return jsonDecode(resp.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<Map<String, dynamic>> sharePost({
    required String board,
    required String section,
    required String filename,
  }) async {
    final url = Uri.parse('${_getBaseUrl()}/api/post/share-record');
    final headers = _getSessionCookie()..addAll({'Content-Type': 'application/json'});
    final body = jsonEncode({
      "board": board,
      "section": section,
      "filename": filename,
    });
    try {
      final resp = await http.post(url, headers: headers, body: body);
      return jsonDecode(resp.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // Comment Operations
  static Future<Map<String, dynamic>> addComment({
    required String filename,
    required String content,
    int? parentId,
    int? replyToId,
  }) async {
    final url = Uri.parse('${_getBaseUrl()}/api/comment/add');
    final headers = _getSessionCookie()..addAll({'Content-Type': 'application/json'});
    final body = {
      "filename": filename,
      "content": content,
      "parent_id": ?parentId,
      "reply_to_id": ?replyToId,
    };
    
    try {
      final resp = await http.post(url, headers: headers, body: jsonEncode(body));
      return jsonDecode(resp.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<Map<String, dynamic>> deleteComment(int id) async {
    final url = Uri.parse('${_getBaseUrl()}/api/comment/delete');
    final headers = _getSessionCookie()..addAll({'Content-Type': 'application/json'});
    try {
      final resp = await http.post(url, headers: headers, body: jsonEncode({"id": id.toString()}));
      return jsonDecode(resp.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<Map<String, dynamic>> editComment(int id, String content) async {
    final url = Uri.parse('${_getBaseUrl()}/api/comment/edit');
    final headers = _getSessionCookie()..addAll({'Content-Type': 'application/json'});
    try {
      final resp = await http.post(url, headers: headers, body: jsonEncode({"id": id.toString(), "content": content}));
      return jsonDecode(resp.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // AI Translation & Explanation
  static Stream<String> streamAiAction({
    required String mode, // 'translate' or 'explain'
    required String content,
    String? title,
    String targetLang = "zh",
  }) async* {
    final url = Uri.parse('${_getBaseUrl()}/api/ai/translate-explain');
    final headers = _getSessionCookie()..addAll({'Content-Type': 'application/json'});
    final body = jsonEncode({
      "mode": mode,
      "content": content,
      "title": title ?? "",
      "target_lang": targetLang,
    });

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = body;

    final client = http.Client();
    try {
      final response = await client.send(request);
      if (response.statusCode != 200) return;

      String buffer = "";
      await for (var chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        while (buffer.contains('\n\n')) {
          final parts = buffer.split('\n\n');
          final eventString = parts.removeAt(0);
          buffer = parts.join('\n\n');

          for (var line in eventString.split('\n')) {
            if (line.startsWith('event: done')) {
              return;
            } else if (line.startsWith('data: ')) {
              try {
                final data = jsonDecode(line.substring(6).trim());
                if (data['text'] != null) yield data['text'];
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      print("[BBBS AI] SSE error: $e");
    } finally {
      client.close();
    }
  }

  static Stream<String> streamBlorikoChat({
    required String content,
    String role = "user",
  }) async* {
    final url = Uri.parse('${_getBaseUrl()}/api/ai/bloriko-chat');
    final headers = _getSessionCookie()
      ..addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
      });
    final body = jsonEncode({
      "role": role,
      "content": content,
    });

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = body;

    final client = http.Client();
    try {
      final response = await client.send(request);
      if (response.statusCode != 200) {
        print("[Bloriko Chat] Error: ${response.statusCode}");
        return;
      }

      String buffer = "";
      await for (var chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        // 兼容 \n\n 或 \r\n\r\n 换行符
        while (buffer.contains('\n\n')) {
          final parts = buffer.split('\n\n');
          final eventString = parts.removeAt(0);
          buffer = parts.join('\n\n');

          for (var line in eventString.split('\n')) {
            line = line.trim();
            if (line.startsWith('event: done')) {
              return;
            } else if (line.startsWith('data: ')) {
              try {
                final jsonStr = line.substring(6).trim();
                if (jsonStr == "{}") continue;
                final data = jsonDecode(jsonStr);
                if (data['text'] != null) yield data['text'];
              } catch (e) {
                print("[Bloriko Chat] JSON Parse Error: $e");
              }
            }
          }
        }
      }
    } catch (e) {
      print("[Bloriko Chat] SSE error: $e");
    } finally {
      client.close();
    }
  }
}