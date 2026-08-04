import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'live_service.dart';

class WebRTCManager {
  final String spaceId;
  final String myUserId;
  final Function(String userId, MediaStream stream) onAddRemoteStream;
  final Function(String userId) onRemoveRemoteStream;
  final Function(String userId, RTCPeerConnectionState state) onConnectionStateChanged;

  MediaStream? localStream;
  MediaStream? localScreenStream;
  Map<String, RTCPeerConnection> peers = {};
  Map<String,List<RTCIceCandidate>> pendingCandidates = {};
  final Completer<void> _initCompleter = Completer<void>();

  final Set<String> _processedSignalHashes = {};
  final Set<String> _sentSignalHashes = {};

  bool _videoEnabled = false;
  bool _screenEnabled = false;

  WebRTCManager({
    required this.spaceId,
    required this.myUserId,
    required this.onAddRemoteStream,
    required this.onRemoveRemoteStream,
    required this.onConnectionStateChanged,
  });

  Future<void> init() async {
    final constraints = {
      'audio': true,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 640},
        'height': {'ideal': 480},
      }
    };

    try {
      localStream =
      await navigator.mediaDevices.getUserMedia(constraints);

      for (var track in localStream!.getAudioTracks()) {
        track.enabled = false;
      }

      for (var track in localStream!.getVideoTracks()) {
        track.enabled = false;
      }

      debugPrint("[WebRTC] Camera initialized");

    } catch (e) {
      debugPrint("[WebRTC] getUserMedia error: $e");
    } finally {
      if (!_initCompleter.isCompleted) _initCompleter.complete();
    }
  }

  void toggleAudio(bool enabled) {
    localStream?.getAudioTracks().forEach((track) => track.enabled = enabled);
  }

  void toggleVideo(bool enabled) {
    _videoEnabled = enabled;
    final cameraTrack = localStream?.getVideoTracks().firstOrNull;
    if (cameraTrack != null) {
      cameraTrack.enabled = enabled;
    }

    if (!_screenEnabled) {
      _updateAllPeersVideoTrack(cameraTrack);
    }
  }

  Future<void> toggleScreen(bool enabled) async {
    if (!enabled) {
      await stopScreenShare();
      return;
    }

    try {
      try {
        final sources = await desktopCapturer.getSources(
          types: [SourceType.Screen, SourceType.Window],
        );
        debugPrint("[WebRTC] Capture sources: ${sources.length}");
      } catch (e) {
        debugPrint("[WebRTC] enumerate source failed: $e");
      }

      localScreenStream = await navigator.mediaDevices.getDisplayMedia({
        "video": {
          "cursor": "always",
          "width": {"ideal": 1920},
          "height": {"ideal": 1080},
          "frameRate": {"ideal": 30}
        },
        "audio": false,
      });

      if (localScreenStream == null || localScreenStream!.getVideoTracks().isEmpty) {
        throw Exception("No screen video track");
      }

      final track = localScreenStream!.getVideoTracks().first;
      track.enabled = true;
      _screenEnabled = true;

      track.onEnded = () {
        debugPrint("[WebRTC] Screen ended by system");
        stopScreenShare();
      };

      await _updateAllPeersVideoTrack(track);
      await _triggerRenegotiation(forceIceRestart: true);
      debugPrint("[WebRTC] Screen sharing started: ${track.label}");

    } catch (e) {
      debugPrint("[WebRTC] Screen capture failed: $e");
      _screenEnabled = false;
      await stopScreenShare();
    }
  }

  Future<void> stopScreenShare() async {
    _screenEnabled = false;

    MediaStreamTrack? fallbackTrack;
    if (localStream != null && localStream!.getVideoTracks().isNotEmpty) {
      fallbackTrack = localStream!.getVideoTracks().first;
      fallbackTrack.enabled = _videoEnabled; 
    }

    await _updateAllPeersVideoTrack(fallbackTrack);

    if (localScreenStream != null) {
      for (final track in localScreenStream!.getTracks()) {
        try {
          track.onEnded = null;
          await track.stop();
        } catch (_) {}
      }
      await localScreenStream!.dispose();
      localScreenStream = null;
    }

    debugPrint("[WebRTC] Screen sharing stopped, fallback to ${_videoEnabled ? 'Camera' : 'Black Screen'}");
  }

  Future<void> _sendSignal(String target, String type, Map<String, dynamic> payload) async {
    final String fingerprint = "$target-$type-${jsonEncode(payload).hashCode}";
    
    if (_sentSignalHashes.contains(fingerprint)) {
      debugPrint("[WebRTC] Sent duplicate signal prevented: $type to $target");
      return;
    }
    _sentSignalHashes.add(fingerprint);
    if (_sentSignalHashes.length > 100) _sentSignalHashes.remove(_sentSignalHashes.first);

    await LiveService.sendSignal(spaceId, {
      "target": target,
      "type": type,
      "payload": payload
    });
  }

  Future<void> _triggerRenegotiation({bool forceIceRestart = false}) async {
    for (final userId in peers.keys) {
      final pc = peers[userId];
      if (pc != null) {
        try {
          final offer = await pc.createOffer({
            'offerToReceiveVideo': 1,
            'offerToReceiveAudio': 1,
            'iceRestart': forceIceRestart
          });
          await pc.setLocalDescription(offer);
          await _sendSignal(userId, "offer", {"sdp": offer.sdp, "type": "offer"});
          debugPrint("[WebRTC] Renegotiation offer sent to $userId (iceRestart: $forceIceRestart)");
        } catch (e) {
          debugPrint("[WebRTC] Renegotiation error for $userId: $e");
        }
      }
    }
  }

  Future<void> _updateAllPeersVideoTrack(MediaStreamTrack? track) async {
    for (final pc in peers.values) {
      try {
        final senders = await pc.getSenders();
        RTCRtpSender? videoSender;

        for (final s in senders) {
          if (s.track?.kind == "video") {
            videoSender = s;
            break;
          }
        }

        if (videoSender != null) {
          debugPrint("[WebRTC] replaceTrack -> ${track?.label ?? 'NULL (Black Screen)'}");
          await videoSender.replaceTrack(track);
        }
      } catch (e) {
        debugPrint("[WebRTC] update video error: $e");
      }
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(String userId) async {
    await _initCompleter.future;

    final Map<String, dynamic> config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 10,
    };

    final pc = await createPeerConnection(config);

    pc.onIceCandidate = (candidate) {
      debugPrint("[WebRTC] Sending ICE candidate to $userId");
      _sendSignal(userId, "ice", {
        "type": "ice",
        "candidate": candidate.candidate,
        "sdpMid": candidate.sdpMid,
        "sdpMLineIndex": candidate.sdpMLineIndex,
      });
    };

    pc.onTrack = (event) {
      debugPrint("[WebRTC] onTrack triggered! Kind: ${event.track.kind}");
      if (event.streams.isNotEmpty) {
        debugPrint("[WebRTC] Stream ID: ${event.streams[0].id}");
        onAddRemoteStream(userId, event.streams[0]);
      } else {
        debugPrint("[WebRTC] ERROR: No stream found in track event");
      }
    };

    pc.onConnectionState = (state) {
      debugPrint("[WebRTC] Connection state changed for $userId: $state");
      onConnectionStateChanged(userId, state);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _removePeer(userId);
      }
    };

    pc.onIceConnectionState = (state) {
      debugPrint("[WebRTC] ICE connection state changed for $userId: $state");
    };

    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        MediaStreamTrack initialTrack = track;
        if (track.kind == 'video' && _screenEnabled && localScreenStream != null) {
          initialTrack = localScreenStream!.getVideoTracks().firstOrNull ?? track;
        }
        
        await pc.addTrack(initialTrack, localStream!);
      }
    }

    return pc;
  }

  void _removePeer(String userId) {
    peers[userId]?.dispose();
    peers.remove(userId);
    onRemoveRemoteStream(userId);
  }

  Future<void> handleSignal(Map<String, dynamic> event) async {
    final String type = event['type'] ?? "";
    final String from = event['from'] ?? event['user'] ?? '';
    final dynamic payload = event['payload'] ?? {};

    if (from.isEmpty || type.isEmpty) return;

    if (from == myUserId) return;

    final String signalFingerprint = "$from-$type-${payload.toString().hashCode}";
    if (_processedSignalHashes.contains(signalFingerprint)) {
      debugPrint("[WebRTC] Ignored duplicate signal: $type from $from");
      return;
    }
    _processedSignalHashes.add(signalFingerprint);

    if (_processedSignalHashes.length > 100) {
      _processedSignalHashes.remove(_processedSignalHashes.first);
    }

    debugPrint("[WebRTC] Received signal from $from: $type");

    switch (type) {
      case 'offer':
        debugPrint("[WebRTC] Received offer from $from, length: ${payload['sdp']?.length}");

        RTCPeerConnection pc = peers[from] ?? await _createPeerConnection(from);
        peers[from] = pc;

        try {
          await pc.setRemoteDescription(RTCSessionDescription(payload['sdp'], 'offer'));
          debugPrint("[WebRTC] Remote description set successfully.");
          final pending = pendingCandidates.remove(from);
          if (pending != null) {
            for (final candidate in pending) {
              await pc.addCandidate(candidate);
            }
          }
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);

          await _sendSignal(from, "answer", {"sdp": answer.sdp, "type": "answer",});
        } catch (e) {
          debugPrint("[WebRTC] Error setting remote description or creating answer: $e");
        }
        break;

      case 'answer':
        final pc = peers[from];
        if (pc != null) {
          debugPrint("[WebRTC] Applying answer from $from to PeerConnection");
          await pc.setRemoteDescription(RTCSessionDescription(payload['sdp'], 'answer'));
          
          final pending = pendingCandidates.remove(from);
          if (pending != null) {
            for (final candidate in pending) {
              await pc.addCandidate(candidate).catchError((e) => debugPrint("[WebRTC] Pending ICE error: $e"));
            }
          }
        } else {
          debugPrint("[WebRTC] ERROR: Received answer from $from but no PeerConnection found!");
        }
        break;

      case 'ice':
      case 'ice-candidate':
        final candidate = RTCIceCandidate(
          payload['candidate'],
          payload['sdpMid'],
          payload['sdpMLineIndex'],
        );

        final pc = peers[from];
        bool canAdd = false;
        if (pc != null) {
          final remoteDesc = await pc.getRemoteDescription();
          if (remoteDesc != null) {
            canAdd = true;
          }
        }

        if(canAdd){
          await pc!.addCandidate(candidate).catchError((e) => debugPrint("[WebRTC] ICE error: $e"));
          debugPrint("[WebRTC] Successfully added ICE candidate from $from");
        }else{
          pendingCandidates.putIfAbsent(from, () => []).add(candidate);
          debugPrint("[WebRTC] Cached pending ICE candidate from $from (PC or RemoteDesc not ready)");
        }
        break;
        
      case 'user-joined':
        // Optional: Send offer to newcomers
        final pc = await _createPeerConnection(from);
        peers[from] = pc;
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        await _sendSignal(from, "offer", {"sdp": offer.sdp, "type": "offer"});
        break;
    }
  }

  void dispose() {
    localStream?.getTracks().forEach((track) => track.stop());
    localStream?.dispose();
    localStream = null;

    localScreenStream?.getTracks().forEach((track) => track.stop());
    localScreenStream?.dispose();
    localScreenStream = null;

    for (var pc in peers.values) {
      pc.close();
      pc.dispose();
    }
    peers.clear();
    pendingCandidates.clear();
  }
}
