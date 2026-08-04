import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import '../services/config_service.dart';
import '../main.dart';
import '../services/passport_service.dart';
import '../services/win32_icon_service.dart';
import '../shell/main_shell.dart';
import '../widgets/google_widgets.dart';
import '../widgets/windows_widgets.dart';
import '../core/ffi_proxy.dart';
import '../core/java_config.dart';

class WelcomeSetupScreen extends StatefulWidget {
  const WelcomeSetupScreen({super.key});

  @override
  State<WelcomeSetupScreen> createState() => _WelcomeSetupScreenState();
}

class _WelcomeSetupScreenState extends State<WelcomeSetupScreen> with WidgetsBindingObserver {
  int _currentStep = 0;
  final int _totalSteps = 6;

  final List<String> _stepLabels = ['欢迎', '语言', '登录', '同步', 'Java', '目录'];
  
  String _selectedLanguage = 'zh-cn';
  final List<String> _minecraftDirs = ['C:/Users/Administrator/AppData/Roaming/.minecraft'];

  bool _isWaitingForLogin = false;
  HttpServer? _authServer;
  int _actualPort = 25252;
  Timer? _statusChecker;

  final ValueNotifier<bool> _isTokenValidNotifier = ValueNotifier<bool>(false);
  bool _isVerifyingCode = true;

  bool _isCheckingJava = false;
  bool _javaInstalled = false;
  List<Map<String,String>> _detectedJavaList = [];
  String? _javaPath;
  bool _isInstallingJava = false;
  double _installProgress = 0.0;
  String _installStatus = "";
  String _selectedJavaVersion = '21';
  int _checkCount = 0;

  bool _isSyncingAccounts = false;

