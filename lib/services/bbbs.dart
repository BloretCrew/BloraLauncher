import 'dart:convert';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:http/http.dart' as http;

class BbbsService {
  static String _getBaseUrl() {
    return "http://bloret.net:21111";
  }

  static Map<String, String> _getSessionCookie() {
    final session = ConfigService.get('Bloret_PassPort_BBBS_Session') ?? '';
    if (session.isNotEmpty) {
      return {'cookie': 'session=$session'};
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
}