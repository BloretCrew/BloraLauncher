import 'dart:convert';
import 'package:bloret_launcher/core/logger.dart';
import 'package:bloret_launcher/main.dart';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import '../core/i18n.dart';

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
        logger.error("[BBBS] Failed to fetch daily summary, status code: ${response.statusCode}", LogSource.network);
        return null;
      }
    } catch (e) {
      logger.error("[BBBS] Network error fetching daily summary: $e", LogSource.network);
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
        logger.error("[BBBS] Failed to fetch leaderboard posts, status code: ${response.statusCode}", LogSource.network);
        return [];
      }
    } catch (e) {
      logger.error("[BBBS] Network error fetching leaderboard posts: $e", LogSource.network);
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
        logger.error("[BBBS] Failed to fetch latest posts, status code: ${response.statusCode}", LogSource.network);
        return [];
      }
    } catch (e) {
      logger.error("[BBBS] Network error fetching latest posts: $e", LogSource.network);
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
      logger.error("[BBBS] Failed to fetch today's feed: $e", LogSource.network);
    }
    return null;
  }

  static Future<dynamic> fetchPostDetail(String filename) async {
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
      logger.error("[BBBS] Failed to fetch post details: $e", LogSource.network);
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
      logger.error("[BBBS] Failed to fetch board posts: $e", LogSource.network);
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
      logger.error("[BBBS] Failed to fetch current user info: $e", LogSource.network);
    }
    return null;
  }

  // Post Interactions
  static Future<Map<String, dynamic>> likePost({
    required String board,
    required String section,
    required String filename,
    BuildContext? context,
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
      final data = jsonDecode(resp.body);
      if (context != null) {
        if (data['success'] == true && context.mounted) {
          noticeManager.showSuccess(context, (data['message'] as String? ?? "Liked").tl);
        } else {
          if (context.mounted) noticeManager.showWarning(context, (data['message'] as String? ?? "Failed to like post").tl);
        }
      }
      return data;
    } catch (e) {
      logger.error("[BBBS] Like operation failed: $e", LogSource.network);
      if (context != null && context.mounted) noticeManager.showError(context, "Network error, failed to like post".tl);
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<Map<String, dynamic>> sharePost({
    required String board,
    required String section,
    required String filename,
    BuildContext? context,
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
      final data = jsonDecode(resp.body);
      if (context != null && data['success'] == true && context.mounted) {
        noticeManager.showSuccess(context, (data['message'] as String? ?? "Shared successfully").tl);
      }
      return data;
    } catch (e) {
      logger.error("[BBBS] Share record failed: $e", LogSource.network);
      return {"success": false, "message": e.toString()};
    }
  }

  // Comment Operations
  static Future<Map<String, dynamic>> addComment({
    required String filename,
    required String content,
    int? parentId,
    int? replyToId,
    BuildContext? context,
  }) async {
    final url = Uri.parse('${_getBaseUrl()}/api/comment/add');
    final headers = _getSessionCookie()..addAll({'Content-Type': 'application/json'});
    final body = {
      "filename": filename,
      "content": content,
      "parent_id": parentId,
      "reply_to_id": replyToId,
    };
    
    try {
      final resp = await http.post(url, headers: headers, body: jsonEncode(body));
      final data = jsonDecode(resp.body);
      if (context != null) {
        if (data['success'] == true) {
          if (context.mounted) noticeManager.showSuccess(context, "Comment posted successfully".tl);
        } else {
          if (context.mounted) noticeManager.showWarning(context, (data['message'] as String? ?? "Failed to post comment").tl);
        }
      }
      return data;
    } catch (e) {
      logger.error("[BBBS] Failed to post comment: $e", LogSource.network);
      if (context != null && context.mounted) noticeManager.showError(context, "Network error, failed to post comment".tl);
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<Map<String, dynamic>> deleteComment(int id, {BuildContext? context}) async {
    final url = Uri.parse('${_getBaseUrl()}/api/comment/delete');
    final headers = _getSessionCookie()..addAll({'Content-Type': 'application/json'});
    try {
      final resp = await http.post(url, headers: headers, body: jsonEncode({"id": id.toString()}));
      final data = jsonDecode(resp.body);
      if (context != null && data['success'] == true && context.mounted) {
        noticeManager.showSuccess(context, "Comment deleted".tl);
      }
      return data;
    } catch (e) {
      logger.error("[BBBS] Failed to delete comment: $e", LogSource.network);
      if (context != null && context.mounted) noticeManager.showError(context, "Network error, failed to delete comment".tl);
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<Map<String, dynamic>> editComment(int id, String content, {BuildContext? context}) async {
    final url = Uri.parse('${_getBaseUrl()}/api/comment/edit');
    final headers = _getSessionCookie()..addAll({'Content-Type': 'application/json'});
    try {
      final resp = await http.post(url, headers: headers, body: jsonEncode({"id": id.toString(), "content": content}));
      final data = jsonDecode(resp.body);
      if (context != null && data['success'] == true && context.mounted) {
        noticeManager.showSuccess(context, "Comment updated".tl);
      }
      return data;
    } catch (e) {
      logger.error("[BBBS] Failed to edit comment: $e", LogSource.network);
      if (context != null && context.mounted) noticeManager.showError(context, "Network error, failed to edit comment".tl);
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
      logger.error("[BBBS AI] SSE error: $e", LogSource.network);
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
        logger.error("[Bloriko Chat] Connection error: ${response.statusCode}", LogSource.network);
        return;
      }

      String buffer = "";
      await for (var chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
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
                logger.error("[Bloriko Chat] JSON Parse Error: $e", LogSource.network);
              }
            }
          }
        }
      }
    } catch (e) {
      logger.error("[Bloriko Chat] SSE error: $e", LogSource.network);
    } finally {
      client.close();
    }
  }
}
