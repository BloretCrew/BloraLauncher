import 'dart:convert';
import 'dart:io';

import 'package:bloret_launcher/core/i18n.dart';
import 'package:bloret_launcher/core/logger.dart';
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
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _msgScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  final List<Map<String, dynamic>> _historyList = [];
  bool _isSelectMode = false;
  final Set<String> _selectedFiles = {};

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

    _agent.addListener(_onAgentStateChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_agent.initialPrompt != null) {
        final prompt = _agent.initialPrompt!;
        _agent.initialPrompt = null;
        _inputController.text = prompt;
        _sendMessage();
      } else {
        await _loadHistoryList();
        if (_agent.messages.isEmpty && _historyList.isNotEmpty) {
          _loadSession(_historyList.first['filename']);
        }
        _scrollToBottom();
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

  IconData _getToolIcon(String? toolName) {
    switch (toolName) {
      case 'read_file': return Icons.file_open_rounded;
      case 'write_file': return Icons.save_rounded;
      case 'get_directory_tree': return Icons.account_tree_rounded;
      case 'set_emotion':
      case 'set_emutation': return Icons.face_rounded;
      case 'memory': return Icons.psychology_rounded;
      case 'list_memory': return Icons.visibility_rounded;
      case 'list_files': return Icons.list_alt_rounded;
      case 'execute_command': return Icons.terminal_rounded;
      case 'interact_with_ui': return Icons.touch_app_rounded;
      case 'perform_ui_actions': return Icons.bolt_rounded;
      case 'get_semantics_tree': return Icons.streetview;
      case 'recall_history': return Icons.history_edu_rounded;
      case 'web_search': return Icons.language_rounded;
      case 'ask_question': return Icons.question_answer_rounded;
      case 'fetch_page': return Icons.web_rounded;
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
          duration: const Duration(milliseconds: 500),
          curve: Curves.linearToEaseOut,
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
      if (_agent.messages.length == 1 || _agent.conversationTitle.isEmpty) {
        _agent.conversationTitle = text.split('\n').first.trim();
      }
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final workspace = await _getWorkspaceDir();
      
      await _agent.chatWithTools(
        text,
        workingDir: workspace.path,
        enableUiInteraction: Bloriko.mode == 'help',
        onTextChunk: (content) {
          if (batchId != _agent.requestBatch || !mounted) return;
          _scrollToBottom();
          _saveSession(shouldRefreshList: false); 
        },
        onToolStart: (name, args) {
          if (batchId != _agent.requestBatch || !mounted) return;
          _scrollToBottom();
        },
        onToolEnd: (name, result) {
          if (batchId != _agent.requestBatch || !mounted) return;
          _saveSession(shouldRefreshList: false);
        },
        onError: (err) {
          if (batchId != _agent.requestBatch || !mounted) return;
          _scrollToBottom();
        }
      );
    } catch (e) {
      if (batchId == _agent.requestBatch && mounted) {
        final l = await AppLogger.getInstance();
        l.log("发送消息异常", level: LogLevel.error, source: LogSource.network, detail: e.toString());
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

  Future<void> _saveSession({bool shouldRefreshList = true}) async {
    if (_agent.messages.isEmpty) return;
    try {
      final dir = await _getHistoryDir();
      
      if (_agent.currentSessionFile == null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        String nameStr = _agent.conversationTitle.isEmpty ? "chat" : _agent.conversationTitle;
        if (nameStr.length > 30) nameStr = "${nameStr.substring(0, 30)}...";
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
      if (shouldRefreshList) {
        _loadHistoryList();
      }
    } catch (e) {
      final l = await AppLogger.getInstance();
      l.log("保存会话失败", level: LogLevel.error, source: LogSource.fileSystem, detail: e.toString());
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
              'timestamp': data['timestamp'] ?? 0,
            });
          } catch (_) {}
        }
      }

      loadedList.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

      setState(() {
        _historyList.clear();
        _historyList.addAll(loadedList);
      });
    } catch (e) {
      final l = await AppLogger.getInstance();
      l.log("加载历史列表失败", level: LogLevel.error, source: LogSource.fileSystem, detail: e.toString());
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
      final l = await AppLogger.getInstance();
      l.log("加载会话失败", level: LogLevel.error, source: LogSource.fileSystem, detail: "Path: $filePath\nError: $e");
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
      final l = await AppLogger.getInstance();
      l.log("删除历史失败", level: LogLevel.error, source: LogSource.fileSystem, detail: "Path: $filePath\nError: $e");
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
      final String? currentFile = _agent.currentSessionFile;
      bool currentDeleted = false;

      for (var path in _selectedFiles) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
            if (path == currentFile) {
              currentDeleted = true;
            }
          }
        } catch (e) {
          final l = await AppLogger.getInstance();
          l.log("批量删除失败", level: LogLevel.error, source: LogSource.fileSystem, detail: "Path: $path\nError: $e");
        }
      }

      setState(() {
        _selectedFiles.clear();
        _isSelectMode = false;
        if (currentDeleted) {
          _agent.clearSession();
        }
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
      final l = await AppLogger.getInstance();
      l.log("导出历史失败", level: LogLevel.error, source: LogSource.fileSystem, detail: "Path: $filePath\nError: $e");
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
    super.build(context);
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
                    padding: const EdgeInsets.only(left: 16, right: 4),
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
                        const SizedBox(width: 8),
                        Expanded(
                          child: _agent.conversationTitle.isNotEmpty 
                            ? Text("— ${_agent.conversationTitle}", style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: secondaryTextColor), maxLines: 1, overflow: TextOverflow.ellipsis)
                            : const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 128,
                          child: Win11Dropdown(
                            initialValue: Bloriko.mode,
                            items: [
                              Win11DropdownItem(label: _tr("自动模式"), value: "auto"),
                              Win11DropdownItem(label: _tr("辅助点击"), value: "help"),
                              Win11DropdownItem(label: _tr("规划模式"), value: "plan"),
                            ],
                            onChanged: (value) { if (value != null) setState(() => Bloriko.mode = value); },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 128,
                          child: Win11Dropdown(
                            initialValue: Bloriko.type,
                            items: [
                              Win11DropdownItem(label: _tr("默认"), value: "default"),
                              Win11DropdownItem(label: _tr("络可"), value: "bloriko"),
                            ],
                            onChanged: (value) async { 
                              if (value != null && value != Bloriko.type) {
                                if (_agent.messages.isNotEmpty) {
                                  final bool? result = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text(_tr("切换角色类型")),
                                      content: Text(_tr("在对话中切换角色可能会导致 AI 上下文紊乱。是否开启新对话以获得最佳体验？")),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false), 
                                          child: Text(_tr("忽略并保持"))
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true), 
                                          child: Text(_tr("开启新对话"))
                                        ),
                                      ],
                                    ),
                                  );
                                  if (result == true) {
                                    _clearHistory();
                                  }
                                }
                                setState(() => Bloriko.type = value);
                              }
                            },
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
                        itemCount: _agent.messages.length + (_agent.busy ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _agent.messages.length) {
                            bool showAvatar = true;
                            if (index > 0 && _agent.messages[index - 1]['role'] == 'assistant') {
                              showAvatar = false;
                            }

                            bool isWaiting = _agent.messages.isNotEmpty && 
                                             ((_agent.messages.last['role'] == 'system' && 
                                               _agent.messages.last['tool'] == 'ask_question' && 
                                               _agent.messages.last['status'] == 'running') ||
                                              (_agent.messages.last['role'] == 'security' &&
                                               _agent.messages.last['status'] == 'waiting'));

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              child: Row(
                                children: [
                                  if (showAvatar) ...[
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: altColor),
                                      child: Icon(getEmotionIcon(_agent.emotion), size: 18, color: textColor.withValues(alpha: 0.5)),
                                    ),
                                    const SizedBox(width: 12),
                                  ] else ...[
                                    const SizedBox(width: 38),
                                  ],
                                  Text(_tr(isWaiting ? "等待中..." : "正在思考..."), style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: secondaryTextColor.withValues(alpha: 0.7))),
                                  const SizedBox(width: 8),
                                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                                ],
                              ),
                            );
                          }
                          final msg = _agent.messages[index];
                          final role = msg['role'];

                          if (role == 'security') {
                            final String cmd = msg['command'] ?? "";
                            final bool isWaiting = msg['status'] == 'waiting';

                            return TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic, tween: Tween(begin: 0.0, end: 1.0),
                              builder: (context, value, child) => Opacity(opacity: value, child: Transform.translate(offset: Offset(0, 10 * (1 - value)), child: child)),
                              child: Container(
                                margin: const EdgeInsets.only(left: 48, right: 16, bottom: 12, top: 12),
                                decoration: BoxDecoration(
                                  color: isWaiting ? Colors.orange.withValues(alpha: 0.1) : altColor.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isWaiting ? Colors.orange.withValues(alpha: 0.3) : borderColor),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isWaiting ? Colors.orange.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.1),
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.security_rounded, size: 16, color: isWaiting ? Colors.orange : secondaryTextColor),
                                          const SizedBox(width: 8),
                                          Text(_tr("安全拦截: 外部命令执行申请"), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isWaiting ? Colors.orange.shade900 : secondaryTextColor)),
                                          const Spacer(),
                                          if (!isWaiting) Icon(Icons.check_circle_rounded, size: 14, color: Colors.green.shade400),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(_tr("LLM 试图执行以下系统命令："), style: const TextStyle(fontSize: 12)),
                                          const SizedBox(height: 8),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(6)),
                                            child: SelectableText(cmd, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                                          ),
                                          const SizedBox(height: 16),
                                          if (isWaiting)
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                TextButton(
                                                  onPressed: () => _agent.handleSecurityAction('deny'),
                                                  child: Text(_tr("拒绝"), style: const TextStyle(color: Colors.redAccent)),
                                                ),
                                                const SizedBox(width: 8),
                                                OutlinedButton(
                                                  onPressed: () => _agent.handleSecurityAction('allow'),
                                                  child: Text(_tr("允许一次")),
                                                ),
                                                const SizedBox(width: 8),
                                                FilledButton.icon(
                                                  onPressed: () => _agent.handleSecurityAction('always', command: cmd),
                                                  icon: const Icon(Icons.verified_user_rounded, size: 16),
                                                  label: Text(_tr("总是允许")),
                                                ),
                                              ],
                                            )
                                          else
                                            Text(
                                              msg['result'] == 'allow' ? _tr("已手动授权执行。") : _tr("已永久加入白名单。"),
                                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: secondaryTextColor),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

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
                                  child: SelectableText(
                                    msg['content'] ?? '', 
                                    style: TextStyle(fontSize: 14, color: theme.colorScheme.onPrimary, height: 1.35),
                                    selectionColor: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                                  ),
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
                                        if (showAvatar)
                                          Container(
                                            margin: const EdgeInsets.only(top: 2),
                                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: altColor, border: Border.all(color: borderColor.withValues(alpha: 0.5))),
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(getEmotionIcon(msg['emotion'] ?? "neutral"), size: 18, color: textColor),
                                          )
                                        else
                                          const SizedBox(width: 32), // 已对齐助手头像宽度 (28+4)
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
                                          padding: const EdgeInsets.all(12),
                                          width: double.infinity,
                                          decoration: BoxDecoration(color: altColor.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8), border: Border.all(color: borderColor.withValues(alpha: 0.3))),
                                          child: StatefulBuilder(builder: (context, setDetailState) {
                                            final List calls = msg['calls'] ?? [];
                                            final int total = calls.isNotEmpty ? calls.length : 1;
                                            int currentIndex = msg['_detailIdx'] ?? (total - 1); // 默认看最后一次（最新的）

                                            Widget buildContent(int idx) {
                                              var data = (calls.isNotEmpty) ? calls[idx] : {'args': msg['args'], 'result': msg['result']};
                                              return Column(
                                                key: ValueKey("call_$idx"),
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (msg['tool'] == 'ask_question' && data['args'] != null) ...[
                                                    Builder(builder: (context) {
                                                      try {
                                                        final Map<String, dynamic> args = jsonDecode(data['args']);
                                                        final String question = args['question'] ?? "";
                                                        final List options = args['options'] ?? [];
                                                        final bool isRunning = msg['status'] == 'running';

                                                        return Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(question, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                                            const SizedBox(height: 12),
                                                            if (isRunning)
                                                              Wrap(
                                                                spacing: 8, runSpacing: 8,
                                                                children: options.map((opt) => BloretButton(
                                                                  text: opt.toString(),
                                                                  onPressed: () => _agent.answerQuestion(opt.toString()),
                                                                )).toList(),
                                                              )
                                                            else
                                                              Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                                decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: accentColor.withValues(alpha: 0.2))),
                                                                child: Row(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                    Icon(Icons.check_circle_outline_rounded, size: 14, color: accentColor),
                                                                    const SizedBox(width: 6),
                                                                    Flexible(
                                                                      child: Text("${_tr("已选择")}: ${data['result'] ?? ''}", style: TextStyle(fontSize: 12, color: accentColor, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                          ],
                                                        );
                                                      } catch (_) { return const Text("解析问题失败"); }
                                                    }),
                                                  ] else ...[
                                                    if (data['args'] != null) ...[Text(_tr("输入参数:"), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(height: 4), SelectableText(data['args'], style: const TextStyle(fontSize: 11, fontFamily: "monospace"))],
                                                    if (data['result'] != null) ...[const SizedBox(height: 12), Text(_tr("执行结果:"), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(height: 4), SelectableText(data['result'], style: const TextStyle(fontSize: 11, fontFamily: "monospace"))],
                                                  ]
                                                ],
                                              );
                                            }

                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (total > 1) ...[
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text("${_tr("第")} ${currentIndex + 1} / $total ${_tr("次调用")}", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor.withValues(alpha: 0.6))),
                                                      Row(
                                                        children: [
                                                          IconButton(
                                                            visualDensity: VisualDensity.compact,
                                                            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                                            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: currentIndex > 0 ? textColor : secondaryTextColor.withValues(alpha: 0.2)),
                                                            onPressed: currentIndex > 0 ? () => setDetailState(() { currentIndex--; msg['_detailIdx'] = currentIndex; }) : null,
                                                          ),
                                                          const SizedBox(width: 12),
                                                          IconButton(
                                                            visualDensity: VisualDensity.compact,
                                                            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                                            icon: Icon(Icons.arrow_forward_ios_rounded, size: 12, color: currentIndex < total - 1 ? textColor : secondaryTextColor.withValues(alpha: 0.2)),
                                                            onPressed: currentIndex < total - 1 ? () => setDetailState(() { currentIndex++; msg['_detailIdx'] = currentIndex; }) : null,
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                  const Divider(height: 16, thickness: 0.5),
                                                ],
                                                AnimatedSwitcher(
                                                  duration: const Duration(milliseconds: 300),
                                                  layoutBuilder: (currentChild, previousChildren) => Stack(alignment: Alignment.topLeft, children: [...previousChildren, if (currentChild != null) currentChild]),
                                                  transitionBuilder: (child, animation) {
                                                    final offsetAnimation = Tween<Offset>(
                                                      begin: const Offset(0.1, 0.0),
                                                      end: Offset.zero,
                                                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
                                                    return FadeTransition(opacity: animation, child: SlideTransition(position: offsetAnimation, child: child));
                                                  },
                                                  child: buildContent(currentIndex),
                                                ),
                                              ],
                                            );
                                          }),
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
