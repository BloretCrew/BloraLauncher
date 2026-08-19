import 'package:bloret_launcher/core/i18n.dart';

import '../core/global.dart';
import '../services/config_service.dart';

enum PermissionRisk { safe, high }

class PermissionMeta {
  final String label;
  final PermissionRisk risk;

  const PermissionMeta({required this.label, required this.risk});
}

class PluginPermissions {
  static const Map<String, PermissionMeta> registry = {
    // UI
    "ui.nav": PermissionMeta(label: "Add Navigation Page", risk: PermissionRisk.safe),
    "ui.theme": PermissionMeta(label: "Modify Theme", risk: PermissionRisk.safe),
    "ui.settings": PermissionMeta(label: "Add Settings Item", risk: PermissionRisk.safe),
    "ui.toolbar": PermissionMeta(label: "Extend Minecraft Toolbar", risk: PermissionRisk.safe),
    "ui.home": PermissionMeta(label: "Extend Home Cards", risk: PermissionRisk.safe),
    "ui.tools": PermissionMeta(label: "Extend Tools Page Cards", risk: PermissionRisk.safe),
    "ui.cores": PermissionMeta(label: "Extend Cores Management Panel", risk: PermissionRisk.safe),
    "ui.mods": PermissionMeta(label: "Extend Mods Page Panel", risk: PermissionRisk.safe),
    "ui.download": PermissionMeta(label: "Extend Download Page Panel", risk: PermissionRisk.safe),
    "ui.live": PermissionMeta(label: "Extend Live Panel", risk: PermissionRisk.safe),
    "ui.passport": PermissionMeta(label: "Extend PassPort Page Panel", risk: PermissionRisk.safe),
    "ui.bbbs": PermissionMeta(label: "Extend BBBS Page Panel", risk: PermissionRisk.safe),
    "ui.stats": PermissionMeta(label: "Extend Statistics Page Panel", risk: PermissionRisk.safe),
    "ui.info": PermissionMeta(label: "Extend Information Page Panel", risk: PermissionRisk.safe),
    "ui.bloriko": PermissionMeta(label: "Extend Bloriko Page Panel", risk: PermissionRisk.safe),
    "ui.rpe": PermissionMeta(label: "Extend Resource Pack Editor Panel", risk: PermissionRisk.safe),
    "ui.multiplayer": PermissionMeta(label: "Extend Multiplayer Page Panel", risk: PermissionRisk.safe),
    "ui.tray": PermissionMeta(label: "Extend System Tray Menu", risk: PermissionRisk.high),
    "ui.hotkey": PermissionMeta(label: "Register Global Hotkey", risk: PermissionRisk.high),

    // Launch / Download
    "launch.hooks": PermissionMeta(label: "Intercept/Modify Game Launch", risk: PermissionRisk.high),
    "launch.control": PermissionMeta(label: "Control Game Launch and Process", risk: PermissionRisk.high),
    "launch.items": PermissionMeta(label: "Register Custom Launch Items", risk: PermissionRisk.high),
    "download.hooks": PermissionMeta(label: "Intercept Download/Installation Flow", risk: PermissionRisk.high),
    "download.control": PermissionMeta(label: "Control Download Tasks", risk: PermissionRisk.high),
    "download.source": PermissionMeta(label: "Register Custom Download Sources", risk: PermissionRisk.high),

    // Content
    "versions.read": PermissionMeta(label: "Read Versions List", risk: PermissionRisk.safe),
    "versions.write": PermissionMeta(label: "Modify or Delete Versions", risk: PermissionRisk.high),
    "mods.read": PermissionMeta(label: "Read Mods List", risk: PermissionRisk.safe),
    "mods.write": PermissionMeta(label: "Install/Enable/Delete Mods", risk: PermissionRisk.high),
    "mods.source": PermissionMeta(label: "Register Mods Content Sources", risk: PermissionRisk.high),
    "content.read": PermissionMeta(label: "Read Resource Packs/Servers etc.", risk: PermissionRisk.safe),
    "content.write": PermissionMeta(label: "Modify Resource Packs/Servers etc.", risk: PermissionRisk.high),

    // Account / Live
    "accounts.read": PermissionMeta(label: "Read Account Summary", risk: PermissionRisk.safe),
    "accounts.write": PermissionMeta(label: "Switch or Manage Accounts", risk: PermissionRisk.high),
    "live.control": PermissionMeta(label: "Control Live / EasyTier", risk: PermissionRisk.high),

    // Agent / Notify
    "agent.bloriko": PermissionMeta(label: "Extend Bloriko Agent", risk: PermissionRisk.high),
    "agent.blrpe": PermissionMeta(label: "Extend Blora Agent", risk: PermissionRisk.high),
    "agent.provider": PermissionMeta(label: "Register Custom AI Providers", risk: PermissionRisk.high),
    "notify.send": PermissionMeta(label: "Send System Notifications", risk: PermissionRisk.safe),
    "notify.channel": PermissionMeta(label: "Register Notification Channels", risk: PermissionRisk.high),

    // System
    "config.read": PermissionMeta(label: "Read Launcher Configuration", risk: PermissionRisk.safe),
    "config.write": PermissionMeta(label: "Write Launcher Configuration", risk: PermissionRisk.high),
    "fs.datapath": PermissionMeta(label: "Access Data Directory Files", risk: PermissionRisk.high),
    "net.http": PermissionMeta(label: "Initiate Network Requests", risk: PermissionRisk.high),
    "process.exec": PermissionMeta(label: "Execute External Processes", risk: PermissionRisk.high),
    "web.routes": PermissionMeta(label: "Register Local Web Routes", risk: PermissionRisk.high),
    "java.manage": PermissionMeta(label: "Manage Java Runtimes", risk: PermissionRisk.high),
    "protocol.handle": PermissionMeta(label: "Handle Custom Protocol Links", risk: PermissionRisk.high),
    "stats.read": PermissionMeta(label: "Read Play Statistics", risk: PermissionRisk.safe),
  };

