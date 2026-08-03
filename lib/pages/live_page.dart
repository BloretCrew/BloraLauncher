import 'dart:async';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
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
  StreamSubscription? _eventSub;
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
      _initWebRTC(spaceId);
      _startEventListener(spaceId);
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

  void _startEventListener(String spaceId) {
    _eventSub?.cancel();
    _eventSub = LiveService.subscribeEvents(spaceId).listen((event) {
      if (!mounted) return;
      final type = event['type'];
      
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
          _easytierState = event['easytier'] ?? {};
          _scrollToBottom();
        } else if (type == 'chat') {
          setState(() {
            _chatMessages = List.from(_chatMessages)..add(event);
          });
          _scrollToBottom();
        } else if (type == 'user-joined') {
          if (event['user'] != null) {
            _onlineUsers.add(event['user']);
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
      body: Stack(
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
    );
  }

  Widget _buildVideoGrid() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 4 / 3,
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
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => FullScreenVideoPage(
              renderer: renderer,
              title: name,
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
                tag: 'video-$name',
                child: showStream
                    ? RTCVideoView(
                  renderer!,
                  mirror: isLocal && _videoEnabled && !_screenEnabled,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
                    : const Center(
                  child: Icon(Icons.person, size: 48, color: Colors.white54),
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
                      child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                    const Spacer(),
                    if (audio) Icon(isMuted ? Icons.mic_off : Icons.mic, color: isMuted ? Colors.red : Colors.white, size: 12),
                    if (video) const Icon(Icons.videocam, color: Colors.white, size: 12),
                    if (screen) const Icon(Icons.screen_share, color: Colors.white, size: 12),
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
    return SliverPadding(
      padding: const EdgeInsets.all(24),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            Text("Live", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(width: 10),
            Text("实时空间".tl, style: TextStyle(fontSize: 14, color: secondaryColor)),
            const SizedBox(width: 10),
            _buildBadge("Bloret BBS", Colors.green),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                    child: child,
                  ),
                );
              },
              child: _buildHeaderActions(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderActions() {
    if (!_isAuthenticated) return const SizedBox.shrink(key: ValueKey("none"));

    if (_inSpace) {
      return Row(
        key: const ValueKey("in_space"),
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(_audioEnabled ? Icons.mic : Icons.mic_off),
            onPressed: () {
              setState(() {
                _audioEnabled = !_audioEnabled;
                _rtcManager?.toggleAudio(_audioEnabled);
                _sendState();
              });
            },
          ),
          IconButton(
            icon: Icon(_videoEnabled ? Icons.videocam : Icons.videocam_off),
            color: _videoEnabled ? Colors.green : null,
            onPressed: () async {
              setState(() {
                _videoEnabled = !_videoEnabled;
                if (_videoEnabled) _screenEnabled = false;
              });
              
              if (_videoEnabled) {
                await _rtcManager?.toggleScreen(false);
              }
              _rtcManager?.toggleVideo(_videoEnabled);

              setState(() {
                _localRenderer.srcObject = _rtcManager?.localStream;
              });
              
              _sendState();
            },
          ),
          IconButton(
            icon: Icon(_screenEnabled ? Icons.desktop_windows : Icons.desktop_access_disabled),
            color: _screenEnabled ? Colors.green : null,
            onPressed: () async {
              setState(() {
                _screenEnabled = !_screenEnabled;
                if (_screenEnabled) _videoEnabled = false;
              });

              if (_screenEnabled) {
                _rtcManager?.toggleVideo(false);
              }
              await _rtcManager?.toggleScreen(_screenEnabled);

              if (mounted) {
                setState(() {
                  _screenEnabled = _rtcManager?.localScreenStream != null;
                  _localRenderer.srcObject = _screenEnabled 
                      ? _rtcManager?.localScreenStream 
                      : _rtcManager?.localStream;
                });
              }
              _sendState();
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.exit_to_app),
            label: Text("离开".tl),
            onPressed: () async {
              LiveService.sendSignal(_currentSpace['id'], {
                "type": "leave",
                "payload": {}
              });

              _eventSub?.cancel();
              _eventSub = null;
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: _checkAuthAndFetch),
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
          Text("${"在线: ".tl} ", style: TextStyle(color: secondaryColor, fontSize: 12)),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _onlineUsers.map((u) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(label: Text(u?['username'] ?? "", style: const TextStyle(fontSize: 11)), padding: EdgeInsets.zero),
                )).toList(),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                          final isShift = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) || HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
                          if (!isShift) { _sendMessage(); return KeyEventResult.handled; }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _chatController,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          hintText: "输入消息...".tl,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _sendMessage(),
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(fontSize: 14, color: textColor),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  padding: const EdgeInsets.all(12),
                  icon: const Icon(Icons.send, size: 20),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
