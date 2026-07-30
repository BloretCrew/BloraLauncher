import 'dart:convert';
import 'dart:io';

import 'package:bloret_launcher/core/i18n.dart';
import 'package:bloret_launcher/services/bloriko.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:bloret_launcher/widgets/windows_widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/config_service.dart';

class BloraChatPage extends StatefulWidget {
  const BloraChatPage({super.key});

  @override
  State<BloraChatPage> createState() => _BloraChatPageState();
}

class _BloraChatPageState extends State<BloraChatPage> with AutomaticKeepAliveClientMixin {
  bool _historyPanelOpen = false;
  String _currentMode = "auto";
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _msgScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  final List<Map<String, dynamic>> _historyList = [];
  bool _isSelectMode = false;
  final Set<String> _selectedFiles = {};

  // 快捷访问 Bloriko 状态
  Bloriko get _agent => Bloriko.instance;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
    _loadModels();
    
    // 监听全局状态
    _agent.addListener(_onAgentStateChanged);

    // 自动加载最近历史逻辑
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadHistoryList();
      if (_agent.messages.isEmpty && _historyList.isNotEmpty) {
        _loadSession(_historyList.first['filename']);
      }
    });
  }

  void _onAgentStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inputController.dispose();
    _msgScrollController.dispose();
    _agent.removeListener(_onAgentStateChanged);
    super.dispose();
  }

  String _getToolFriendlyName(String name) {
    switch (name) {
      case 'read_file': return _tr("读取文件");
      case 'write_file': return _tr("写入文件");
      case 'get_directory_tree': return _tr("查看目录树");
      case 'set_emotion':
      case 'set_emutation': return _tr("切换心情");
      case 'memory': return _tr("管理记忆");
      case 'list_files': return _tr("列出文件");
      case 'execute_command': return _tr("执行命令");
      case 'interact_with_ui': return _tr("辅助点击");
      default: return name;
    }
  }

  IconData _getToolIcon(String? toolName) {
    switch (toolName) {
      case 'read_file': return Icons.file_open_rounded;
      case 'write_file': return Icons.save_rounded;
      case 'get_directory_tree': return Icons.account_tree_rounded;
      case 'set_emotion':
      case 'set_emutation': return Icons.face_rounded;
      case 'memory': return Icons.psychology_rounded;
      case 'list_files': return Icons.list_alt_rounded;
      case 'execute_command': return Icons.terminal_rounded;
      case 'interact_with_ui': return Icons.touch_app_rounded;
      default: return Icons.auto_fix_high_rounded;
    }
  }

  void _deleteMessage(int index) {
    setState(() {
      _agent.messages.removeAt(index);
    });
    _saveSession();
  }

  void _showMessageMenu(BuildContext context, Offset tapPosition, int index) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          onTap: () {
            Clipboard.setData(ClipboardData(text: _agent.messages[index]['content'] ?? ""));
          },
          child: Row(
            children: [
              const Icon(Icons.copy_rounded, size: 18),
              const SizedBox(width: 8),
              Text(_tr("复制内容")),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () => _deleteMessage(index),
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text(_tr("删除消息"), style: const TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_msgScrollController.hasClients) {
        _msgScrollController.animateTo(
          _msgScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _agent.busy) return;

    final batchId = ++_agent.requestBatch;
    setState(() {
      _agent.messages.add({'role': 'user', 'content': text});
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final workspace = await _getWorkspaceDir();
      
      await _agent.chatWithTools(
        text,
        workingDir: workspace.path,
        enableUiInteraction: _currentMode == 'help',
        onTextChunk: (content) {
          if (batchId != _agent.requestBatch || !mounted) return;
          
          final cleanContent = content.replaceAll("[DONE]", "").replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
          if (cleanContent.isEmpty) return;

          setState(() {
            if (_agent.messages.isNotEmpty && _agent.messages.last['role'] == 'assistant') {
              _agent.messages.last['content'] = cleanContent;
              _agent.messages.last['emotion'] = _agent.emotion;
            } else {
              _agent.messages.add({
                'role': 'assistant',
                'content': cleanContent,
                'emotion': _agent.emotion,
              });
            }

            if (_agent.messages.length <= 2) {
               _agent.conversationTitle = text.split('\n').first.trim();
            }
          });
          _scrollToBottom();
        },
        onToolStart: (name, args) {
          if (batchId != _agent.requestBatch || !mounted) return;
          final friendlyName = _getToolFriendlyName(name);
          setState(() {
            _agent.messages.add({
              'role': 'system', 
              'content': _tr("正在执行工具: ") + friendlyName,
              'tool': name,
              'args': jsonEncode(args),
              'isExpanded': false,
            });
          });
          _scrollToBottom();
        },
        onToolEnd: (name, result) {
          if (batchId != _agent.requestBatch || !mounted) return;
          setState(() {
            for (int i = _agent.messages.length - 1; i >= 0; i--) {
              if (_agent.messages[i]['role'] == 'system' && _agent.messages[i]['tool'] == name) {
                _agent.messages[i]['result'] = result;
                break;
              }
            }
          });
        },
        onError: (err) {
          if (batchId != _agent.requestBatch || !mounted) return;
          setState(() {
            _agent.messages.add({'role': 'error', 'content': err});
          });
          _scrollToBottom();
        }
      );
    } catch (e) {
      if (batchId == _agent.requestBatch && mounted) {
        setState(() {
          _agent.messages.add({'role': 'error', 'content': 'Error: $e'});
        });
        _scrollToBottom();
      }
    } finally {
      if (batchId == _agent.requestBatch && mounted) {
        _saveSession();
      }
    }
  }

  void _clearHistory() {
    if (_agent.busy) return;
    _agent.clearSession();
    setState(() {});
  }

  Future<Directory> _getBloraDataDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dataDir = Directory(p.join(appDir.path, 'blora_agent'));
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return dataDir;
  }

  Future<Directory> _getHistoryDir() async {
    final base = await _getBloraDataDir();
    final historyDir = Directory(p.join(base.path, 'history'));
    if (!await historyDir.exists()) {
      await historyDir.create(recursive: true);
    }
    return historyDir;
  }

  Future<Directory> _getWorkspaceDir() async {
    final base = await _getBloraDataDir();
    final workspaceDir = Directory(p.join(base.path, 'workspace'));
    if (!await workspaceDir.exists()) {
      await workspaceDir.create(recursive: true);
    }
    return workspaceDir;
  }

  Future<void> _saveSession() async {
    if (_agent.messages.isEmpty) return;
    try {
      final dir = await _getHistoryDir();
      
      if (_agent.currentSessionFile == null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final nameStr = _agent.conversationTitle.isEmpty ? "chat" : _agent.conversationTitle;
        final safeName = nameStr.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        _agent.currentSessionFile = p.join(dir.path, "${safeName}_$timestamp.json");
      }

      final file = File(_agent.currentSessionFile!);
      final data = {
        'title': _agent.conversationTitle,
        'messages': _agent.messages,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      await file.writeAsString(jsonEncode(data));
      _loadHistoryList();
    } catch (e) {
      debugPrint("Error saving session: $e");
    }
  }

  Future<void> _loadHistoryList() async {
    try {
      final dir = await _getHistoryDir();
      final List<FileSystemEntity> files = dir.listSync();
      final List<Map<String, dynamic>> loadedList = [];

      for (var file in files) {
        if (file is File && file.path.endsWith('.json')) {
          try {
            final content = await file.readAsString();
            final data = jsonDecode(content);
            loadedList.add({
              'displayText': data['title']?.toString().isNotEmpty == true 
                  ? data['title'] 
                  : p.basename(file.path),
              'subText': p.basename(file.path),
              'filename': file.path,
            });
          } catch (_) {}
        }
      }

      loadedList.sort((a, b) => b['subText'].compareTo(a['subText']));

      setState(() {
        _historyList.clear();
        _historyList.addAll(loadedList);
      });
    } catch (e) {
      debugPrint("Error loading history list: $e");
    }
  }

  Future<void> _loadSession(String filePath) async {
    if (_agent.busy) return;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        setState(() {
          _agent.messages.clear();
          _agent.messages.addAll(List<Map<String, dynamic>>.from(data['messages']));
          _agent.conversationTitle = data['title'] ?? "";
          _agent.currentSessionFile = filePath;
          _historyPanelOpen = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("Error loading session: $e");
    }
  }

  Future<void> _deleteHistoryItem(String filePath) async {
    if (_agent.busy) return;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        if (_agent.currentSessionFile == filePath) {
          _clearHistory();
        }
        _selectedFiles.remove(filePath);
        _loadHistoryList();
      }
    } catch (e) {
      debugPrint("Error deleting history: $e");
    }
  }

  Future<void> _deleteSelectedSessions() async {
    if (_selectedFiles.isEmpty || _agent.busy) return;
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tr("删除确认")),
        content: Text(_tr("确定要删除选中的 ${_selectedFiles.length} 条记录吗？")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_tr("取消"))),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: Text(_tr("删除"), style: const TextStyle(color: Colors.redAccent))
          ),
        ],
      ),
    );

    if (confirm == true) {
      for (var path in _selectedFiles) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      setState(() {
        _selectedFiles.clear();
        _isSelectMode = false;
      });
      _loadHistoryList();
    }
  }

  Future<void> _exportSelectedSessions() async {
    if (_selectedFiles.isEmpty) return;
    for (var path in _selectedFiles) {
      await _exportHistoryItem(path);
    }
    setState(() {
      _isSelectMode = false;
      _selectedFiles.clear();
    });
  }

  Future<void> _exportHistoryItem(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: _tr("导出对话记录"),
          fileName: p.basename(filePath),
          type: FileType.custom,
          allowedExtensions: ['json'],
        );

        if (outputFile != null) {
          final exportFile = File(outputFile);
          await exportFile.writeAsString(content);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_tr("导出成功"))),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Error exporting history: $e");
    }
  }

  void _showHistoryMenu(BuildContext context, Offset tapPosition, Map<String, dynamic> item) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          onTap: () => _exportHistoryItem(item['filename'] ?? ""),
          child: Row(
            children: [
              const Icon(Icons.output_rounded, size: 18),
              const SizedBox(width: 8),
              Text(_tr("导出 JSON")),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () => _deleteHistoryItem(item['filename'] ?? ""),
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text(_tr("删除记录"), style: const TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    );
  }

  String _tr(String text) {
    return text.tl;
  }

  IconData getEmotionIcon(String emotion) {
    switch (emotion) {
      case 'neutral': return Icons.sentiment_satisfied;
      case 'happy': return Icons.sentiment_very_satisfied;
      case 'shy': return Icons.face_retouching_natural;
      case 'angry': return Icons.sentiment_very_dissatisfied;
      case 'sad': return Icons.sentiment_dissatisfied;
      case 'excited': return Icons.celebration;
      case 'curious': return Icons.help_outline;
      default: return Icons.sentiment_satisfied;
    }
  }

  String _getEmotionDisplay(String emotion) {
    switch (emotion) {
      case 'neutral': return _tr("平静");
      case 'happy': return _tr("开心");
      case 'shy': return _tr("害羞");
      case 'angry': return _tr("生气");
      case 'sad': return _tr("难过");
      case 'excited': return _tr("兴奋");
      case 'curious': return _tr("好奇");
      default: return _tr("平静");
    }
  }

  String _currentProviderKey = ConfigService.get('ai_provider') ?? 'bloret_passport';
  String? _currentModelId = ConfigService.get('ai_model');
  List<Map<String, dynamic>> _currentModels = [];

  void _loadModels() {
    final Map<String, dynamic> builtinProviders = {
      "bloret_passport": {
        "models": [{"id": "default", "name": "Claude Fable 5", "tool_call": true}],
      },
      "opencode_zen": {
        "models": [
          {"id": "deepseek-v4-flash-free", "name": "DeepSeek V4 Flash (Free)", "tool_call": true},
          {"id": "mimo-v2.5-free", "name": "Mimo V2.5 (Free)", "tool_call": true},
          {"id": "qwen3.6-plus-free", "name": "Qwen 3.6 Plus (Free)", "tool_call": true},
          {"id": "minimax-m2.5-free", "name": "MiniMax M2.5 (Free)", "tool_call": true},
          {"id": "nemotron-3-super-free", "name": "Nemotron 3 Super (Free)", "tool_call": true},
        ],
      },
    };

    final providerData = builtinProviders[_currentProviderKey];
    _currentModels = providerData != null ? List<Map<String, dynamic>>.from(providerData["models"]) : [];
    if (!_currentModels.any((m) => m["id"] == _currentModelId) && _currentModels.isNotEmpty) {
      _currentModelId = _currentModels[0]["id"];
      ConfigService.set('ai_model', _currentModelId);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    final borderColor = theme.dividerColor;
    final altColor = theme.colorScheme.surfaceContainerHighest;
    final textColor = theme.colorScheme.onSurface;
    final secondaryTextColor = theme.colorScheme.onSurfaceVariant;
    final accentColor = theme.colorScheme.primary;

    return Row(
      children: [
        Expanded(
          child: Stack(
            children: [
              Column(
                children: [
                  Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor))),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 28, height: 28, color: Colors.grey.shade300,
                            child: const Icon(Icons.smart_toy, size: 18),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(_tr("Blora Agent"), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
                        if (_agent.conversationTitle.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text("— ${_agent.conversationTitle}", style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: secondaryTextColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                        const SizedBox(width: 10),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 300),
                          key: ValueKey(_agent.emotion),
                          builder: (context, value, child) => Transform.scale(scale: 0.8 + (0.2 * value), child: Opacity(opacity: value, child: child)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: altColor, border: Border.all(color: borderColor)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(getEmotionIcon(_agent.emotion), size: 14, color: textColor),
                                const SizedBox(width: 4),
                                Text(_getEmotionDisplay(_agent.emotion), style: TextStyle(fontSize: 11, color: textColor)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(_agent.busy ? _tr("思考中...") : _tr("就绪"), style: TextStyle(fontSize: 12, color: _agent.busy ? accentColor : secondaryTextColor)),
                        const Spacer(),
                        SizedBox(
                          width: 128,
                          child: Win11Dropdown(
                            initialValue: _currentMode,
                            items: [
                              Win11DropdownItem(label: _tr("自动模式"), value: "auto"),
                              Win11DropdownItem(label: _tr("辅助点击"), value: "help"),
                              Win11DropdownItem(label: _tr("规划模式"), value: "plan"),
                            ],
                            onChanged: (value) { if (value != null) setState(() => _currentMode = value); },
                          ),
                        ),
                        const SizedBox(width: 8),
                        BloretButton(onPressed: _agent.busy ? null : _clearHistory, text: _tr("新对话")),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: AnimatedRotation(turns: _historyPanelOpen ? 0.25 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.menu, size: 20)),
                          onPressed: () {
                            setState(() {
                              _historyPanelOpen = !_historyPanelOpen;
                              if (_historyPanelOpen) _loadHistoryList();
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: _agent.messages.isEmpty 
                          ? Center(
                        key: const ValueKey("empty"),
                        child: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
                          ClipRRect(borderRadius: BorderRadius.circular(36), child: Container(width: 72, height: 72, color: Colors.grey.shade300, child: const Icon(Icons.smart_toy, size: 36))),
                          const SizedBox(height: 12),
                          Text(_tr("Blora Agent"), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
                          const SizedBox(height: 12),
                          Text(_tr("哥哥好呀！ Blora Agent 在这里等你很久啦~(开心地挥挥小手)\n\n试试跟 Blora Agent 说：\n• 帮我创建一个文件\n• 搜索一下项目里的 TODO\n• 执行一个命令看看\n• 记住我的偏好是..."), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.4, color: secondaryTextColor)),
                        ])),
                      )
                          : ListView.builder(
                        key: const ValueKey("chat_list"),
                        controller: _msgScrollController,
                        itemCount: _agent.messages.length,
                        itemBuilder: (context, index) {
                          final msg = _agent.messages[index];
                          final role = msg['role'];

                          if (role == 'user') {
                            return Align(
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
                                onSecondaryTapDown: (details) => _showMessageMenu(context, details.globalPosition, index),
                                onLongPressStart: (details) => _showMessageMenu(context, details.globalPosition, index),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                  decoration: BoxDecoration(
                                    color: accentColor,
                                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(4)),
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
                                  ),
                                  child: SelectableText(msg['content'] ?? '', style: TextStyle(fontSize: 14, color: theme.colorScheme.onPrimary, height: 1.35)),
                                ),
                              ),
                            );
                          } else if (role == 'assistant') {
                            bool showAvatar = true;
                            if (index > 0) {
                              int prevAssistantIdx = -1;
                              bool intermediateBlocking = false;
                              for (int i = index - 1; i >= 0; i--) {
                                if (_agent.messages[i]['role'] == 'assistant') { prevAssistantIdx = i; break; }
                                else if (_agent.messages[i]['role'] != 'system') { intermediateBlocking = true; break; }
                              }
                              if (prevAssistantIdx != -1 && !intermediateBlocking) {
                                if ((msg['emotion'] ?? 'neutral') == (_agent.messages[prevAssistantIdx]['emotion'] ?? 'neutral')) showAvatar = false;
                              }
                            }

                            return TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic, tween: Tween(begin: 0.0, end: 1.0),
                              builder: (context, value, child) => Opacity(opacity: value, child: Transform.translate(offset: Offset(0, 10 * (1 - value)), child: child)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                                child: GestureDetector(
                                  onSecondaryTapDown: (details) => _showMessageMenu(context, details.globalPosition, index),
                                  onLongPressStart: (details) => _showMessageMenu(context, details.globalPosition, index),
                                  behavior: HitTestBehavior.translucent,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Opacity(
                                        opacity: showAvatar ? 1.0 : 0.0,
                                        child: Container(
                                          margin: const EdgeInsets.only(top: 2),
                                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: altColor, border: Border.all(color: borderColor.withValues(alpha: 0.5))),
                                          padding: const EdgeInsets.all(4),
                                          child: Icon(getEmotionIcon(msg['emotion'] ?? "neutral"), size: 18, color: textColor),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 4), child: GptMarkdown(msg['content'] ?? '...', style: TextStyle(fontSize: 14, color: textColor, height: 1.35)))),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          } else if (role == 'system') {
                            final isExpanded = msg['isExpanded'] ?? false;
                            final hasDetail = msg['args'] != null || msg['result'] != null;
                            return TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic, tween: Tween(begin: 0.0, end: 1.0),
                              builder: (context, value, child) => Opacity(opacity: value, child: Transform.translate(offset: Offset(0, 5 * (1 - value)), child: child)),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 16),
                                  padding: const EdgeInsets.only(left: 32), // 统一对齐：让整条系统消息向右偏移，避开头像位
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: hasDetail ? () => setState(() => msg['isExpanded'] = !isExpanded) : null,
                                        behavior: HitTestBehavior.opaque,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(_getToolIcon(msg['tool']), size: 13, color: secondaryTextColor.withValues(alpha: 0.7)),
                                            const SizedBox(width: 8),
                                            Text(msg['content'] ?? '', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: secondaryTextColor.withValues(alpha: 0.7))),
                                            if (hasDetail) ...[const SizedBox(width: 4), Icon(isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 14, color: secondaryTextColor.withValues(alpha: 0.5))],
                                          ],
                                        ),
                                      ),
                                      AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 300),
                                        switchInCurve: Curves.easeOutBack, switchOutCurve: Curves.easeOutExpo,
                                        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: SizeTransition(sizeFactor: animation, alignment: Alignment.topCenter, child: child)),
                                        child: (isExpanded && hasDetail)
                                            ? Container(
                                          key: const ValueKey("detail"), 
                                          margin: const EdgeInsets.only(top: 8, bottom: 4), 
                                          padding: const EdgeInsets.all(10),
                                          width: double.infinity,
                                          decoration: BoxDecoration(color: altColor.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8), border: Border.all(color: borderColor.withValues(alpha: 0.3))),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (msg['args'] != null) ...[Text(_tr("输入参数:"), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(height: 4), SelectableText(msg['args'], style: const TextStyle(fontSize: 11, fontFamily: "monospace"))],
                                              if (msg['result'] != null) ...[const Divider(height: 16), Text(_tr("执行结果:"), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(height: 4), SelectableText(msg['result'], style: const TextStyle(fontSize: 11, fontFamily: "monospace"))],
                                            ],
                                          ),
                                        ) : const SizedBox(key: ValueKey("empty")),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),

                  Container(
                    decoration: BoxDecoration(color: cardColor, border: Border(top: BorderSide(color: borderColor))),
                    child: Column(
                      children: [
                        if (_agent.busy) const LinearProgressIndicator(minHeight: 2),
                        Padding(
                          padding: const EdgeInsets.only(left: 12, right: 12, top: 12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 160,
                                child: Win11Dropdown(
                                  items: [Win11DropdownItem(label: "Bloret PassPort", value: "bloret_passport"), Win11DropdownItem(label: "OpenCode Zen", value: "opencode_zen")],
                                  initialValue: _currentProviderKey,
                                  onChanged: (value) async { if (value != null) { await ConfigService.set('ai_provider', value); setState(() { _currentProviderKey = value; _loadModels(); }); } },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Win11Dropdown(
                                  items: _currentModels.map((model) => Win11DropdownItem(label: model["name"] ?? "", value: model["id"])).toList(),
                                  initialValue: _currentModelId,
                                  onChanged: (value) async { if (value != null) { await ConfigService.set('ai_model', value); setState(() => _currentModelId = value); } },
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200), curve: Curves.easeInOut,
                                  constraints: const BoxConstraints(maxHeight: 120),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: altColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: _isFocused ? theme.colorScheme.onSurface : borderColor, width: _isFocused ? 1.8 : 1.0)),
                                  child: Scrollbar(
                                    thumbVisibility: true, controller: _msgScrollController, radius: const Radius.circular(8),
                                    child: SingleChildScrollView(
                                      child: Focus(
                                        onKeyEvent: (node, event) {
                                          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                                            final isShift = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) || HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
                                            if (!isShift) { _sendMessage(); return KeyEventResult.handled; }
                                          }
                                          return KeyEventResult.ignored;
                                        },
                                        child: TextField(controller: _inputController, focusNode: _focusNode, maxLines: null, keyboardType: TextInputType.multiline, enabled: !_agent.busy, decoration: InputDecoration(hintText: _tr("向 Blora Agent 说些什么... (Enter 发送, Shift+Enter 换行)"), border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 6)), style: TextStyle(fontSize: 14, color: textColor)),
                                      ),
                                    )
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              IconButton.filled(padding: const EdgeInsets.all(2), icon: Icon(_agent.busy ? Icons.stop : Icons.send, size: 20), onPressed: () { if (_agent.busy) { _agent.cancelAgent(); return; } _sendMessage(); }),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              IgnorePointer(ignoring: !_historyPanelOpen, child: AnimatedOpacity(duration: const Duration(milliseconds: 250), opacity: _historyPanelOpen ? 1.0 : 0.0, child: GestureDetector(onTap: () => setState(() => _historyPanelOpen = false), child: Container(color: Colors.black.withValues(alpha: 0.15))))),
            ],
          ),
        ),

        AnimatedContainer(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOutQuad, width: _historyPanelOpen ? 260 : 0,
          child: ClipRect(child: OverflowBox(
            minWidth: 260, maxWidth: 260, alignment: Alignment.centerRight,
            child: Material(elevation: 0, color: theme.cardColor, child: Container(
              decoration: BoxDecoration(border: Border(left: BorderSide(color: borderColor.withValues(alpha: 0.2)))),
              child: Column(children: [
                Container(height: 52, padding: const EdgeInsets.symmetric(horizontal: 14), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor))), child: Row(children: [
                  if (_isSelectMode) IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => setState(() { _isSelectMode = false; _selectedFiles.clear(); }))
                  else Icon(Icons.history, size: 20, color: textColor),
                  const SizedBox(width: 8),
                  Text(_isSelectMode ? "${_selectedFiles.length} ${_tr("已选择")}" : _tr("历史对话"), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (!_isSelectMode) ...[IconButton(icon: const Icon(Icons.checklist_rtl_rounded, size: 20), onPressed: _agent.busy ? null : () => setState(() => _isSelectMode = true), tooltip: _tr("批量操作")), IconButton(icon: Icon(Icons.refresh, size: 20, color: _agent.busy ? textColor.withValues(alpha: 0.3) : textColor), onPressed: _agent.busy ? null : _loadHistoryList, tooltip: _tr("刷新列表"))]
                  else TextButton(
                    onPressed: () {
                      setState(() {
                        if (_selectedFiles.length == _historyList.length) {
                          _selectedFiles.clear();
                        } else {
                          _selectedFiles.addAll(_historyList.map((e) => e['filename'] as String));
                        }
                      });
                    },
                    child: Text(_selectedFiles.length == _historyList.length ? _tr("取消全选") : _tr("全选"))
                  ),
                ])),
                Expanded(child: Stack(children: [
                  ListView.builder(itemCount: _historyList.length, itemBuilder: (context, index) {
                    final item = _historyList[index];
                    final filePath = item['filename'] ?? "";
                    final isSelected = _selectedFiles.contains(filePath);
                    return GestureDetector(
                      onSecondaryTapDown: (details) => _isSelectMode ? null : _showHistoryMenu(context, details.globalPosition, item),
                      onLongPressStart: (details) => _isSelectMode ? null : _showHistoryMenu(context, details.globalPosition, item),
                      child: InkWell(onTap: () { if (_isSelectMode) {
                        setState(() { if (isSelected) {
                          _selectedFiles.remove(filePath);
                        } else {
                          _selectedFiles.add(filePath);
                        } });
                      } else {
                        _loadSession(filePath);
                      } }, child: Container(
                        height: 58, padding: const EdgeInsets.symmetric(horizontal: 14), decoration: BoxDecoration(color: isSelected ? accentColor.withValues(alpha: 0.1) : null, border: Border(bottom: BorderSide(color: borderColor.withValues(alpha: 0.1)))),
                        child: Row(children: [
                          if (_isSelectMode) ...[Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: isSelected ? accentColor : secondaryTextColor), const SizedBox(width: 12)],
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center, 
                              crossAxisAlignment: CrossAxisAlignment.start, 
                              children: [
                                Text(
                                  item['displayText'] ?? '', 
                                  style: TextStyle(
                                    fontSize: 13, 
                                    fontWeight: FontWeight.bold, 
                                    color: textColor
                                  ), 
                                  maxLines: 1, 
                                  overflow: TextOverflow.ellipsis
                                ), 
                                const SizedBox(height: 2), 
                                Text(
                                  item['subText'] ?? '', 
                                  style: TextStyle(
                                    fontSize: 11, 
                                    color: secondaryTextColor.withValues(alpha: 0.7)
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              ]
                            )
                          ),
                        ]),
                      )),
                    );
                  }),
                  if (_isSelectMode && _selectedFiles.isNotEmpty) Positioned(bottom: 16, left: 16, right: 16, child: Container(height: 50, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [IconButton(icon: const Icon(Icons.output_rounded, color: Colors.blue), onPressed: _exportSelectedSessions, tooltip: _tr("批量导出")), const VerticalDivider(width: 1, indent: 12, endIndent: 12), IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: _deleteSelectedSessions, tooltip: _tr("批量删除"))]))),
                  if (_historyList.isEmpty) Center(child: Text(_tr("暂无历史记录"), style: TextStyle(fontSize: 13, color: secondaryTextColor))),
                ])),
              ]),
            )),
          )),
        ),
      ],
    );
  }
}
