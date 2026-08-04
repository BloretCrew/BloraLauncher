import 'dart:async';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:pasteboard/pasteboard.dart';
import '../core/i18n.dart';
import '../services/bbbs.dart';
import '../services/live_service.dart';
import '../services/webrtc_service.dart';
import '../main.dart';
import 'fullscreen_video_page.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> with TickerProviderStateMixin {
  List<dynamic> _spaceList = [];
  bool _isLoading = true;
  bool _isAuthenticated = false;
  
  // In-Space State
  bool _inSpace = false;
  Map<String, dynamic> _currentSpace = {};
  List<dynamic> _chatMessages = [];
  List<dynamic> _onlineUsers = [];
  List<dynamic> _memberHistory = [];
  StreamSubscription? _eventSub;
  Timer? _heartbeatTimer;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  // WebRTC State
  WebRTCManager? _rtcManager;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, RTCPeerConnectionState> _peerStates = {};
  final Set<String> _mutedUsers = {};
  bool _audioEnabled = false;
  bool _videoEnabled = false;
  bool _screenEnabled = false;

  // EasyTier State
  Map<String, dynamic> _easytierState = {};
  bool _isStartingEasyTier = false;
  bool _isUploadingImage = false;

  final Map<String, Map<String, dynamic>> _userProfiles = {};

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _checkAuthAndFetch();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _heartbeatTimer?.cancel();
    _chatController.dispose();
    _chatScrollController.dispose();
    _rtcManager?.dispose();
    _localRenderer.dispose();
    _remoteRenderers.forEach((_, r) => r.dispose());
    super.dispose();
  }

  Future<void> _checkAuthAndFetch() async {
    setState(() => _isLoading = true);
    _isAuthenticated = BbbsService.isAuthenticated();
    if (_isAuthenticated) {
      _spaceList = await LiveService.fetchSpaceList();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _joinSpace(Map<String, dynamic> space, {String password = ""}) async {
    final String? spaceId = (space['id'] ?? space['spaceId'])?.toString();
    if (spaceId == null) {
      if (mounted) {
        noticeManager.show(context, message: "空间 ID 异常".tl, icon: Icons.error);
        setState(() => _isLoading = false);
      }
      return;
    }

    setState(() => _isLoading = true);
    final res = await LiveService.verifyPassword(spaceId, password);
    if (res['success'] == true) {
      if (!mounted) return;
      setState(() {
        _inSpace = true;
        _currentSpace = Map<String, dynamic>.from(space);
        if (_currentSpace['id'] == null && _currentSpace['spaceId'] != null) {
          _currentSpace['id'] = _currentSpace['spaceId'];
        }

        _chatMessages = List.from(space['chatHistory'] ?? []);
        _onlineUsers = List.from(space['users'] ?? []);
        _easytierState = space['easytier'] ?? {};
      });
      _fetchAndStoreUserProfile(ConfigService.get("Bloret_PassPort_UserName") ?? "");
      _initWebRTC(spaceId);
      _startEventListener(spaceId);
      _startHeartbeat(spaceId);
    } else {
      if (!mounted) return;
      noticeManager.show(context, message: res['message'] ?? "加入失败".tl, icon: Icons.error);
    }
    setState(() => _isLoading = false);
  }

  void _initWebRTC(String spaceId) async {
    _rtcManager = WebRTCManager(
      spaceId: spaceId,
      myUserId: ConfigService.get("Bloret_PassPort_UserName") ?? "",
      onAddRemoteStream: (userId, stream) async {
        debugPrint("DEBUG [LivePage]: !!! Adding Remote Stream for $userId");
        final renderer = RTCVideoRenderer();
        await renderer.initialize();
        renderer.srcObject = stream;

        if (_mutedUsers.contains(userId)) {
          for (var track in stream.getAudioTracks()) {
            track.enabled = false;
          }
        }

        final videoTracks = stream.getVideoTracks();
        if (videoTracks.isNotEmpty) {
          debugPrint("DEBUG: Video track enabled: ${videoTracks.first.enabled}");
          debugPrint("DEBUG: Video track muted: ${videoTracks.first.muted}");
          debugPrint("DEBUG: Video track label: ${videoTracks.first.label}");
        }
        setState(() {
          _remoteRenderers[userId] = renderer;
        });
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() {});
        });
        debugPrint("DEBUG: Renderer set. Is valid: ${renderer.textureId != null}");
      },
      onRemoveRemoteStream: (userId) {
        setState(() {
          _remoteRenderers[userId]?.dispose();
          _remoteRenderers.remove(userId);
          _peerStates.remove(userId);
        });
      },
      onConnectionStateChanged: (userId, state) {
        debugPrint("DEBUG [LivePage]: Connection State -> $state");
        setState(() => _peerStates[userId] = state);
      },
    );
    await _rtcManager!.init();
    setState(() {
      _localRenderer.srcObject = _rtcManager!.localStream;
    });
  }

  Future<void> _fetchAndStoreUserProfile(String username) async {
    if (_userProfiles.containsKey(username)) return;
    final profile = await LiveService.fetchUserProfile(username);
    if (profile != null && mounted) {
      setState(() {
        _userProfiles[username] = profile;
      });
    }
  }

  void _startEventListener(String spaceId) {
    _eventSub?.cancel();
    _eventSub = LiveService.subscribeEvents(spaceId).listen((event) {
      if (!mounted) return;
      final type = event['type'];
      
      if (type == 'ping') return; // Ignore ping events
      
      // Handle WebRTC Signaling
      if (['offer', 'answer', 'ice-candidate', 'ice'].contains(type)) {
        _rtcManager?.handleSignal(event);
        return;
      }

      setState(() {
        if (type == 'init') {
          final List<dynamic> chatHistory = event['chatHistory'] ?? [];
          final List<dynamic> memberHistory = event['memberHistory'] ?? [];
          
          final List<Map<String, dynamic>> systemEvents = [];
          for (var record in memberHistory) {
            systemEvents.add({
              "type": "user-joined",
              "user": {"username": record['username']},
              "time": record['joinTime'],
              "count": 1
            });
            if (record['leaveTime'] != null) {
              systemEvents.add({
                "type": "user-left",
                "user": {"username": record['username']},
                "time": record['leaveTime'],
                "count": 1
              });
            }
          }
          
          final combined = [...chatHistory, ...systemEvents];
          combined.sort((a, b) {
            final timeA = (a['time'] ?? 0) as int;
            final timeB = (b['time'] ?? 0) as int;
            return timeA.compareTo(timeB);
          });

          _chatMessages = combined;

          _onlineUsers = event['users'] != null 
            ? event['users'].entries.map((e) => {'username': e.key, ...e.value}).toList()
            : [];
          
          _memberHistory = List.from(memberHistory);

          for (var u in _onlineUsers) {
            if (u != null && u['username'] != null) {
              _fetchAndStoreUserProfile(u['username']);
            }
          }
          
          for (var m in _memberHistory) {
            if (m != null && m['username'] != null) {
              _fetchAndStoreUserProfile(m['username']);
            }
          }

          _easytierState = event['easytier'] ?? {};
          _scrollToBottom();
        } else if (type == 'chat') {
          setState(() {
            _chatMessages = List.from(_chatMessages)..add(event);
          });
          _scrollToBottom();
        } else if (type == 'user-joined') {
          final username = event['from'] ?? event['user']?['username'];
          if (username != null) {
            final existingIdx = _onlineUsers.indexWhere((u) => u?['username'] == username);
            final userData = {
              'username': username,
              ...(event['user'] is Map ? event['user'] : {}),
              ...(event['state'] is Map ? event['state'] : {}),
            };
            
            if (existingIdx == -1) {
              _onlineUsers.add(userData);
            } else {
              _onlineUsers[existingIdx] = {...(_onlineUsers[existingIdx] as Map), ...userData};
            }

            if (!_memberHistory.any((m) => m['username'] == username)) {
              _memberHistory.add({'username': username, 'joinTime': DateTime.now().millisecondsSinceEpoch});
            }
            
            _fetchAndStoreUserProfile(username);
            _rtcManager?.handleSignal(event);
          }
        } else if (type == 'user-left') {
          final leftUser = event['user'];
          if (leftUser != null && leftUser['username'] != null) {
            final username = leftUser['username'];
            _onlineUsers.removeWhere((u) => u != null && u['username'] == username);
            _remoteRenderers[username]?.dispose();
            _remoteRenderers.remove(username);
          }
        } else if (type == 'state') {
          final from = event['from'];
          final payload = event['payload'];
          if (from != null && payload != null) {
            final userIdx = _onlineUsers.indexWhere((u) => u != null && u['username'] == from);
            if (userIdx != -1) {
              _onlineUsers[userIdx] = <String, dynamic>{..._onlineUsers[userIdx] as Map, ...payload as Map};
            }
          }
        } else if (type == 'easytier-status') {
          _easytierState = event['payload'] ?? {};
        }
      });
    });
  }

  void _startHeartbeat(String spaceId) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_inSpace || !mounted) {
        timer.cancel();
        return;
      }
      LiveService.sendSignal(spaceId, {"target": null, "type": "ping"});
      LiveService.publishAiStats(spaceId);
    });
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        if (animate) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _chatScrollController.jumpTo(_chatScrollController.position.maxScrollExtent);
        }
      }
    });
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    final message = {
      "from": ConfigService.get("Bloret_PassPort_UserName"),
      "payload": {"msg": text},
      "time": DateTime.now().millisecondsSinceEpoch
    };
    setState(() {
      _chatMessages = List.from(_chatMessages)..add(message);
    });
    _scrollToBottom();
    
    LiveService.sendSignal(_currentSpace['id'], {
      "type": "chat",
      "payload": {"msg": text}
    });
    _chatController.clear();
    setState(() {});
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result != null && result.files.single.bytes != null) {
      _uploadAndSendImage(result.files.single.bytes!, result.files.single.name);
    }
  }

  Future<void> _handlePaste() async {
    if (_isUploadingImage) return;
    final image = await Pasteboard.image;
    if (image != null) {
      _uploadAndSendImage(image, "pasted_image.png");
    }
  }

  Future<void> _uploadAndSendImage(Uint8List bytes, String filename) async {
    setState(() => _isUploadingImage = true);
    try {
      final res = await LiveService.uploadImage(bytes, filename);
      if (res != null && res['success'] == true) {
        final url = "https://img.bloret.net${res['data']['url']}";
        final markdown = "![image]($url)";

        final message = {
          "from": ConfigService.get("Bloret_PassPort_UserName"),
          "payload": {"msg": markdown},
          "time": DateTime.now().millisecondsSinceEpoch
        };

        setState(() {
          _chatMessages = List.from(_chatMessages)..add(message);
        });
        _scrollToBottom();

        LiveService.sendSignal(_currentSpace['id'], {
          "type": "chat",
          "payload": {"msg": markdown}
        });
      } else {
        if (mounted) noticeManager.show(context, message: "图片上传失败".tl, icon: Icons.error);
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  void _sendState() {
    LiveService.sendSignal(_currentSpace['id'], {
      "type": "state",
      "payload": {
        "audio": _audioEnabled, 
        "video": _videoEnabled,
        "screen": _screenEnabled
      }
    });
    _chatController.clear();
  }

  Widget _buildChatAvatar(String username, {double radius = 16}) {
    final avatarUrl = _userProfiles[username]?['avatar'];
    return GestureDetector(
      onTap: () => _showUserProfileDialog(username),
      child: Hero(
        tag: 'avatar-$username',
        child: CircleAvatar(
          radius: radius,
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
          child: avatarUrl == null ? Text(username[0].toUpperCase(), style: TextStyle(fontSize: radius * 0.75)) : null,
        ),
      ),
    );
  }

  void _showUserProfileDialog(String username) {
    final profile = _userProfiles[username];
    showDialog(
      context: context,
      builder: (context) => Center(
        child: Hero(
          tag: 'avatar-$username',
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: profile?['avatar'] != null ? NetworkImage(profile!['avatar']) : null,
                    child: profile?['avatar'] == null ? Text(username[0].toUpperCase(), style: const TextStyle(fontSize: 40)) : null,
                  ),
                  const SizedBox(height: 16),
                  Text(username, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  if (profile?['title'] != null) ...[
                    const SizedBox(height: 4),
                    _buildBadge(profile!['title'], Colors.blue),
                  ],
                  const SizedBox(height: 12),
                  Text(profile?['bio']?.toString().isNotEmpty == true ? profile!['bio'] : "这个用户很懒，什么都没写".tl,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildProfileStat("帖子".tl, profile?['postCount'] ?? 0),
                      _buildProfileStat("获赞".tl, profile?['receivedLikes'] ?? 0),
                      _buildProfileStat("浏览".tl, profile?['totalViews'] ?? 0),
                    ],
                  ),
                  const SizedBox(height: 20),
                  BloretButton(
                    text: "确定".tl,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileStat(String label, dynamic count) {
    return Column(
      children: [
        Text(count.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
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

  void _showCreateSpaceDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("创建 Live 空间".tl),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: "空间名称".tl),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("取消".tl)),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context);
                setState(() => _isLoading = true);
                final res = await LiveService.createSpace(name);
                if (res != null && res['success'] != false) {
                  _joinSpace(res);
                } else {
                  setState(() => _isLoading = false);
                  if (!context.mounted) return;
                  noticeManager.show(context, message: res?['message'] ?? "创建失败".tl, icon: Icons.error);
                }
              }
            },
            child: Text("创建".tl),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final secondaryColor = theme.colorScheme.onSurfaceVariant;
    final cardColor = theme.cardColor;
    final borderColor = theme.dividerColor.withValues(alpha: 0.1);

    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            CustomScrollView(
            slivers: [
              _buildHeader(textColor, secondaryColor),
              if (!_isAuthenticated) _buildLoginWarning(cardColor, borderColor, textColor, secondaryColor),
              if (_isAuthenticated && !_inSpace) _buildSpaceList(cardColor, borderColor, textColor, secondaryColor),
              if (_isAuthenticated && _inSpace) ...[
                _buildVideoGrid(),
                _buildSpaceDetail(cardColor, borderColor, textColor, secondaryColor),
              ],
            ],
          ),
          if (_isLoading)
            const Positioned.fill(
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    ));
  }

  Widget _buildVideoGrid() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 16 / 9,
        ),
        delegate: SliverChildListDelegate([
          _buildVideoCard(
            ConfigService.get("Bloret_PassPort_UserName") ?? "我".tl, 
            _localRenderer, 
            isLocal: true
          ),

          ..._onlineUsers.where((u) {
            final username = u?['username'];
            return u != null && username != ConfigService.get("Bloret_PassPort_UserName");
          }).map((u) {
            final username = u['username'] ?? "未知";
            return _buildVideoCard(username, _remoteRenderers[username]);
          }),
        ]),
      ),
    );
  }

  Widget _buildVideoCard(String name, RTCVideoRenderer? renderer, {bool isLocal = false}) {

    final userInfo = isLocal 
      ? {'audio': _audioEnabled, 'video': _videoEnabled, 'screen': _screenEnabled}
      : (_onlineUsers.firstWhere((u) => u != null && u['username'] == name, orElse: () => {}));

    final audio = userInfo['audio'] == true;
    final video = userInfo['video'] == true;
    final screen = userInfo['screen'] == true;
    final isMuted = _mutedUsers.contains(name);

    final bool showStream = (renderer?.srcObject != null) && (video || screen);
    const shadows = [Shadow(color: Colors.black45, offset: Offset(0, 1), blurRadius: 4)];

    return TweenAnimationBuilder<double>(
      key: ValueKey('video-anim-$name'),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Align(
            heightFactor: value,
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
      child: InkWell(
        onTap: () {
          // 移除焦点，防止返回时自动聚焦
          FocusScope.of(context).unfocus();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => FullScreenVideoPage(
              renderer: renderer,
              title: name,
              spaceId: _currentSpace['id']?.toString(),
              initialMessages: List.from(_chatMessages),
            ),
          ));
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Hero(
                tag: 'avatar-$name',
                child: showStream
                    ? RTCVideoView(
                  renderer!,
                  mirror: isLocal && _videoEnabled && !_screenEnabled,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
                    : GestureDetector(
                        onTap: () => _showUserProfileDialog(name),
                        child: Center(
                          child: _userProfiles[name]?['avatar'] != null 
                            ? CircleAvatar(
                                radius: 40,
                                backgroundImage: NetworkImage(_userProfiles[name]!['avatar']),
                                backgroundColor: Colors.white10,
                              )
                            : Icon(Icons.person, size: 48, color: Colors.white54, shadows: shadows),
                        ),
                      ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: !isLocal ? IconButton(
                  icon: Icon(
                    isMuted ? Icons.volume_off : Icons.volume_up,
                    color: isMuted ? Colors.red : Colors.white70,
                    size: 20,
                    shadows: shadows,
                  ),
                  onPressed: () {
                    setState(() {
                      if (isMuted) {
                        _mutedUsers.remove(name);
                      } else {
                        _mutedUsers.add(name);
                      }

                      final r = _remoteRenderers[name];
                      if (r?.srcObject != null) {
                        for (var track in r!.srcObject!.getAudioTracks()) {
                          track.enabled = isMuted;
                        }
                      }
                    });
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                  ),
                ) : const SizedBox.shrink(),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                      child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 10, shadows: shadows)),
                    ),
                    const Spacer(),
                    if (audio) Icon(isMuted ? Icons.mic_off : Icons.mic, color: isMuted ? Colors.red : Colors.white, size: 12, shadows: shadows),
                    if (video) Icon(Icons.videocam, color: Colors.white, size: 12, shadows: shadows),
                    if (screen) Icon(Icons.screen_share, color: Colors.white, size: 12, shadows: shadows),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color textColor, Color secondaryColor) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final displayTitle = _inSpace ? (_currentSpace['name'] ?? "Live") : "Live";

    return SliverPadding(
      padding: const EdgeInsets.all(24),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            if (isPortrait)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayTitle, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Row(
                      children: [
                        Text(_inSpace ? "正在通话".tl : "实时空间".tl, style: TextStyle(fontSize: 14, color: secondaryColor)),
                        const SizedBox(width: 8),
                        _buildBadge("Bloret BBS", Colors.green),
                      ],
                    ),
                  ],
                ),
              )
            else ...[
              Text(displayTitle, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(width: 10),
              Text(_inSpace ? "正在通话".tl : "实时空间".tl, style: TextStyle(fontSize: 14, color: secondaryColor)),
              const SizedBox(width: 10),
              _buildBadge("Bloret BBS", Colors.green),
              const Spacer(),
            ],
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildHeaderActions(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderActions() {
    if (!_isAuthenticated) return const SizedBox.shrink(key: ValueKey("none"));
    const shadows = [Shadow(color: Colors.black12, offset: Offset(0, 1), blurRadius: 4)];

    if (_inSpace) {
      return Row(
        key: const ValueKey("in_space"),
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            icon: Icon(Icons.settings_input_component, shadows: shadows),
            tooltip: "媒体控制".tl,
            offset: const Offset(0, 40),
            onSelected: (value) async {
              if (value == 'audio') {
                setState(() {
                  _audioEnabled = !_audioEnabled;
                  _rtcManager?.toggleAudio(_audioEnabled);
                  _sendState();
                });
              } else if (value == 'video') {
                setState(() {
                  _videoEnabled = !_videoEnabled;
                  if (_videoEnabled) _screenEnabled = false;
                });
                if (_videoEnabled) await _rtcManager?.toggleScreen(false);
                _rtcManager?.toggleVideo(_videoEnabled);
                setState(() => _localRenderer.srcObject = _rtcManager?.localStream);
                _sendState();
              } else if (value == 'screen') {
                setState(() {
                  _screenEnabled = !_screenEnabled;
                  if (_screenEnabled) _videoEnabled = false;
                });
                if (_screenEnabled) _rtcManager?.toggleVideo(false);
                await _rtcManager?.toggleScreen(_screenEnabled);
                if (mounted) {
                  setState(() {
                    _screenEnabled = _rtcManager?.localScreenStream != null;
                    _localRenderer.srcObject = _screenEnabled ? _rtcManager?.localScreenStream : _rtcManager?.localStream;
                  });
                }
                _sendState();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'audio',
                child: ListTile(
                  leading: Icon(_audioEnabled ? Icons.mic : Icons.mic_off, color: _audioEnabled ? Colors.green : null),
                  title: Text("麦克风".tl),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'video',
                child: ListTile(
                  leading: Icon(_videoEnabled ? Icons.videocam : Icons.videocam_off, color: _videoEnabled ? Colors.green : null),
                  title: Text("摄像头".tl),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'screen',
                child: ListTile(
                  leading: Icon(_screenEnabled ? Icons.desktop_windows : Icons.desktop_access_disabled, color: _screenEnabled ? Colors.green : null),
                  title: Text("屏幕共享".tl),
                  dense: true,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            icon: const Icon(Icons.exit_to_app, shadows: shadows),
            label: Text("离开".tl),
            onPressed: () async {
              LiveService.sendSignal(_currentSpace['id'], {
                "type": "leave",
                "payload": {}
              });

              _eventSub?.cancel();
              _eventSub = null;
              _heartbeatTimer?.cancel();
              _heartbeatTimer = null;
              _rtcManager?.dispose();
              _rtcManager = null;
              _localRenderer.srcObject = null;

              setState(() {
                _inSpace = false;
                _currentSpace = {};
                _chatMessages = [];
                _onlineUsers = [];
                _easytierState = {};
                _remoteRenderers.forEach((_, r) => r.dispose());
                _remoteRenderers.clear();
                _peerStates.clear();
              });
            },
          )
        ],
      );
    } else {
      return Row(
        key: const ValueKey("list"),
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.refresh, shadows: shadows), onPressed: _checkAuthAndFetch),
          if (_spaceList.isNotEmpty) ...[
            const SizedBox(width: 8),
            BloretButton(
              icon: Icons.add,
              text: "创建空间".tl,
              onPressed: _showCreateSpaceDialog,
              height: 42,
            ),
          ]
        ],
      );
    }
  }


  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLoginWarning(Color cardColor, Color borderColor, Color textColor, Color secondaryColor) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
        child: Column(
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 12),
            Text("请先登录 Bloret PassPort".tl, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 8),
            Text("登录后即可加入 Live 空间，进行实时聊天和联机。".tl, textAlign: TextAlign.center, style: TextStyle(color: secondaryColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildSpaceList(Color cardColor, Color borderColor, Color textColor, Color secondaryColor) {
    if (_spaceList.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sensors_off, size: 48, color: secondaryColor.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text("暂无活跃的 Live 空间".tl, style: TextStyle(color: secondaryColor)),
              const SizedBox(height: 24),
              BloretButton(
                onPressed: _showCreateSpaceDialog,
                icon: Icons.add,
                text: "创建一个新空间".tl,
                height: 42,
              ),
            ],
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final space = _spaceList[index];
          final spaceId = (space['id'] ?? space['spaceId'])?.toString() ?? index.toString();
          
          return TweenAnimationBuilder<double>(
            key: ValueKey('space-item-$spaceId'),
            duration: Duration(milliseconds: 400 + (index * 100).clamp(0, 600)),
            curve: Curves.easeOutQuart,
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 30 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: borderColor)),
              child: ListTile(
                leading: CircleAvatar(child: Text(space['name']?[0]?.toUpperCase() ?? "L")),
                title: Text(space['name'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("${"在线: ".tl} ${space['userCount'] ?? 0}"),
                trailing: BloretButton(
                  onPressed: () => _showJoinDialog(space),
                  text: "加入".tl,
                ),
              ),
            ),
          );
        }, childCount: _spaceList.length),
      ),
    );
  }

  void _showJoinDialog(Map<String, dynamic> space) {
    if (space['hasPassword'] == true) {
      final ctrl = TextEditingController();
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("需要密码".tl),
          content: TextField(controller: ctrl, decoration: InputDecoration(hintText: "请输入密码".tl), obscureText: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text("取消".tl)),
            TextButton(onPressed: () {
              Navigator.pop(context);
              _joinSpace(space, password: ctrl.text);
            }, child: Text("加入".tl)),
          ],
        ),
      );
    } else {
      _joinSpace(space);
    }
  }

  Widget _buildSpaceDetail(Color cardColor, Color borderColor, Color textColor, Color secondaryColor) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          _buildEasyTierCard(cardColor, borderColor, textColor, secondaryColor),
          const SizedBox(height: 16),
          _buildOnlineUsersCard(cardColor, borderColor, secondaryColor),
          const SizedBox(height: 16),
          _buildPastUsersCard(cardColor, borderColor, secondaryColor),
          const SizedBox(height: 16),
          _buildChatCard(cardColor, borderColor, textColor, secondaryColor),
        ]),
      ),
    );
  }

  Widget _buildEasyTierCard(Color cardColor, Color borderColor, Color textColor, Color secondaryColor) {
    final active = _easytierState['active'] == true;
    final ready = _easytierState['ready'] == true;
    final isOwner = _currentSpace['isOwner'] == true;
    final hostIp = _easytierState['hostVirtualIp'] ?? "";
    final gamePort = _easytierState['gamePort']?.toString() ?? "25565";

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.network_check, size: 20),
              const SizedBox(width: 8),
              const Text("EasyTier 联机网", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              _buildBadge(active ? (ready ? "就绪".tl : "启动中".tl) : "未启用".tl, active ? Colors.green : Colors.grey),
            ],
          ),
          const SizedBox(height: 12),

          if (!active) 
            Text(
              isOwner 
                ? "1. 点击开始网络\n2. 启动 Minecraft 开放局域网\n3. 端口会自动同步给成员".tl 
                : "房主尚未开启 EasyTier 网络，请等待房主启动。".tl,
              style: TextStyle(fontSize: 12, color: secondaryColor, height: 1.5),
            )
          else ...[
            Text(ready ? "网络已就绪，成员可以直接连接".tl : "正在等待房主在游戏内开放局域网...".tl, 
              style: TextStyle(fontSize: 13, color: ready ? Colors.green : secondaryColor)),
            if (ready && !isOwner) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    Text("房主地址: ".tl, style: TextStyle(fontSize: 12, color: secondaryColor)),
                    Text("$hostIp:$gamePort", style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  ],
                ),
              ),
            ],
          ],

          if (isOwner) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _isStartingEasyTier ? null : () async {
                    setState(() => _isStartingEasyTier = true);
                    await LiveService.startEasyTier(_currentSpace['id']);
                    setState(() => _isStartingEasyTier = false);
                  },
                  child: Text(active ? "重新启动".tl : "开始网络".tl),
                ),
                if (active) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: "手动端口".tl,
                        hintText: "25565",
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onSubmitted: (val) {
                        final port = int.tryParse(val);
                        if (port != null) {
                          LiveService.publishEndpoint(_currentSpace['id'], hostIp, port);
                        }
                      },
                    ),
                  ),
                ]
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildOnlineUsersCard(Color cardColor, Color borderColor, Color secondaryColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
      child: Row(
        children: [
          Text("${"在线".tl}: ", style: TextStyle(color: secondaryColor, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _onlineUsers.map((u) {
                  final username = u?['username'] ?? "";
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _buildChatAvatar(username, radius: 14),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPastUsersCard(Color cardColor, Color borderColor, Color secondaryColor) {
    final onlineNames = _onlineUsers.map((u) => u?['username']).toSet();
    final pastUsers = _memberHistory.where((m) => !onlineNames.contains(m['username'])).toList();
    
    if (pastUsers.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
      child: Row(
        children: [
          Text("${"往期".tl}: ", style: TextStyle(color: secondaryColor, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: pastUsers.map((u) {
                  final username = u?['username'] ?? "";
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Opacity(
                      opacity: 0.5,
                      child: _buildChatAvatar(username, radius: 14),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatCard(Color cardColor, Color borderColor, Color textColor, Color secondaryColor) {
    return Container(
      height: 400,
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _chatScrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _chatMessages.length,
              itemBuilder: (context, index) {
                final dynamic msg = _chatMessages[index];
                if (msg is! Map) return const SizedBox.shrink();

                final isJoinRecord = (msg['type'] == 'user-joined' || msg['type'] == 'user-left');

                Widget item;
                if (isJoinRecord) {
                  final username = msg['user']?['username'] ?? msg['from'];
                  if (index > 0) {
                    if (msg['type'] == 'user-left') {
                      final username = msg['user']?['username'] ?? msg['from'];

                      if (index + 1 < _chatMessages.length) {
                        final dynamic next = _chatMessages[index + 1];

                        if (next is Map && next['type'] == 'user-joined' &&
                            next['user']?['username'] == username) {
                          return const SizedBox.shrink();
                        }
                      }
                    }
                    final dynamic prev = _chatMessages[index - 1];
                    if (prev is Map && prev['type'] == 'user-left' && msg['type'] == 'user-joined' && prev['user']?['username'] == username) {
                      int reEntryCount = 1;
                      for (int i = index + 1; i < _chatMessages.length - 1; i++) {
                         final m1 = _chatMessages[i];
                         final m2 = _chatMessages[i+1];
                         if (m1 is Map && m2 is Map && 
                             m1['type'] == 'user-left' && m2['type'] == 'user-joined' &&
                             m1['user']?['username'] == username) {
                           reEntryCount++;
                           i++;
                         } else {
                           break;
                         }
                      }
                      item = Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          "$username ${"重进了空间".tl} ${reEntryCount > 1 ? ' x$reEntryCount' : ''}",
                          style: TextStyle(fontSize: 10, color: secondaryColor, fontStyle: FontStyle.italic),
                          textAlign: TextAlign.center,
                        ),
                      );
                    } else {
                      int count = 1;
                      if (index > 0) {
                        final prevMsg = _chatMessages[index-1];
                        if (prevMsg is Map && prevMsg['type'] == msg['type'] && prevMsg['user']?['username'] == username) {
                          return const SizedBox.shrink();
                        }
                      }
                      for (int i = index + 1; i < _chatMessages.length; i++) {
                        final nextMsg = _chatMessages[i];
                        if (nextMsg is Map && nextMsg['type'] == msg['type'] && nextMsg['user']?['username'] == username) {
                          count++;
                        } else {
                          break;
                        }
                      }

                      item = Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          "$username ${msg['type'] == 'user-joined' ? '加入了空间'.tl : '离开了空间'.tl} ${count > 1 ? ' x$count' : ''}",
                          style: TextStyle(fontSize: 10, color: secondaryColor, fontStyle: FontStyle.italic),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                  } else {
                    item = Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        "$username ${msg['type'] == 'user-joined' ? '加入了空间'.tl : '离开了空间'.tl}",
                        style: TextStyle(fontSize: 10, color: secondaryColor, fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                } else {
                  final sender = msg['from'] ?? msg['user'] ?? "?";
                  
                  // 安全解析消息内容：payload 可能是 Map 或是 String
                  String text = "";
                  final dynamic payload = msg['payload'];
                  if (payload is Map) {
                    text = payload['msg']?.toString() ?? payload['message']?.toString() ?? "";
                  } else if (payload is String) {
                    text = payload;
                  } else {
                    text = msg['msg']?.toString() ?? msg['message']?.toString() ?? "";
                  }

                  final isMe = sender == ConfigService.get("Bloret_PassPort_UserName");

                  item = Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe) ...[
                            _buildChatAvatar(sender),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Text(sender, style: TextStyle(fontSize: 10, color: secondaryColor)),
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isMe ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : cardColor,
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(isMe ? 12 : 0),
                                      topRight: Radius.circular(isMe ? 0 : 12),
                                      bottomLeft: const Radius.circular(12),
                                      bottomRight: const Radius.circular(12),
                                    ),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: text.startsWith("![") 
                                    ? InkWell(
                                        onTap: () {
                                          final regExp = RegExp(r'!\[.*?\]\((.*?)\)');
                                          final match = regExp.firstMatch(text);
                                          if (match != null) {
                                            final url = match.group(1);
                                            if (url != null) {
                                              _showImageDialog(context, url, 'chat_img_${msg['time'] ?? index}');
                                            }
                                          }
                                        },
                                        child: Hero(
                                          tag: 'chat_img_${msg['time'] ?? index}',
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 300, maxHeight: 200),
                                            child: GptMarkdown(text),
                                          ),
                                        ),
                                      )
                                    : Text(text, style: TextStyle(fontSize: 14, color: textColor)),
                                ),
                              ],
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 8),
                            _buildChatAvatar(sender),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return TweenAnimationBuilder<double>(
                  key: ValueKey(msg['time'] ?? index),
                  duration: const Duration(milliseconds: 400),
                  tween: Tween(begin: 0.0, end: 1.0),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: item,
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _chatController.text.isNotEmpty ? Theme.of(context).colorScheme.primary : borderColor,
                        width: _chatController.text.isNotEmpty ? 1.5 : 1.0,
                      ),
                    ),
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent) {
                          if (event.logicalKey == LogicalKeyboardKey.enter) {
                            final isShift = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) || HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
                            if (!isShift) { _sendMessage(); return KeyEventResult.handled; }
                          } else if (event.logicalKey == LogicalKeyboardKey.keyV) {
                            final isCtrl = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) || HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight) || HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.metaLeft) || HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.metaRight);
                            if (isCtrl) {
                              _handlePaste();
                              // return ignored to allow normal text paste if it's text
                              return KeyEventResult.ignored;
                            }
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _chatController,
                        enabled: !_isUploadingImage,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText: _isUploadingImage ? "正在上传图片...".tl : "输入消息...".tl,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.image_outlined, size: 20),
                            onPressed: _isUploadingImage ? null : _pickImage,
                            tooltip: "发送图片".tl,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _isUploadingImage ? null : _sendMessage(),
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(fontSize: 14, color: textColor),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  padding: const EdgeInsets.all(12),
                  icon: _isUploadingImage 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, size: 20, shadows: [Shadow(color: Colors.black26, offset: Offset(0, 1), blurRadius: 4)]),
                  onPressed: _isUploadingImage ? null : _sendMessage,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