  static PermissionRisk getRisk(String id) {
    return registry[id]?.risk ?? PermissionRisk.high;
  }

  static String getLabel(String id) {
    return registry[id]?.label.tl ?? id;
  }
}

class BloretPlugin {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final Map<String, dynamic> contributions;
  final List<String> requestedPermissions;
  final Map<String, dynamic> translations;
  final Map<String, dynamic> settingsSchema;
  final Map<String, dynamic> runtimeValues = {};
  final Map<String, dynamic> persistentValues = {};
  final Map<String, dynamic> pluginSettingsValues = {};
  List<String> grantedPermissions;
  bool isEnabled;
  bool isBusy = false;

  BloretPlugin({
    required this.id,
    required this.name,
    required this.version,
    this.author = "Unknown",
    this.description = "",
    this.contributions = const {},
    this.translations = const {},
    this.settingsSchema = const {},
    required this.requestedPermissions,
    this.grantedPermissions = const [],
    this.isEnabled = true,
  });

  bool hasPermission(String permission) {
    if (grantedPermissions.contains(permission)) return true;
    final prefix = "${permission.split('.').first}.*";
    return grantedPermissions.contains(prefix);
  }

  String translate(String text) {
    final lang = I18n.currentLang.toLowerCase();
    if (translations.containsKey(lang)) {
      final langMap = translations[lang] as Map<String, dynamic>;
      if (langMap.containsKey(text)) {
        return langMap[text].toString();
      }
    }
    return text.tl;
  }

  String resolve(String text) {
    String result = translate(text);

    result = result.replaceAllMapped(RegExp(r'([*&$@%~>])([a-zA-Z0-9_\.\[\]]+)'), (match) {
      final prefix = match.group(1);
      final key = match.group(2)!;
      
      switch (prefix) {
        case r'$': return runtimeValues[key]?.toString() ?? match.group(0)!;
        case '%': return persistentValues[key]?.toString() ?? match.group(0)!;
        case '~': return pluginRuntimeGlobalStore[key]?.toString() ?? match.group(0)!;
        case '>': return pluginSettingsValues[key]?.toString() ?? match.group(0)!;
        default: return match.group(0)!;
      }
    });
    
    return result;
  }

  factory BloretPlugin.fromJson(Map<String, dynamic> json) {
    final plugin = BloretPlugin(
      id: json['id'] ?? "",
      name: json['name'] ?? "",
      version: json['version'] ?? "1.0.0",
      author: json['author'] ?? "Unknown",
      description: json['description'] ?? "",
      contributions: json['contributions'] ?? {},
      translations: json['translate'] ?? {},
      settingsSchema: json['settings'] ?? {},
      requestedPermissions: List<String>.from(json['permissions'] ?? []),
      isEnabled: json['enabled'] ?? true,
    );
    
    final config = ConfigService.get("plugin_config_${plugin.id}") ?? {};
    plugin.grantedPermissions = List<String>.from(config['granted_permissions'] ?? []);
    plugin.isEnabled = config['enabled'] ?? true;
    if (config['persistent_values'] != null) {
      plugin.persistentValues.addAll(Map<String, dynamic>.from(config['persistent_values']));
    }
    
    plugin.settingsSchema.forEach((key, schema) {
      if (config['settings_values']?[key] != null) {
        plugin.pluginSettingsValues[key] = config['settings_values'][key];
      } else {
        plugin.pluginSettingsValues[key] = (schema as Map)['default'];
      }
    });
    
    return plugin;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'author': author,
      'description': description,
      'contributions': contributions,
      'translate': translations,
      'permissions': requestedPermissions,
      'granted_permissions': grantedPermissions,
      'enabled': isEnabled,
    };
  }
}
