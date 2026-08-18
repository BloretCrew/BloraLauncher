import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/ffi_proxy.dart';
import '../core/logger.dart';
import '../main.dart';
import '../tools/isolate.dart';
import 'config_service.dart';

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
  String category;

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
    this.category = "Standard",
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'showname': name, // Compatibility with Python
    'exePath': exePath,
    'path': exePath, // Compatibility with Python
    'iconPath': iconPath,
    'args': args,
    'workingDir': workingDir,
    'runAsAdmin': runAsAdmin,
    'priority': priority,
    'envVars': envVars,
    'killOnExit': killOnExit,
    'category': category,
  };

  factory CustomApp.fromJson(Map<String, dynamic> json) => CustomApp(
    id:
        json['id'] ??
        json['showname'] ??
        DateTime.now().millisecondsSinceEpoch.toString(),
    name: json['name'] ?? json['showname'] ?? "Unknown",
    exePath: json['exePath'] ?? json['path'] ?? "",
    iconPath: json['iconPath'],
    args: json['args'] ?? "",
    workingDir: json['workingDir'],
    runAsAdmin: json['runAsAdmin'] ?? false,
    priority: json['priority'] ?? "Normal",
    envVars: json['envVars'] ?? "",
    killOnExit: json['killOnExit'] ?? json['closeLauncher'] ?? false,
    category: json['category'] ?? "Standard",
  );
}

class ExternalAppService {
  static final ExternalAppService instance = ExternalAppService._();
  ExternalAppService._();

  List<CustomApp> getCustomApps() {
    final List<dynamic>? raw =
        ConfigService.get('custom_apps') ?? ConfigService.get('Customize');
    if (raw == null) return [];
    return raw.map((e) => CustomApp.fromJson(e)).toList();
  }

  Future<void> saveCustomApps(List<CustomApp> apps) async {
    final List<Map<String, dynamic>> jsonList = apps
        .map((e) => e.toJson())
        .toList();
    await ConfigService.set('custom_apps', jsonList);
    await ConfigService.set('Customize', jsonList); // Keep both in sync
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

  Future<List<Map<String, dynamic>>> listRunningProcesses() async {
    if (!Platform.isWindows) return [];

    try {
      return await runIsolate(_listProcessesTask, null);
    } catch (e) {
      logger.error("Failed to list processes: $e", LogSource.system);
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> _listProcessesTask(
    dynamic _,
  ) async {
    final psCommand =
        'Get-CimInstance Win32_Process | Select-Object ProcessId, Name, ExecutablePath, ParentProcessId | ConvertTo-Json';
    final result = await Process.run('powershell', ['-Command', psCommand]);

    if (result.exitCode == 0) {
      final List<dynamic> data = jsonDecode(result.stdout);
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  Future<String?> extractIcon(String exePath) async {
    if (!Platform.isWindows) return null;

    try {
      final appDir = await getApplicationSupportDirectory();
      final iconDir = Directory(p.join(appDir.path, 'custom_app_icons'));
      if (!iconDir.existsSync()) await iconDir.create(recursive: true);

      final iconPath = p.join(
        iconDir.path,
        '${DateTime.now().millisecondsSinceEpoch}.png',
      );

      final bool success = await runIsolate(_extractIconTask, {
        'exePath': exePath,
        'iconPath': iconPath,
      });

      if (success && File(iconPath).existsSync()) {
        return iconPath;
      }
    } catch (e) {
      logger.error("Exception extracting icon: $e", LogSource.system);
    }
    return null;
  }

  static Future<bool> _extractIconTask(Map<String, String> params) async {
    final exePath = params['exePath']!;
    final iconPath = params['iconPath']!;

    // FFI call in isolate
    final result = WinProcess.extractHighResIcon(exePath, iconPath);
    if (result == 0) return true;

    // Fallback in isolate
    final psCommand =
        '''
Add-Type -AssemblyName System.Drawing
try {
  [System.Drawing.Icon]::ExtractAssociatedIcon("${exePath.replaceAll('"', '`"')}").ToBitmap().Save("${iconPath.replaceAll('"', '`"')}", [System.Drawing.Imaging.ImageFormat]::Png)
  exit 0
} catch {
  exit 1
}
''';
    final fallbackResult = await Process.run('powershell', [
      '-Command',
      psCommand,
    ]);
    return fallbackResult.exitCode == 0;
  }
}
