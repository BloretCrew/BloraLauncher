import 'dart:convert';
import 'dart:io';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/services/passport_service.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:bloret_launcher/main.dart';
import 'package:bloret_launcher/core/i18n.dart';
import 'package:bloret_launcher/core/grammer_candy.dart';
import 'package:bloret_launcher/core/uuid_utils.dart';
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
  int _actualPort = 25254;
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
    final url = Uri.parse('https://passport.bloret.net/app/oauth?app_id=${PassportService.appId}&redirect_uri=http://localhost:$_actualPort/login/Bloret-PassPort');
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
      _authServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 25254);
      _actualPort = 25254;
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
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${"Login Success".tl}</title>
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
            100% { transform: scale(0.95); opacity: 0.5; }
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

  void _addOfflineAccount() {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Add Offline Account".tl),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: "Enter username".tl,
          ),
          autofocus: true,
          onSubmitted: (val) => _performAddOffline(controller.text, context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel".tl),
          ),
          TextButton(
            onPressed: () => _performAddOffline(controller.text, context),
            child: Text("Add".tl),
          ),
        ],
      ),
    );
  }

  Future<void> _performAddOffline(String name, BuildContext context) async {
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) {
      final newAccount = {
        'username': trimmedName,
        'uuid': UUIDUtils.generateOfflineUUID(trimmedName),
        'type': 'Offline',
        'locate': 'Local',
        'login_time': DateTime.now().toString(),
      };
      final rawData = ConfigService.get('MinecraftAccountList');
      List<dynamic> currentAccounts = [];
      if (rawData is List) {
        currentAccounts = List.from(rawData);
      }
      
      currentAccounts.add(jsonEncode(newAccount));

      await ConfigService.set(
        'MinecraftAccountList',
        currentAccounts,
      );

      final int currentChosen = ConfigService.get('MinecraftAccount_Chosen') ?? 0;
      int newChosen = currentChosen;
      if (currentAccounts.length == 1) {
        newChosen = 0;
        await ConfigService.set('MinecraftAccount_Chosen', 0);
      }

      // Keep legacy blob in sync
      final newAccountData = {
        "logined": currentAccounts.any((e) => jsonDecode(e.toString())['locate'] != 'Local'),
        "chosen": newChosen,
        "accounts": currentAccounts.map((e) => jsonDecode(e.toString())).toList(),
      };
      await ConfigService.set('MinecraftAccount', jsonEncode(newAccountData));

      setState(() {});
      if (context.mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
      showSuccess("Account added".tl);
    }
  }

  Future<void> _deleteAccount(int originalIndex, String username) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Account".tl),
        content: Text("${"Are you sure you want to delete account".tl} '$username'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel".tl),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("Delete".tl, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final rawData = ConfigService.get('MinecraftAccountList');
      if (rawData is List) {
        final List<dynamic> newList = List.from(rawData);
        final int? chosenIdx = int.tryParse(ConfigService.get('MinecraftAccount_Chosen')?.toString() ?? "");
        
        newList.removeAt(originalIndex);
        await ConfigService.set('MinecraftAccountList', newList);

        int newChosen = chosenIdx ?? 0;
        if (chosenIdx != null) {
          if (chosenIdx == originalIndex) {
            newChosen = newList.isEmpty ? -1 : 0;
          } else if (chosenIdx > originalIndex) {
            newChosen = chosenIdx - 1;
          }
        }
        await ConfigService.set('MinecraftAccount_Chosen', newChosen);

        // Keep legacy blob in sync
        final newAccountData = {
          "logined": newList.any((e) => jsonDecode(e.toString())['locate'] != 'Local'),
          "chosen": newChosen,
          "accounts": newList.map((e) => jsonDecode(e.toString())).toList(),
        };
        await ConfigService.set('MinecraftAccount', jsonEncode(newAccountData));

        setState(() {});
        showSuccess("Account deleted".tl);
      }
    }
  }

  Widget _buildAccountItem(Map<String, String> account, int originalIndex, bool isDefault, ThemeData theme) {
    final bool isOffline = account['type'] == 'Offline';
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FluentCard(
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: account['avatarUrl'] ?? "https://mc-heads.net/avatar/${account['uuid']}/32",
                width: 32,
                height: 32,
                placeholder: (context, _) => const Icon(Icons.account_circle, size: 32),
                errorWidget: (_, _, _) => const Icon(Icons.account_circle, size: 32),
              ),
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: (account['locate'] == 'Local' ? Colors.orange : Colors.blue).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: (account['locate'] == 'Local' ? Colors.orange : Colors.blue).withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          (account['locate'] == 'Local' ? "Local".tl : "Cloud".tl),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: account['locate'] == 'Local' ? Colors.orange : Colors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text((account['type'] ?? "Offline").toString().tl, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            if (isOffline && account["locate"] == "Local")
              IconButton(
                onPressed: () => _deleteAccount(originalIndex, account['username'] ?? ""),
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                tooltip: "Delete Account".tl,
              ),
            BloretButton(
              onPressed: isDefault ? null : () async {
                await ConfigService.set('MinecraftAccount_Chosen', originalIndex);
                
                // Keep legacy blob in sync
                final List<dynamic> rawAccounts = ConfigService.get('MinecraftAccountList') ?? [];
                final newAccountData = {
                  "logined": rawAccounts.any((e) => jsonDecode(e.toString())['locate'] != 'Local'),
                  "chosen": originalIndex,
                  "accounts": rawAccounts.map((e) => jsonDecode(e.toString())).toList(),
                };
                await ConfigService.set('MinecraftAccount', jsonEncode(newAccountData));

                if (mounted) setState(() {});
              },
              text: isDefault ? "Using".tl : "Use This".tl,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
    final userName = ConfigService.get('Bloret_PassPort_UserName') ?? "Guest".tl;
    final avatar = ConfigService.get('Bloret_PassPort_Avatar') ?? "";
    
    final List<dynamic> rawAccountList = ConfigService.get('MinecraftAccountList') as List<dynamic>? ?? [];
    final List<Map<String, String>> accountData = [];
    
    for (int i = 0; i < rawAccountList.length; i++) {
      try {
        final decoded = jsonDecode(rawAccountList[i].toString()) as Map<String, dynamic>;
        final map = decoded.map((k, v) => MapEntry(k, v.toString()));
        map['_index'] = i.toString();
        accountData.add(map);
      } catch (_) {}
    }

    final passportAccounts = accountData.where((a) => a['locate'] != 'Local').toList();
    final localAccounts = accountData.where((a) => a['locate'] == 'Local').toList();
    final chosenIndex = int.tryParse(ConfigService.get("MinecraftAccount_Chosen")?.toString() ?? "-1");

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
                      if (_isWaitingForLogin) {
                        await _authServer?.close();
                        _authServer = null;
                      }
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
                      await ConfigService.set('Bloret_PassPort_BBBS_Session', '');
                      await ConfigService.set('Bloret_PassPort_BBBS_Session.sig', '');

                      final rawData = ConfigService.get('MinecraftAccountList');
                      if (rawData is List) {
                        int? currentChosenIdx = ConfigService.get('MinecraftAccount_Chosen');
                        String? chosenUuid;
                        if (currentChosenIdx != null && currentChosenIdx >= 0 && currentChosenIdx < rawData.length) {
                           chosenUuid = jsonDecode(rawData[currentChosenIdx].toString())['uuid'];
                        }

                        final filtered = rawData.where((e) {
                          try {
                            final decoded = jsonDecode(e.toString());
                            return decoded['locate'] == 'Local';
                          } catch (_) {
                            return false;
                          }
                        }).toList();
                        await ConfigService.set('MinecraftAccountList', filtered);

                        int newChosenIdx = -1;
                        if (chosenUuid != null) {
                           for (int i = 0; i < filtered.length; i++) {
                              if (jsonDecode(filtered[i].toString())['uuid'] == chosenUuid) {
                                 newChosenIdx = i;
                                 break;
                              }
                           }
                        }
                        
                        if (newChosenIdx == -1 && filtered.isNotEmpty) {
                           newChosenIdx = 0;
                        }
                        await ConfigService.set('MinecraftAccount_Chosen', newChosenIdx);

                        // Keep legacy blob in sync
                        final newAccountData = {
                          "logined": false,
                          "chosen": newChosenIdx,
                          "accounts": filtered.map((e) => jsonDecode(e.toString())).toList(),
                        };
                        await ConfigService.set('MinecraftAccount', jsonEncode(newAccountData));
                      }

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
              ),
              IconButton(
                onPressed: _addOfflineAccount,
                icon: const Icon(Icons.add_circle_outline),
                tooltip: "Add Offline Account".tl,
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          if (passportAccounts.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text("PassPort Accounts".tl, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
            ),
            ...passportAccounts.map((account) {
              final idx = int.parse(account['_index']!);
              return _buildAccountItem(account, idx, chosenIndex == idx, theme);
            }),
            const SizedBox(height: 12),
          ],

          if (localAccounts.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text("Local Accounts".tl, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.secondary)),
            ),
            ...localAccounts.map((account) {
              final idx = int.parse(account['_index']!);
              return _buildAccountItem(account, idx, chosenIndex == idx, theme);
            }),
            const SizedBox(height: 12),
          ],

          if (accountData.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.all(20), child: Text("No accounts, please add or sync".tl, style: const TextStyle(fontWeight: FontWeight.w600)))),

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
                          if (mounted) setState(() => _isSyncing = false);
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
