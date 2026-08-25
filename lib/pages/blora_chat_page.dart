import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloret_launcher/core/i18n.dart';
import 'package:bloret_launcher/core/logger.dart';
import 'package:bloret_launcher/services/bloriko.dart';
import 'package:bloret_launcher/shell/main_shell.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:bloret_launcher/widgets/windows_widgets.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:image/image.dart' hide Image, Color;
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/global.dart';
import '../core/grammer_candy.dart';
import '../main.dart';
import '../services/config_service.dart';

class BloraChatPage extends StatefulWidget {
  const BloraChatPage({super.key});

  @override
  State<BloraChatPage> createState() => _BloraChatPageState();
}

class _BloraChatPageState extends State<BloraChatPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  bool _historyPanelOpen = false;
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _inputAnswerController = TextEditingController();
  final ScrollController _msgScrollController = ScrollController();
  final ScrollController _inputScrollController = ScrollController();
  final ScrollController _answerScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _focusAnswerNode = FocusNode();
  bool _isFocused = false;

  final List<Map<String, dynamic>> _historyList = [];
  bool _isSelectMode = false;
  final Set<String> _selectedFiles = {};

  bool _isMultiSelectMode = false;
  final Set<int> _selectedMessageIndices = {};
  bool _showScrollToBottom = false;
  late AnimationController _scrollToBottomController;
  int? _hoveredMessageIndex;

  final List<File> _attachments = [];
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final TextEditingController _unlockKeyController = TextEditingController();
  bool _isDocumentMode = false;
  bool _isRecording = false;
  String _textBeforeSpeech = "";

  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  static const int _maxTotalAttachmentSize = 5 * 1024 * 1024;

  Bloriko get _agent => Bloriko.instance;

  Future<int> _calculateTotalAttachmentSize() async {
    int total = 0;
    for (var file in _attachments) {
      if (await file.exists()) {
        total += await file.length();
      }
    }
    return total;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
    _loadModels();
    _initSpeech();

    _agent.addListener(_onAgentStateChanged);

    _scrollToBottomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _msgScrollController.addListener(() {
      if (_msgScrollController.offset > 200) {
        if (!_showScrollToBottom) {
          setState(() => _showScrollToBottom = true);
          _scrollToBottomController.forward();
        }
      } else {
        if (_showScrollToBottom) {
          setState(() => _showScrollToBottom = false);
          _scrollToBottomController.reverse();
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_agent.initialPrompt != null) {
        final prompt = _agent.initialPrompt!;
        _agent.initialPrompt = null;
        _inputController.text = prompt;
        _sendMessage();
      } else {
        final bool isLoggedIn =
            ConfigService.get('Bloret_PassPort_Login') ?? false;
        if (isLoggedIn) {
          _loadHistoryList().then((_) async {
            await Future.delayed(const Duration(milliseconds: 400));
            bool isNewSessionState =
                ConfigService.get('blora_is_new_session_state') ?? false;
            if (!isNewSessionState &&
                _agent.messages.isEmpty &&
                _historyList.isNotEmpty) {
              _loadSession(_historyList.first['filename']);
            }
          });
        }
        if (_agent.messages.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 200), () {
            _scrollToBottom();
          });
        }
      }
    });
  }

  void _onAgentStateChanged() {
    if (!mounted) return;
    if (_agent.initialPrompt != null && !_agent.busy) {
      final prompt = _agent.initialPrompt!;
      _agent.initialPrompt = null;
      _inputController.text = prompt;
      _sendMessage();
    }
    setState(() {});
  }

  Widget _buildCrashCard(Map<String, dynamic> data, ThemeData theme) {
    return BloraCrashCard(data: data, theme: theme);
  }

  @override
  void deactivate() {
    if (_isRecording) {
      _stopRecording();
    }
    super.deactivate();
  }

  @override
  void dispose() {
    if (_isRecording) {
      _speechToText.cancel();
    }
    _inputController.dispose();
    _inputAnswerController.dispose();
    _unlockKeyController.dispose();
    _msgScrollController.dispose();
    _inputScrollController.dispose();
    _answerScrollController.dispose();
    _scrollToBottomController.dispose();
    _agent.removeListener(_onAgentStateChanged);
    super.dispose();
  }

  IconData _getToolIcon(String? toolName) {
    switch (toolName) {
      case 'read_file':
        return Icons.file_open_rounded;
      case 'write_file':
        return Icons.save_rounded;
      case 'get_directory_tree':
        return Icons.account_tree_rounded;
      case 'set_emotion':
      case 'set_emutation':
        return Icons.face_rounded;
      case 'memory':
        return Icons.psychology_rounded;
      case 'list_memory':
        return Icons.visibility_rounded;
      case 'list_files':
        return Icons.list_alt_rounded;
      case 'execute_command':
        return Icons.terminal_rounded;
      case 'interact_with_ui':
        return Icons.touch_app_rounded;
      case 'perform_ui_actions':
        return Icons.bolt_rounded;
      case 'get_semantics_tree':
        return Icons.streetview;
      case 'recall_history':
        return Icons.history_edu_rounded;
      case 'web_search':
        return Icons.language_rounded;
      case 'ask_question':
        return Icons.question_answer_rounded;
      case 'ask_question_details':
        return Icons.message;
      case 'fetch_page':
        return Icons.web_rounded;
      case 'delegate_task':
        return Icons.call_split_rounded;
      case 'shizuku_init':
        return Icons.flash_on_rounded;
      case 'shizuku_check_permission':
        return Icons.verified_user_rounded;
      case 'shizuku_run_shell':
        return Icons.terminal_rounded;
      default:
        return Icons.auto_fix_high_rounded;
    }
  }

  void _deleteMessage(int index) {
    setState(() {
      _agent.messages.removeAt(index);
      _selectedMessageIndices.remove(index);
    });
    _saveSession();
  }

  void _branchConversation(int index) async {
    final messagesToKeep = List<Map<String, dynamic>>.from(
      _agent.messages.sublist(0, index + 1),
    );
    final title = _agent.conversationTitle;

    _clearHistory();
    setState(() {
      _agent.messages.addAll(messagesToKeep);
      _agent.conversationTitle = "$title (Branch)";
      _agent.currentSessionFile = null; // Mark as new session
    });
    _saveSession();
    _scrollToBottom();
    showSuccess("Branched to new conversation".tl);
  }

  void _retryMessage(int index) {
    if (_agent.busy) return;

    // Find the last user message before or at this index
    int lastUserIndex = -1;
    for (int i = index; i >= 0; i--) {
      if (_agent.messages[i]['role'] == 'user') {
        lastUserIndex = i;
        break;
      }
    }

    if (lastUserIndex == -1) return;

    final userMsg = _agent.messages[lastUserIndex];
    setState(() {
      _agent.messages.removeRange(lastUserIndex + 1, _agent.messages.length);
      // Also remove user message to re-send it properly
      _agent.messages.removeAt(lastUserIndex);
    });

    _inputController.text =
        userMsg['displayText'] ??
        (userMsg['content'] is String ? userMsg['content'] : "");
    _sendMessage();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showSuccess("Copied to clipboard".tl);
  }

  void _shareMessage(int index) {
    final msg = _agent.messages[index];
    final content = msg['content']?.toString() ?? "";
    Share.share(content, subject: 'Blora Chat Message');
  }

  void _shareSelectedMessages() {
    if (_selectedMessageIndices.isEmpty) return;
    final List<int> sorted = _selectedMessageIndices.toList()..sort();
    final buffer = StringBuffer();
    for (var idx in sorted) {
      final msg = _agent.messages[idx];
      final role = msg['role'] == 'user' ? "User".tl : "Assistant".tl;
      buffer.writeln("$role: ${msg['content']}");
      buffer.writeln();
    }
    Share.share(buffer.toString(), subject: 'Blora Chat Conversation');
  }

  Future<void> _screenshotSelectedMessages() async {
    if (_selectedMessageIndices.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ScreenshotGenerator(
        messages: _agent.messages,
        selectedIndices: _selectedMessageIndices,
        onCaptured: (bytes) async {
          Navigator.pop(context);
          final tempDir = await getTemporaryDirectory();
          final file = File(
            p.join(
              tempDir.path,
              'chat_capture_${DateTime.now().millisecondsSinceEpoch}.png',
            ),
          );
          await file.writeAsBytes(bytes);

          if (mounted) {
            final int? action = await showDialog<int>(
              context: this.context,
              builder: (context) => AlertDialog(
                title: Text("Screenshot Captured".tl),
                content: Image.memory(bytes, height: 300, fit: BoxFit.contain),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, 0),
                    child: Text("Cancel".tl),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, 1),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text("Copy to Clipboard".tl),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, 2),
                    icon: const Icon(Icons.save_alt_rounded, size: 18),
                    label: Text("Save to File".tl),
                  ),
                ],
              ),
            );

            if (action == 1) {
              await Pasteboard.writeFiles([file.path]);
              showSuccess("Copied to clipboard".tl);
            } else if (action == 2) {
              String? outputFile = await FilePicker.platform.saveFile(
                dialogTitle: "Save Screenshot".tl,
                fileName:
                    'blora_chat_${DateTime.now().millisecondsSinceEpoch}.png',
                type: FileType.image,
              );
              if (outputFile != null) {
                await File(outputFile).writeAsBytes(bytes);
                showSuccess("Saved successfully".tl);
              }
            }
          }
        },
      ),
    );
  }

  void _showMessageMenu(BuildContext context, Offset tapPosition, int index) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final msg = _agent.messages[index];
    final content = msg['content']?.toString() ?? "";
    final regExp = RegExp(r'!\[.*?\]\((.*?)\)');
    final matches = regExp.allMatches(content);

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          onTap: () => _copyToClipboard(content),
          child: Row(
            children: [
              const Icon(Icons.copy_rounded, size: 18),
              const SizedBox(width: 8),
              Text("Copy Content".tl),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () {
            setState(() {
              _isMultiSelectMode = true;
              _selectedMessageIndices.add(index);
            });
          },
          child: Row(
            children: [
              const Icon(Icons.checklist_rounded, size: 18),
              const SizedBox(width: 8),
              Text("Multi-select".tl),
            ],
          ),
        ),
        if (matches.isNotEmpty)
          PopupMenuItem(
            onTap: () {
              for (final m in matches) {
                final url = m.group(1);
                if (url != null) _downloadImage(url);
              }
            },
            child: Row(
              children: [
                const Icon(
                  Icons.download_for_offline_rounded,
                  size: 18,
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                Text(
                  "Download All Images".tl,
                  style: const TextStyle(color: Colors.blue),
                ),
              ],
            ),
          ),
        PopupMenuItem(
          onTap: () => _deleteMessage(index),
          child: Row(
            children: [
              const Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.redAccent,
              ),
              const SizedBox(width: 8),
              Text(
                "Delete Message".tl,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_msgScrollController.hasClients && _agent.messages.isNotEmpty) {
        _msgScrollController.animateTo(
          _msgScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.linearToEaseOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_isRecording) {
      await _stopRecording();
    }
    final text = _inputController.text.trim();
    if (text.isEmpty && _attachments.isEmpty) {
      _inputController.clear();
      return;
    }
    if (_agent.busy) return;

    if (_currentModelId == null) {
      if (_currentModels.isNotEmpty) {
        _currentModelId = _currentModels[0]['id'];
      } else {
        _currentModelId = "default";
      }
    }

    final batchId = ++_agent.requestBatch;

    dynamic userContent;
    final List<Map<String, dynamic>> parts = [];

    String effectiveText = text;
    if (text.isNotEmpty) {
      parts.add({"type": "input_text", "text": text});
    }

    for (var file in _attachments) {
      if (!file.existsSync()) continue;
      final bytes = await file.readAsBytes();
      final base64Data = base64Encode(bytes);
      final filename = p.basename(file.path);
      final ext = p.extension(file.path).toLowerCase();

      if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
        final mimeType = ext == '.jpg' ? 'jpeg' : ext.replaceAll('.', '');
        parts.add({
          "type": "input_image",
          "image_url": "data:image/$mimeType;base64,$base64Data",
          "_decodedBytes": bytes,
        });
      } else {
        parts.add({
          "type": "input_file",
          "filename": filename,
          "file_data": base64Data,
        });
      }
    }

    if (parts.length == 1 && parts[0]['type'] == 'input_text') {
      userContent = text;
    } else {
      userContent = parts;
    }

    setState(() {
      _agent.messages.add({
        'role': 'user',
        'content': userContent,
        'displayText': effectiveText.isNotEmpty
            ? effectiveText
            : "[${"Attachment".tl}]",
      });
      if (_agent.messages.length == 1 || _agent.conversationTitle.isEmpty) {
        _agent.conversationTitle = text.isNotEmpty
            ? text.split('\n').first.trim()
            : "Image/File Conversation".tl;
      }
      _attachments.clear();
    });

    _inputController.clear();
    _scrollToBottom();

    try {
      final workspace = await _getWorkspaceDir();

      await _agent.chatWithTools(
        userContent,
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
        },
      );
    } catch (e) {
      if (batchId == _agent.requestBatch && mounted) {
        logger.error(
          "[BloraChat] Exception sending message: $e",
          LogSource.network,
        );
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
    ConfigService.set('blora_is_new_session_state', true);
    setState(() {});
  }

  Future<Directory> _getBloraDataDir() async {
    final appDir = await getSupportData();
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
        String nameStr = _agent.conversationTitle.isEmpty
            ? "chat"
            : _agent.conversationTitle;
        if (nameStr.length > 30) nameStr = "${nameStr.substring(0, 30)}...";
        final safeName = nameStr.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        _agent.currentSessionFile = p.join(
          dir.path,
          "${safeName}_$timestamp.json",
        );
      }

      final file = File(_agent.currentSessionFile!);
      final data = {
        'title': _agent.conversationTitle,
        'messages': _agent.messages,
        'agentType': Bloriko.type,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await file.writeAsString(jsonEncode(data));
      ConfigService.set('blora_is_new_session_state', false);
      if (shouldRefreshList) {
        _loadHistoryList();
      }
    } catch (e) {
      logger.error(
        "[BloraChat] Failed to save session: $e",
        LogSource.fileSystem,
      );
    }
  }

  Future<void> _loadHistoryList() async {
    final bool isLoggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
    if (!isLoggedIn) return;

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
      logger.error(
        "[BloraChat] Failed to load history list: $e",
        LogSource.fileSystem,
      );
    }
  }

  Future<void> _loadSession(String filePath) async {
    if (_agent.busy) return;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);

        final String? savedType = data['agentType'];
        if (savedType != null && savedType != Bloriko.type) {
          if (!mounted) return;
          final bool? result = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text("Character Type Mismatch".tl),
              content: Text(
                "This conversation last used character '%s', while current is '%s'. Loading directly may cause context confusion."
                    .tl.format(agentNameFn(savedType), agentNameFn(Bloriko.type)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text("Ignore and Load".tl),
                ),
                TextButton(
                  onPressed: () {
                    Bloriko.setType(savedType);
                    Navigator.pop(context, true);
                  },
                  child: Text("${"Switch to".tl} ${agentNameFn(savedType)}"),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context, null);
                    _clearHistory();
                  },
                  child: Text("Start New Conversation".tl),
                ),
              ],
            ),
          );
          if (result == null) return;
        }

        if (!mounted) return;
        setState(() {
          _agent.messages.clear();
          _agent.messages.addAll(
            List<Map<String, dynamic>>.from(data['messages']),
          );
          _agent.conversationTitle = data['title'] ?? "";
          _agent.currentSessionFile = filePath;
          _historyPanelOpen = false;
        });
        ConfigService.set('blora_is_new_session_state', false);
        if (_agent.messages.isNotEmpty) _scrollToBottom();
      }
    } catch (e) {
      logger.error(
        "[BloraChat] Failed to load session: $filePath, Error: $e",
        LogSource.fileSystem,
      );
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
      logger.error(
        "[BloraChat] Failed to delete history: $filePath, Error: $e",
        LogSource.fileSystem,
      );
    }
  }

  Future<void> _deleteSelectedSessions() async {
    if (_selectedFiles.isEmpty || _agent.busy) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Confirmation".tl),
        content: Text(
          "${"Are you sure you want to delete selected".tl} ${_selectedFiles.length} ${"records?".tl}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel".tl),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              "Delete".tl,
              style: const TextStyle(color: Colors.redAccent),
            ),
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
          logger.error(
            "[BloraChat] Failed batch delete: $path, Error: $e",
            LogSource.fileSystem,
          );
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
          dialogTitle: "Export Conversation History".tl,
          fileName: p.basename(filePath),
          type: FileType.custom,
          allowedExtensions: ['json'],
        );

        if (outputFile != null) {
          final exportFile = File(outputFile);
          await exportFile.writeAsString(content);
          if (mounted) {
            showSuccess("Export successful".tl);
          }
        }
      }
    } catch (e) {
      logger.error(
        "[BloraChat] Failed to export history: $filePath, Error: $e",
        LogSource.fileSystem,
      );
    }
  }

  void _showHistoryMenu(
    BuildContext context,
    Offset tapPosition,
    Map<String, dynamic> item,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
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
              Text("Export JSON".tl),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () => _deleteHistoryItem(item['filename'] ?? ""),
          child: Row(
            children: [
              const Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.redAccent,
              ),
              const SizedBox(width: 8),
              Text(
                "Delete Record".tl,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _downloadImage(String url) async {
    try {
      final dio = Dio();
      final response = await dio.get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: "Save Image".tl,
        fileName:
            'downloaded_image_${DateTime.now().millisecondsSinceEpoch}.png',
        type: FileType.image,
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(response.data);
        if (mounted) showSuccess("Image Saved".tl);
      }
    } catch (e) {
      if (mounted) showError("${"Download Failed".tl}: $e");
    }
  }

  void _showImageDialog(
    BuildContext context,
    dynamic imageSource,
    String heroTag,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (context, _, _) => Scaffold(
          backgroundColor: Colors.black.withValues(alpha: 0.85),
          body: Stack(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Center(
                  child: Hero(
                    tag: heroTag,
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: imageSource is File
                          ? Image.file(imageSource)
                          : Image.memory(
                              base64Decode(
                                imageSource.toString().split(',').last,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black26,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'pdf',
        'docx',
        'pptx',
        'txt',
        'csv',
        'xlsx',
        'tsv',
        'dart',
        'py',
        'js',
        'ts',
        'java',
        'kt',
        'cpp',
        'c',
        'h',
        'html',
        'css',
        'json',
        'yaml',
        'xml',
        'md',
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
      ],
    );
    if (result != null) {
      int currentTotal = await _calculateTotalAttachmentSize();
      for (var path in result.paths) {
        if (path != null) {
          final file = File(path);
          final bytes = await file.length();
          if (currentTotal + bytes > _maxTotalAttachmentSize) {
            if (mounted) {
              showWarning(
                "Total attachment size exceeds 5MB, cannot add more files".tl,
              );
            }
            break;
          }
          currentTotal += bytes;
          _attachments.add(file);
          _listKey.currentState?.insertItem(
            _attachments.length - 1,
            duration: const Duration(milliseconds: 300),
          );
        }
      }
      setState(() {});
    }
  }

  void _removeAttachment(int index) {
    if (index < 0 || index >= _attachments.length) return;
    final removedFile = _attachments.removeAt(index);
    _listKey.currentState?.removeItem(
      index,
      (context, animation) => _buildAttachmentItem(removedFile, animation, -1),
      duration: const Duration(milliseconds: 250),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (val) => debugPrint('Speech error: $val'),
        onStatus: _onSpeechStatus,
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Speech init failed: $e');
    }
  }

  void _onSpeechStatus(String status) {
    debugPrint('Speech status: $status');
    if (status == 'done' || status == 'notListening') {
      if (mounted && _isRecording) {
        setState(() => _isRecording = false);
      }
    }
  }

  void _toggleRecording() async {
    if (_agent.busy) return;
    if (!_speechEnabled) {
      await _initSpeech();
      if (!_speechEnabled) {
        if (mounted) {
          showWarning("Voice permissions not granted or unavailable".tl);
        }
        return;
      }
    }

    if (_isRecording) {
      _stopRecording();
    } else {
      _startListening();
    }
  }

  void _startListening() async {
    _textBeforeSpeech = _inputController.text;

    setState(() {
      _isRecording = true;
    });

    try {
      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            final newText = _textBeforeSpeech + result.recognizedWords;
            _inputController.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: newText.length),
            );
          });
          if (result.finalResult) {
            _stopRecording();
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: 'zh_CN',
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
      );
      if (mounted) showInfo("Listening...".tl);
    } catch (e) {
      debugPrint("Speech listen error: $e");
      setState(() {
        _isRecording = false;
      });
      if (mounted) showError("Speech recognition failed to start".tl);
    }
    _focusNode.requestFocus();
  }

  Future<void> _stopRecording() async {
    _isRecording = false;
    setState(() {});
    await _speechToText.stop();
    if (!mounted) return;
    _focusNode.requestFocus();
  }

  Future<void> _handlePaste() async {
    final isInputInitiallyEmpty = _inputController.text.trim().isEmpty;
    try {
      final List<String> files = await Pasteboard.files();
      if (files.isNotEmpty) {
        final allowedExts = {
          '.pdf',
          '.docx',
          '.pptx',
          '.txt',
          '.csv',
          '.xlsx',
          '.tsv',
          '.dart',
          '.py',
          '.js',
          '.ts',
          '.java',
          '.kt',
          '.cpp',
          '.c',
          '.h',
          '.html',
          '.css',
          '.json',
          '.yaml',
          '.xml',
          '.md',
          '.jpg',
          '.jpeg',
          '.png',
          '.gif',
          '.webp',
        };

        int currentTotal = await _calculateTotalAttachmentSize();
        for (var path in files) {
          final file = File(path);
          final ext = p.extension(path).toLowerCase();
          final bytes = await file.length();

          if (currentTotal + bytes > _maxTotalAttachmentSize) {
            if (mounted) {
              showWarning(
                "Total attachment size exceeds 5MB, cannot paste more files".tl,
              );
            }
            break;
          }

          if (file.existsSync() &&
              allowedExts.contains(ext) &&
              !_attachments.any((a) => a.path == path)) {
            currentTotal += bytes;
            _attachments.add(file);
            _listKey.currentState?.insertItem(
              _attachments.length - 1,
              duration: const Duration(milliseconds: 300),
            );
          }
        }
        setState(() {});
        return;
      }

      final imageBytes = await Pasteboard.image;
      if (imageBytes != null) {
        Uint8List? compBytes;
        if (imageBytes.length > 2 * 1024 * 1024) {
          final img = decodeImage(imageBytes);
          final comp = encodeJpg(img!, quality: 50);
          compBytes = Uint8List.fromList(comp);
        }

        final finalBytes = compBytes ?? imageBytes;
        int currentTotal = await _calculateTotalAttachmentSize();
        if (currentTotal + finalBytes.length > _maxTotalAttachmentSize) {
          if (mounted) {
            showWarning(
              "Total attachment size exceeds 5MB, cannot paste this image".tl,
            );
          }
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final fileName =
            'pasted_img_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(p.join(tempDir.path, fileName));
        await file.writeAsBytes(finalBytes);
        _attachments.add(file);
        _listKey.currentState?.insertItem(
          _attachments.length - 1,
          duration: const Duration(milliseconds: 300),
        );
        setState(() {});
        return;
      }

      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final plainText = clipboardData?.text;
      if (plainText != null) {
        if (plainText.length > 4000 && isInputInitiallyEmpty) {
          final utf8Bytes = utf8.encode(plainText);
          int currentTotal = await _calculateTotalAttachmentSize();
          if (currentTotal + utf8Bytes.length > _maxTotalAttachmentSize) {
            if (mounted) {
              showWarning(
                "Pasted text too long and attachment limit reached".tl,
              );
            }
            return;
          }

          final tempDir = await getTemporaryDirectory();
          final fileName =
              'pasted_text_${DateTime.now().millisecondsSinceEpoch}.txt';
          final file = File(p.join(tempDir.path, fileName));
          await file.writeAsString(plainText);

          setState(() {
            _attachments.add(file);
            _listKey.currentState?.insertItem(
              _attachments.length - 1,
              duration: const Duration(milliseconds: 300),
            );
            _inputController.text = '';
            _isDocumentMode = false;
          });
        } else {
          final text = _inputController.text;
          final selection = _inputController.selection;

          String newText;
          int newOffset;

          if (selection.isValid) {
            newText = text.replaceRange(
              selection.start,
              selection.end,
              plainText,
            );
            newOffset = selection.start + plainText.length;
          } else {
            newText = text + plainText;
            newOffset = newText.length;
          }

          _inputController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newOffset),
          );

          if (newText.length > 500) {
            setState(() => _isDocumentMode = true);
          }
        }
      }
    } catch (e) {
      debugPrint("Paste error: $e");
    }
  }

  Widget _buildAttachmentItem(
    File file,
    Animation<double> animation,
    int index,
  ) {
    final isImage = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
    ].any((ext) => file.path.toLowerCase().endsWith(ext));
    final heroTag =
        'attachment_${file.path}_${DateTime.now().millisecondsSinceEpoch}_$index';

    final bounceAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.linearToEaseOut,
    );

    return SizeTransition(
      sizeFactor: bounceAnimation,
      axis: Axis.horizontal,
      alignment: Alignment.centerLeft,
      child: FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: bounceAnimation,
          child: Container(
            width: 70,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              ),
              color: Theme.of(context).colorScheme.surface,
            ),
            child: Stack(
              children: [
                Center(
                  child: isImage
                      ? GestureDetector(
                          onTap: () => _showImageDialog(context, file, heroTag),
                          child: Hero(
                            tag: heroTag,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.file(
                                file,
                                width: 70,
                                height: 70,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                key: ValueKey(file.path),
                              ),
                            ),
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.insert_drive_file_outlined,
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                p.basename(file.path),
                                style: const TextStyle(fontSize: 8),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (file.path.contains('pasted_text_') &&
                                file.path.endsWith('.txt'))
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.keyboard_return_rounded,
                                    size: 14,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () async {
                                    try {
                                      final text = await file.readAsString();
                                      if (text.length > 7500) {
                                        if (mounted) {
                                          showWarning(
                                            "Pasted text too long, cannot restore"
                                                .tl,
                                          );
                                        }
                                        return;
                                      }
                                      setState(() {
                                        _inputController.text = text;
                                        _removeAttachment(index);
                                      });
                                      _focusNode.requestFocus();
                                    } catch (_) {}
                                  },
                                  tooltip: "Restore to Input Box".tl,
                                  constraints: const BoxConstraints(
                                    minHeight: 20,
                                    minWidth: 20,
                                  ),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                          ],
                        ),
                ),
                if (index != -1)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => _removeAttachment(index),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      height: _attachments.isEmpty ? 0 : 90,
      margin: EdgeInsets.only(
        top: _attachments.isEmpty ? 0 : 8,
        bottom: _attachments.isEmpty ? 0 : 4,
      ),
      child: AnimatedList(
        key: _listKey,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        scrollDirection: Axis.horizontal,
        initialItemCount: _attachments.length,
        itemBuilder: (context, index, animation) {
          if (index >= _attachments.length) return const SizedBox.shrink();
          return _buildAttachmentBarItem(_attachments[index], animation, index);
        },
      ),
    );
  }

  Widget _buildAttachmentBarItem(
    File file,
    Animation<double> animation,
    int index,
  ) {
    return _buildAttachmentItem(file, animation, index);
  }

  IconData getEmotionIcon(String emotion) {
    switch (emotion) {
      case 'neutral':
        return Icons.sentiment_satisfied;
      case 'happy':
        return Icons.sentiment_very_satisfied;
      case 'shy':
        return Icons.face_retouching_natural;
      case 'angry':
        return Icons.sentiment_very_dissatisfied;
      case 'sad':
        return Icons.sentiment_dissatisfied;
      case 'excited':
        return Icons.celebration;
      case 'curious':
        return Icons.help_outline;
      default:
        return Icons.sentiment_satisfied;
    }
  }

  String _currentProviderKey =
      ConfigService.get('ai_provider') ?? 'bloret_passport';
  String? _currentModelId = ConfigService.get('ai_model');
  List<Map<String, dynamic>> _currentModels = [];
  bool _isFetchingModels = false;

  Future<void> _fetchRemoteModels() async {
    if (_isFetchingModels) return;

    final key = _currentProviderKey == 'google_ai_studio'
        ? 'google_ai_key'
        : 'custom_ai_key';
    if (ConfigService.get(key) == null || ConfigService.get(key).isEmpty) {
      return;
    }

    setState(() => _isFetchingModels = true);
    try {
      final response = await Bloriko.client.models.list();
      final List<Map<String, dynamic>> remoteModels = [];

      for (var model in response.data) {
        if (_currentProviderKey == 'google_ai_studio' &&
            !model.id.contains('gemini')) {
          continue;
        }

        String rawName = model.id.replaceAll('models/', '');
        String formattedName = rawName
            .split('-')
            .map((word) {
              if (word.isEmpty) return word;
              return word[0].toUpperCase() + word.substring(1);
            })
            .join(' ');

        remoteModels.add({
          "id": model.id,
          "name": formattedName,
          "tool_call": true,
        });
      }

      if (remoteModels.isNotEmpty) {
        setState(() {
          _currentModels = remoteModels;

          final lastModelKey = 'ai_model_last_$_currentProviderKey';
          final savedLastModel = ConfigService.get(lastModelKey);

          if (savedLastModel != null &&
              _currentModels.any((m) => m["id"] == savedLastModel)) {
            _currentModelId = savedLastModel;
          } else if (!_currentModels.any((m) => m["id"] == _currentModelId)) {
            _currentModelId = _currentModels[0]["id"];
          }

          ConfigService.set('ai_model', _currentModelId);
        });
      }
    } catch (e) {
      debugPrint("Fetch models error: $e");
    } finally {
      if (mounted) setState(() => _isFetchingModels = false);
    }
  }

  void _loadModels() {
    final Map<String, dynamic> builtinProviders = {
      "bloret_passport": {
        "models": [
          {"id": "default", "name": "Claude Fable 5", "tool_call": true},
        ],
      },
      "opencode_zen": {
        "models": [
          {
            "id": "deepseek-v4-flash-free",
            "name": "DeepSeek V4 Flash (Free)",
            "tool_call": true,
          },
          {
            "id": "mimo-v2.5-free",
            "name": "Mimo V2.5 (Free)",
            "tool_call": true,
          },
          {
            "id": "qwen3.6-plus-free",
            "name": "Qwen 3.6 Plus (Free)",
            "tool_call": true,
          },
          {
            "id": "minimax-m2.5-free",
            "name": "MiniMax M2.5 (Free)",
            "tool_call": true,
          },
          {
            "id": "nemotron-3-super-free",
            "name": "Nemotron 3 Super (Free)",
            "tool_call": true,
          },
        ],
      },
      "google_ai_studio": {
        "models": [
          {"id": "none", "name": "No models fetched".tl, "tool_call": false},
        ],
      },
      "custom_api": {
        "models": [
          {
            "id": ConfigService.get("custom_ai_model") ?? "custom-model",
            "name": "Custom Model".tl,
            "tool_call": true,
          },
        ],
      },
    };

    final providerData = builtinProviders[_currentProviderKey];
    _currentModels = providerData != null
        ? List<Map<String, dynamic>>.from(providerData["models"])
        : [];

    if (_currentProviderKey == 'google_ai_studio' ||
        _currentProviderKey == 'custom_api') {
      _fetchRemoteModels();
    }

    final lastModelKey = 'ai_model_last_$_currentProviderKey';
    final savedLastModel = ConfigService.get(lastModelKey);

    if (savedLastModel != null &&
        _currentModels.any((m) => m["id"] == savedLastModel)) {
      _currentModelId = savedLastModel;
    } else if (!_currentModels.any((m) => m["id"] == _currentModelId) &&
        _currentModels.isNotEmpty) {
      _currentModelId = _currentModels[0]["id"];
    }

    ConfigService.set('ai_model', _currentModelId);
  }

  Future<void> _showCustomApiDialog() async {
    final urlController = TextEditingController(
      text:
          ConfigService.get("custom_ai_base_url") ??
          "https://api.openai.com/v1",
    );
    final keyController = TextEditingController(
      text: ConfigService.get("custom_ai_key") ?? "",
    );
    final modelController = TextEditingController(
      text: ConfigService.get("custom_ai_model") ?? "gpt-4o",
    );

    final isGoogle = _currentProviderKey == 'google_ai_studio';
    if (isGoogle) {
      keyController.text = ConfigService.get("google_ai_key") ?? "";
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isGoogle
              ? "Configure Google AI Studio".tl
              : "Configure Custom API".tl,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isGoogle)
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: "Base URL".tl,
                  hintText: "https://api.example.com/v1",
                ),
              ),
            TextField(
              controller: keyController,
              decoration: InputDecoration(
                labelText: "API Key".tl,
                hintText: "AQ.xxxxxx",
              ),
              obscureText: true,
            ),
            if (!isGoogle)
              TextField(
                controller: modelController,
                decoration: InputDecoration(
                  labelText: "Default Model ID".tl,
                  hintText: "gpt-4o",
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel".tl),
          ),
          TextButton(
            onPressed: () async {
              if (isGoogle) {
                await ConfigService.set("google_ai_key", keyController.text);
              } else {
                await ConfigService.set(
                  "custom_ai_base_url",
                  urlController.text,
                );
                await ConfigService.set("custom_ai_key", keyController.text);
                await ConfigService.set(
                  "custom_ai_model",
                  modelController.text,
                );
                _currentModelId = modelController.text;
                await ConfigService.set("ai_model", _currentModelId);
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
              if (mounted) {
                setState(() {
                  _loadModels();
                });
              }
            },
            child: Text("Save".tl),
          ),
        ],
      ),
    );
  }

  Widget _buildModelSelectorButton(ThemeData theme) {
    final Map<String, String> providers = {
      "bloret_passport": "Bloret PassPort",
      "opencode_zen": "OpenCode Zen",
      "google_ai_studio": "Google AI Studio",
      "custom_api": "Custom API",
    };

    final List<Win11DropdownItem> menuItems = [
      Win11DropdownItem(
        label: "Switch Provider".tl,
        value: "switch_provider",
        icon: Icons.hub_outlined,
        children: providers.entries
            .map(
              (e) => Win11DropdownItem(
                label: e.value,
                value: "provider:${e.key}",
                icon: e.key == _currentProviderKey
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
            )
            .toList(),
      ),
      ..._currentModels.map(
        (m) => Win11DropdownItem(
          label: m['name'] ?? "",
          value: m['id'],
          icon: m['id'] == _currentModelId ? Icons.check : null,
        ),
      ),
      if (_currentProviderKey == 'custom_api' ||
          _currentProviderKey == 'google_ai_studio')
        Win11DropdownItem(
          label: "Configure API".tl,
          value: "config_api",
          icon: Icons.settings_outlined,
        ),
    ];

    return Win11Dropdown(
      items: menuItems,
      initialValue: _currentModelId,
      height: 32,
      onChanged: (value) async {
        if (value == null) return;
        if (value == "config_api") {
          _showCustomApiDialog();
        } else if (value.startsWith('provider:')) {
          final p = value.replaceFirst('provider:', '');
          await ConfigService.set('ai_provider', p);
          setState(() {
            _currentProviderKey = p;
            _loadModels();
          });
          if (p == 'custom_api' || p == 'google_ai_studio') {
            final key = p == 'google_ai_studio'
                ? 'google_ai_key'
                : 'custom_ai_key';
            if (ConfigService.get(key) == null ||
                ConfigService.get(key).isEmpty) {
              _showCustomApiDialog();
            }
          }
        } else if (value != "switch_provider") {
          await ConfigService.set('ai_model', value);
          await ConfigService.set('ai_model_last_$_currentProviderKey', value);
          setState(() => _currentModelId = value);
        }
      },
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.surfaceContainerHighest),
      ),
    );
  }

  Widget _buildInputCapsule(
    ThemeData theme,
    Color altColor,
    Color borderColor,
    Color textColor,
    Color secondaryTextColor,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: _isFocused
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : borderColor,
          width: _isFocused ? 1.5 : 1.0,
        ),
        boxShadow: [
          if (_isFocused)
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          if (_isDocumentMode)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 5,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAttachmentBar(),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: _isDocumentMode
                    ? MediaQuery.of(context).size.height * 0.5
                    : 200,
              ),
              child: Scrollbar(
                thumbVisibility: true,
                controller: _inputScrollController,
                child: SingleChildScrollView(
                  controller: _inputScrollController,
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (Platform.isAndroid) return KeyEventResult.ignored;

                      final isV = event.logicalKey == LogicalKeyboardKey.keyV;
                      final isControl =
                          HardwareKeyboard.instance.logicalKeysPressed.contains(
                            LogicalKeyboardKey.controlLeft,
                          ) ||
                          HardwareKeyboard.instance.logicalKeysPressed.contains(
                            LogicalKeyboardKey.controlRight,
                          );

                      if (isV && isControl && event is KeyDownEvent) {
                        _handlePaste();
                        return KeyEventResult.handled;
                      }

                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        final isShift =
                            HardwareKeyboard.instance.logicalKeysPressed
                                .contains(LogicalKeyboardKey.shiftLeft) ||
                            HardwareKeyboard.instance.logicalKeysPressed
                                .contains(LogicalKeyboardKey.shiftRight);
                        if (!isShift) {
                          _sendMessage();
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _inputController,
                      focusNode: _focusNode,
                      maxLines: null,
                      onChanged: (val) {
                        setState(() {});
                        if (val.length > 500 && !_isDocumentMode) {
                          setState(() => _isDocumentMode = true);
                        } else if (val.length <= 500 && _isDocumentMode) {
                          setState(() => _isDocumentMode = false);
                        }
                      },
                      keyboardType: TextInputType.multiline,
                      enabled: !_agent.busy,
                      decoration: InputDecoration(
                        hintText:
                            "${"To".tl} ${Bloriko.type == "bloriko" ? "Bloriko".tl : "Blora Agent".tl} ${"say something".tl}...",
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      style: TextStyle(fontSize: 15, color: textColor),
                    ),
                  ),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                  onPressed: _pickFiles,
                  visualDensity: VisualDensity.compact,
                  tooltip: "Add Images or Files".tl,
                ),
                const SizedBox(width: 8),
                _buildModelSelectorButton(theme),
                const Spacer(),
                if (_isDocumentMode)
                  IconButton(
                    icon: const Icon(Icons.edit_note_rounded, size: 22),
                    onPressed: () async {
                      final result = await showDialog<String>(
                        context: context,
                        builder: (context) => _LongTextEditorDialog(
                          initialText: _inputController.text,
                        ),
                      );
                      if (result != null) _inputController.text = result;
                    },
                    tooltip: "Full-screen Edit".tl,
                  ),
                if (!Platform.isLinux)
                  IconButton(
                    icon: Icon(
                      _isRecording ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: _agent.busy
                          ? secondaryTextColor.withValues(alpha: 0.3)
                          : (_isRecording
                                ? theme.colorScheme.error
                                : secondaryTextColor),
                      size: 22,
                    ),
                    onPressed: _agent.busy ? null : _toggleRecording,
                    tooltip: "Voice Input".tl,
                  ),
                const SizedBox(width: 8),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchOutCurve: Curves.easeOutBack,
                    switchInCurve: Curves.easeOutBack,
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: _agent.busy
                        ? IconButton.filled(
                            key: const ValueKey("stop"),
                            icon: const Icon(Icons.stop_rounded, size: 20),
                            onPressed: _agent.cancelAgent,
                            style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                              padding: const EdgeInsets.all(8),
                              minimumSize: const Size(36, 36),
                            ),
                          )
                        : (_inputController.text.trim().isNotEmpty ||
                              _attachments.isNotEmpty)
                        ? IconButton.filled(
                            key: const ValueKey("send"),
                            icon: const Icon(
                              Icons.arrow_upward_rounded,
                              size: 20,
                            ),
                            onPressed: (_currentModelId == null)
                                ? null
                                : _sendMessage,
                            style: IconButton.styleFrom(
                              padding: const EdgeInsets.all(8),
                              minimumSize: const Size(36, 36),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey("none")),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    
    final bool isLoggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
    final bool hasKey = (ConfigService.get('custom_ai_key')?.toString().isNotEmpty ?? false) || 
                        (ConfigService.get('google_ai_key')?.toString().isNotEmpty ?? false);

    if (!isLoggedIn && !hasKey) {
      return _buildLockScreen(theme);
    }

    final isPortrait =
        MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;
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
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: borderColor)),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 28,
                            height: 28,
                            color: Colors.grey.shade300,
                            child: Bloriko.type == "bloriko"
                                ? Image.asset("assets/bloriko.png")
                                : const Icon(Icons.smart_toy, size: 18),
                          ),
                        ),
                        const SizedBox(width: 10),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, animation) =>
                              SizeTransition(
                                sizeFactor: animation,
                                axis: Axis.horizontal,
                                alignment: Alignment.centerLeft,
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              ),
                          child:
                              Bloriko.type == "bloriko" ||
                                  Bloriko.type == "bloriko_r18"
                              ? Text(
                                  "Bloriko".tl,
                                  key: const ValueKey("bloriko"),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                )
                              : Text(
                                  "Blora Agent".tl,
                                  key: const ValueKey("blora"),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        ListenableBuilder(
                          listenable: _agent,
                          builder: (context, child) {
                            final provider = ConfigService.get('ai_provider');
                            final isGoogle = provider == 'google_ai_studio';

                            if (_agent.connectionStatus ==
                                    BlorikoConnectionStatus.idle ||
                                _agent.connectionStatus ==
                                    BlorikoConnectionStatus.finished) {
                              if (isGoogle) {
                                return Tooltip(
                                  message:
                                      "Google AI Studio mode does not support tools/automation yet"
                                          .tl,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: Colors.orange.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          size: 12,
                                          color: Colors.orange,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          "Text Only".tl,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            }

                            String statusText = "";
                            Color statusColor = accentColor;
                            switch (_agent.connectionStatus) {
                              case BlorikoConnectionStatus.connecting:
                                statusText = "Connecting...".tl;
                                break;
                              case BlorikoConnectionStatus.handshake:
                                statusText = "Responding...".tl;
                                break;
                              case BlorikoConnectionStatus.streaming:
                                statusText = "Receiving...".tl;
                                break;
                              case BlorikoConnectionStatus.error:
                                statusText = "Connection failed".tl;
                                statusColor = Colors.red;
                                break;
                              default:
                                break;
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_agent.connectionStatus !=
                                      BlorikoConnectionStatus.error)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: SizedBox(
                                        width: 10,
                                        height: 10,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _agent.conversationTitle.isNotEmpty
                              ? Text(
                                  "— ${_agent.conversationTitle}",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    color: secondaryTextColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 8),
                        if (!isPortrait) ...[
                          SizedBox(
                            width: 128,
                            child: Win11Dropdown(
                              initialValue: Bloriko.mode,
                              items: [
                                Win11DropdownItem(
                                  label: "Auto Mode".tl,
                                  value: "auto",
                                ),
                                Win11DropdownItem(
                                  label: "Assist Click".tl,
                                  value: "help",
                                ),
                                Win11DropdownItem(
                                  label: "Planning Mode".tl,
                                  value: "plan",
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    Bloriko.setMode(value);
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 128,
                            child: Win11Dropdown(
                              initialValue: Bloriko.type,
                              items: [
                                Win11DropdownItem(
                                  label: "Default".tl,
                                  value: "default",
                                ),
                                Win11DropdownItem(
                                  label: "Bloriko".tl,
                                  value: "bloriko",
                                ),
                                if (ConfigService.get("develop_mode") ?? false)
                                  Win11DropdownItem(
                                    label: "Bloriko (R18)".tl,
                                    value: "bloriko_r18",
                                  ),
                              ],
                              onChanged: (value) async {
                                if (value != null && value != Bloriko.type) {
                                  if (_agent.messages.isNotEmpty) {
                                    final bool? result = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text("Switch Character Type".tl),
                                        content: Text(
                                          "Switching characters during a conversation may cause AI context confusion. Start a new conversation for the best experience?"
                                              .tl,
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: Text("Ignore and Keep".tl),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: Text(
                                              "Start New Conversation".tl,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (result == true) {
                                      _clearHistory();
                                    }
                                  }
                                  Bloriko.setType(value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        BloretButton(
                          onPressed: _agent.busy ? null : _clearHistory,
                          text: "New Chat".tl,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: AnimatedRotation(
                            turns: _historyPanelOpen ? 0.25 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(Icons.menu, size: 20),
                          ),
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
                            scale: Tween<double>(
                              begin: 0.96,
                              end: 1.0,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: _agent.messages.isEmpty
                          ? AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween<double>(
                                      begin: 0.96,
                                      end: 1.0,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child:
                                  Bloriko.type == "bloriko" ||
                                      Bloriko.type == "bloriko_r18"
                                  ? Center(
                                      key: const ValueKey("empty_bloriko"),
                                      child: SizedBox(
                                        width: 360,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(36),
                                              child: Container(
                                                width: 72,
                                                height: 72,
                                                color: Colors.grey.shade300,
                                                child: Image.asset(
                                                  "assets/bloriko.png",
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              "Bloriko".tl,
                                              style: TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color: textColor,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              "${ConfigService.get("user_identity") == "sister"
                                                  ? "Sister".tl
                                                  : ConfigService.get("user_identity") == "little_sister"
                                                  ? "Little Sister".tl
                                                  : "Brother".tl} ${"Hello".tl}${Bloriko.type == "bloriko_r18" ? "♥" : "!"} ${"Bloriko has been waiting for you for a long time~ (waves happily)\n\nTry telling Bloriko:\n• Help me create a file\n• Search for TODOs in the project".tl}",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.4,
                                                color: secondaryTextColor,
                                              ),
                                            ),
                                            AnimatedSwitcher(
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              transitionBuilder:
                                                  (child, anim) =>
                                                      SizeTransition(
                                                        sizeFactor: anim,
                                                        alignment:
                                                            Alignment.center,
                                                        child: FadeTransition(
                                                          opacity: anim,
                                                          child: child,
                                                        ),
                                                      ),
                                              child: Bloriko.mode == "help"
                                                  ? Text(
                                                      "• Try clicking the page"
                                                          .tl,
                                                      key: const ValueKey(
                                                        "bloriko_help",
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        height: 1.4,
                                                        color:
                                                            secondaryTextColor,
                                                      ),
                                                    )
                                                  : const SizedBox.shrink(
                                                      key: ValueKey(
                                                        "bloriko_no_help",
                                                      ),
                                                    ),
                                            ),
                                            Text(
                                              "• Execute a command\n• Remember my preference is..."
                                                  .tl,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.4,
                                                color: secondaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : Center(
                                      key: const ValueKey("empty_blora"),
                                      child: SizedBox(
                                        width: 360,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(36),
                                              child: Container(
                                                width: 72,
                                                height: 72,
                                                color: Colors.grey.shade300,
                                                child: const Icon(
                                                  Icons.smart_toy,
                                                  size: 36,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              "Blora Agent".tl,
                                              style: TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color: textColor,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              "Hello, I am Blora Agent. I can help you with Bloret Launcher.\n\nSend Blora Agent:\n• Help me create files\n• Search for TODOs in the project"
                                                  .tl,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.4,
                                                color: secondaryTextColor,
                                              ),
                                            ),
                                            AnimatedSwitcher(
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              transitionBuilder:
                                                  (child, anim) =>
                                                      SizeTransition(
                                                        sizeFactor: anim,
                                                        alignment:
                                                            Alignment.center,
                                                        child: FadeTransition(
                                                          opacity: anim,
                                                          child: child,
                                                        ),
                                                      ),
                                              child: Bloriko.mode == "help"
                                                  ? Text(
                                                      "• Help me click the page"
                                                          .tl,
                                                      key: const ValueKey(
                                                        "help_mode",
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        height: 1.4,
                                                        color:
                                                            secondaryTextColor,
                                                      ),
                                                    )
                                                  : const SizedBox.shrink(
                                                      key: ValueKey("no_help"),
                                                    ),
                                            ),
                                            Text(
                                              "• Execute a command\n• Remember my preference..."
                                                  .tl,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.4,
                                                color: secondaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            )
                          : LayoutBuilder(
                              key: const ValueKey("chat_list_wrapper"),
                              builder: (context, constraints) {
                                return ListView.builder(
                                  key: const ValueKey("chat_list"),
                                  padding: const EdgeInsets.only(bottom: 240),
                                  controller: _agent.messages.isEmpty
                                      ? null
                                      : _msgScrollController,
                                  itemCount:
                                      _agent.messages.length +
                                      (_agent.busy ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == _agent.messages.length) {
                                      bool showAvatar = true;
                                      if (index > 0 &&
                                          _agent.messages[index - 1]['role'] ==
                                              'assistant') {
                                        showAvatar = false;
                                      }
                                      if (isPortrait) showAvatar = false;

                                      bool isWaiting =
                                          _agent.messages.isNotEmpty &&
                                          ((_agent.messages.last['role'] ==
                                                      'system' &&
                                                  (_agent
                                                              .messages
                                                              .last['tool'] ==
                                                          'ask_question' ||
                                                      _agent
                                                              .messages
                                                              .last['tool'] ==
                                                          'ask_question_details') &&
                                                  _agent
                                                          .messages
                                                          .last['status'] ==
                                                      'running') ||
                                              (_agent.messages.last['role'] ==
                                                      'security' &&
                                                  _agent
                                                          .messages
                                                          .last['status'] ==
                                                      'waiting'));

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 16,
                                        ),
                                        child: Row(
                                          children: [
                                            if (showAvatar) ...[
                                              Container(
                                                width: 32,
                                                height: 32,
                                                clipBehavior: Clip.antiAlias,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: altColor,
                                                ),
                                                child:
                                                    Bloriko.type == "bloriko" ||
                                                        Bloriko.type ==
                                                            "bloriko_r18"
                                                    ? Image.asset(
                                                        "assets/bloriko.png",
                                                        filterQuality:
                                                            FilterQuality.high,
                                                      )
                                                    : const Icon(
                                                        Icons.smart_toy,
                                                        color: Colors.grey,
                                                        size: 16,
                                                      ),
                                              ),
                                              const SizedBox(width: 12),
                                            ] else if (!isPortrait) ...[
                                              const SizedBox(width: 44),
                                            ],
                                            ListenableBuilder(
                                              listenable: _agent,
                                              builder: (context, child) {
                                                String text;
                                                if (isWaiting) {
                                                  text = "Waiting...".tl;
                                                } else {
                                                  text = switch (_agent
                                                      .connectionStatus) {
                                                    BlorikoConnectionStatus
                                                        .connecting =>
                                                      "Connecting...".tl,
                                                    BlorikoConnectionStatus
                                                        .handshake =>
                                                      "Verifying...".tl,
                                                    BlorikoConnectionStatus
                                                        .streaming =>
                                                      "Receiving...".tl,
                                                    _ => "Thinking...".tl,
                                                  };
                                                }
                                                return Text(
                                                  text,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontStyle: FontStyle.italic,
                                                    color: secondaryTextColor
                                                        .withValues(alpha: 0.7),
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 8),
                                            const SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }

                                    final msg = _agent.messages[index];
                                    final role = msg['role'];
                                    final isSelected = _selectedMessageIndices
                                        .contains(index);

                                    Widget messageWidget =
                                        const SizedBox.shrink();

                                    if (role == 'security') {
                                      final String cmd = msg['command'] ?? "";

                                      void hideSecurityCard() {
                                        setState(() {
                                          msg['hidden'] = true;
                                        });
                                      }

                                      messageWidget = AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        transitionBuilder: (child, animation) {
                                          return SizeTransition(
                                            sizeFactor: animation,
                                            alignment: Alignment.topCenter,
                                            child: FadeTransition(
                                              opacity: animation,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: msg['hidden'] != true
                                            ? TweenAnimationBuilder<double>(
                                                key: const ValueKey("security"),
                                                duration: const Duration(
                                                  milliseconds: 400,
                                                ),
                                                curve: Curves.easeOutCubic,
                                                tween: Tween(
                                                  begin: 0.0,
                                                  end: 1.0,
                                                ),
                                                builder:
                                                    (
                                                      context,
                                                      value,
                                                      child,
                                                    ) => Opacity(
                                                      opacity: value,
                                                      child:
                                                          Transform.translate(
                                                            offset: Offset(
                                                              0,
                                                              10 * (1 - value),
                                                            ),
                                                            child: child,
                                                          ),
                                                    ),
                                                child: BloraSecurityCard(
                                                  msg: msg,
                                                  theme: theme,
                                                  onDeny: () {
                                                    hideSecurityCard();
                                                    _agent.handleSecurityAction(
                                                      'deny',
                                                    );
                                                  },
                                                  onAllowOnce: () {
                                                    hideSecurityCard();
                                                    _agent.handleSecurityAction(
                                                      'allow',
                                                    );
                                                  },
                                                  onAlwaysAllow: () {
                                                    hideSecurityCard();
                                                    _agent.handleSecurityAction(
                                                      'always',
                                                      command: cmd,
                                                    );
                                                  },
                                                ),
                                              )
                                            : const SizedBox.shrink(
                                                key: ValueKey("empty"),
                                              ),
                                      );
                                    } else if (role == 'user') {
                                      final rawContent =
                                          msg['content']?.toString() ?? "";
                                      final crashRegExp = RegExp(
                                        r'<crash_card>(.*?)</crash_card>',
                                        dotAll: true,
                                      );
                                      final crashMatch = crashRegExp.firstMatch(
                                        rawContent,
                                      );

                                      if (crashMatch != null) {
                                        try {
                                          final data = jsonDecode(
                                            crashMatch.group(1)!,
                                          );
                                          messageWidget = Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                              horizontal: 16,
                                            ),
                                            child: _buildCrashCard(data, theme),
                                          );
                                        } catch (e) {
                                          messageWidget = const Text(
                                            "Error parsing crash card",
                                          );
                                        }
                                      } else {
                                        final content = msg['content'];
                                        final List<String> imageUrls = [];
                                        final List<Map<String, dynamic>> files =
                                            [];

                                        if (content is List) {
                                          for (var part in content) {
                                            if (part is Map) {
                                              if (part['type'] ==
                                                      'input_image' ||
                                                  part['type'] ==
                                                      'image_url') {
                                                imageUrls.add(
                                                  part['image_url']
                                                          ?.toString() ??
                                                      "",
                                                );
                                              } else if (part['type'] ==
                                                  'input_file') {
                                                files.add(
                                                  Map<String, dynamic>.from(
                                                    part,
                                                  ),
                                                );
                                              }
                                            }
                                          }
                                        }

                                        messageWidget = Align(
                                          alignment: Alignment.centerRight,
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 8,
                                              horizontal: 16,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 14,
                                            ),
                                            constraints: BoxConstraints(
                                              maxWidth:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  0.8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: accentColor,
                                              borderRadius:
                                                  const BorderRadius.only(
                                                    topLeft: Radius.circular(
                                                      16,
                                                    ),
                                                    topRight: Radius.circular(
                                                      16,
                                                    ),
                                                    bottomLeft: Radius.circular(
                                                      16,
                                                    ),
                                                    bottomRight: Radius.circular(
                                                      4,
                                                    ),
                                                  ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.05),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                if (imageUrls.isNotEmpty)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 8,
                                                        ),
                                                    child: Wrap(
                                                      spacing: 4,
                                                      runSpacing: 4,
                                                      children: (content
                                                              as List)
                                                          .asMap()
                                                          .entries
                                                          .where(
                                                            (e) =>
                                                                e.value is Map &&
                                                                (e.value['type'] ==
                                                                        'input_image' ||
                                                                    e.value['type'] ==
                                                                        'image_url'),
                                                          )
                                                          .map((e) {
                                                            final imgIdx = e.key;
                                                            final part =
                                                                e.value as Map;
                                                            final url =
                                                                part['image_url']
                                                                    ?.toString() ??
                                                                "";
                                                            if (!url.startsWith(
                                                              'data:image',
                                                            )) {
                                                              return const SizedBox.shrink();
                                                            }
                                                            final heroTag =
                                                                'msg_${index}_img_$imgIdx';

                                                            return GestureDetector(
                                                              onTap: () =>
                                                                  _showImageDialog(
                                                                    context,
                                                                    url,
                                                                    heroTag,
                                                                  ),
                                                              child: Hero(
                                                                tag: heroTag,
                                                                child: ClipRRect(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                            8,
                                                                          ),
                                                                  child:
                                                                      part['_decodedBytes'] !=
                                                                          null
                                                                      ? Image.memory(
                                                                          Uint8List.fromList(
                                                                            (part['_decodedBytes']
                                                                                    as List)
                                                                                .cast(),
                                                                          ),
                                                                          width:
                                                                              100,
                                                                          height:
                                                                              100,
                                                                          fit: BoxFit
                                                                              .cover,
                                                                          gaplessPlayback:
                                                                              true,
                                                                          key: ValueKey(
                                                                            url,
                                                                          ),
                                                                        )
                                                                      : Image.memory(
                                                                          base64Decode(
                                                                            url
                                                                                .split(
                                                                                  ',',
                                                                                )
                                                                                .last,
                                                                          ),
                                                                          width:
                                                                              100,
                                                                          height:
                                                                              100,
                                                                          fit: BoxFit
                                                                              .cover,
                                                                          gaplessPlayback:
                                                                              true,
                                                                          key: ValueKey(
                                                                            url,
                                                                          ),
                                                                        ),
                                                                ),
                                                              ),
                                                            );
                                                          })
                                                          .toList(),
                                                    ),
                                                  ),
                                                if (files.isNotEmpty)
                                                  Column(
                                                    children: files.map((file) {
                                                      final isLongText =
                                                          file['filename'] ==
                                                          "long_text.txt";
                                                      return Container(
                                                        margin: const EdgeInsets
                                                            .only(bottom: 8),
                                                        padding:
                                                            const EdgeInsets.all(
                                                              10,
                                                            ),
                                                        decoration:
                                                            BoxDecoration(
                                                              color: Colors
                                                                  .white
                                                                  .withValues(
                                                                    alpha: 0.15,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                        10,
                                                                      ),
                                                              border: Border
                                                                  .all(
                                                                    color: Colors
                                                                        .white
                                                                        .withValues(
                                                                          alpha:
                                                                              0.2,
                                                                        ),
                                                                  ),
                                                            ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            const Icon(
                                                              Icons
                                                                  .insert_drive_file_rounded,
                                                              color: Colors
                                                                  .white,
                                                              size: 24,
                                                            ),
                                                            const SizedBox(
                                                              width: 10,
                                                            ),
                                                            Flexible(
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(
                                                                    file['filename'] ??
                                                                        "Unknown",
                                                                    style:
                                                                        const TextStyle(
                                                                          color:
                                                                              Colors
                                                                                  .white,
                                                                          fontSize:
                                                                              13,
                                                                          fontWeight:
                                                                              FontWeight
                                                                                  .bold,
                                                                          fontFamily:
                                                                              'sans-serif',
                                                                        ),
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                  if (isLongText)
                                                                    TextButton(
                                                                      style: TextButton.styleFrom(
                                                                        visualDensity:
                                                                            VisualDensity
                                                                                .compact,
                                                                        padding:
                                                                            EdgeInsets
                                                                                .zero,
                                                                        minimumSize:
                                                                            const Size(
                                                                              0,
                                                                              0,
                                                                            ),
                                                                      ),
                                                                      onPressed:
                                                                          () {
                                                                            try {
                                                                              final decoded =
                                                                                  utf8.decode(
                                                                                    base64Decode(
                                                                                      file['file_data'],
                                                                                    ),
                                                                                  );
                                                                              setState(
                                                                                () {
                                                                                  _inputController
                                                                                          .text =
                                                                                      decoded;
                                                                                  _agent
                                                                                      .messages
                                                                                      .removeAt(
                                                                                        index,
                                                                                      );
                                                                                },
                                                                              );
                                                                              _focusNode
                                                                                  .requestFocus();
                                                                            } catch (
                                                                              _
                                                                            ) {}
                                                                          },
                                                                      child: Text(
                                                                        "Restore to Input Box"
                                                                            .tl,
                                                                        style:
                                                                            const TextStyle(
                                                                              color:
                                                                                  Colors
                                                                                      .white70,
                                                                              fontSize:
                                                                                  11,
                                                                              decoration:
                                                                                  TextDecoration
                                                                                      .underline,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                                GptMarkdown(
                                                  msg['displayText'] ??
                                                      (msg['content'] is String
                                                          ? msg['content']
                                                          : "[Attachment]".tl),
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color:
                                                        theme
                                                            .colorScheme
                                                            .onPrimary,
                                                    height: 1.35,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }
                                    } else if (role == 'assistant') {
                                      bool showAvatar = true;
                                      if (isPortrait) {
                                        showAvatar = false;
                                      } else if (index > 0) {
                                        int prevAssistantIdx = -1;
                                        bool intermediateBlocking = false;
                                        for (int i = index - 1; i >= 0; i--) {
                                          if (_agent.messages[i]['role'] ==
                                              'assistant') {
                                            prevAssistantIdx = i;
                                            break;
                                          } else if (_agent
                                                  .messages[i]['role'] !=
                                              'system') {
                                            intermediateBlocking = true;
                                            break;
                                          }
                                        }
                                        if (prevAssistantIdx != -1 &&
                                            !intermediateBlocking) {
                                          if ((msg['emotion'] ?? 'neutral') ==
                                              (_agent.messages[prevAssistantIdx]['emotion'] ??
                                                  'neutral')) {
                                            showAvatar = false;
                                          }
                                        }
                                      }

                                      final assistantType =
                                          msg['agentType'] ?? Bloriko.type;

                                      messageWidget = TweenAnimationBuilder<double>(
                                        duration: const Duration(
                                          milliseconds: 400,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        tween: Tween(begin: 0.0, end: 1.0),
                                        builder: (context, value, child) =>
                                            Opacity(
                                              opacity: value,
                                              child: Transform.translate(
                                                offset: Offset(
                                                  0,
                                                  10 * (1 - value),
                                                ),
                                                child: child,
                                              ),
                                            ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                            horizontal: 16,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (showAvatar)
                                                Container(
                                                  width: 32,
                                                  height: 32,
                                                  margin: const EdgeInsets.only(
                                                    top: 8,
                                                  ),
                                                  clipBehavior: Clip.antiAlias,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: altColor,
                                                  ),
                                                  child:
                                                      assistantType ==
                                                              "bloriko" ||
                                                          assistantType ==
                                                              "bloriko_r18"
                                                      ? Image.asset(
                                                          "assets/bloriko.png",
                                                          filterQuality:
                                                              FilterQuality
                                                                  .high,
                                                        )
                                                      : const Icon(
                                                          Icons.smart_toy,
                                                          color: Colors.grey,
                                                          size: 16,
                                                        ),
                                                )
                                              else if (!isPortrait)
                                                const SizedBox(width: 44),
                                              if (!isPortrait)
                                                const SizedBox(width: 20),
                                              Expanded(
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 4,
                                                      ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      GestureDetector(
                                                        onSecondaryTapDown:
                                                            (
                                                              details,
                                                            ) => _showMessageMenu(
                                                              context,
                                                              details
                                                                  .globalPosition,
                                                              index,
                                                            ),
                                                        onLongPressStart:
                                                            (
                                                              details,
                                                            ) => _showMessageMenu(
                                                              context,
                                                              details
                                                                  .globalPosition,
                                                              index,
                                                            ),
                                                        child: GptMarkdown(
                                                          msg['content'] ??
                                                              '...',
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            color: textColor,
                                                            height: 1.35,
                                                          ),
                                                        ),
                                                      ),
                                                      Builder(
                                                        builder: (context) {
                                                          final content =
                                                              msg['content']
                                                                  ?.toString() ??
                                                              "";
                                                          final regExp = RegExp(
                                                            r'!\[.*?\]\((.*?)\)',
                                                          );
                                                          final matches = regExp
                                                              .allMatches(
                                                                content,
                                                              );
                                                          if (matches.isEmpty) {
                                                            return const SizedBox.shrink();
                                                          }

                                                          return Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  top: 8,
                                                                ),
                                                            child: Wrap(
                                                              spacing: 8,
                                                              children: matches.map((
                                                                m,
                                                              ) {
                                                                final url =
                                                                    m.group(
                                                                      1,
                                                                    ) ??
                                                                    "";
                                                                return IconButton.filledTonal(
                                                                  icon: const Icon(
                                                                    Icons
                                                                        .download_rounded,
                                                                    size: 16,
                                                                  ),
                                                                  onPressed: () =>
                                                                      _downloadImage(
                                                                        url,
                                                                      ),
                                                                  tooltip:
                                                                      "Download Image"
                                                                          .tl,
                                                                );
                                                              }).toList(),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                      const SizedBox(height: 8),
                                                      AnimatedOpacity(
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 200,
                                                            ),
                                                        opacity:
                                                            (_agent.busy &&
                                                                index ==
                                                                    _agent
                                                                            .messages
                                                                            .length -
                                                                        1)
                                                            ? 0.0
                                                            : (_hoveredMessageIndex ==
                                                                      index
                                                                  ? 1.0
                                                                  : 0.0),
                                                        child: Row(
                                                          children: [
                                                            IconButton(
                                                              icon: const Icon(
                                                                Icons
                                                                    .copy_rounded,
                                                                size: 16,
                                                              ),
                                                              onPressed: () =>
                                                                  _copyToClipboard(
                                                                    msg['content'] ??
                                                                        "",
                                                                  ),
                                                              tooltip:
                                                                  "Copy".tl,
                                                              visualDensity:
                                                                  VisualDensity
                                                                      .compact,
                                                            ),
                                                            IconButton(
                                                              icon: const Icon(
                                                                Icons
                                                                    .share_rounded,
                                                                size: 16,
                                                              ),
                                                              onPressed: () =>
                                                                  _shareMessage(
                                                                    index,
                                                                  ),
                                                              tooltip:
                                                                  "Share".tl,
                                                              visualDensity:
                                                                  VisualDensity
                                                                      .compact,
                                                            ),
                                                            IconButton(
                                                              icon: const Icon(
                                                                Icons
                                                                    .refresh_rounded,
                                                                size: 16,
                                                              ),
                                                              onPressed: () =>
                                                                  _retryMessage(
                                                                    index,
                                                                  ),
                                                              tooltip:
                                                                  "Retry".tl,
                                                              visualDensity:
                                                                  VisualDensity
                                                                      .compact,
                                                            ),
                                                            IconButton(
                                                              icon: const Icon(
                                                                Icons
                                                                    .call_split_rounded,
                                                                size: 16,
                                                              ),
                                                              onPressed: () =>
                                                                  _branchConversation(
                                                                    index,
                                                                  ),
                                                              tooltip:
                                                                  "Branch Conversation"
                                                                      .tl,
                                                              visualDensity:
                                                                  VisualDensity
                                                                      .compact,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    } 
else if (role == 'system') {
                                      if (msg['tool'] == 'set_user_identity') {
                                        return const SizedBox.shrink();
                                      }
                                      final isExpanded =
                                          msg['isExpanded'] ?? false;
                                      final hasDetail =
                                          msg['args'] != null ||
                                          msg['result'] != null;
                                      messageWidget = TweenAnimationBuilder<double>(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        tween: Tween(begin: 0.0, end: 1.0),
                                        builder: (context, value, child) =>
                                            Opacity(
                                              opacity: value,
                                              child: Transform.translate(
                                                offset: Offset(
                                                  0,
                                                  5 * (1 - value),
                                                ),
                                                child: child,
                                              ),
                                            ),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 3,
                                              horizontal: 16,
                                            ),
                                            padding: const EdgeInsets.only(
                                              left: 32,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                GestureDetector(
                                                  onTap: hasDetail
                                                      ? () => setState(
                                                          () =>
                                                              msg['isExpanded'] =
                                                                  !isExpanded,
                                                        )
                                                      : null,
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (msg['tool']
                                                              ?.toString()
                                                              .startsWith(
                                                                'shizuku_',
                                                              ) ??
                                                          false)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                right: 6,
                                                              ),
                                                          child: Image.asset(
                                                            "assets/icons/shizuku.png",
                                                            width: 14,
                                                            height: 14,
                                                          ),
                                                        ),
                                                      Icon(
                                                        _getToolIcon(
                                                          msg['tool'],
                                                        ),
                                                        size: 13,
                                                        color:
                                                            secondaryTextColor
                                                                .withValues(
                                                                  alpha: 0.7,
                                                                ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        msg['content'] ?? '',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontStyle:
                                                              FontStyle.italic,
                                                          color:
                                                              secondaryTextColor
                                                                  .withValues(
                                                                    alpha: 0.7,
                                                                  ),
                                                        ),
                                                      ),
                                                      if (hasDetail) ...[
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Icon(
                                                          isExpanded
                                                              ? Icons
                                                                    .keyboard_arrow_up_rounded
                                                              : Icons
                                                                    .keyboard_arrow_down_rounded,
                                                          size: 14,
                                                          color:
                                                              secondaryTextColor
                                                                  .withValues(
                                                                    alpha: 0.5,
                                                                  ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                AnimatedSwitcher(
                                                  duration: const Duration(
                                                    milliseconds: 300,
                                                  ),
                                                  switchInCurve:
                                                      Curves.easeOutBack,
                                                  switchOutCurve:
                                                      Curves.easeInCubic,
                                                  transitionBuilder:
                                                      (
                                                        child,
                                                        animation,
                                                      ) => FadeTransition(
                                                        opacity: animation,
                                                        child: SizeTransition(
                                                          sizeFactor: animation,
                                                          alignment: Alignment
                                                              .topCenter,
                                                          child: child,
                                                        ),
                                                      ),
                                                  child:
                                                      (isExpanded && hasDetail)
                                                      ? Container(
                                                          key: const ValueKey(
                                                            "detail",
                                                          ),
                                                          margin:
                                                              const EdgeInsets.only(
                                                                top: 8,
                                                                bottom: 4,
                                                              ),
                                                          padding:
                                                              const EdgeInsets.all(
                                                                12,
                                                              ),
                                                          width:
                                                              double.infinity,
                                                          decoration: BoxDecoration(
                                                            color: altColor
                                                                .withValues(
                                                                  alpha: 0.5,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                            border: Border.all(
                                                              color: borderColor
                                                                  .withValues(
                                                                    alpha: 0.3,
                                                                  ),
                                                            ),
                                                          ),
                                                          child: StatefulBuilder(
                                                            builder:
                                                                (
                                                                  context,
                                                                  setDetailState,
                                                                ) {
                                                                  final List
                                                                  calls =
                                                                      msg['calls'] ??
                                                                      [];
                                                                  final int
                                                                  total =
                                                                      calls
                                                                          .isNotEmpty
                                                                      ? calls
                                                                            .length
                                                                      : 1;
                                                                  int
                                                                  currentIndex =
                                                                      msg['_detailIdx'] ??
                                                                      (total -
                                                                          1);

                                                                  Widget
                                                                  buildContent(
                                                                    int idx,
                                                                  ) {
                                                                    var data =
                                                                        (calls
                                                                            .isNotEmpty)
                                                                        ? calls[idx]
                                                                        : {
                                                                            'args':
                                                                                msg['args'],
                                                                            'result':
                                                                                msg['result'],
                                                                          };
                                                                    return Column(
                                                                      key: ValueKey(
                                                                        "call_$idx",
                                                                      ),
                                                                      crossAxisAlignment:
                                                                          CrossAxisAlignment
                                                                              .start,
                                                                      children: [
                                                                        if (msg['tool'] ==
                                                                                'ask_question' &&
                                                                            data['args'] !=
                                                                                null) ...[
                                                                          Builder(
                                                                            builder:
                                                                                (
                                                                                  context,
                                                                                ) {
                                                                                  try {
                                                                                    final Map<
                                                                                      String,
                                                                                      dynamic
                                                                                    >
                                                                                    args = jsonDecode(
                                                                                      data['args'],
                                                                                    );
                                                                                    final String question =
                                                                                        args['question'] ??
                                                                                        "";
                                                                                    final List options =
                                                                                        args['options'] ??
                                                                                        [];
                                                                                    final bool isRunning =
                                                                                        msg['status'] ==
                                                                                        'running';

                                                                                    return Column(
                                                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                                                      children: [
                                                                                        Text(
                                                                                          question,
                                                                                          style: const TextStyle(
                                                                                            fontSize: 13,
                                                                                            fontWeight: FontWeight.bold,
                                                                                          ),
                                                                                        ),
                                                                                        const SizedBox(
                                                                                          height: 12,
                                                                                        ),
                                                                                        if (isRunning)
                                                                                          Wrap(
                                                                                            spacing: 8,
                                                                                            runSpacing: 8,
                                                                                            children: options
                                                                                                .map(
                                                                                                  (
                                                                                                    opt,
                                                                                                  ) => BloretButton(
                                                                                                    text: opt.toString(),
                                                                                                    onPressed: () => _agent.answerQuestion(
                                                                                                      opt.toString(),
                                                                                                    ),
                                                                                                  ),
                                                                                                )
                                                                                                .toList(),
                                                                                          )
                                                                                        else
                                                                                          Container(
                                                                                            padding: const EdgeInsets.symmetric(
                                                                                              horizontal: 10,
                                                                                              vertical: 6,
                                                                                            ),
                                                                                            decoration: BoxDecoration(
                                                                                              color: accentColor.withValues(
                                                                                                alpha: 0.1,
                                                                                              ),
                                                                                              borderRadius: BorderRadius.circular(
                                                                                                6,
                                                                                              ),
                                                                                              border: Border.all(
                                                                                                color: accentColor.withValues(
                                                                                                  alpha: 0.2,
                                                                                                ),
                                                                                              ),
                                                                                            ),
                                                                                            child: Row(
                                                                                              mainAxisSize: MainAxisSize.min,
                                                                                              children: [
                                                                                                Icon(
                                                                                                  Icons.check_circle_outline_rounded,
                                                                                                  size: 14,
                                                                                                  color: accentColor,
                                                                                                ),
                                                                                                const SizedBox(
                                                                                                  width: 6,
                                                                                                ),
                                                                                                Flexible(
                                                                                                  child: Text(
                                                                                                    "${"Selected".tl}: ${data['result'] ?? ''}",
                                                                                                    style: TextStyle(
                                                                                                      fontSize: 12,
                                                                                                      color: accentColor,
                                                                                                      fontWeight: FontWeight.bold,
                                                                                                    ),
                                                                                                    maxLines: 1,
                                                                                                    overflow: TextOverflow.ellipsis,
                                                                                                  ),
                                                                                                ),
                                                                                              ],
                                                                                            ),
                                                                                          ),
                                                                                      ],
                                                                                    );
                                                                                  } catch (
                                                                                    _
                                                                                  ) {
                                                                                    return const Text(
                                                                                      "Failed to parse question",
                                                                                    );
                                                                                  }
                                                                                },
                                                                          ),
                                                                        ] else if (msg['tool'] ==
                                                                                'ask_question_details' &&
                                                                            data['args'] !=
                                                                                null) ...[
                                                                          Builder(
                                                                            builder:
                                                                                (
                                                                                  context,
                                                                                ) {
                                                                                  try {
                                                                                    final Map<
                                                                                      String,
                                                                                      dynamic
                                                                                    >
                                                                                    args = jsonDecode(
                                                                                      data['args'],
                                                                                    );
                                                                                    final String question =
                                                                                        args['question'] ??
                                                                                        "";
                                                                                    final String description =
                                                                                        args['description'] ??
                                                                                        "";
                                                                                    final bool isRunning =
                                                                                        msg['status'] ==
                                                                                        'running';

                                                                                    return Column(
                                                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                                                      children: [
                                                                                        Text(
                                                                                          question,
                                                                                          style: const TextStyle(
                                                                                            fontSize: 13,
                                                                                            fontWeight: FontWeight.bold,
                                                                                          ),
                                                                                        ),
                                                                                        const SizedBox(
                                                                                          height: 12,
                                                                                        ),
                                                                                        if (isRunning)
                                                                                          Padding(
                                                                                            padding: const EdgeInsets.all(
                                                                                              12.0,
                                                                                            ),
                                                                                            child: Row(
                                                                                              children: [
                                                                                                Expanded(
                                                                                                  child: AnimatedContainer(
                                                                                                    duration: const Duration(
                                                                                                      milliseconds: 200,
                                                                                                    ),
                                                                                                    curve: Curves.easeInOut,
                                                                                                    constraints: const BoxConstraints(
                                                                                                      maxHeight: 120,
                                                                                                    ),
                                                                                                    padding: const EdgeInsets.symmetric(
                                                                                                      horizontal: 10,
                                                                                                      vertical: 4,
                                                                                                    ),
                                                                                                    decoration: BoxDecoration(
                                                                                                      color: altColor,
                                                                                                      borderRadius: BorderRadius.circular(
                                                                                                        8,
                                                                                                      ),
                                                                                                      border: Border.all(
                                                                                                        color: _isFocused
                                                                                                            ? theme.colorScheme.onSurface
                                                                                                            : borderColor,
                                                                                                        width: _isFocused
                                                                                                            ? 1.8
                                                                                                            : 1.0,
                                                                                                      ),
                                                                                                    ),
                                                                                                    child: Scrollbar(
                                                                                                      thumbVisibility: true,
                                                                                                      controller: _answerScrollController,
                                                                                                      radius: const Radius.circular(
                                                                                                        8,
                                                                                                      ),
                                                                                                      child: SingleChildScrollView(
                                                                                                        controller: _answerScrollController,
                                                                                                        child: Focus(
                                                                                                          onKeyEvent:
                                                                                                              (
                                                                                                                node,
                                                                                                                event,
                                                                                                              ) {
                                                                                                                if (event
                                                                                                                        is KeyDownEvent &&
                                                                                                                    event.logicalKey ==
                                                                                                                        LogicalKeyboardKey.enter) {
                                                                                                                  final isShift =
                                                                                                                      HardwareKeyboard.instance.logicalKeysPressed.contains(
                                                                                                                        LogicalKeyboardKey.shiftLeft,
                                                                                                                      ) ||
                                                                                                                      HardwareKeyboard.instance.logicalKeysPressed.contains(
                                                                                                                        LogicalKeyboardKey.shiftRight,
                                                                                                                      );
                                                                                                                  if (!isShift) {
                                                                                                                    _sendMessage();
                                                                                                                    return KeyEventResult.handled;
                                                                                                                  }
                                                                                                                }
                                                                                                                return KeyEventResult.ignored;
                                                                                                              },
                                                                                                          child: TextField(
                                                                                                            controller: _inputAnswerController,
                                                                                                            focusNode: _focusAnswerNode,
                                                                                                            maxLines: null,
                                                                                                            keyboardType: TextInputType.multiline,
                                                                                                            decoration: InputDecoration(
                                                                                                              hintText: description,
                                                                                                              border: InputBorder.none,
                                                                                                              isDense: true,
                                                                                                              contentPadding: const EdgeInsets.symmetric(
                                                                                                                vertical: 6,
                                                                                                              ),
                                                                                                            ),
                                                                                                            style: TextStyle(
                                                                                                              fontSize: 14,
                                                                                                              color: textColor,
                                                                                                            ),
                                                                                                          ),
                                                                                                        ),
                                                                                                      ),
                                                                                                    ),
                                                                                                  ),
                                                                                                ),
                                                                                                const SizedBox(
                                                                                                  width: 10,
                                                                                                ),
                                                                                                IconButton.filled(
                                                                                                  padding: const EdgeInsets.all(
                                                                                                    2,
                                                                                                  ),
                                                                                                  icon: const Icon(
                                                                                                    Icons.send,
                                                                                                    size: 20,
                                                                                                  ),
                                                                                                  onPressed: () {
                                                                                                    data['result'] = _inputAnswerController.text;
                                                                                                    if (data['result'] !=
                                                                                                        null) {
                                                                                                      _agent.answerDetailQuestion(
                                                                                                        data['result'],
                                                                                                      );
                                                                                                      _inputAnswerController.clear();
                                                                                                    }
                                                                                                  },
                                                                                                ),
                                                                                              ],
                                                                                            ),
                                                                                          )
                                                                                        else
                                                                                          Container(
                                                                                            padding: const EdgeInsets.symmetric(
                                                                                              horizontal: 10,
                                                                                              vertical: 6,
                                                                                            ),
                                                                                            decoration: BoxDecoration(
                                                                                              color: accentColor.withValues(
                                                                                                alpha: 0.1,
                                                                                              ),
                                                                                              borderRadius: BorderRadius.circular(
                                                                                                6,
                                                                                              ),
                                                                                              border: Border.all(
                                                                                                color: accentColor.withValues(
                                                                                                  alpha: 0.2,
                                                                                                ),
                                                                                              ),
                                                                                            ),
                                                                                            child: Row(
                                                                                              mainAxisSize: MainAxisSize.min,
                                                                                              children: [
                                                                                                Icon(
                                                                                                  Icons.check_circle_outline_rounded,
                                                                                                  size: 14,
                                                                                                  color: accentColor,
                                                                                                ),
                                                                                                const SizedBox(
                                                                                                  width: 6,
                                                                                                ),
                                                                                                Flexible(
                                                                                                  child: Text(
                                                                                                    data['result'],
                                                                                                    style: TextStyle(
                                                                                                      fontSize: 12,
                                                                                                      color: accentColor,
                                                                                                      fontWeight: FontWeight.bold,
                                                                                                    ),
                                                                                                    maxLines: 1,
                                                                                                    overflow: TextOverflow.ellipsis,
                                                                                                  ),
                                                                                                ),
                                                                                              ],
                                                                                            ),
                                                                                          ),
                                                                                      ],
                                                                                    );
                                                                                  } catch (
                                                                                    _
                                                                                  ) {
                                                                                    return const Text(
                                                                                      "Failed to parse question",
                                                                                    );
                                                                                  }
                                                                                },
                                                                          ),
                                                                        ] else ...[
                                                                          if (data['args'] !=
                                                                              null) ...[
                                                                            Text(
                                                                              "Input Parameters:".tl,
                                                                              style: const TextStyle(
                                                                                fontSize: 11,
                                                                                fontWeight: FontWeight.bold,
                                                                              ),
                                                                            ),
                                                                            const SizedBox(
                                                                              height: 4,
                                                                            ),
                                                                            SelectableText(
                                                                              data['args'],
                                                                              style: const TextStyle(
                                                                                fontSize: 11,
                                                                                fontFamily: "monospace",
                                                                              ),
                                                                            ),
                                                                          ],
                                                                          if (data['result'] !=
                                                                              null) ...[
                                                                            const SizedBox(
                                                                              height: 12,
                                                                            ),
                                                                            Text(
                                                                              "Execution Result:".tl,
                                                                              style: const TextStyle(
                                                                                fontSize: 11,
                                                                                fontWeight: FontWeight.bold,
                                                                              ),
                                                                            ),
                                                                            const SizedBox(
                                                                              height: 4,
                                                                            ),
                                                                            SelectableText(
                                                                              data['result'],
                                                                              style: const TextStyle(
                                                                                fontSize: 11,
                                                                                fontFamily: "monospace",
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        ],
                                                                      ],
                                                                    );
                                                                  }

                                                                  return Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      if (total >
                                                                          1) ...[
                                                                        Row(
                                                                          mainAxisAlignment:
                                                                              MainAxisAlignment.spaceBetween,
                                                                          children: [
                                                                            Text(
                                                                              "${"Call".tl} ${currentIndex + 1} / $total",
                                                                              style: TextStyle(
                                                                                fontSize: 10,
                                                                                fontWeight: FontWeight.bold,
                                                                                color: secondaryTextColor.withValues(
                                                                                  alpha: 0.6,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            Row(
                                                                              children: [
                                                                                IconButton(
                                                                                  visualDensity: VisualDensity.compact,
                                                                                  padding: EdgeInsets.zero,
                                                                                  constraints: const BoxConstraints(),
                                                                                  icon: Icon(
                                                                                    Icons.arrow_back_ios_new_rounded,
                                                                                    size: 12,
                                                                                    color:
                                                                                        currentIndex >
                                                                                            0
                                                                                        ? textColor
                                                                                        : secondaryTextColor.withValues(
                                                                                            alpha: 0.2,
                                                                                          ),
                                                                                  ),
                                                                                  onPressed:
                                                                                      currentIndex >
                                                                                          0
                                                                                      ? () => setDetailState(() {
                                                                                          currentIndex--;
                                                                                          msg['_detailIdx'] = currentIndex;
                                                                                        })
                                                                                      : null,
                                                                                ),
                                                                                const SizedBox(
                                                                                  width: 12,
                                                                                ),
                                                                                IconButton(
                                                                                  visualDensity: VisualDensity.compact,
                                                                                  padding: EdgeInsets.zero,
                                                                                  constraints: const BoxConstraints(),
                                                                                  icon: Icon(
                                                                                    Icons.arrow_forward_ios_rounded,
                                                                                    size: 12,
                                                                                    color:
                                                                                        currentIndex <
                                                                                            total -
                                                                                                1
                                                                                        ? textColor
                                                                                        : secondaryTextColor.withValues(
                                                                                            alpha: 0.2,
                                                                                          ),
                                                                                  ),
                                                                                  onPressed:
                                                                                      currentIndex <
                                                                                          total -
                                                                                              1
                                                                                      ? () => setDetailState(() {
                                                                                          currentIndex++;
                                                                                          msg['_detailIdx'] = currentIndex;
                                                                                        })
                                                                                      : null,
                                                                                ),
                                                                              ],
                                                                            ),
                                                                          ],
                                                                        ),
                                                                        const Divider(
                                                                          height:
                                                                              16,
                                                                          thickness:
                                                                              0.5,
                                                                        ),
                                                                      ],
                                                                      AnimatedSwitcher(
                                                                        duration: const Duration(
                                                                          milliseconds:
                                                                              300,
                                                                        ),
                                                                        layoutBuilder:
                                                                            (
                                                                              currentChild,
                                                                              previousChildren,
                                                                            ) => Stack(
                                                                              alignment: Alignment.topLeft,
                                                                              children: [
                                                                                ...previousChildren,
                                                                                ?currentChild,
                                                                              ],
                                                                            ),
                                                                        transitionBuilder:
                                                                            (
                                                                              child,
                                                                              animation,
                                                                            ) {
                                                                              final offsetAnimation =
                                                                                  Tween<
                                                                                        Offset
                                                                                      >(
                                                                                        begin: const Offset(
                                                                                          0.1,
                                                                                          0.0,
                                                                                        ),
                                                                                        end: Offset.zero,
                                                                                      )
                                                                                      .animate(
                                                                                        CurvedAnimation(
                                                                                          parent: animation,
                                                                                          curve: Curves.easeOutCubic,
                                                                                        ),
                                                                                      );
                                                                              return FadeTransition(
                                                                                opacity: animation,
                                                                                child: SlideTransition(
                                                                                  position: offsetAnimation,
                                                                                  child: child,
                                                                                ),
                                                                              );
                                                                            },
                                                                        child: buildContent(
                                                                          currentIndex,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  );
                                                                },
                                                          ),
                                                        )
                                                      : const SizedBox(
                                                          key: ValueKey(
                                                            "empty",
                                                          ),
                                                        ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    } else if (role == 'error') {
                                      final String title =
                                          msg['title'] ?? "Error Occurred".tl;
                                      final String content =
                                          msg['content'] ?? "";

                                      messageWidget = Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 8,
                                            horizontal: 16,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 14,
                                          ),
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.75,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: Colors.redAccent
                                                  .withValues(alpha: 0.25),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.05,
                                                ),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 2,
                                                  right: 10,
                                                ),
                                                child: Icon(
                                                  Icons.error_outline_rounded,
                                                  size: 20,
                                                  color:
                                                      theme.colorScheme.error,
                                                ),
                                              ),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      title,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: theme
                                                            .colorScheme
                                                            .error,
                                                      ),
                                                    ),
                                                    if (content.isNotEmpty) ...[
                                                      const SizedBox(height: 4),
                                                      SelectableText(
                                                        content,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: theme
                                                              .colorScheme
                                                              .onSurface,
                                                          height: 1.35,
                                                        ),
                                                        selectionColor: theme
                                                            .colorScheme
                                                            .error
                                                            .withValues(
                                                              alpha: 0.2,
                                                            ),
                                                      ),
                                                    ],
                                                    const SizedBox(height: 8),
                                                    OutlinedButton.icon(
                                                      onPressed: () =>
                                                          _retryMessage(index),
                                                      style: OutlinedButton
                                                          .styleFrom(
                                                            foregroundColor:
                                                                theme
                                                                    .colorScheme
                                                                    .error,
                                                            side: BorderSide(
                                                              color: theme
                                                                  .colorScheme
                                                                  .error
                                                                  .withValues(
                                                                    alpha: 0.5,
                                                                  ),
                                                            ),
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                  horizontal:
                                                                      12,
                                                                  vertical: 4,
                                                                ),
                                                            minimumSize:
                                                                const Size(
                                                              0,
                                                              32,
                                                            ),
                                                            visualDensity:
                                                                VisualDensity
                                                                    .compact,
                                                          ),
                                                      icon: const Icon(
                                                        Icons.refresh_rounded,
                                                        size: 16,
                                                      ),
                                                      label: Text(
                                                        "Retry".tl,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }

                                    return InkWell(
                                      onTap: () {
                                        if (_isMultiSelectMode) {
                                          setState(() {
                                            if (isSelected) {
                                              _selectedMessageIndices.remove(
                                                index,
                                              );
                                            } else {
                                              _selectedMessageIndices.add(
                                                index,
                                              );
                                            }
                                          });
                                        }
                                      },
                                      onHover: (hovering) {
                                        setState(() {
                                          _hoveredMessageIndex = hovering
                                              ? index
                                              : null;
                                        });
                                      },
                                      onSecondaryTapDown: (details) =>
                                          _showMessageMenu(
                                            context,
                                            details.globalPosition,
                                            index,
                                          ),
                                      hoverColor: theme.colorScheme.primary
                                          .withValues(alpha: 0.05),
                                      highlightColor: theme.colorScheme.primary
                                          .withValues(alpha: 0.1),
                                      child: GestureDetector(
                                        onLongPressStart: (details) =>
                                            _showMessageMenu(
                                              context,
                                              details.globalPosition,
                                              index,
                                            ),
                                        behavior: HitTestBehavior.translucent,
                                        child: Container(
                                          color: isSelected
                                              ? theme.colorScheme.primary
                                                    .withValues(alpha: 0.1)
                                              : null,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(child: messageWidget),
                                              if (_isMultiSelectMode)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 16,
                                                        top: 16,
                                                      ),
                                                  child: Checkbox(
                                                    value: isSelected,
                                                    onChanged: (val) {
                                                      setState(() {
                                                        if (val == true) {
                                                          _selectedMessageIndices
                                                              .add(index);
                                                        } else {
                                                          _selectedMessageIndices
                                                              .remove(index);
                                                        }
                                                      });
                                                    },
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ),

                  Container(
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: _buildInputCapsule(
                      theme,
                      altColor,
                      borderColor,
                      textColor,
                      secondaryTextColor,
                    ),
                  ),
                ],
              ),
              IgnorePointer(
                ignoring: !_historyPanelOpen,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _historyPanelOpen ? 1.0 : 0.0,
                  child: GestureDetector(
                    onTap: () => setState(() => _historyPanelOpen = false),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              ),

              // Scroll to bottom button
              // Positioned(
              //   bottom: 110,
              //   right: 20,
              //   child: FadeTransition(
              //     opacity: _scrollToBottomController,
              //     child: ScaleTransition(
              //       scale: _scrollToBottomController,
              //       child: Container(
              //         decoration: BoxDecoration(
              //           color: theme.colorScheme.surface,
              //           shape: BoxShape.circle,
              //           border: Border.all(color: borderColor, width: 1),
              //           boxShadow: [
              //             BoxShadow(
              //               color: Colors.black.withValues(alpha: 0.1),
              //               blurRadius: 10,
              //               spreadRadius: 2,
              //             ),
              //           ],
              //         ),
              //         child: IconButton(
              //           icon: const Icon(Icons.arrow_downward_rounded),
              //           onPressed: _scrollToBottom,
              //           tooltip: "Scroll to Bottom".tl,
              //         ),
              //       ),
              //     ),
              //   ),
              // ),
              if (_isMultiSelectMode)
                Positioned(
                  bottom: 120,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 20),
                          onPressed: () {
                            final texts = _selectedMessageIndices
                                .map(
                                  (i) =>
                                      _agent.messages[i]['content']
                                          ?.toString() ??
                                      "",
                                )
                                .toList();
                            _copyToClipboard(texts.join("\n\n"));
                          },
                          tooltip: "Copy Selected".tl,
                        ),
                        const SizedBox(width: 4),
                        Container(width: 1, height: 20, color: borderColor),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.share_rounded, size: 20),
                          onPressed: _shareSelectedMessages,
                          tooltip: "Share Selected".tl,
                        ),
                        const SizedBox(width: 4),
                        Container(width: 1, height: 20, color: borderColor),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.camera_alt_rounded, size: 20),
                          onPressed: _screenshotSelectedMessages,
                          tooltip: "Screenshot Selected".tl,
                        ),
                        const SizedBox(width: 4),
                        Container(width: 1, height: 20, color: borderColor),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: Colors.redAccent,
                          ),
                          onPressed: () {
                            setState(() {
                              final sortedIndices =
                                  _selectedMessageIndices.toList()
                                    ..sort((a, b) => b.compareTo(a));
                              for (final i in sortedIndices) {
                                _agent.messages.removeAt(i);
                              }
                              _selectedMessageIndices.clear();
                              _isMultiSelectMode = false;
                            });
                            _saveSession();
                          },
                          tooltip: "Delete Selected".tl,
                        ),
                        const SizedBox(width: 4),
                        Container(width: 1, height: 20, color: borderColor),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => setState(() {
                            _isMultiSelectMode = false;
                            _selectedMessageIndices.clear();
                          }),
                          tooltip: "Cancel".tl,
                        ),
                      ],
                    ),
                  ),
                ),

              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutQuad,
                  width: _historyPanelOpen ? 280 : 0,
                  child: ClipRect(
                    child: OverflowBox(
                      minWidth: 280,
                      maxWidth: 280,
                      alignment: Alignment.centerRight,
                      child: _buildHistorySidebar(
                        theme,
                        borderColor,
                        textColor,
                        secondaryTextColor,
                        accentColor,
                        isPortrait,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLockScreen(ThemeData theme) {
    final textColor = theme.colorScheme.onSurface;
    final secondaryTextColor = theme.colorScheme.onSurfaceVariant;

    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_person_rounded,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Blora Agent Locked".tl,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Please login to Bloret PassPort or enter an API Key to continue using Blora Agent."
                  .tl,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: secondaryTextColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _unlockKeyController,
              decoration: InputDecoration(
                labelText: "API Key".tl,
                hintText: "sk-xxxxxx...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Padding(padding: const EdgeInsetsGeometry.only(left: 4), child: const Icon(Icons.key_rounded),),
                suffixIcon: Padding(padding: const EdgeInsetsGeometry.only(right: 4), child: IconButton(
                  icon: const Icon(Icons.check_circle_rounded),
                  onPressed: () async {
                    final key = _unlockKeyController.text.trim();
                    if (key.isNotEmpty) {
                      await ConfigService.set('custom_ai_key', key);
                      await ConfigService.set('ai_provider', 'custom_api');
                      setState(() {
                        _currentProviderKey = 'custom_api';
                        _loadModels();
                      });
                      showSuccess("Key saved, feature unlocked".tl);
                    }
                  },
                ),),
              ),
              obscureText: true,
              onSubmitted: (val) async {
                 if (val.trim().isNotEmpty) {
                    await ConfigService.set('custom_ai_key', val.trim());
                    await ConfigService.set('ai_provider', 'custom_api');
                    setState(() {
                      _currentProviderKey = 'custom_api';
                      _loadModels();
                    });
                    showSuccess("Key saved, feature unlocked".tl);
                 }
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text("OR".tl, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () {
                  MainShellState.instance?.jumpToPage(.passport);
                },
                icon: const Icon(Icons.login_rounded),
                label: Text(
                  "Login with Bloret PassPort".tl,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySidebar(
    ThemeData theme,
    Color borderColor,
    Color textColor,
    Color secondaryTextColor,
    Color accentColor,
    bool isPortrait,
  ) {
    return Material(
      elevation: 0,
      color: theme.cardColor,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: borderColor.withValues(alpha: 0.2)),
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  if (_isSelectMode)
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(() {
                        _isSelectMode = false;
                        _selectedFiles.clear();
                      }),
                    )
                  else
                    Icon(Icons.history, size: 20, color: textColor),
                  const SizedBox(width: 8),
                  Text(
                    _isSelectMode
                        ? "${_selectedFiles.length} ${"Selected".tl}"
                        : "History".tl,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (!_isSelectMode) ...[
                    IconButton(
                      icon: const Icon(Icons.checklist_rtl_rounded, size: 20),
                      onPressed: _agent.busy
                          ? null
                          : () => setState(() => _isSelectMode = true),
                      tooltip: "Batch Operations".tl,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.refresh,
                        size: 20,
                        color: _agent.busy
                            ? textColor.withValues(alpha: 0.3)
                            : textColor,
                      ),
                      onPressed: _agent.busy ? null : _loadHistoryList,
                      tooltip: "Refresh List".tl,
                    ),
                  ] else
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (_selectedFiles.length == _historyList.length) {
                            _selectedFiles.clear();
                          } else {
                            _selectedFiles.addAll(
                              _historyList.map((e) => e['filename'] as String),
                            );
                          }
                        });
                      },
                      child: Text(
                        _selectedFiles.length == _historyList.length
                            ? "Deselect All".tl
                            : "Select All".tl,
                      ),
                    ),
                ],
              ),
            ),
            if (isPortrait)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: borderColor.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Win11Dropdown(
                      initialValue: Bloriko.mode,
                      items: [
                        Win11DropdownItem(label: "Auto Mode".tl, value: "auto"),
                        Win11DropdownItem(
                          label: "Assist Click".tl,
                          value: "help",
                        ),
                        Win11DropdownItem(
                          label: "Planning Mode".tl,
                          value: "plan",
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => Bloriko.setMode(value));
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Win11Dropdown(
                      initialValue: Bloriko.type,
                      items: [
                        Win11DropdownItem(
                          label: "Default".tl,
                          value: "default",
                        ),
                        Win11DropdownItem(
                          label: "Bloriko".tl,
                          value: "bloriko",
                        ),
                        if (ConfigService.get("develop_mode") ?? false)
                          Win11DropdownItem(
                            label: "Bloriko (R18)".tl,
                            value: "bloriko_r18",
                          ),
                      ],
                      onChanged: (value) async {
                        if (value != null && value != Bloriko.type) {
                          if (_agent.messages.isNotEmpty) {
                            final bool? result = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text("Switch Character Type".tl),
                                content: Text(
                                  "Switching characters during a conversation may cause AI context confusion. Start a new conversation for the best experience?"
                                      .tl,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: Text("Ignore and Keep".tl),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: Text("Start New Conversation".tl),
                                  ),
                                ],
                              ),
                            );
                            if (result == true) {
                              _clearHistory();
                            }
                          }
                          Bloriko.setType(value);
                        }
                      },
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    itemCount: _historyList.length,
                    itemBuilder: (context, index) {
                      final item = _historyList[index];
                      final filePath = item['filename'] ?? "";
                      final isSelected = _selectedFiles.contains(filePath);
                      return GestureDetector(
                        onSecondaryTapDown: (details) => _isSelectMode
                            ? null
                            : _showHistoryMenu(
                                context,
                                details.globalPosition,
                                item,
                              ),
                        onLongPressStart: (details) => _isSelectMode
                            ? null
                            : _showHistoryMenu(
                                context,
                                details.globalPosition,
                                item,
                              ),
                        child: InkWell(
                          onTap: () {
                            if (_isSelectMode) {
                              setState(() {
                                if (isSelected) {
                                  _selectedFiles.remove(filePath);
                                } else {
                                  _selectedFiles.add(filePath);
                                }
                              });
                            } else {
                              _loadSession(filePath);
                            }
                          },
                          child: Container(
                            height: 58,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? accentColor.withValues(alpha: 0.1)
                                  : null,
                              border: Border(
                                bottom: BorderSide(
                                  color: borderColor.withValues(alpha: 0.1),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                if (_isSelectMode) ...[
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 18,
                                    color: isSelected
                                        ? accentColor
                                        : secondaryTextColor,
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['displayText'] ?? '',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: textColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item['subText'] ?? '',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: secondaryTextColor.withValues(
                                            alpha: 0.7,
                                          ),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (_isSelectMode && _selectedFiles.isNotEmpty)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.output_rounded,
                                color: Colors.blue,
                              ),
                              onPressed: _exportSelectedSessions,
                              tooltip: "Batch Export".tl,
                            ),
                            const VerticalDivider(
                              width: 1,
                              indent: 12,
                              endIndent: 12,
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                              ),
                              onPressed: _deleteSelectedSessions,
                              tooltip: "Batch Delete".tl,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_historyList.isEmpty)
                    Center(
                      child: Text(
                        "No history records".tl,
                        style: TextStyle(
                          fontSize: 13,
                          color: secondaryTextColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BloraCrashCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final ThemeData theme;

  const BloraCrashCard({super.key, required this.data, required this.theme});

  @override
  Widget build(BuildContext context) {
    final version = data['version'] ?? "Unknown";
    final analysis = data['analysis'] ?? "No analysis available";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.bug_report_rounded,
              color: Colors.redAccent,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${"Crash Analysis: ".tl}$version",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  analysis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text("${"Crash Details: ".tl}$version"),
                        content: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Analysis Result".tl,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(analysis),
                              const Divider(height: 24),
                              Text(
                                "Version Settings".tl,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  const JsonEncoder.withIndent("  ").convert(
                                    data['settings'] ?? {},
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("OK"),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.info_outline_rounded, size: 14),
                  label: Text("View Details".tl),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BloraSecurityCard extends StatelessWidget {
  final Map<String, dynamic> msg;
  final ThemeData theme;
  final bool isScreenshot;
  final VoidCallback? onDeny;
  final VoidCallback? onAllowOnce;
  final VoidCallback? onAlwaysAllow;

  const BloraSecurityCard({
    super.key,
    required this.msg,
    required this.theme,
    this.isScreenshot = false,
    this.onDeny,
    this.onAllowOnce,
    this.onAlwaysAllow,
  });

  @override
  Widget build(BuildContext context) {
    final String cmd = msg['command'] ?? "";
    final bool isWaiting = msg['status'] == 'waiting';
    final Color borderColor = theme.dividerColor;
    final Color altColor = theme.colorScheme.surfaceContainerHighest;
    final Color secondaryTextColor = theme.colorScheme.onSurfaceVariant;

    return Container(
      margin: isScreenshot
          ? EdgeInsets.zero
          : const EdgeInsets.only(left: 48, right: 16, bottom: 12, top: 12),
      decoration: BoxDecoration(
        color: isWaiting
            ? Colors.orange.withValues(alpha: 0.1)
            : altColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWaiting ? Colors.orange.withValues(alpha: 0.3) : borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isWaiting
                  ? Colors.orange.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.security_rounded,
                  size: 16,
                  color: isWaiting ? Colors.orange : secondaryTextColor,
                ),
                const SizedBox(width: 8),
                Text(
                  "Security Block: External Command Execution Request".tl,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color:
                        isWaiting ? Colors.orange.shade900 : secondaryTextColor,
                  ),
                ),
                const Spacer(),
                if (!isWaiting)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: Colors.green.shade400,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "LLM is attempting to execute the following system command:".tl,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    cmd,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (isWaiting && !isScreenshot)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: onDeny,
                        child: Text(
                          "Deny".tl,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: onAllowOnce,
                        child: Text("Allow Once".tl),
                      ),
                      FilledButton.icon(
                        onPressed: onAlwaysAllow,
                        icon: const Icon(Icons.verified_user_rounded, size: 16),
                        label: Text("Always Allow".tl),
                      ),
                    ],
                  )
                else if (!isWaiting)
                  Text(
                    msg['result'] == 'allow'
                        ? "Execution manually authorized.".tl
                        : msg['result'] == 'deny'
                            ? "Execution of the command refused.".tl
                            : "Permanently added to whitelist.".tl,
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: secondaryTextColor,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LongTextEditorDialog extends StatefulWidget {
  final String initialText;
  const _LongTextEditorDialog({required this.initialText});

  @override
  State<_LongTextEditorDialog> createState() => _LongTextEditorDialogState();
}

class _LongTextEditorDialogState extends State<_LongTextEditorDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text("Edit Long Text".tl),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _controller.text),
              child: Text("Save and Return".tl),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            decoration: InputDecoration(
              hintText: "Enter or paste long text here...".tl,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
            ),
            style: const TextStyle(
              fontSize: 16,
              height: 1.5,
              fontFamily: 'Microsoft',
            ),
          ),
        ),
      ),
    );
  }
}

class _ScreenshotGenerator extends StatefulWidget {
  final List<Map<String, dynamic>> messages;
  final Set<int> selectedIndices;
  final Function(Uint8List) onCaptured;

  const _ScreenshotGenerator({
    required this.messages,
    required this.selectedIndices,
    required this.onCaptured,
  });

  @override
  State<_ScreenshotGenerator> createState() => _ScreenshotGeneratorState();
}

class _ScreenshotGeneratorState extends State<_ScreenshotGenerator> {
  final GlobalKey _repaintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  Future<void> _capture() async {
    try {
      // Give some time for rendering
      await Future.delayed(const Duration(milliseconds: 500));
      final RenderRepaintBoundary boundary =
          _repaintKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) {
        widget.onCaptured(byteData.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint("Capture error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedIndices = widget.selectedIndices.toList()..sort();

    return Material(
      color: Colors.transparent,
      child: Center(
        child: SingleChildScrollView(
          child: RepaintBoundary(
            key: _repaintKey,
            child: Container(
              width: 500,
              padding: const EdgeInsets.all(24),
              color: theme.scaffoldBackgroundColor,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Blora Conversation Export".tl,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...sortedIndices.map((idx) {
                    final msg = widget.messages[idx];
                    final role = msg['role'];
                    final isUser = role == 'user';
                    final agentType = msg['agentType'] ?? "default";
                    final agentName =
                        (agentType == "bloriko" || agentType == "bloriko_r18")
                        ? "Bloriko".tl
                        : "Blora Agent".tl;

                    final rawContent = msg['content']?.toString() ?? "";
                    final crashRegExp = RegExp(
                      r'<crash_card>(.*?)</crash_card>',
                      dotAll: true,
                    );
                    final crashMatch = crashRegExp.firstMatch(rawContent);

                    Widget contentWidget;
                    bool isSpecialCard = false;

                    if (role == 'security') {
                      isSpecialCard = true;
                      contentWidget = BloraSecurityCard(
                        msg: msg,
                        theme: theme,
                        isScreenshot: true,
                      );
                    } else if (crashMatch != null) {
                      isSpecialCard = true;
                      try {
                        final data = jsonDecode(crashMatch.group(1)!);
                        contentWidget = BloraCrashCard(data: data, theme: theme);
                      } catch (e) {
                        contentWidget = const Text("Error parsing crash card");
                      }
                    } else {
                      contentWidget = GptMarkdown(
                        msg['displayText'] ??
                            (msg['content'] is String
                                ? msg['content']
                                : "[${"Attachment".tl}]"),
                        style: TextStyle(
                          fontSize: 13,
                          color: isUser
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: isUser
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: isUser
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            children: [
                              if (!isUser)
                                const Icon(
                                  Icons.smart_toy,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                              if (!isUser) const SizedBox(width: 4),
                              Text(
                                isUser
                                    ? ConfigService.get(
                                            "Bloret_PassPort_UserName",
                                          ) ??
                                          "Me".tl
                                    : agentName,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                              if (isUser) const SizedBox(width: 4),
                              if (isUser)
                                const Icon(
                                  Icons.person,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (isSpecialCard)
                            contentWidget
                          else
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: contentWidget,
                            ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  const Divider(),
                  Text(
                    "Exported from Blora Launcher".tl,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}