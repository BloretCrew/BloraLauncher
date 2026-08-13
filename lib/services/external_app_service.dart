import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'config_service.dart';
import '../core/logger.dart';
import '../core/ffi_proxy.dart';
import '../main.dart';

class CustomApp {
  final String id;
  String name;
  String exePath;
  String? iconPath;
  String args;
  String? workingDir;
  bool runAsAdmin;
  String priority;
  String envVars;
  bool killOnExit;

  CustomApp({
    required this.id,
    required this.name,
    required this.exePath,
    this.iconPath,
    this.args = "",
    this.workingDir,
    this.runAsAdmin = false,
    this.priority = "Normal",
    this.envVars = "",
    this.killOnExit = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'exePath': exePath,
    'iconPath': iconPath,
    'args': args,
    'workingDir': workingDir,
    'runAsAdmin': runAsAdmin,
    'priority': priority,
    'envVars': envVars,
    'killOnExit': killOnExit,
  };

  factory CustomApp.fromJson(Map<String, dynamic> json) => CustomApp(
    id: json['id'],
    name: json['name'],
    exePath: json['exePath'],
    iconPath: json['iconPath'],
    args: json['args'] ?? "",
    workingDir: json['workingDir'],
    runAsAdmin: json['runAsAdmin'] ?? false,
    priority: json['priority'] ?? "Normal",
    envVars: json['envVars'] ?? "",
    killOnExit: json['killOnExit'] ?? json['closeLauncher'] ?? false,
  );
}

class ExternalAppService {
  static final ExternalAppService instance = ExternalAppService._();
  ExternalAppService._();

  List<CustomApp> getCustomApps() {
    final List<dynamic>? raw = ConfigService.get('custom_apps');
    if (raw == null) return [];
    return raw.map((e) => CustomApp.fromJson(e)).toList();
  }

  Future<void> saveCustomApps(List<CustomApp> apps) async {
    await ConfigService.set('custom_apps', apps.map((e) => e.toJson()).toList());
  }

  Future<void> addApp(CustomApp app) async {
    final apps = getCustomApps();
    apps.add(app);
    await saveCustomApps(apps);
  }

  Future<void> removeApp(String id) async {
    final apps = getCustomApps();
    apps.removeWhere((e) => e.id == id);
    await saveCustomApps(apps);
  }

  Future<String?> extractIcon(String exePath) async {
    if (!Platform.isWindows) return null;

    try {
      final appDir = await getApplicationSupportDirectory();
      final iconDir = Directory(p.join(appDir.path, 'custom_app_icons'));
      if (!iconDir.existsSync()) await iconDir.create(recursive: true);

      final iconPath = p.join(iconDir.path, '${DateTime.now().millisecondsSinceEpoch}.png');

      // FFI FFI i c your M
      final result = WinProcess.extractHighResIcon(exePath, iconPath);
      
      if (result == 0 && File(iconPath).existsSync()) {
        logger.info("High-res icon extracted successfully for $exePath", LogSource.system);
        return iconPath;
      } else {
        logger.warning("High-res extraction failed (code: $result), trying fallback...", LogSource.system);

        final psCommand = '''
Add-Type -AssemblyName System.Drawing
[System.Drawing.Icon]::ExtractAssociatedIcon("${exePath.replaceAll('"', '`"')}").ToBitmap().Save("${iconPath.replaceAll('"', '`"')}", [System.Drawing.Imaging.ImageFormat]::Png)
''';
        final fallbackResult = await Process.run('powershell', ['-Command', psCommand]);
        if (fallbackResult.exitCode == 0 && File(iconPath).existsSync()) {
          return iconPath;
        }
      }
    } catch (e) {
      logger.error("Exception extracting icon: $e", LogSource.system);
    }
    return null;
  }
}