  String _localIp = "127.0.0.1";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateAppIcon();
    });
    _checkJavaEnvironment();
    _getLocalIp();
  }

  Future<void> _checkJavaEnvironment() async {
    final List<Map<String, String>> detected = [];
    if (_isCheckingJava) return;
    setState(() {
      _isCheckingJava = true;
      _checkCount++;
    });

    try {
      final List<String> searchPaths = [];

      if (Platform.isWindows) {
        for (int i = 67; i <= 90; i++) {
          final drive = "${String.fromCharCode(i)}:\\";
          try {
            if (Directory(drive).existsSync()) {
              searchPaths.add(drive);
            }
          } catch (_) {
            print("Error checking drive $drive");
          }
        }

        final envVars = ['JAVA_HOME', 'JDK_HOME', 'PROGRAMFILES', 'PROGRAMFILES(X86)'];
        for (var env in envVars) {
          final value = Platform.environment[env];
          if (value != null && value.isNotEmpty) {
            try {
              if (Directory(value).existsSync()) {
                searchPaths.add(value);
              }
            } catch (_) {
              print("Error checking environment variable $env");
            }
          }
        }

        final commonDirs = [
          r'Program Files\Java',
          r'Program Files (x86)\Java',
          r'Program Files\Eclipse Adoptium',
          r'Program Files\Zulu',
          r'Program Files\Microsoft',
          r'Program Files\Amazon Corretto',
          r'.minecraft\runtime',
          r'.jdks',
        ];

        for (var drive in List.from(searchPaths)) {
          for (var common in commonDirs) {
            final p = path.join(drive, common);
            try {
              if (Directory(p).existsSync()) {
                if (!searchPaths.contains(p)) searchPaths.add(p);
                try {
                  await for (var subEntity in Directory(p).list(followLinks: false)) {
                    if (subEntity is Directory) {
                      try {
                        if (Directory(subEntity.path).existsSync()) {
                          if (!searchPaths.contains(subEntity.path)) {
                            searchPaths.add(subEntity.path);
                          }
                          try {
                            await for (var subSubEntity in subEntity.list(followLinks: false)) {
                              if (subSubEntity is Directory) {
                                try {
                                  if (Directory(subSubEntity.path).existsSync()) {
                                    if (!searchPaths.contains(subSubEntity.path)) {
                                      searchPaths.add(subSubEntity.path);
                                    }
                                  }
                                } catch (_) {
                                  print("Error checking directory $subSubEntity");
                                }
                              }
                            }
                          } catch (_) {
                            print("Error listing subdirectories of $subEntity");
                          }
                        }
                      } catch (_) {
                        print("Error checking directory $subEntity");
                      }
                    }
                  }
                } catch (_) {
                  print("Error listing subdirectories of $p");
                }
              }
            } catch (_) {
              print("Error checking directory $p");
            }
          }
        }
      } else {
        searchPaths.addAll(['/usr/lib/jvm', '/usr/java', '/Library/Java/JavaVirtualMachines', '/opt']);
        final home = Platform.environment['HOME'];
        if (home != null) {
          searchPaths.add('$home/.jdks');
          searchPaths.add('$home/.sdkman');
        }
      }

      try {
        final result = await Process.run(Platform.isWindows ? 'where' : 'which', ['java']);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split(Platform.isWindows ? '\r\n' : '\n');
          for (var line in lines) {
            final trimmed = line.trim();
            if (trimmed.isNotEmpty) {
              try {
                if (File(trimmed).existsSync()) {
                  final parent = Directory(trimmed).parent;
                  if (path.basename(parent.path).toLowerCase() == 'bin') {
                    final candidate = parent.parent.path;

                    if (!detected.any((e) => e["path"] == candidate)) {
                      String version = "?";

                      final name = path.basename(candidate);

                      final match = RegExp(r'(\d+)').firstMatch(name);
                      if (match != null) {
                        version = match.group(1)!;
                      }

                      detected.add({
                        "version": version,
                        "path": candidate,
                      });
                    }
                  }
                }
              } catch (_) {
                print("Error checking file $trimmed");
              }
            }
          }
        }
      } catch (_) {
        print("Error checking java");
      }

      final List<String> targetDirs = [];

      for (var rootPath in searchPaths) {
        if (rootPath.length <= 3) continue;

        final rootDir = Directory(rootPath);

        try {
          if (!rootDir.existsSync()) continue;
        } catch (_) {
          continue;
        }

        try {
          await for (var entity in rootDir.list(
            recursive: false,
            followLinks: false,
          )) {
            if (entity is Directory) {
              targetDirs.add(entity.path);
            } else if (entity is File &&
                path.basename(entity.path).toLowerCase() == 'java.exe') {

              final binDir = entity.parent;

              if (path.basename(binDir.path).toLowerCase() == 'bin') {
                final candidate = binDir.parent.path;

                if (!detected.any((e) => e["path"] == candidate)) {
                  detected.add({
                    "version": _getJavaVersion(candidate),
                    "path": candidate,
                  });
                }
              }
            }
          }
        } catch (_) {}
      }

      Future<void> scanJavaDir(
          Directory dir,
          int depth,
          ) async {

        if (depth > 3) return;

        try {
          await for (var entity in dir.list(
            recursive: false,
            followLinks: false,
          )) {

            if (entity is File &&
                path.basename(entity.path).toLowerCase() == 'java.exe') {

              final binDir = entity.parent;

              if (path.basename(binDir.path).toLowerCase() == 'bin') {

                final candidate = binDir.parent.path;

                if (!detected.any((e) => e["path"] == candidate)) {
                  detected.add({
                    "version": _getJavaVersion(candidate),
                    "path": candidate,
                  });
                }
              }
            }


            if (entity is Directory) {
              await scanJavaDir(
                entity,
                depth + 1,
              );
            }
          }

        } catch (_) {}
      }


      for (var dirPath in targetDirs) {
        await scanJavaDir(
          Directory(dirPath),
          0,
        );
      }
    } catch (_) {
      print("Error checking java environment");
    }

    if (mounted) {
      setState(() {
        _isCheckingJava = false;
        _checkCount++;

        _detectedJavaList = detected;

        if (detected.isNotEmpty) {
          _javaInstalled = true;

          final preferred = detected.firstWhere(
                (e) => e["version"] == "21",
            orElse: () => detected.first,
          );

          _javaPath = preferred["path"];
        } else {
          _javaInstalled = false;
          _javaPath = "";
        }
      });
    }
  }

  String _getJavaVersion(String candidate) {
    final name = path.basename(candidate);

    final match = RegExp(r'(\d+)').firstMatch(name);

    return match?.group(1) ?? "?";
  }

  Future<void> _installJava() async {
    setState(() {
      _isInstallingJava = true;
      _installProgress = 0.0;
      _installStatus = "准备下载...";
    });

    WinTaskbar.showProgress(0, 100);

    try {
      final url = JavaConfig.versions[_selectedJavaVersion]?['Windows']?['x64'];
      if (url == null) throw "不支持的版本或平台";

      final tempDir = await getTemporaryDirectory();
      final savePath = path.join(tempDir.path, "java_installer_$_selectedJavaVersion.msi");

      final dio = Dio();
      await dio.download(
        url,
        savePath,
        onReceiveProgress: (count, total) {
          if (total != -1) {
            double progress = count / total;
            int percent = (progress * 100).toInt();
            if (mounted) {
              setState(() {
                _installProgress = progress;
                _installStatus = "正在下载 Java $_selectedJavaVersion... ($percent%)";
              });
            }
            WinTaskbar.showProgress(percent, 100);
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _installStatus = "正在静默安装 Java $_selectedJavaVersion...";
        _installProgress = 1.0;
      });
      WinTaskbar.setIndeterminate();

      final process = await Process.start('msiexec', ['/i', savePath, '/quiet', '/qn']);
      
      final exitCode = await process.exitCode;

      try {
        final installerFile = File(savePath);
        if (await installerFile.exists()) {
          await installerFile.delete();
        }
      } catch (e) {}
      
      if (exitCode == 0 || exitCode == 3010) {
        if (mounted) {
          setState(() {
            _isInstallingJava = false;
            _javaInstalled = true;
            _javaPath = "C:/Program Files/Java/jdk-$_selectedJavaVersion";
            _installStatus = "安装完成";
            _installProgress = 1.0;
          });
        }
        WinTaskbar.showProgress(100, 100);
      } else {
        throw "安装失败，退出码: $exitCode";
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInstallingJava = false;
          _installStatus = "操作失败: $e";
        });
      }
      WinTaskbar.setError();
    } finally {
      Future.delayed(const Duration(seconds: 2), () {
        WinTaskbar.hideProgress();
      });
    }
  }

  Future<void> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        setState(() {
          _localIp = interfaces.first.addresses.first.address;
        });
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _getAccounts() {
    final data = ConfigService.get('MinecraftAccountList');
    if (data is List<String>) {
      return data.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    }

    final oldData = ConfigService.get('MinecraftAccount');
    if (oldData is String) {
      try {
        final decoded = jsonDecode(oldData);
        if (decoded is Map && decoded.containsKey('accounts')) {
          final List accs = decoded['accounts'];
          return accs.cast<Map<String, dynamic>>();
        }
      } catch (_) {}
    }
    return [];
  }

  int _getChosenIndex() {
    return ConfigService.get('MinecraftAccount_Chosen') ?? 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authServer?.close(force: true);
    _statusChecker?.cancel();
    _isTokenValidNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    _updateAppIcon();
  }

  void _updateAppIcon() {
    final isDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    Win32IconService.switchIcon(isDark);
  }

  Future<void> _checkTokenValidity() async {
    setState(() => _isVerifyingCode = true);
    try {
      final result = await PassportService.syncMinecraftAccounts();
      if (!mounted) return;
      _isTokenValidNotifier.value = result;
    } catch (_) {
      _isTokenValidNotifier.value = false;
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
          setState(() => _isVerifyingCode = true);
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
          setState(() => _isVerifyingCode = false);
          
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            // 史，用Copilot生成
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
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: theme.colorScheme.surfaceContainer,
              padding: EdgeInsets.only(top: isPortrait ? 10 : 20, bottom: 8),
              child: _buildStepProgressIndicator(isPortrait),
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
            child: _buildBottomButtons(isPortrait),
          ),
        ],
      ),
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
            Text("欢迎使用 $name Launcher", textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 8),
            Text("Flutter Edition", textAlign: TextAlign.center, style: hintStyle),
            const SizedBox(height: 16),
            Text("欢迎！让我们一起开启 $name Launcher 的旅程！\n接下来，我们需要进行一些必备操作。",
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
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
              ),
              child: Win11Dropdown(
                items: [
                  Win11DropdownItem(label: '简体中文', value: 'zh-cn'),
                  Win11DropdownItem(label: 'English', value: 'en-us'),
                ],
                initialValue: 'zh-cn',
                onChanged: (val) => setState(() => _selectedLanguage = val!),
              ),
            ),
          ],
        );
      case 2:
        final bool isLoggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
        String buttonText = isLoggedIn ? "已登录，继续" : (_isWaitingForLogin ? "重新打开登录页面" : "前往登录");

        return ValueListenableBuilder<bool>(
          valueListenable: _isTokenValidNotifier,
          builder: (context, isTokenValid, _) {
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
                  scale: _isWaitingForLogin || _isVerifyingCode ? 1.05 : 1.0,
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
                      if (!isTokenValid) {
                        await _loginBloretPassPort();
                        return;
                      }
                      if (ConfigService.get('Bloret_PassPort_Login') ?? false) {
                        setState(() => _currentStep++);
                      } else {
                        await _loginBloretPassPort();
                      }
                    },
                    child: Text(
                      isTokenValid ? buttonText : isLoggedIn ? "令牌失效，请重新登录" : "前往登录",
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
        final accounts = _getAccounts();
        final int chosenIndex = _getChosenIndex();

        return Column(
          children: [
            Text("同步 Minecraft 账户", textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 12),
            Text("从 Bloret PassPort 同步您的 Minecraft 账户信息。", textAlign: TextAlign.center, style: hintStyle),
            const SizedBox(height: 24),
            if (_isSyncingAccounts)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("正在同步账户...", style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              )
            else if (accounts.isEmpty)
              Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text("未找到 Minecraft 账户", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text("请先前往 passport.bloret.net ，添加一个离线账户或微软账户，然后点击这里的同步按钮再继续。",
                        textAlign: TextAlign.center, style: hintStyle),
                  ),
                ],
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 250),
                width: isPortrait ? double.infinity : 450,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final account = accounts[index];
                    final isSelected = chosenIndex == index;
                    return InkWell(
                      onTap: () async {
                        await ConfigService.set('MinecraftAccount_Chosen', index);
                        final oldData = ConfigService.get('MinecraftAccount');
                        if (oldData is String) {
                           try {
                             final decoded = jsonDecode(oldData) as Map<String, dynamic>;
                             decoded['chosen'] = index;
                             await ConfigService.set('MinecraftAccount', jsonEncode(decoded));
                           } catch (_) {}
                        }
                        setState(() {});
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: isSelected 
                              ? LinearGradient(
                                  colors: [
                                    theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                                    theme.colorScheme.primaryContainer.withValues(alpha: 0.05),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isSelected ? null : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? theme.colorScheme.primary : theme.dividerColor.withValues(alpha: 0.1),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                          boxShadow: isSelected ? [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ] : [],
                        ),
                        child: Row(
                          children: [
                            AnimatedScale(
                              duration: const Duration(milliseconds: 300),
                              scale: isSelected ? 1.1 : 1.0,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                  child: Stack(
                                    children: [
                                      const Center(child: Icon(Icons.account_circle, size: 24, color: Colors.grey)),
                                      CachedNetworkImage(
                                        imageUrl: account['avatarUrl'] ?? "https://mc-heads.net/avatar/${account['uuid']}/32",
                                        width: 32,
                                        height: 32,
                                        fit: BoxFit.cover,
                                        placeholder: (context, _) {
                                          return AnimatedOpacity(
                                            opacity: 1,
                                            duration: const Duration(milliseconds: 500),
                                            curve: Curves.easeOut,
                                            child: const CircularProgressIndicator(),
                                          );
                                        },
                                        errorWidget: (context, error, stackTrace) => const SizedBox.shrink(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(account['username'] ?? "Unknown",
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                                      color: isSelected ? theme.colorScheme.primary : null,
                                    )
                                  ),
                                  Row(
                                    children: [
                                      Text(account['type'] ?? "Offline", style: hintStyle.copyWith(fontSize: 12)),
                                      if (account['login_time'] != null) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          account['login_time'].toString().split(' ').first,
                                          style: hintStyle.copyWith(fontSize: 10, color: Colors.grey),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20)
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text("切换", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 32),
            AnimatedScale(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              scale: _isSyncingAccounts ? 0.9 : 1.0,
              child: ElevatedButton.icon(
                onPressed: _isSyncingAccounts ? null : () async {
                  setState(() => _isSyncingAccounts = true);
                  await PassportService.syncMinecraftAccounts();
                  if (mounted) setState(() => _isSyncingAccounts = false);
                },
                icon: const Icon(Icons.sync),
                label: Text(accounts.isEmpty ? "同步账户" : "重新同步", style: const TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        );
      case 4:
        return Column(
          children: [
            Text("Java 运行环境", textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Row(
                key: ValueKey("check_status_$_checkCount"),
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_isCheckingJava)
                    const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Icon(
                      _javaInstalled ? Icons.check_circle : Icons.info_outline,
                      color: _javaInstalled ? Colors.green : Colors.orange,
                      size: 24,
                    ),
                  const SizedBox(width: 12),
                  Text(
                    _isCheckingJava
                        ? "正在检查 Java 环境..."
                        : (_javaInstalled ? "已检测到 Java 运行环境。" : "未检测到 Java 环境，建议安装 Java 21。"),
                    textAlign: TextAlign.start,
                    style: bodyStyle,
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              child: _javaInstalled && _javaPath != null
                  ? Center(
                child: Container(
                  width: isPortrait ? double.infinity : 400,
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "当前检测到的 Java：",
                              style: hintStyle.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            Win11Dropdown(
                              items: _detectedJavaList.map((java) {
                                return Win11DropdownItem(
                                  label:
                                  "Java ${java["version"] ?? ""} (${java["path"] ?? ""})",
                                  value:
                                  java["path"] ?? "",
                                );
                              }).toList(),

                              initialValue: _javaPath,

                              themeColor: theme.colorScheme.primary,

                              onChanged: (value) {
                                setState(() {
                                  _javaPath = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),
            Text("安装或更换 Java 版本", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
                height: 42,
                width: isPortrait ? double.infinity : 300,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
                ),
                child: Win11Dropdown(
                  items: JavaConfig.versionList.map((String version) {
                    return Win11DropdownItem(
                      value: version,
                      label: "Java $version",
                    );
                  }).toList(),
                  initialValue: "21",
                  onChanged: _isInstallingJava ? null : (val) => setState(() => _selectedJavaVersion = val!),
                )
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
              child: _isInstallingJava
                  ? Padding(
                padding: const EdgeInsets.only(top: 24),
                child: SizedBox(
                  width: isPortrait ? double.infinity : 400,
                  child: Column(
                    children: [
                      IgnorePointer(
                        child: GoogleSquigglySlider(
                          value: _installProgress * 100, 
                          max: 100,
                          isPlaying: _installStatus.contains("下载"), // 安装阶段开启精子
                          activeColor: Theme.of(context).colorScheme.primary,
                          inactiveColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(_installStatus, textAlign: TextAlign.center, style: hintStyle),
                    ],
                  ),
                ),
              )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _isCheckingJava || _isInstallingJava ? null : _checkJavaEnvironment,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(width: 1.5, color: theme.dividerColor),
                  ),
                  child: const Text("重新检测"),
                ),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: _isCheckingJava || _isInstallingJava ? null : _installJava,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(_isInstallingJava ? "正在安装..." : (_javaInstalled ? "更换为 Java $_selectedJavaVersion" : "安装 Java $_selectedJavaVersion")),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text("推荐安装 Java 21，这是 Minecraft 最新版本的推荐版本。", textAlign: TextAlign.center, style: hintStyle),
          ],
        );
      case 5:
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: isPortrait ? 24 : 0),
          child: Column(
            children: [
              Text("Minecraft 游戏文件夹", textAlign: TextAlign.center, style: headerStyle),
              const SizedBox(height: 16),
              Text("请选择或确认您的 Minecraft 游戏文件夹位置。\n您可以添加多个目录，Launcher 将自动扫描其中的版本。",
                  textAlign: TextAlign.center, style: hintStyle),
              const SizedBox(height: 32),
              Container(
                constraints: const BoxConstraints(maxHeight: 250),
                width: isPortrait ? double.infinity : 500,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: _minecraftDirs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.folder, size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _minecraftDirs[index],
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _minecraftDirs.removeAt(index)),
                            icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                  if (selectedDirectory != null) {
                    setState(() {
                      if (!_minecraftDirs.contains(selectedDirectory)) {
                        _minecraftDirs.add(selectedDirectory);
                      }
                    });
                  }
                },
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text("添加游戏目录", style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 24),
              Text("提示：如果您不知道在哪里，可以使用默认路径。", textAlign: TextAlign.center, style: hintStyle),
            ],
          ),
        );
      case 6:
        return Column(
          children: [
            Text("手机遥控手柄", textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 16),
            Text("您可以将手机作为 Minecraft 的遥控手柄使用！\n扫描下方二维码，或在浏览器打开以下地址访问遥控页面：",
                textAlign: TextAlign.center, style: bodyStyle),
            const SizedBox(height: 32),
            Container(
              width: 160,
              height: 160,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.qr_code_2, size: 140, color: Colors.black), // Mock QR code
            ),
            const SizedBox(height: 24),
            Text("扫码或在浏览器打开：", style: bodyStyle),
            const SizedBox(height: 8),
            SelectableText(
              "http://$_localIp:25252/",
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 24),
            Text("提示：确保手机和电脑在同一网络下。", textAlign: TextAlign.center, style: hintStyle),
          ],
        );
      default:
        return Column(
          children: [
            Text(_stepLabels[step], textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 16),
            Text("未定义的步骤内容", textAlign: TextAlign.center, style: bodyStyle),
          ],
        );
    }
  }

  Widget _buildBottomButtons(bool isPortrait) {
    final theme = Theme.of(context);
    final bool isLoggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
    
    bool canProceed() {
      switch (_currentStep) {
        case 0: return true;
        case 1: return true;
        case 2: return isLoggedIn && _isTokenValidNotifier.value;
        case 3: return _getAccounts().isNotEmpty;
        case 4: return _javaInstalled || Platform.isAndroid;
        case 5: return _minecraftDirs.isNotEmpty;
        case 6: return true;
        default: return false;
      }
    }

    final bool nextDisabled = !canProceed();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isPortrait ? 10.0 : 32.0, vertical: isPortrait ? 4.0 : 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_currentStep > 0)
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                setState(() => _currentStep--);
                if (_currentStep == 2) {
                  _checkTokenValidity();
                }
              },
              child: const Text("返回", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(width: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: nextDisabled ? null : () async {
              if (_currentStep < _totalSteps - 1) {
                setState(() => _currentStep++);
                if (_currentStep == 2) {
                  _checkTokenValidity();
                }
              } else {
                await ConfigService.setLanguage(_selectedLanguage);
                await ConfigService.set('minecraft_dirs', _minecraftDirs);
                await ConfigService.setFirstRunCompleted();

                if (mounted) {
                  Navigator.of(context).pushReplacement(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => const MainShell(),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.05),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                            child: child,
                          ),
                        );
                      },
                      transitionDuration: const Duration(milliseconds: 800),
                    ),
                  );
                }
              }
            },
            child: Text(_currentStep == _totalSteps - 1 ? "完成" : "下一步", style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _GeneratedJavaSelector extends StatefulWidget {
  final List<String> paths;
  final String current;
  final ValueChanged<String> onChanged;

  const _GeneratedJavaSelector({
    required this.paths,
    required this.current,
    required this.onChanged,
  });

  @override
  State<_GeneratedJavaSelector> createState() => _GeneratedJavaSelectorState();
}

class _GeneratedJavaSelectorState extends State<_GeneratedJavaSelector> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              open = !open;
            });
          },
          child: Row(
            children: [
              Icon(
                Icons.folder_open,
                size: 20,
                color: theme.colorScheme.primary,
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "当前检测到的路径：",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    Text(
                      widget.current,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: "monospace",
                      ),
                    ),
                  ],
                ),
              ),

              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_down),
              ),
            ],
          ),
        ),

        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: open
              ? Column(
            children: widget.paths.map((path) {
              return ListTile(
                dense: true,
                leading: const Icon(Icons.computer, size: 18),
                title: Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: "monospace",
                    fontSize: 12,
                  ),
                ),
                selected: path == widget.current,
                onTap: () {
                  widget.onChanged(path);
                  setState(() {
                    open = false;
                  });
                },
              );
            }).toList(),
          )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}