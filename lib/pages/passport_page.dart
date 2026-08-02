import 'dart:convert';
import 'dart:io';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/services/passport_service.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:bloret_launcher/main.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

class PassPortPage extends StatefulWidget {
  const PassPortPage({super.key});

  @override
  State<PassPortPage> createState() => _PassPortPageState();
}

class _PassPortPageState extends State<PassPortPage> {
  bool _isSyncing = false;
  bool _displayUuid = true;
  bool _isWaitingForLogin = false;
  HttpServer? _authServer;
  int _actualPort = 25252;
  final ValueNotifier<bool> _isTokenValidNotifier = ValueNotifier<bool>(false);

  Map<String, dynamic> _getAccountData() {
    final data = ConfigService.get('MinecraftAccount');
    if (data == null) return {"logined": false, "chosen": -1, "accounts": []};
    if (data is String) return jsonDecode(data);
    return data as Map<String, dynamic>;
  }

  void _syncStateToUi() {
    if (mounted) {
      setState(() {
        final bool loggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
        if (loggedIn) {
          _isWaitingForLogin = false;
        }
      });
    }
  }

  Future<void> _loginBloretPassPort() async {
    await _startAuthServer();
    final url = Uri.parse('https://passport.bloret.net/app/oauth?app_id=BloraLauncher&redirect_uri=http://localhost:$_actualPort/login/Bloret-PassPort');
    if (await canLaunchUrl(url)) {
      await launchUrl(
          url,
          mode: Platform.isAndroid ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication
      );
      setState(() => _isWaitingForLogin = true);
    }
  }

  Future<void> _startAuthServer() async {
    await _authServer?.close(force: true);
    try {
      _authServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 25252);
      _actualPort = 25252;
    } catch (_) {
      _authServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _actualPort = _authServer!.port;
    }

