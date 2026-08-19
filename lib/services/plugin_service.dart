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

            if (plugin.isEnabled) {
              runOnLoad(plugin);
            }
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
      final plugin = _plugins[index];
      plugin.isEnabled = enabled;
      await _savePluginConfig(plugin);
      if (enabled) {
        runOnLoad(plugin);
      }
      notifyListeners();
    }
  }

  Future<void> runOnLoad(BloretPlugin plugin) async {
    final onLoadSteps = plugin.contributions['flows']?['on_load'];
    if (onLoadSteps is List) {
      plugin.isBusy = true;
      notifyListeners();
      
      final decoder = PluginDecoder(plugin, plugin.contributions);
      await decoder.runFlow(onLoadSteps);
      
      plugin.isBusy = false;
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

  Future<void> updatePluginSettings(String id, Map<String, dynamic> settings) async {
    final index = _plugins.indexWhere((p) => p.id == id);
    if (index != -1) {
      final plugin = _plugins[index];
      plugin.pluginSettingsValues.clear();
      plugin.pluginSettingsValues.addAll(settings);
      await _savePluginConfig(plugin);
      
      // 设置变更后，自动触发一次加载逻辑以同步 UI
      runOnLoad(plugin);
      notifyListeners();
    }
  }

  Future<void> deletePlugin(String id) async {
    final index = _plugins.indexWhere((p) => p.id == id);
    if (index != -1) {
      final pluginDir = await getPluginsDir();
      // 假设文件夹名字和ID一致，或者从路径获取。实际开发中应该在加载时记录路径。
      // 这里我们为了演示，通过扫描找到匹配的文件夹
      final List<FileSystemEntity> entities = pluginDir.listSync();
      for (var entity in entities) {
        if (entity is Directory) {
          final manifestFile = File(p.join(entity.path, 'manifest.json'));
          if (await manifestFile.exists()) {
            final content = await manifestFile.readAsString();
            final jsonMap = json.decode(content);
            if (jsonMap['id'] == id) {
              await entity.delete(recursive: true);
              break;
            }
          }
        }
      }
      _plugins.removeAt(index);
      await ConfigService.set("plugin_config_$id", null);
      notifyListeners();
    }
  }

  Future<void> deleteAllPlugins() async {
    final dir = await getPluginsDir();
    if (await dir.exists()) {
      final List<FileSystemEntity> entities = dir.listSync();
      for (var entity in entities) {
        if (entity is Directory) {
          await entity.delete(recursive: true);
        }
      }
    }
    _plugins.clear();
    notifyListeners();
  }

  Future<void> _savePluginConfig(BloretPlugin plugin) async {
    await ConfigService.set("plugin_config_${plugin.id}", {
      'enabled': plugin.isEnabled,
      'granted_permissions': plugin.grantedPermissions,
      'persistent_values': plugin.persistentValues,
      'settings_values': plugin.pluginSettingsValues,
    });
  }

  List<Map<String, dynamic>> getHomeCards() {
    List<Map<String, dynamic>> cards = [];
    for (var plugin in _plugins) {
      if (plugin.isEnabled && 
          plugin.hasPermission('ui.home') && 
          plugin.contributions.containsKey('home_cards')) {
        final pluginCards = plugin.contributions['home_cards'];
        if (pluginCards is List) {
          for (var card in pluginCards) {
            if (card is Map<String, dynamic>) {
              Map<String, dynamic> cardWithMeta = Map.from(card);
              cardWithMeta['_pluginId'] = plugin.id;
              cards.add(cardWithMeta);
            }
          }
        }
      }
    }
    return cards;
  }

  List<Map<String, dynamic>> getToolsContributions() {
    List<Map<String, dynamic>> tools = [];
    for (var plugin in _plugins) {
      if (plugin.isEnabled && 
          plugin.hasPermission('ui.tools') && 
          plugin.contributions.containsKey('tool_cards')) {
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

    plugin.isBusy = true;
    notifyListeners();

    final decoder = PluginDecoder(plugin, plugin.contributions);
    
    if (action is Map && action.containsKey('flow')) {
      final flowName = action['flow'];
      final flowSteps = plugin.contributions['flows']?[flowName];
      if (flowSteps is List) {
        await decoder.runFlow(flowSteps);
      }
    }

    plugin.isBusy = false;
    notifyListeners();
  }
}
