import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../core/logger.dart';
import '../core/plugin_decoder.dart';
import '../main.dart';
import '../models/plugin.dart';
import 'config_service.dart';

class PluginService extends ChangeNotifier {
  static final PluginService instance = PluginService._();
  PluginService._();

  final List<BloretPlugin> _plugins = [];
  List<BloretPlugin> get plugins => _plugins;

  bool _isInitialized = false;
  StreamSubscription<FileSystemEvent>? _watcherSubscription;
  bool _isHotReloadEnabled = false;
  bool get isHotReloadEnabled => _isHotReloadEnabled;

  Future<void> init() async {
    if (_isInitialized) return;
    await scanPlugins();
    _isHotReloadEnabled = ConfigService.get("plugin_hot_reload") ?? false;
    if (_isHotReloadEnabled) {
      _startWatching();
    }
    _isInitialized = true;
  }

  Future<Directory> getPluginsDir() async {
    Directory supportDir = await getSupportData();
    final dir = Directory(p.join(supportDir.path, 'plugins'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> setHotReload(bool enabled) async {
    _isHotReloadEnabled = enabled;
    await ConfigService.set("plugin_hot_reload", enabled);
    if (enabled) {
      _startWatching();
    } else {
      _stopWatching();
    }
    notifyListeners();
  }

  void _startWatching() async {
    _stopWatching();
    final dir = await getPluginsDir();
    _watcherSubscription = dir.watch(recursive: true).listen((event) {
      scanPlugins();
    });
    logger.info("[PluginService] Hot reload started", LogSource.system);
  }

  void _stopWatching() {
    _watcherSubscription?.cancel();
    _watcherSubscription = null;
  }

  Future<void> scanPlugins() async {
    try {
      final dir = await getPluginsDir();
      final List<FileSystemEntity> entities = dir.listSync();
      
      _plugins.clear();
      
      for (var entity in entities) {
        if (entity is Directory) {
          final plugin = await _loadPluginFromDirectory(entity);
          if (plugin != null) {
            if (plugins.any((e) => e.id == plugin.id)) {
              plugins.remove(plugins.firstWhere((e) => e.id == plugin.id));
            }
            _plugins.add(plugin);
          }
        }
      }
      
      notifyListeners();
    } catch (e) {
      logger.error("[PluginService] Scan failed: $e", LogSource.system);
    }
  }

  Future<BloretPlugin?> _loadPluginFromDirectory(Directory dir) async {
    try {
      final manifestFile = File(p.join(dir.path, 'manifest.json'));
      if (!await manifestFile.exists()) return null;

      final content = await manifestFile.readAsString();
      final Map<String, dynamic> jsonMap = json.decode(content);
      
      final plugin = BloretPlugin.fromJson(jsonMap);

      final config = ConfigService.get("plugin_config_${plugin.id}") ?? {};
      plugin.grantedPermissions = List<String>.from(config['granted_permissions'] ?? []);
      plugin.isEnabled = config['enabled'] ?? true;
      
      return plugin;
    } catch (e) {
      logger.error("[PluginService] Load failed for ${dir.path}: $e", LogSource.system);
      return null;
    }
  }

  Future<void> togglePlugin(String id, bool enabled) async {
    final index = _plugins.indexWhere((p) => p.id == id);
    if (index != -1) {
      _plugins[index].isEnabled = enabled;
      await _savePluginConfig(_plugins[index]);
      notifyListeners();
    }
  }

  Future<void> updatePermissions(String id, List<String> permissions) async {
    final index = _plugins.indexWhere((p) => p.id == id);
    if (index != -1) {
      _plugins[index].grantedPermissions = permissions;
      await _savePluginConfig(_plugins[index]);
      notifyListeners();
    }
  }

  Future<void> _savePluginConfig(BloretPlugin plugin) async {
    await ConfigService.set("plugin_config_${plugin.id}", {
      'enabled': plugin.isEnabled,
      'granted_permissions': plugin.grantedPermissions,
    });
  }

  List<Map<String, dynamic>> getToolsContributions() {
    List<Map<String, dynamic>> tools = [];
    for (var plugin in _plugins) {
      if (plugin.isEnabled && plugin.contributions.containsKey('tool_cards')) {
        final cards = plugin.contributions['tool_cards'];
        if (cards is List) {
          for (var card in cards) {
            if (card is Map<String, dynamic>) {
              Map<String, dynamic> cardWithMeta = Map.from(card);
              cardWithMeta['_pluginId'] = plugin.id;
              tools.add(cardWithMeta);
            }
          }
        }
      }
    }
    return tools;
  }

  Future<void> runToolAction(Map<String, dynamic> card) async {
    final pluginId = card['_pluginId'];
    final action = card['action'];
    if (pluginId == null || action == null) return;

    final plugin = _plugins.firstWhere((p) => p.id == pluginId);
    if (!plugin.isEnabled) return;

    final decoder = PluginDecoder(plugin, plugin.contributions);
    
    if (action is Map && action.containsKey('flow')) {
      final flowName = action['flow'];
      final flowSteps = plugin.contributions['flows']?[flowName];
      if (flowSteps is List) {
        await decoder.runFlow(flowSteps);
      }
    }
  }
}