    _authServer!.listen((HttpRequest request) async {
      if (request.uri.path == '/login/Bloret-PassPort') {
        final params = request.uri.queryParameters;
        final code = params['code'];

        if (code != null) {
          final userInfo = await PassportService.verifyCode(code);
          if (userInfo != null) {
            await ConfigService.set('Bloret_PassPort_Login', true);
            await ConfigService.set('Bloret_PassPort_UserName', userInfo['username']);
            await ConfigService.set('Bloret_PassPort_Avatar', userInfo['avatar']);
            await ConfigService.set('Bloret_PassPort_Email', userInfo['email']);
            await ConfigService.set('Bloret_PassPort_Token', userInfo['apptoken']);
            await ConfigService.set('Bloret_PassPort_BBBS_Session', userInfo['bbbs_session']);
            await ConfigService.set('Bloret_PassPort_BBBS_Session.sig', userInfo['bbbs_session.sig']);

            final syncResult = await PassportService.syncMinecraftAccounts();
            _isTokenValidNotifier.value = syncResult;
            _syncStateToUi();
          } else {
            _isTokenValidNotifier.value = false;
          }
          setState(() {});

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write('''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>登录成功</title>
    <style>
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        body {
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background-color: #121212;
            color: #ffffff;
            overflow: hidden;
        }
        .container {
            text-align: center;
            padding: 48px;
            background: #1e1e1e;
            border-radius: 24px;
            box-shadow: 0 12px 40px rgba(0, 0, 0, 0.5);
            border: 1px solid rgba(255, 255, 255, 0.05);
            max-width: 400px;
            width: 90%;
            animation: fadeIn 0.6s cubic-bezier(0.16, 1, 0.3, 1);
        }
        .icon-wrapper {
            position: relative;
            width: 80px;
            height: 80px;
            margin: 0 auto 24px;
        }
        .success-pulse {
            position: absolute;
            width: 100%;
            height: 100%;
            background: rgba(159, 168, 218, 0.2);
            border-radius: 50%;
            animation: pulse 2s infinite;
        }
        .success-icon {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: #9FA8DA;
            border-radius: 50%;
            display: flex;
            justify-content: center;
            align-items: center;
            box-shadow: 0 4px 20px rgba(159, 168, 218, 0.4);
        }
        .success-icon svg {
            width: 40px;
            height: 40px;
            fill: none;
            stroke: #121212;
            stroke-width: 4;
            stroke-linecap: round;
            stroke-linejoin: round;
            stroke-dasharray: 100;
            stroke-dashoffset: 100;
            animation: drawCheck 0.6s 0.3s forwards cubic-bezier(0.16, 1, 0.3, 1);
        }
        h1 {
            font-size: 24px;
            font-weight: 600;
            margin-bottom: 12px;
            letter-spacing: 0.5px;
        }
        p {
            font-size: 14px;
            color: rgba(255, 255, 255, 0.5);
            line-height: 1.6;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        @keyframes pulse {
            0% { transform: scale(0.95); opacity: 0.5; }
            50% { transform: scale(1.2); opacity: 0; }
            100% { transform: scale(0.95); opacity: 0; }
        }
        @keyframes drawCheck {
            to { stroke-dashoffset: 0; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon-wrapper">
            <div class="success-pulse"></div>
            <div class="success-icon">
                <svg viewBox="0 0 24 24">
                    <polyline points="20 6 9 17 4 12"></polyline>
                </svg>
            </div>
        </div>
        <h1>Bloret PassPort 授权成功</h1>
        <p>您现在可以安全地关闭此窗口并返回 Launcher 继续设置。</p>
    </div>
</body>
</html>
''')
            ..close();

          await _authServer?.close();
          _authServer = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
    final userName = ConfigService.get('Bloret_PassPort_UserName') ?? "访客";
    final avatar = ConfigService.get('Bloret_PassPort_Avatar') ?? "";
    final accountData = _getAccountData();
    // fuck
    final List accounts = accountData['accounts'] ?? [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text("通行证", style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          Text("Bloret PassPort", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          FluentCard(
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: avatar.isNotEmpty && isLoggedIn
                      ? CachedNetworkImage(imageUrl: avatar, width: 48, height: 48, fit: BoxFit.cover, )
                      : SizedBox(width: 48, height: 48, child: Image.asset(Theme.of(context).brightness == Brightness.dark ? "assets/bloret_dark.png" : "assets/bloret_light.png")),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(userName, style: const TextStyle(fontWeight: FontWeight.w700))),
                if (!isLoggedIn)
                  BloretButton(
                    onPressed: () async {
                      await _loginBloretPassPort();
                    },
                    text: _isWaitingForLogin ? "等待登录..." : "登录",
                  )
                else
                  BloretButton(
                    onPressed: () async {
                      await ConfigService.set('Bloret_PassPort_Login', false);
                      await ConfigService.set('Bloret_PassPort_UserName', '');
                      await ConfigService.set('Bloret_PassPort_PassWord', '');
                      accounts.clear();
                      setState(() {});
                    },
                    text: "退出登录",
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text("使用 Bloret 通行证，可享受几乎所有的 Bloret 服务。",
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 32),
          Row(
            children: [
              Text("Minecraft 账户", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              if (_isSyncing)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              IconButton(
                onPressed: () {
                  setState(() => _displayUuid = !_displayUuid);
                },
                icon: !_displayUuid ? const Icon(Icons.visibility_off) : const Icon(Icons.visibility),
              )
            ],
          ),
          const SizedBox(height: 12),
          if (!isLoggedIn)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("您还未登录，请先登录", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 40))))
          else if (accounts.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("暂无账户，请从云端同步", style: TextStyle(fontWeight: FontWeight.w600))))
          else
            ...accounts.asMap().entries.map((entry) {
              final index = entry.key;
              final account = entry.value;
              final isDefault = accountData['chosen'] == index;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FluentCard(
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(imageUrl: account['avatarUrl'] ?? "https://mc-heads.net/avatar/${account['uuid']}/32", width: 32, height: 32, errorWidget: (_, _, _) => const Icon(Icons.account_circle, size: 32)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    account['username'] ?? "Unknown",
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_displayUuid && account['uuid'] != null)
                                  Flexible(
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Text(
                                        "(${account['uuid']})",
                                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: theme.colorScheme.outline),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            Text(account['type'] ?? "Offline", style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      BloretButton(
                        onPressed: isDefault ? null : () async {
                          final newData = Map<String, dynamic>.from(accountData);
                          newData['chosen'] = index;
                          await ConfigService.set('MinecraftAccount', jsonEncode(newData));
                          setState(() {});
                        },
                        text: isDefault ? "正在使用" : "使用此账户",
                      ),
                    ],
                  ),
                ),
              );
            }),
          if (isLoggedIn) ...[
            const SizedBox(height: 32),
            FluentCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("通过 Bloret PassPort 管理你的账户", style: TextStyle(fontWeight: FontWeight.w700)),
                  Text("轻松登录你的 Minecraft Account，便捷地进行操作。",
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          launchUrlString("https://passport.bloret.net/minecraft");
                        },
                        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: const Text("网站管理", style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () async {
                          setState(() => _isSyncing = true);
                          await PassportService.syncMinecraftAccounts();
                          setState(() => _isSyncing = false);
                        },
                        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: const Text("云端同步", style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }
}
