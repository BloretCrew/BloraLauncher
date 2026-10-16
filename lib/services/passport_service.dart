import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/global.dart';
import '../main.dart';
import 'config_service.dart';

class PassportService {
  static String baseUrl = 'http://$serverIP:20000';
  static const String appId = 'bp_300950b2630e250c';
  static const String appSecret = 'bs_6f6dfdf0fa563b10bb1d51389eab92a5d485cfd3d29f904c';
  static final Dio dio = Dio();

  static HttpServer? _authServer;
  static int _actualPort = 25254;

  static Future<void> cancelLogin() async {
    await _authServer?.close(force: true);
    _authServer = null;
  }

  static Future<void> startLoginFlow({
    required Function(Map<String, dynamic> userInfo) onLoginSuccess,
    required VoidCallback onLoginFail,
    required VoidCallback onStartWaiting,
    required String successHtml,
  }) async {
    await cancelLogin();
    
    try {
      _authServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 25254);
      _actualPort = 25254;
    } catch (_) {
      _authServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _actualPort = _authServer!.port;
    }

    final url = Uri.parse('https://passport.bloret.net/app/oauth?app_id=$appId&redirect_uri=http://localhost:$_actualPort/login/Bloret-PassPort');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(
          url,
          mode: Platform.isAndroid ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication
      );
      onStartWaiting();
    }

    _authServer!.listen((HttpRequest request) async {
      if (request.uri.path == '/login/Bloret-PassPort') {
        final params = request.uri.queryParameters;
        final code = params['code'];

        if (code != null) {
          final userInfo = await verifyCode(code);
          if (userInfo != null) {
            await ConfigService.set('Bloret_PassPort_Login', true);
            await ConfigService.set('Bloret_PassPort_UserName', userInfo['username']);
            await ConfigService.set('Bloret_PassPort_NickName', userInfo['nickname']);
            await ConfigService.set('Bloret_PassPort_Avatar', userInfo['avatar']);
            await ConfigService.set('Bloret_PassPort_Email', userInfo['email']);
            await ConfigService.set('Bloret_PassPort_Token', userInfo['apptoken']);
            await ConfigService.set('Bloret_PassPort_BBBS_Session', userInfo['bbbs_session']);
            await ConfigService.set('Bloret_PassPort_BBBS_Session.sig', userInfo['bbbs_session.sig']);

            await syncMinecraftAccounts();
            onLoginSuccess(userInfo);
          } else {
            onLoginFail();
          }

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(successHtml)
            ..close();

          await cancelLogin();
        }
      }
    });
  }

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
      final userToken = ConfigService.get('Bloret_PassPort_Token') ?? '';
      
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

      final response = await dio.get(
        '$baseUrl/app/MinecraftAccounts',
        queryParameters: {
          'app_id': appId,
          'app_secret': appSecret,
          'user': username,
          'usertoken': userToken,
        }
      ).timeout(const Duration(seconds: 30));
      
      final apiResult = response.data is Map ? response.data : jsonDecode(response.data.toString());

      if (apiResult['status'] == 'success') {
        final List accounts = apiResult['accounts'] ?? [];

        final List<dynamic> currentList = ConfigService.get('MinecraftAccountList') as List<dynamic>? ?? [];
        final List<dynamic> localAccounts = currentList.where((e) {
          try {
            final decoded = jsonDecode(e.toString());
            return decoded['locate'] == 'Local';
          } catch (_) {
            return false;
          }
        }).toList();

        // Use Set to prevent name collisions between local and cloud accounts with same type
        final Map<String, String> uniqueAccounts = {};
        
        // Add cloud accounts first (they are more "official")
        for (var acc in accounts) {
          final String jsonStr = jsonEncode(acc);
          final String key = "${acc['type']}_${acc['uuid']}";
          uniqueAccounts[key] = jsonStr;
        }
        
        // Add local accounts if they don't exist in cloud
        for (var accStr in localAccounts) {
          final acc = jsonDecode(accStr.toString());
          final String key = "${acc['type']}_${acc['uuid']}";
          if (!uniqueAccounts.containsKey(key)) {
            uniqueAccounts[key] = accStr.toString();
          }
        }

        final List<String> combinedList = uniqueAccounts.values.toList();

        // Get current chosen account info robustly
        final int oldChosen = ConfigService.get('MinecraftAccount_Chosen') ?? 0;
        String? chosenUuid;
        String? chosenType;

        if (oldChosen >= 0 && oldChosen < currentList.length) {
          try {
            final chosenAccount = jsonDecode(currentList[oldChosen].toString());
            chosenUuid = chosenAccount['uuid'];
            chosenType = chosenAccount['type'];
          } catch (_) {}
        }

        await ConfigService.set('MinecraftAccountList', combinedList);

        int newChosen = -1;
        if (chosenUuid != null) {
          for (int i = 0; i < combinedList.length; i++) {
            final acc = jsonDecode(combinedList[i]);
            if (acc['uuid'] == chosenUuid && acc['type'] == chosenType) {
              newChosen = i;
              break;
            }
          }
        }
        
        if (newChosen == -1 && combinedList.isNotEmpty) {
          newChosen = 0;
        }
        
        await ConfigService.set('MinecraftAccount_Chosen', newChosen);

        // Keep legacy blob in sync
        final newAccountData = {
          "logined": accounts.isNotEmpty,
          "chosen": newChosen,
          "accounts": combinedList.map((e) => jsonDecode(e)).toList(),
        };
        await ConfigService.set('MinecraftAccount', jsonEncode(newAccountData));
        
        if (apiResult.containsKey('avatar')) {
          await ConfigService.set('Bloret_PassPort_Avatar', apiResult['avatar']);
        }
        
        return true;
      }
    } catch (e) {
      logger.error("Passport sync error: $e", .network);
    }
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
        final dynamic data = response.data;
        final Map<String, dynamic> result = data is Map ? Map<String, dynamic>.from(data) : jsonDecode(data.toString());
        return result['success'] ?? false;
      }
    } catch (_) {}
    return false;
  }
}