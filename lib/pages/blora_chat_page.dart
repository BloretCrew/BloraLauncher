import 'dart:convert';
import 'dart:io';

import 'package:bloret_launcher/core/i18n.dart';
import 'package:bloret_launcher/core/logger.dart';
import 'package:bloret_launcher/services/bloriko.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:bloret_launcher/widgets/windows_widgets.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:image/image.dart' hide Image, Color;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pasteboard/pasteboard.dart';

import '../services/config_service.dart';

class BloraChatPage extends StatefulWidget {
  const BloraChatPage({super.key});

  @override
  State<BloraChatPage> createState() => _BloraChatPageState();
}

class _BloraChatPageState extends State<BloraChatPage> with AutomaticKeepAliveClientMixin {
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

  final List<File> _attachments = [];
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  bool _isDocumentMode = false;

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
        _loadHistoryList().then((_) {
          if (_agent.messages.isEmpty && _historyList.isNotEmpty) {
            _loadSession(_historyList.first['filename']);
          }
        });
        if (_agent.messages.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 200), () {
            _scrollToBottom();
          });
        }
      }
    });
  }

  void _onAgentStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputAnswerController.dispose();
    _msgScrollController.dispose();
    _inputScrollController.dispose();
    _answerScrollController.dispose();
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
      case 'ask_question_details': return Icons.message;
      case 'fetch_page': return Icons.web_rounded;
      case 'delegate_task': return Icons.call_split_rounded;
      case 'shizuku_init': return Icons.flash_on_rounded;
      case 'shizuku_check_permission': return Icons.verified_user_rounded;
      case 'shizuku_run_shell': return Icons.terminal_rounded;
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
          onTap: () {
            Clipboard.setData(ClipboardData(text: content));
          },
          child: Row(
            children: [
              const Icon(Icons.copy_rounded, size: 18),
              const SizedBox(width: 8),
              Text(_tr("复制内容")),
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
                const Icon(Icons.download_for_offline_rounded, size: 18, color: Colors.blue),
                const SizedBox(width: 8),
                Text(_tr("下载所有图片"), style: const TextStyle(color: Colors.blue)),
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
    final text = _inputController.text.trim();
    if (text.isEmpty && _attachments.isEmpty) {
      _inputController.clear();
      return;
    }
    if (_agent.busy || _currentModelId == null) return;

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
        'displayText': effectiveText.isNotEmpty ? effectiveText : "[${_tr("附件")}]"
      });
      if (_agent.messages.length == 1 || _agent.conversationTitle.isEmpty) {
        _agent.conversationTitle = text.isNotEmpty ? text.split('\n').first.trim() : _tr("图片/文件对话");
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
        if (_agent.messages.isNotEmpty) _scrollToBottom();
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

  Future<void> _downloadImage(String url) async {
    try {
      final dio = Dio();
      final response = await dio.get(url, options: Options(responseType: ResponseType.bytes));

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: _tr("保存图片"),
        fileName: 'downloaded_image_${DateTime.now().millisecondsSinceEpoch}.png',
        type: FileType.image,
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(response.data);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr("图片已保存"))));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr("下载失败: $e"))));
    }
  }

  void _showImageDialog(BuildContext context, dynamic imageSource, String heroTag) {
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
                        : Image.memory(base64Decode(imageSource.toString().split(',').last)),
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
                        decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
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

  String _tr(String text) {
    return text.tl;
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'pdf', 'docx', 'pptx', 'txt', 'csv', 'xlsx', 'tsv',
        'dart', 'py', 'js', 'ts', 'java', 'kt', 'cpp', 'c', 'h', 'html', 'css', 'json', 'yaml', 'xml', 'md',
        'jpg', 'jpeg', 'png', 'gif', 'webp'
      ],
    );
    if (result != null) {
      for (var path in result.paths) {
        if (path != null) {
          final file = File(path);
          final bytes = await file.length();
          if (bytes > 3 * 1024 * 1024) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("${_tr("文件")} ${p.basename(file.path)} ${_tr("超过 3MB，无法添加")}"))
              );
            }
            continue;
          }
          _attachments.add(file);
          _listKey.currentState?.insertItem(_attachments.length - 1, duration: const Duration(milliseconds: 300));
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
    setState(() {});
  }

  Future<void> _handlePaste() async {
    try {
      final List<String> files = await Pasteboard.files();
      if (files.isNotEmpty) {
        final allowedExts = {
          '.pdf', '.docx', '.pptx', '.txt', '.csv', '.xlsx', '.tsv',
          '.dart', '.py', '.js', '.ts', '.java', '.kt', '.cpp', '.c', '.h', '.html', '.css', '.json', '.yaml', '.xml', '.md',
          '.jpg', '.jpeg', '.png', '.gif', '.webp'
        };

        for (var path in files) {
          final file = File(path);
          final ext = p.extension(path).toLowerCase();
          final bytes = await file.length();
          if (bytes > 3 * 1024 * 1024) {
             if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(content: Text("${_tr("文件")} ${p.basename(file.path)} ${_tr("超过 3MB，无法添加")}"))
               );
             }
             continue;
          }
          if (file.existsSync() && allowedExts.contains(ext) && !_attachments.any((a) => a.path == path)) {
            _attachments.add(file);
            _listKey.currentState?.insertItem(_attachments.length - 1, duration: const Duration(milliseconds: 300));
          }
        }
        setState(() {});
        return;
      }

      final imageBytes = await Pasteboard.image;
      if (imageBytes != null) {
        Uint8List? compBytes;
        if (imageBytes.length > 3 * 1024 * 1024) {
          final img = decodeImage(imageBytes);
          final comp = encodeJpg(img!, quality: 50);
          compBytes = Uint8List.fromList(comp);
          if (imageBytes.length > 3 * 1024 * 1024) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr("图片超过 3MB，无法添加"))));
            }
            return;
          }
        }
        final tempDir = await getTemporaryDirectory();
        final fileName = 'pasted_img_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(p.join(tempDir.path, fileName));
        await file.writeAsBytes(compBytes ?? imageBytes);
        _attachments.add(file);
        _listKey.currentState?.insertItem(_attachments.length - 1, duration: const Duration(milliseconds: 300));
        setState(() {});
        return;
      }

      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final plainText = clipboardData?.text;
      if (plainText != null) {
        final hasExistingText = _inputController.text.trim().isNotEmpty;
        if (plainText.length > 4000 || hasExistingText) {
          final tempDir = await getTemporaryDirectory();
          final fileName = 'pasted_text_${DateTime.now().millisecondsSinceEpoch}.txt';
          final file = File(p.join(tempDir.path, fileName));
          await file.writeAsString(plainText);

          setState(() {
            _attachments.add(file);
            _listKey.currentState?.insertItem(_attachments.length - 1, duration: const Duration(milliseconds: 300));
            _inputController.text = '';
            _isDocumentMode = false;
          });
        } else {
          _inputController.text = plainText;
        }
      }
    } catch (e) {
      debugPrint("Paste error: $e");
    }
  }

  Widget _buildAttachmentItem(File file, Animation<double> animation, int index) {
    final isImage = ['.jpg', '.jpeg', '.png', '.gif', '.webp'].any((ext) => file.path.toLowerCase().endsWith(ext));
    final heroTag = 'attachment_${file.path}_${DateTime.now().millisecondsSinceEpoch}_$index';

    return ScaleTransition(
      scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
      child: FadeTransition(
        opacity: animation,
        child: Container(
          width: 70,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
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
                            width: 70, height: 70,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            key: ValueKey(file.path),
                          )
                        ),
                      ),
                    )
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.insert_drive_file_outlined, size: 24),
                      const SizedBox(height: 4),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(p.basename(file.path), style: const TextStyle(fontSize: 8), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (file.path.contains('pasted_text_') && file.path.endsWith('.txt'))
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: IconButton(
                            icon: const Icon(Icons.keyboard_return_rounded, size: 14, color: Colors.blue),
                            onPressed: () async {
                              try {
                                final text = await file.readAsString();
                                setState(() {
                                  _inputController.text = text;
                                  _removeAttachment(index);
                                });
                                _focusNode.requestFocus();
                              } catch (_) {}
                            },
                            tooltip: _tr("还原到输入框"),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ]),
              ),
              if (index != -1)
                Positioned(
                  top: 2, right: 2,
                  child: GestureDetector(
                    onTap: () => _removeAttachment(index),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentBar() {
    if (_attachments.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 80,
      margin: const EdgeInsets.only(bottom: 8),
      child: AnimatedList(
        key: _listKey,
        scrollDirection: Axis.horizontal,
        initialItemCount: _attachments.length,
        itemBuilder: (context, index, animation) {
          return _buildAttachmentItem(_attachments[index], animation, index);
        },
      ),
    );
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
  bool _isFetchingModels = false;

  Future<void> _fetchRemoteModels() async {
    if (_isFetchingModels) return;

    final key = _currentProviderKey == 'google_ai_studio' ? 'google_ai_key' : 'custom_ai_key';
    if (ConfigService.get(key) == null || ConfigService.get(key).isEmpty) return;

    setState(() => _isFetchingModels = true);
    try {
      final response = await Bloriko.client.models.list();
      final List<Map<String, dynamic>> remoteModels = [];

      for (var model in response.data) {
        if (_currentProviderKey == 'google_ai_studio' && !model.id.contains('gemini')) continue;

        String rawName = model.id.replaceAll('models/', '');
        String formattedName = rawName.split('-').map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1);
        }).join(' ');

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

          if (savedLastModel != null && _currentModels.any((m) => m["id"] == savedLastModel)) {
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
      "google_ai_studio": {
        "models": [
          {"id": "none", "name": "未获取到模型", "tool_call": false},
        ],
      },
      "custom_api": {
        "models": [
          {"id": ConfigService.get("custom_ai_model") ?? "custom-model", "name": _tr("自定义模型"), "tool_call": true},
        ],
      },
    };

    final providerData = builtinProviders[_currentProviderKey];
    _currentModels = providerData != null ? List<Map<String, dynamic>>.from(providerData["models"]) : [];

    if (_currentProviderKey == 'google_ai_studio' || _currentProviderKey == 'custom_api') {
      _fetchRemoteModels();
    }

    final lastModelKey = 'ai_model_last_$_currentProviderKey';
    final savedLastModel = ConfigService.get(lastModelKey);

    if (savedLastModel != null && _currentModels.any((m) => m["id"] == savedLastModel)) {
      _currentModelId = savedLastModel;
    } else if (!_currentModels.any((m) => m["id"] == _currentModelId) && _currentModels.isNotEmpty) {
      _currentModelId = _currentModels[0]["id"];
    }

    ConfigService.set('ai_model', _currentModelId);
  }

  Future<void> _showCustomApiDialog() async {
    final urlController = TextEditingController(text: ConfigService.get("custom_ai_base_url") ?? "https://api.openai.com/v1");
    final keyController = TextEditingController(text: ConfigService.get("custom_ai_key") ?? "");
    final modelController = TextEditingController(text: ConfigService.get("custom_ai_model") ?? "gpt-4o");

    final isGoogle = _currentProviderKey == 'google_ai_studio';
    if (isGoogle) {
      keyController.text = ConfigService.get("google_ai_key") ?? "";
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isGoogle ? _tr("配置 Google AI Studio") : _tr("配置自定义 API")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isGoogle)
              TextField(
                controller: urlController,
                decoration: InputDecoration(labelText: _tr("Base URL"), hintText: "https://api.example.com/v1"),
              ),
            TextField(
              controller: keyController,
              decoration: InputDecoration(labelText: _tr("API Key"), hintText: "AQ.xxxxxx"),
              obscureText: true,
            ),
            if (!isGoogle)
              TextField(
                controller: modelController,
                decoration: InputDecoration(labelText: _tr("默认模型 ID"), hintText: "gpt-4o"),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(_tr("取消"))),
          TextButton(
            onPressed: () async {
              if (isGoogle) {
                await ConfigService.set("google_ai_key", keyController.text);
              } else {
                await ConfigService.set("custom_ai_base_url", urlController.text);
                await ConfigService.set("custom_ai_key", keyController.text);
                await ConfigService.set("custom_ai_model", modelController.text);
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
            child: Text(_tr("保存")),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;
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
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, animation) => SizeTransition(
                            sizeFactor: animation,
                            axis: Axis.horizontal,
                            alignment: Alignment.centerLeft,
                            child: FadeTransition(opacity: animation, child: child),
                          ),
                          child: Bloriko.type == "bloriko"
                            ? Text(_tr("络可"), key: const ValueKey("bloriko"), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor))
                            : Text(_tr("Blora Agent"), key: const ValueKey("blora"), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
                        ),
                        const SizedBox(width: 8),
                        ListenableBuilder(
                          listenable: _agent,
                          builder: (context, child) {
                            if (_agent.connectionStatus == BlorikoConnectionStatus.idle || _agent.connectionStatus == BlorikoConnectionStatus.finished) {
                              return const SizedBox.shrink();
                            }
                            String statusText = "";
                            Color statusColor = accentColor;
                            switch (_agent.connectionStatus) {
                              case BlorikoConnectionStatus.connecting: statusText = "正在连接..."; break;
                              case BlorikoConnectionStatus.handshake: statusText = "正在响应..."; break;
                              case BlorikoConnectionStatus.streaming: statusText = "接收数据中..."; break;
                              case BlorikoConnectionStatus.error: statusText = "连接失败"; statusColor = Colors.red; break;
                              default: break;
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_agent.connectionStatus != BlorikoConnectionStatus.error)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: statusColor)),
                                    ),
                                  Text(statusText, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _agent.conversationTitle.isNotEmpty
                            ? Text("— ${_agent.conversationTitle}", style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: secondaryTextColor), maxLines: 1, overflow: TextOverflow.ellipsis)
                            : const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 8),
                        if (!isPortrait) ...[
                          SizedBox(
                            width: 128,
                            child: Win11Dropdown(
                              initialValue: Bloriko.mode,
                              items: [
                                Win11DropdownItem(label: _tr("自动模式"), value: "auto"),
                                Win11DropdownItem(label: _tr("辅助点击"), value: "help"),
                                Win11DropdownItem(label: _tr("规划模式"), value: "plan"),
                              ],
                              onChanged: (value) { if (value != null) {
                                setState(() {
                                  Bloriko.setMode(value);
                                });
                              }},
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
                                if (ConfigService.get("develop_mode") ?? false) Win11DropdownItem(label: _tr("络可 (R18)"), value: "bloriko_r18"),
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
                                  Bloriko.setType(value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
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
                          ? AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: Bloriko.type == "bloriko" || Bloriko.type == "bloriko_r18"
                                  ? Center(
                                      key: const ValueKey("empty_bloriko"),
                                      child: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
                                        ClipRRect(borderRadius: BorderRadius.circular(36), child: Container(width: 72, height: 72, color: Colors.grey.shade300, child: const Icon(Icons.smart_toy, size: 36))),
                                        const SizedBox(height: 12),
                                        Text(_tr("络可"), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
                                        const SizedBox(height: 12),
                                        Text(_tr("${ConfigService.get("user_identity") == "sister" ? "姐姐" : ConfigService.get("user_identity") == "little_sister" ? "妹妹" : "哥哥"}好呀${Bloriko.type == "bloriko_r18" ? "♥" : "！"} 络可在这里等你很久啦~(开心地挥挥小手)\n\n试试跟 Bloriko 说：\n• 帮我创建一个文件\n• 搜索一下项目里的 TODO"), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.4, color: secondaryTextColor)),
                                        AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 300),
                                          transitionBuilder: (child, anim) => SizeTransition(sizeFactor: anim, alignment: Alignment.center, child: FadeTransition(opacity: anim, child: child)),
                                          child: Bloriko.mode == "help"
                                            ? Text(_tr("• 点击一下页面试试"), key: const ValueKey("bloriko_help"), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.4, color: secondaryTextColor))
                                            : const SizedBox.shrink(key: ValueKey("bloriko_no_help")),
                                        ),
                                        Text(_tr("• 执行一个命令看看\n• 记住我的偏好是..."), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.4, color: secondaryTextColor)),
                                      ])),
                                    )
                                  : Center(
                                      key: const ValueKey("empty_blora"),
                                      child: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
                                        ClipRRect(borderRadius: BorderRadius.circular(36), child: Container(width: 72, height: 72, color: Colors.grey.shade300, child: const Icon(Icons.smart_toy, size: 36))),
                                        const SizedBox(height: 12),
                                        Text(_tr("Blora Agent"), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
                                        const SizedBox(height: 12),
                                        Text(_tr("您好，我是Blora Agent，我可以协助您使用Bloret Launcher\n\n向 Blora Agent 发送：\n• 帮我创建文件\n• 搜索项目里的 TODO"), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.4, color: secondaryTextColor)),
                                        AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 300),
                                          transitionBuilder: (child, anim) => SizeTransition(sizeFactor: anim, alignment: Alignment.center, child: FadeTransition(opacity: anim, child: child)),
                                          child: Bloriko.mode == "help"
                                            ? Text("• 帮我点击页面", key: const ValueKey("help_mode"), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.4, color: secondaryTextColor))
                                            : const SizedBox.shrink(key: ValueKey("no_help")),
                                        ),
                                        Text(_tr("• 执行一个命令\n• 记住我的偏好..."), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.4, color: secondaryTextColor)),
                                      ])),
                                    ),
                            )
                          : LayoutBuilder(
                              key: const ValueKey("chat_list_wrapper"),
                              builder: (context, constraints) {
                                return ListView.builder(
                                  key: const ValueKey("chat_list"),
                                  padding: const EdgeInsets.only(bottom: 240),
                                  controller: _agent.messages.isEmpty ? null : _msgScrollController,
                                  itemCount: _agent.messages.length + (_agent.busy ? 1 : 0),
                                  itemBuilder: (context, index) {
                          if (index == _agent.messages.length) {
                            bool showAvatar = true;
                            if (index > 0 && _agent.messages[index - 1]['role'] == 'assistant') {
                              showAvatar = false;
                            }

                            bool isWaiting = _agent.messages.isNotEmpty &&
                                             ((_agent.messages.last['role'] == 'system' &&
                                               (_agent.messages.last['tool'] == 'ask_question' || _agent.messages.last['tool'] == 'ask_question_details') &&
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
                                  ListenableBuilder(
                                    listenable: _agent,
                                    builder: (context, child) {
                                      String text;
                                      if (isWaiting) {
                                        text = _tr("等待中...");
                                      } else {
                                        text = switch (_agent.connectionStatus) {
                                          BlorikoConnectionStatus.connecting => _tr("正在连接..."),
                                          BlorikoConnectionStatus.handshake => _tr("正在验证..."),
                                          BlorikoConnectionStatus.streaming => _tr("正在接收..."),
                                          _ => _tr("正在思考..."),
                                        };
                                      }
                                      return Text(text, style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: secondaryTextColor.withValues(alpha: 0.7)));
                                    },
                                  ),
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

                            void hideSecurityCard() {
                              setState(() {
                                msg['hidden'] = true;
                              });
                            }

                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
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
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                alignment: WrapAlignment.end,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  TextButton(
                                                    onPressed: () {
                                                      hideSecurityCard();
                                                      _agent.handleSecurityAction('deny');
                                                    },
                                                    child: Text(
                                                      _tr("拒绝"),
                                                      style: const TextStyle(color: Colors.redAccent),
                                                    ),
                                                  ),

                                                  OutlinedButton(
                                                    onPressed: () {
                                                      hideSecurityCard();
                                                      _agent.handleSecurityAction('allow');
                                                    },
                                                    child: Text(_tr("允许一次")),
                                                  ),

                                                  FilledButton.icon(
                                                    onPressed: () {
                                                      hideSecurityCard();
                                                      _agent.handleSecurityAction(
                                                        'always',
                                                        command: cmd,
                                                      );
                                                    },
                                                    icon: const Icon(Icons.verified_user_rounded, size: 16),
                                                    label: Text(_tr("总是允许")),
                                                  ),
                                                ],
                                              )
                                            else
                                              Text(
                                                msg['result'] == 'allow'
                                                  ? _tr("已手动授权执行。")
                                                  : msg['result'] == 'deny'
                                                    ? _tr("已拒绝执行该命令。")
                                                    : _tr("已永久加入白名单。"),
                                                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: secondaryTextColor),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                                  : const SizedBox.shrink(key: ValueKey("empty")),
                            );
                          }

                          if (role == 'user') {
                            final content = msg['content'];
                            final List<String> imageUrls = [];
                            final List<Map<String, dynamic>> files = [];

                            if (content is List) {
                              for (var part in content) {
                                if (part is Map) {
                                  if (part['type'] == 'input_image' || part['type'] == 'image_url') {
                                    imageUrls.add(part['image_url']?.toString() ?? "");
                                  } else if (part['type'] == 'input_file') {
                                    files.add(Map<String, dynamic>.from(part));
                                  }
                                }
                              }
                            }

                            return Align(
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
                                onSecondaryTapDown: (details) => _showMessageMenu(context, details.globalPosition, index),
                                onLongPressStart: (details) => _showMessageMenu(context, details.globalPosition, index),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                                  decoration: BoxDecoration(
                                    color: accentColor,
                                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(4)),
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (imageUrls.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: Wrap(
                                            spacing: 4, runSpacing: 4,
                                            children: (content as List).asMap().entries.where((e) => e.value is Map && (e.value['type'] == 'input_image' || e.value['type'] == 'image_url')).map((e) {
                                              final imgIdx = e.key;
                                              final part = e.value as Map;
                                              final url = part['image_url']?.toString() ?? "";
                                              if (!url.startsWith('data:image')) return const SizedBox.shrink();
                                              final heroTag = 'msg_${index}_img_$imgIdx';

                                              return GestureDetector(
                                                onTap: () => _showImageDialog(context, url, heroTag),
                                                child: Hero(
                                                  tag: heroTag,
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: part['_decodedBytes'] != null
                                                      ? Image.memory(
                                                          Uint8List.fromList((part['_decodedBytes'] as List).cast()),
                                                          width: 100, height: 100, fit: BoxFit.cover,
                                                          gaplessPlayback: true,
                                                          key: ValueKey(url),
                                                        )
                                                      : Image.memory(
                                                          base64Decode(url.split(',').last),
                                                          width: 100, height: 100, fit: BoxFit.cover,
                                                          gaplessPlayback: true,
                                                          key: ValueKey(url),
                                                        ),
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      if (files.isNotEmpty)
                                        Column(
                                          children: files.map((file) {
                                            final isLongText = file['filename'] == "long_text.txt";
                                            return Container(
                                              margin: const EdgeInsets.only(bottom: 8),
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.insert_drive_file_rounded, color: Colors.white, size: 24),
                                                  const SizedBox(width: 10),
                                                  Flexible(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          file['filename'] ?? "Unknown",
                                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                                        ),
                                                        if (isLongText)
                                                          TextButton(
                                                            style: TextButton.styleFrom(
                                                              visualDensity: VisualDensity.compact,
                                                              padding: EdgeInsets.zero,
                                                              minimumSize: const Size(0, 0),
                                                            ),
                                                            onPressed: () {
                                                              try {
                                                                final decoded = utf8.decode(base64Decode(file['file_data']));
                                                                setState(() {
                                                                  _inputController.text = decoded;
                                                                  _agent.messages.removeAt(index);
                                                                });
                                                                _focusNode.requestFocus();
                                                              } catch (_) {}
                                                            },
                                                            child: Text(_tr("还原到输入框"), style: const TextStyle(color: Colors.white70, fontSize: 11, decoration: TextDecoration.underline)),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      SelectableText(
                                        msg['displayText'] ?? (msg['content'] is String ? msg['content'] : _tr("[附件]")),
                                        style: TextStyle(fontSize: 14, color: theme.colorScheme.onPrimary, height: 1.35),
                                        selectionColor: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                                      ),
                                    ],
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
                                          const SizedBox(width: 32),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 4),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                GptMarkdown(msg['content'] ?? '...', style: TextStyle(fontSize: 14, color: textColor, height: 1.35)),
                                                // 提取并显示下载图片的按钮
                                                Builder(builder: (context) {
                                                  final content = msg['content']?.toString() ?? "";
                                                  final regExp = RegExp(r'!\[.*?\]\((.*?)\)');
                                                  final matches = regExp.allMatches(content);
                                                  if (matches.isEmpty) return const SizedBox.shrink();

                                                  return Padding(
                                                    padding: const EdgeInsets.only(top: 8),
                                                    child: Wrap(
                                                      spacing: 8,
                                                      children: matches.map((m) {
                                                        final url = m.group(1) ?? "";
                                                        return IconButton.filledTonal(
                                                          icon: const Icon(Icons.download_rounded, size: 16),
                                                          onPressed: () => _downloadImage(url),
                                                          tooltip: _tr("下载图片"),
                                                        );
                                                      }).toList(),
                                                    ),
                                                  );
                                                }),
                                              ],
                                            )
                                          )
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            } else if (role == 'system') {
                              if (msg['tool'] == 'set_user_identity') {
                                return const SizedBox.shrink();
                              }
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
                                  padding: const EdgeInsets.only(left: 32),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: hasDetail ? () => setState(() => msg['isExpanded'] = !isExpanded) : null,
                                        behavior: HitTestBehavior.opaque,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (msg['tool']?.toString().startsWith('shizuku_') ?? false)
                                              Padding(
                                                padding: const EdgeInsets.only(right: 6),
                                                child: Image.asset("assets/icons/shizuku.png", width: 14, height: 14),
                                              ),
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
                                            int currentIndex = msg['_detailIdx'] ?? (total - 1);

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
                                                  ] else if (msg['tool'] == 'ask_question_details' && data['args'] != null) ...[
                                                    Builder(builder: (context) {
                                                      try {
                                                        final Map<String, dynamic> args = jsonDecode(data['args']);
                                                        final String question = args['question'] ?? "";
                                                        final String description = args['description'] ?? "";
                                                        final bool isRunning = msg['status'] == 'running';

                                                        return Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(question, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                                            const SizedBox(height: 12),
                                                            if (isRunning)
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
                                                                            thumbVisibility: true, controller: _answerScrollController, radius: const Radius.circular(8),
                                                                            child: SingleChildScrollView(
                                                                              controller: _answerScrollController,
                                                                              child: Focus(
                                                                                onKeyEvent: (node, event) {
                                                                                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                                                                                    final isShift = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) || HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
                                                                                    if (!isShift) { _sendMessage(); return KeyEventResult.handled; }
                                                                                  }
                                                                                  return KeyEventResult.ignored;
                                                                                },
                                                                                child: TextField(controller: _inputAnswerController, focusNode: _focusAnswerNode, maxLines: null, keyboardType: TextInputType.multiline, decoration: InputDecoration(hintText: description, border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 6)), style: TextStyle(fontSize: 14, color: textColor)),
                                                                              ),
                                                                            )
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(width: 10),
                                                                    IconButton.filled(padding: const EdgeInsets.all(2), icon: Icon(Icons.send, size: 20), onPressed: () {
                                                                      data['result'] = _inputAnswerController.text;
                                                                      if (data['result'] != null) {
                                                                        _agent.answerDetailQuestion(data['result']);
                                                                        _inputAnswerController.clear();
                                                                      }}),
                                                                  ],
                                                                ),
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
                                                                      child: Text(data['result'], style: TextStyle(fontSize: 12, color: accentColor, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                                                  layoutBuilder: (currentChild, previousChildren) => Stack(alignment: Alignment.topLeft, children: [...previousChildren, ?currentChild]),
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
                          } else if (role == 'error') {
                            final String title = msg['title'] ?? "发生错误";
                            final String content = msg['content'] ?? "";

                            return Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                onSecondaryTapDown: (details) => _showMessageMenu(context, details.globalPosition, index),
                                onLongPressStart: (details) => _showMessageMenu(context, details.globalPosition, index),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.redAccent.withValues(alpha: 0.25),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2, right: 10),
                                        child: Icon(
                                          Icons.error_outline_rounded,
                                          size: 20,
                                          color: theme.colorScheme.error,
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: theme.colorScheme.error,
                                              ),
                                            ),
                                            if (content.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              SelectableText(
                                                content,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: theme.colorScheme.onSurface,
                                                  height: 1.35,
                                                ),
                                                selectionColor: theme.colorScheme.error.withValues(alpha: 0.2),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      );
                    }
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
                                  items: [
                                    Win11DropdownItem(label: "Bloret PassPort", value: "bloret_passport"),
                                    Win11DropdownItem(label: "OpenCode Zen", value: "opencode_zen"),
                                    Win11DropdownItem(label: "Google AI Studio", value: "google_ai_studio"),
                                    Win11DropdownItem(label: _tr("自定义 API"), value: "custom_api"),
                                  ],
                                  initialValue: _currentProviderKey,
                                  onChanged: (value) async {
                                    if (value != null) {
                                      await ConfigService.set('ai_provider', value);
                                      if (!mounted) return;
                                      setState(() {
                                        _currentProviderKey = value;
                                        _loadModels();
                                      });
                                      if (value == 'custom_api' || value == 'google_ai_studio') {
                                        final key = value == 'google_ai_studio' ? 'google_ai_key' : 'custom_ai_key';
                                        if (ConfigService.get(key) == null || ConfigService.get(key).isEmpty) {
                                          _showCustomApiDialog();
                                        }
                                      }
                                    }
                                  },
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                transitionBuilder: (Widget child, Animation<double> animation) {
                                  return SizeTransition(
                                    sizeFactor: animation,
                                    axis: Axis.horizontal,
                                    alignment: Alignment.centerLeft,
                                    child: FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                  );
                                },
                                child: (_currentProviderKey == 'custom_api' || _currentProviderKey == 'google_ai_studio')
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(left: 4),
                                            child: IconButton(
                                              icon: const Icon(Icons.settings_outlined, size: 18),
                                              onPressed: _showCustomApiDialog,
                                              tooltip: _tr("配置 API"),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(left: 4),
                                            child: AnimatedSwitcher(
                                              duration: const Duration(milliseconds: 200),
                                              transitionBuilder: (child, animation) {
                                                return ScaleTransition(
                                                  scale: animation,
                                                  child: FadeTransition(opacity: animation, child: child),
                                                );
                                              },
                                              child: _isFetchingModels
                                                  ? const SizedBox(key: ValueKey("loading"), width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                                  : IconButton(
                                                      key: const ValueKey("refresh"),
                                                      icon: const Icon(Icons.refresh_rounded, size: 18),
                                                      onPressed: _fetchRemoteModels,
                                                      tooltip: _tr("同步云端模型"),
                                                    ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              if (!isPortrait || (_currentProviderKey != 'custom_api' && _currentProviderKey != 'google_ai_studio')) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Win11Dropdown(
                                    items: _currentModels.map((model) => Win11DropdownItem(label: model["name"] ?? "", value: model["id"])).toList(),
                                    initialValue: _currentModelId,
                                    onChanged: (value) async {
                                      if (value != null) {
                                        await ConfigService.set('ai_model', value);
                                        await ConfigService.set('ai_model_last_$_currentProviderKey', value);
                                        setState(() => _currentModelId = value);
                                      }
                                    },
                                  ),
                                ),
                              ]
                            ],
                          ),
                        ),
                        if (isPortrait && (_currentProviderKey == 'custom_api' || _currentProviderKey == 'google_ai_studio'))
                          Padding(
                            padding: const EdgeInsets.only(left: 12, right: 12, top: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Win11Dropdown(
                                    items: _currentModels.map((model) => Win11DropdownItem(label: model["name"] ?? "", value: model["id"])).toList(),
                                    initialValue: _currentModelId,
                                    onChanged: (value) async {
                                      if (value != null) {
                                        await ConfigService.set('ai_model', value);
                                        await ConfigService.set('ai_model_last_$_currentProviderKey', value);
                                        setState(() => _currentModelId = value);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            )
                          ),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline_rounded),
                                onPressed: _pickFiles,
                                tooltip: _tr("添加图片或文件"),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300), curve: Curves.easeInOutCubic,
                                  constraints: BoxConstraints(maxHeight: _isDocumentMode ? MediaQuery.of(context).size.height * 0.6 : 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: altColor,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _isFocused ? theme.colorScheme.onSurface : borderColor, width: _isFocused ? 1.8 : 1.0),
                                    boxShadow: _isDocumentMode ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 5)] : [],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // 图 文
                                      AnimatedSize(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeOutQuart,
                                        child: _buildAttachmentBar(),
                                      ),
                                      if (_attachments.isNotEmpty) const Divider(height: 1),
                                      // 文
                                      Flexible(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Flexible(
                                              child: Scrollbar(
                                                thumbVisibility: true, controller: _inputScrollController, radius: const Radius.circular(8),
                                                child: SingleChildScrollView(
                                                  controller: _inputScrollController,
                                                  child: Focus(
                                                    onKeyEvent: (node, event) {
                                                      if (Platform.isAndroid) return KeyEventResult.ignored;

                                                      // 你复制个集贸 (Ctrl+V)
                                                      final isV = event.logicalKey == LogicalKeyboardKey.keyV;
                                                      final isControl = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                                                                       HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);

                                                      if (isV && isControl && event is KeyDownEvent) {
                                                        _handlePaste();
                                                        return KeyEventResult.ignored;
                                                      }

                                                      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                                                        final isShift = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) || HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
                                                        if (!isShift) { _sendMessage(); return KeyEventResult.handled; }
                                                      }
                                                      return KeyEventResult.ignored;
                                                    },
                                                    child: Builder(
                                                      builder: (context) {
                                                        final agentName = Bloriko.type == "bloriko" ? _tr("络可") : _tr("Blora Agent");
                                                        String hint = _tr("向 $agentName 说些什么...");

                                                        return TextField(
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
                                                            hintText: hint,
                                                            border: InputBorder.none,
                                                            isDense: true,
                                                            contentPadding: const EdgeInsets.symmetric(vertical: 6)
                                                          ),
                                                          style: TextStyle(fontSize: 14, color: textColor)
                                                        );
                                                      }
                                                    ),
                                                  ),
                                                )
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_isDocumentMode)
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            onPressed: () => setState(() => _isDocumentMode = false),
                                            icon: const Icon(Icons.fullscreen_exit, size: 14),
                                            label: Text(_tr("退出预览"), style: const TextStyle(fontSize: 11)),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (_isDocumentMode)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: IconButton.filledTonal(
                                        icon: const Icon(Icons.edit_note_rounded),
                                        onPressed: () async {
                                          final result = await showDialog<String>(
                                            context: context,
                                            builder: (context) => _LongTextEditorDialog(initialText: _inputController.text),
                                          );
                                          if (result != null) {
                                            _inputController.text = result;
                                          }
                                        },
                                        tooltip: _tr("全屏编辑"),
                                      ),
                                    ),
                                  Tooltip(
                                    message: _currentModelId == null ? _tr("请先选择 AI 模型") : "",
                                    child: IconButton.filled(
                                      padding: const EdgeInsets.all(2),
                                      icon: Icon(_agent.busy ? Icons.stop : Icons.send, size: 20),
                                      onPressed: (_currentModelId == null && !_agent.busy) ? null : () {
                                        if (_agent.busy) {
                                          _agent.cancelAgent();
                                          return;
                                        }
                                        _sendMessage();
                                      }
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              IgnorePointer(ignoring: !_historyPanelOpen, child: AnimatedOpacity(duration: const Duration(milliseconds: 250), opacity: _historyPanelOpen ? 1.0 : 0.0, child: GestureDetector(onTap: () => setState(() => _historyPanelOpen = false), child: Container(color: Colors.black.withValues(alpha: 0.15))))),

              Positioned(
                top: 0, bottom: 0, right: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300), curve: Curves.easeInOutQuad, width: _historyPanelOpen ? 280 : 0,
                  child: ClipRect(child: OverflowBox(
                    minWidth: 280, maxWidth: 280, alignment: Alignment.centerRight,
                    child: _buildHistorySidebar(theme, borderColor, textColor, secondaryTextColor, accentColor, isPortrait),
                  )),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistorySidebar(ThemeData theme, Color borderColor, Color textColor, Color secondaryTextColor, Color accentColor, bool isPortrait) {
    return Material(elevation: 0, color: theme.cardColor, child: Container(
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
        if (isPortrait)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor.withValues(alpha: 0.1)))),
            child: Column(
              children: [
                Win11Dropdown(
                  initialValue: Bloriko.mode,
                  items: [
                    Win11DropdownItem(label: _tr("自动模式"), value: "auto"),
                    Win11DropdownItem(label: _tr("辅助点击"), value: "help"),
                    Win11DropdownItem(label: _tr("规划模式"), value: "plan"),
                  ],
                  onChanged: (value) { if (value != null) setState(() => Bloriko.setMode(value)); },
                ),
                const SizedBox(height: 8),
                Win11Dropdown(
                  initialValue: Bloriko.type,
                  items: [
                    Win11DropdownItem(label: _tr("默认"), value: "default"),
                    Win11DropdownItem(label: _tr("络可"), value: "bloriko"),
                    if (ConfigService.get("develop_mode") ?? false) Win11DropdownItem(label: _tr("络可 (R18)"), value: "bloriko_r18"),
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
                              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_tr("忽略并保持"))),
                              TextButton(onPressed: () => Navigator.pop(context, true), child: Text(_tr("开启新对话"))),
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
    ));
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
          title: Text("编辑长文本".tl),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _controller.text),
              child: Text("保存并返回".tl),
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
              hintText: "在此输入或粘贴长文本...".tl,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            style: const TextStyle(fontSize: 16, height: 1.5, fontFamily: 'Microsoft'),
          ),
        ),
      ),
    );
  }
}
