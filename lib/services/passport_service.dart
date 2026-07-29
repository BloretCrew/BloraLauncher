import 'dart:convert';
import 'package:dio/dio.dart';

import 'config_service.dart';

class PassportService {
  static const String baseUrl = 'http://bloret.net:20000';
  static const String appId = 'BloretLauncher';
  static const String appSecret = 's4d56f4a68sd46g54asd46f54a5dsf654asdf546';
  static final Dio dio = Dio();

  static Future<Map<String, dynamic>?> verifyCode(String code) async {
    try {
      final response = await dio.get('https://passport.bloret.net/app/verify?app_id=$appId&app_secret=$appSecret&code=$code').timeout(const Duration(seconds: 10));
      await ConfigService.set('Bloret_PassPort_Code', code);
      if (response.statusCode == 200) {
        if (response.data is String) {
          return jsonDecode(response.data);
        } else if (response.data is Map) {
          return response.data;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> saveData(String key, dynamic data, {bool public = false}) async {
    try {
      final user = ConfigService.get('Bloret_PassPort_UserName') ?? '';
      final userToken = ConfigService.get('Bloret_PassPort_PassWord') ?? '';
      
      String dataStr = (data is String) ? data : jsonEncode(data);
      
      final String userParam = public ? 'public' : user;
      final String tokenParam = public ? '' : '&usertoken=$userToken';
      
      final url = '$baseUrl/app/data/save?'
          'app_id=$appId&'
          'app_secret=$appSecret&'
          'user=$userParam'
          '$tokenParam&'
          'key=$key&'
          'data=${Uri.encodeComponent(dataStr)}';

      final response = await dio.get(url).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<dynamic> readData(String key, {bool public = false}) async {
    try {
      final user = ConfigService.get('Bloret_PassPort_UserName') ?? '';
      final userToken = ConfigService.get('Bloret_PassPort_Token') ?? '';
      
      final String userParam = public ? 'public' : user;
      final String tokenParam = public ? '' : '&usertoken=$userToken';

      final url = '$baseUrl/app/data/get?'
          'app_id=$appId&'
          'app_secret=$appSecret&'
          'user=$userParam'
          '$tokenParam&'
          'key=$key';

      final response = await dio.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final result = response.data;
        try {
          if ((result.startsWith('{') && result.endsWith('}')) || (result.startsWith('[') && result.endsWith(']'))) {
            return jsonDecode(result);
          }
        } catch (_) {}
        return result;
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> syncMinecraftAccounts() async {
    try {
      final isLoggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
      if (!isLoggedIn) return false;

      final username = ConfigService.get('Bloret_PassPort_UserName');
      final userToken = ConfigService.get('Bloret_PassPort_Token');

      final url = '$baseUrl/app/MinecraftAccounts?'
          'app_id=$appId&'
          'app_secret=$appSecret&'
          'user=$username&'
          'usertoken=$userToken';

      final response = await dio.get(url).timeout(const Duration(seconds: 30));
      final apiResult = response.data is Map ? response.data : jsonDecode(response.data);

      if (apiResult['status'] == 'success') {
        final List accounts = apiResult['accounts'] ?? [];
        
        final oldAccountData = ConfigService.get('MinecraftAccount');
        int oldChosen = 0;
        if (oldAccountData is String) {
          try {
             oldChosen = jsonDecode(oldAccountData)['chosen'] ?? 0;
          } catch (_) {}
        } else if (oldAccountData is Map) {
          oldChosen = oldAccountData['chosen'] ?? 0;
        }

        int newChosen = (oldChosen >= 0 && oldChosen < accounts.length) ? oldChosen : (accounts.isNotEmpty ? 0 : -1);

        await ConfigService.set('MinecraftAccountList', accounts.map((e) => jsonEncode(e)).toList());
        await ConfigService.set('MinecraftAccount_Chosen', newChosen);

        final newAccountData = {
          "logined": accounts.isNotEmpty,
          "chosen": newChosen,
          "accounts": accounts
        };
        await ConfigService.set('MinecraftAccount', jsonEncode(newAccountData));
        
        if (apiResult.containsKey('avatar')) {
          await ConfigService.set('Bloret_PassPort_Avatar', apiResult['avatar']);
        }
        
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> refreshMinecraftToken() async {
    try {
      final isLoggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
      if (!isLoggedIn) return false;

      final username = ConfigService.get('Bloret_PassPort_UserName');
      if (username == null) return false;

      final url = '$baseUrl/api/login/Minecraft/Refresh';
      final response = await dio.post(
        url,
        options: Options(
          headers: {'Cookie': 'username=$username'}
        ),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.data);
        return result['success'] ?? false;
      }
    } catch (e) {}
    return false;
  }
}
