import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import '../services/config_service.dart';
import '../main.dart';
import '../services/passport_service.dart';

class WelcomeSetupScreen extends StatefulWidget {
  const WelcomeSetupScreen({super.key});

  @override
  State<WelcomeSetupScreen> createState() => _WelcomeSetupScreenState();
}

class _WelcomeSetupScreenState extends State<WelcomeSetupScreen> {
  int _currentStep = 0;
  final int _totalSteps = 6;

  final List<String> _stepLabels = ['欢迎', '语言', '登录', '同步', 'Java', '目录'];
  
  String _selectedLanguage = 'zh-cn';
  final String _minecraftDir = 'C:/Users/Administrator/AppData/Roaming/.minecraft';

  bool _isWaitingForLogin = false;
  HttpServer? _authServer;
  int _actualPort = 25252;
  Timer? _statusChecker;

  final ValueNotifier<bool> _isCodeValidNotifier = ValueNotifier<bool>(false);
  bool _isVerifyingCode = true;

  @override
  void initState() {
    super.initState();
    _checkPassportCode();
  }

  @override
  void dispose() {
    _authServer?.close(force: true);
    _statusChecker?.cancel();
    _isCodeValidNotifier.dispose();
    super.dispose();
  }

  Future<void> _checkPassportCode() async {
    setState(() => _isVerifyingCode = true);
    try {
      final code = ConfigService.get('Bloret_PassPort_Code') ?? '';
      final result = await PassportService.verifyCode(code);
      if (!mounted) return;
      _isCodeValidNotifier.value = (result != null);
    } catch (_) {
      _isCodeValidNotifier.value = false;
    } finally {
      if (mounted) {
        setState(() => _isVerifyingCode = false);
      }
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

            _syncStateToUi();
          }
          
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

  void _syncStateToUi() {
    if (mounted) {
      setState(() {
        final bool loggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
        if (loggedIn) {
          _isWaitingForLogin = false;
          if (_currentStep == 2) _currentStep++;
          _statusChecker?.cancel();
        }
      });
    }
  }

  Future<void> _loginBloretPassPort() async {
    await _startAuthServer();
    final url = Uri.parse('https://passport.bloret.net/app/oauth?app_id=BloretLauncher&redirect_uri=http://localhost:$_actualPort/login/Bloret-PassPort');
    if (await canLaunchUrl(url)) {
      await launchUrl(
        url, 
        mode: Platform.isAndroid ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication
      );
      setState(() => _isWaitingForLogin = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          Container(
            color: theme.colorScheme.surfaceContainer,
            padding: EdgeInsets.only(top: isPortrait ? 20 : 36, bottom: 8),
            child: SafeArea(bottom: false, child: _buildStepProgressIndicator(isPortrait)),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: isPortrait ? const Offset(0, 0.05) : const Offset(0.1, 0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Padding(
                          key: ValueKey(_currentStep),
                          padding: EdgeInsets.symmetric(horizontal: isPortrait ? 20.0 : 40.0, vertical: 20),
                          child: _buildStepContent(_currentStep, isPortrait),
                        ),
                      ),
                    ),
                  ),
                );
              }
            ),
          ),
          Container(
            color: theme.colorScheme.surfaceContainer,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: SafeArea(top: false, child: _buildBottomButtons(isPortrait)),
          ),
        ],
      ),
    );
  }

  Widget _buildStepProgressIndicator(bool isPortrait) {
    final theme = Theme.of(context);
    
    return Container(
      padding: EdgeInsets.symmetric(vertical: isPortrait ? 0 : 8, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPortrait)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _stepLabels[_currentStep],
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.primary,
                  letterSpacing: 2,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_totalSteps, (index) {
              final isCurrent = index == _currentStep;
              final isCompleted = index < _currentStep;
              final showLabel = index <= _currentStep + 1;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOutBack,
                    margin: const EdgeInsets.symmetric(horizontal: 8.0),
                    height: 10,
                    width: isCurrent ? (isPortrait ? 30 : 40) : 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      color: isCompleted
                          ? Colors.green
                          : (isCurrent ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
                    ),
                  ),
                  if (!isPortrait)
                    const SizedBox(height: 14),
                  if (!isPortrait)
                    SizedBox(
                      width: 60,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 400),
                        opacity: showLabel ? 1.0 : 0.0,
                        child: Text(
                          _stepLabels[index],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isCompleted
                                ? Colors.green
                                : (isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                            fontSize: 13,
                            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  DropdownMenuItem<String> _buildWin11MenuItem(String value, String text, ThemeData theme) {
    return DropdownMenuItem<String>(
      value: value,
      child: Container(
        width: double.infinity,
        height: 36,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        margin: const EdgeInsets.symmetric(vertical: 2.0),
        decoration: BoxDecoration(
          color: _selectedLanguage == value ? theme.colorScheme.secondaryContainer.withOpacity(0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(6.0),
        ),
        child: Row(
          children: [
            if (_selectedLanguage == value)
              Container(
                width: 3,
                height: 16,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(int step, bool isPortrait) {
    final theme = Theme.of(context);
    final headerStyle = (isPortrait ? theme.textTheme.headlineSmall : theme.textTheme.headlineLarge)
        ?.copyWith(fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface);
    final bodyStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface);
    final hintStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey[600]);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildStepSpecificUI(step, theme, isPortrait, headerStyle, bodyStyle, hintStyle),
      ],
    );
  }

  Widget _buildStepSpecificUI(int step, ThemeData theme, bool isPortrait, TextStyle? headerStyle, TextStyle bodyStyle, TextStyle hintStyle) {
    switch (step) {
      case 0:
        return Column(
          children: [
            SizedBox(
              width: isPortrait ? 140 : 120,
              height: isPortrait ? 140 : 120,
              child: Image.asset(
                  theme.brightness == Brightness.light ? "assets/bloret_light.png" : "assets/bloret_dark.png"),
            ),
            const SizedBox(height: 32),
            Text("欢迎使用 Bloret Launcher", textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 8),
            Text("Flutter Edition", textAlign: TextAlign.center, style: hintStyle),
            const SizedBox(height: 16),
            Text("欢迎！让我们一起开启 Bloret Launcher 的旅程！\n接下来，我们需要进行一些必备操作。",
                textAlign: TextAlign.center, style: bodyStyle),
          ],
        );
      case 1:
        return Column(
          children: [
            Text("选择语言", textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 12),
            Text("请选择您希望使用的界面语言：", textAlign: TextAlign.center, style: hintStyle),
            const SizedBox(height: 32),
            Container(
              height: 42,
              width: isPortrait ? double.infinity : 400,
              margin: EdgeInsets.symmetric(horizontal: isPortrait ? 24 : 0),
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLanguage,
                  isExpanded: true,
                  dropdownColor: theme.colorScheme.surface,
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  style: bodyStyle.copyWith(fontSize: 14),
                  menuMaxHeight: 300,
                  borderRadius: BorderRadius.circular(8.0),
                  alignment: AlignmentDirectional.center,
                  items: [
                    _buildWin11MenuItem('zh-cn', '简体中文', theme),
                    _buildWin11MenuItem('en-us', 'English', theme),
                  ],
                  onChanged: (val) => setState(() => _selectedLanguage = val!),
                ),
              ),
            ),
          ],
        );
      case 2:
        final bool isLoggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
        String buttonText = isLoggedIn ? "已登录，继续" : (_isWaitingForLogin ? "重新打开登录页面" : "前往登录");

        return ValueListenableBuilder<bool>(
          valueListenable: _isCodeValidNotifier,
          builder: (context, isCodeValid, _) {
            return Column(
              children: [
                Text("登录 Bloret PassPort", textAlign: TextAlign.center, style: headerStyle),
                const SizedBox(height: 16),
                Text("登录 Bloret PassPort 以同步您的 Minecraft 账户和设置。", textAlign: TextAlign.center, style: bodyStyle),
                const SizedBox(height: 40),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  child: _isWaitingForLogin
                      ? Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text("正在等待登录完成...", style: hintStyle),
                      ],
                    ),
                  )
                      : const SizedBox.shrink(),
                ),
                AnimatedScale(
                  duration: const Duration(milliseconds: 300),
                  scale: _isWaitingForLogin ? 1.05 : 1.0,
                  child: _isVerifyingCode
                      ? const SizedBox(
                    height: 50,
                    child: Center(child: CircularProgressIndicator()),
                  )
                      : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      backgroundColor: _isWaitingForLogin ? theme.colorScheme.secondaryContainer : theme.colorScheme.primary,
                      foregroundColor: _isWaitingForLogin ? theme.colorScheme.onSecondaryContainer : theme.colorScheme.onPrimary,
                      elevation: 2,
                    ),
                    onPressed: () async {
                      if (!isCodeValid) {
                        await _loginBloretPassPort();
                        _checkPassportCode();
                        return;
                      }
                      if (ConfigService.get('Bloret_PassPort_Login') ?? false) {
                        setState(() => _currentStep++);
                      } else {
                        await _loginBloretPassPort();
                        _checkPassportCode();
                      }
                    },
                    child: Text(
                      isCodeValid ? buttonText : isLoggedIn ? "口令失效，请重新登录" : "前往登录",
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text("提示：您必须登录 Bloret PassPort 才能继续使用。", textAlign: TextAlign.center, style: hintStyle),
              ],
            );
          },
        );
      case 3:
        return FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () async {
            final data = await PassportService.syncMinecraftAccounts();
            print(ConfigService.get("Bloret_PassPort_Token"));
            print(data);
          },
          child: Text("Sync", style: const TextStyle(fontWeight: FontWeight.w700)),
        );
      case 5:
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: isPortrait ? 24 : 0),
          child: Column(
            children: [
              Text("Minecraft 游戏文件夹", textAlign: TextAlign.center, style: headerStyle),
              const SizedBox(height: 24),
              TextField(
                controller: TextEditingController(text: _minecraftDir),
                style: const TextStyle(fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: "游戏目录",
                  labelStyle: hintStyle.copyWith(fontWeight: FontWeight.w600),
                  suffixIcon: IconButton(icon: const Icon(Icons.folder_open), onPressed: () {}),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                readOnly: true,
              ),
            ],
          ),
        );
      default:
        return Column(
          children: [
            Text(_stepLabels[step], textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 16),
            Text("一个他妈的占位符，操你妈", textAlign: TextAlign.center, style: bodyStyle),
          ],
        );
    }
  }

  Widget _buildBottomButtons(bool isPortrait) {
    final theme = Theme.of(context);
    final bool isLoggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
    final bool nextDisabled = _currentStep == 2 && !isLoggedIn;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isPortrait ? 10.0 : 32.0, vertical: isPortrait ? 4.0 : 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_currentStep > 0)
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: theme.colorScheme.secondaryContainer.withOpacity(0.5),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => setState(() => _currentStep--),
              child: const Text("返回", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(width: 12),
          FutureBuilder(
            future: _currentStep == 2 ? PassportService.verifyCode(ConfigService.get('Bloret_PassPort_Code') ?? '') : Future.value(true),
            builder: (_, snapshot) {
              final no = snapshot.data == null;
              return FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: nextDisabled || no ? null : () async {
                  if (_currentStep < _totalSteps - 1) {
                    setState(() => _currentStep++);
                  } else {
                    await ConfigService.setLanguage(_selectedLanguage);
                    await ConfigService.set('minecraft_dir', _minecraftDir);
                    await ConfigService.setFirstRunCompleted();

                    if (mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (context) => const MainShell()),
                      );
                    }
                  }
                },
                child: Text(_currentStep == _totalSteps - 1 ? "完成" : "下一步", style: const TextStyle(fontWeight: FontWeight.w700)),
              );
            }
          ),
        ],
      ),
    );
  }
}
