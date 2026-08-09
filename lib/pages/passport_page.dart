import 'dart:convert';
import 'dart:io';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/services/passport_service.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:bloret_launcher/main.dart';
import 'package:bloret_launcher/core/i18n.dart';
import 'package:bloret_launcher/core/grammer_candy.dart';
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
            showSuccess("Logged in successfully".tl);
            logger.info("Passport login success: ${userInfo['username']}", .network);
          } else {
            _isTokenValidNotifier.value = false;
            showError("Authentication failed".tl);
          }
          setState(() {});

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write('''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${"Login Success".tl}</title>
...
        <h1>${"Bloret PassPort Authorized".tl}</h1>
        <p>${"You can now safely close this window and return to the Launcher.".tl}</p>
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
    final userName = ConfigService.get('Bloret_PassPort_UserName') ?? "Guest".tl;
    final avatar = ConfigService.get('Bloret_PassPort_Avatar') ?? "";
    
    final accountData = (ConfigService.get('MinecraftAccountList') as List<dynamic>? ?? []).map((e) => (jsonDecode(e.toString()) as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()))).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text("Passport".tl, style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800)),
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
                    text: _isWaitingForLogin ? "Waiting...".tl : "Login".tl,
                  )
                else
                  BloretButton(
                    onPressed: () async {
                      await ConfigService.set('Bloret_PassPort_Login', false);
                      await ConfigService.set('Bloret_PassPort_UserName', '');
                      await ConfigService.set('Bloret_PassPort_Token', '');
                      await ConfigService.set('Bloret_PassPort_Avatar', '');
                      await ConfigService.set('MinecraftAccountList', []);
                      setState(() {});
                      showInfo("Logged out".tl);
                    },
                    text: "Logout".tl,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text("Use Bloret PassPort to access all Bloret services.".tl,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          Row(
            children: [
              Text("Minecraft Accounts".tl, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
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
            Center(child: Padding(padding: const EdgeInsets.all(20), child: Text("Please log in first".tl, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 32))))
          else if (accountData.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.all(20), child: Text("No accounts, please sync from cloud".tl, style: const TextStyle(fontWeight: FontWeight.w600))))
          else
            ...accountData.asMap().entries.map((entry) {
              final index = entry.key;
              final account = entry.value;
              final isDefault = int.tryParse(ConfigService.get("MinecraftAccount_Chosen").toString()) == index;
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
                            Text((account['type'] ?? "Offline").toString().tl, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      BloretButton(
                        onPressed: isDefault ? null : () async {
                          await ConfigService.set('MinecraftAccount_Chosen', index).then((_) {
                            if (mounted) setState(() {});
                          });
                        },
                        text: isDefault ? "Using".tl : "Use This".tl,
                      ),
                    ],
                  ),
                ),
              );
            }),
          if (isLoggedIn) ...[
            const SizedBox(height: 12),
            FluentCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Manage accounts via Bloret PassPort".tl, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text("Easily manage your Minecraft accounts and settings.".tl,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          launchUrlString("https://passport.bloret.net/minecraft");
                        },
                        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: Text("Website".tl, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () async {
                          setState(() => _isSyncing = true);
                          try {
                            final success = await PassportService.syncMinecraftAccounts();
                            if (success) {
                              showSuccess("Synced successfully".tl);
                            } else {
                              showError("Sync failed".tl);
                            }
                          } catch (e) {
                            showError("Sync failed".tl);
                            logger.error("Passport sync error: $e", .network);
                          }
                          setState(() => _isSyncing = false);
                        },
                        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: Text("Cloud Sync".tl, style: const TextStyle(fontWeight: FontWeight.w600)),
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
