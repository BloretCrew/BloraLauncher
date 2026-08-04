import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:pasteboard/pasteboard.dart';
import '../services/live_service.dart';
import '../services/config_service.dart';
import '../core/i18n.dart';

class FullScreenVideoPage extends StatefulWidget {
  final RTCVideoRenderer? renderer;
  final String title;
  final String? spaceId;
  final List<dynamic>? initialMessages;

  const FullScreenVideoPage({
    super.key, 
    this.renderer, 
    required this.title,
    this.spaceId,
    this.initialMessages,
  });

  @override
  State<FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<FullScreenVideoPage> {
  bool _showControls = true;
  bool _showChat = false;
  Timer? _hideTimer;
  RTCVideoViewObjectFit _objectFit = RTCVideoViewObjectFit.RTCVideoViewObjectFitContain;
  bool _isLandscape = false;
  
  late List<dynamic> _messages;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _messages = List.from(widget.initialMessages ?? []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _chatController.dispose();
    _scrollController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_showChat) return; // 聊天时由于要输入，不自动隐藏
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) _startHideTimer();
    });
  }

  void _toggleOrientation() {
    setState(() {
      _isLandscape = !_isLandscape;
      SystemChrome.setPreferredOrientations(_isLandscape 
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]
      );
    });
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty || widget.spaceId == null) return;

    final msg = {
      "from": ConfigService.get("Bloret_PassPort_UserName"),
      "payload": {"msg": text},
      "time": DateTime.now().millisecondsSinceEpoch
    };

    setState(() {
      _messages.add(msg);
      _chatController.clear();
    });

    LiveService.sendSignal(widget.spaceId!, {
      "type": "chat",
      "payload": {"msg": text}
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result != null && result.files.single.bytes != null) {
      _uploadAndSendImage(result.files.single.bytes!, result.files.single.name);
    }
  }

  Future<void> _handlePaste() async {
    final image = await Pasteboard.image;
    if (image != null) {
      _uploadAndSendImage(image, "pasted_image.png");
    }
  }

  Future<void> _uploadAndSendImage(Uint8List bytes, String filename) async {
    final res = await LiveService.uploadImage(bytes, filename);
    if (res != null && res['success'] == true) {
      final url = "https://img.bloret.net${res['data']['url']}";
      final markdown = "![image]($url)";
      
      final msg = {
        "from": ConfigService.get("Bloret_PassPort_UserName"),
        "payload": {"msg": markdown},
        "time": DateTime.now().millisecondsSinceEpoch
      };

      setState(() {
        _messages.add(msg);
      });

      LiveService.sendSignal(widget.spaceId!, {
        "type": "chat",
        "payload": {"msg": markdown}
      });

      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });
    }
  }

  void _showImageDialog(BuildContext context, String imageUrl, String heroTag) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (context, _, _) => Scaffold(
          backgroundColor: Colors.black.withValues(alpha: 0.8),
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
                      child: Image.network(
                        imageUrl,
                        errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 64, color: Colors.white54),
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
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 32),
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

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Colors.black87, offset: Offset(0, 1), blurRadius: 4)];

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false, // 关键：防止键盘弹出压缩视频
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (FocusScope.of(context).hasFocus) {
            FocusScope.of(context).unfocus();
          } else {
            _toggleControls();
          }
        },
        child: Stack(
          children: [
            // Video Layer
            Center(
              child: Hero(
                tag: 'video-${widget.title}',
                child: AspectRatio(
                  aspectRatio: 16/9,
                  child: widget.renderer != null
                      ? RTCVideoView(widget.renderer!, objectFit: _objectFit)
                      : const Center(child: Icon(Icons.person, size: 64, color: Colors.white54, shadows: shadow)),
                ),
              ),
            ),

            // Chat Panel (Right Side)
            if (_showChat)
              Positioned(
                top: 0, bottom: 0, right: 0,
                width: MediaQuery.of(context).size.width * (MediaQuery.of(context).orientation == Orientation.landscape ? 0.35 : 0.7),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    border: const Border(left: BorderSide(color: Colors.white10)),
                  ),
                  child: SafeArea(
                    left: false,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              const Icon(Icons.chat_bubble_outline, color: Colors.white70, size: 18),
                              const SizedBox(width: 8),
                              Text("实时聊天".tl, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, shadows: shadow)),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                                onPressed: () => setState(() => _showChat = false),
                              )
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Colors.white10),
                        Expanded(
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(12),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) {
                              final m = _messages[i];
                              final isMe = m['from'] == ConfigService.get("Bloret_PassPort_UserName");
                              final text = m['payload']?['msg']?.toString() ?? "";
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m['from'] ?? "Unknown", style: TextStyle(color: isMe ? Colors.blueAccent : Colors.white54, fontSize: 10, shadows: shadow)),
                                    text.startsWith("![")
                                      ? InkWell(
                                          onTap: () {
                                            final regExp = RegExp(r'!\[.*?\]\((.*?)\)');
                                            final match = regExp.firstMatch(text);
                                            if (match != null) {
                                              final url = match.group(1);
                                              if (url != null) {
                                                _showImageDialog(context, url, 'fs_chat_img_${m['time'] ?? i}');
                                              }
                                            }
                                          },
                                          child: Hero(
                                            tag: 'fs_chat_img_${m['time'] ?? i}',
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(maxHeight: 150),
                                              child: GptMarkdown(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                            ),
                                          ),
                                        )
                                      : Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, shadows: shadow)),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        // Input Area inside Chat Panel
                        Container(
                          padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).viewInsets.bottom + 8),
                          color: Colors.black26,
                          child: Row(
                            children: [
                              Expanded(
                                child: Focus(
                                  onKeyEvent: (node, event) {
                                    if (event is KeyDownEvent) {
                                      if (event.logicalKey == LogicalKeyboardKey.keyV) {
                                        final isCtrl = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) || HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight) || HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.metaLeft) || HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.metaRight);
                                        if (isCtrl) { _handlePaste(); return KeyEventResult.handled; }
                                      }
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: TextField(
                                    controller: _chatController,
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: "发送消息...".tl,
                                      hintStyle: const TextStyle(color: Colors.white38),
                                      isDense: true,
                                      border: InputBorder.none,
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.image_outlined, size: 18, color: Colors.white70),
                                        onPressed: _pickImage,
                                      ),
                                    ),
                                    onSubmitted: (_) => _sendMessage(),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send, color: Colors.blueAccent, size: 20),
                                onPressed: _sendMessage,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Controls Overlay
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Container(
                  padding: EdgeInsets.only(left: 16, right: 16, top: MediaQuery.of(context).padding.top + 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28, shadows: shadow),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, shadows: shadow)),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: Colors.white, size: 28, shadows: shadow),
                            onSelected: (value) {
                              if (value == 'rotate') {
                                _toggleOrientation();
                              } else if (value == 'fit') {
                                setState(() => _objectFit = _objectFit == RTCVideoViewObjectFit.RTCVideoViewObjectFitContain ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain);
                              } else if (value == 'chat') {
                                setState(() {
                                  _showChat = !_showChat;
                                  if (_showChat) _showControls = true; // 开启聊天时保持控制条显示
                                });
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(value: 'chat', child: ListTile(leading: const Icon(Icons.chat), title: Text(_showChat ? "隐藏聊天".tl : "显示聊天".tl), dense: true)),
                              PopupMenuItem(value: 'rotate', child: ListTile(leading: const Icon(Icons.screen_rotation), title: Text(_isLandscape ? "切换竖屏".tl : "切换横屏".tl), dense: true)),
                              PopupMenuItem(value: 'fit', child: ListTile(leading: Icon(_objectFit == RTCVideoViewObjectFit.RTCVideoViewObjectFitContain ? Icons.fullscreen : Icons.fullscreen_exit), title: Text("缩放模式".tl), dense: true)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
