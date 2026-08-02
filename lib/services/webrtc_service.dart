import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'live_service.dart';

class WebRTCManager {
  final String spaceId;
  final Function(String userId, MediaStream stream) onAddRemoteStream;
  final Function(String userId) onRemoveRemoteStream;
  final Function(String userId, RTCPeerConnectionState state) onConnectionStateChanged;

  MediaStream? localStream;
  Map<String, RTCPeerConnection> peers = {};
  
  bool _audioEnabled = false;
  bool _videoEnabled = false;

  WebRTCManager({
    required this.spaceId,
    required this.onAddRemoteStream,
    required this.onRemoveRemoteStream,
    required this.onConnectionStateChanged,
  });

  Future<void> init() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 640},
        'height': {'ideal': 480},
      }
    };

    try {
      localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      // Default disabled
      for (var track in localStream!.getAudioTracks()) {
        track.enabled = _audioEnabled;
      }
      for (var track in localStream!.getVideoTracks()) {
        track.enabled = _videoEnabled;
      }
    } catch (e) {
      debugPrint("[WebRTC] getUserMedia error: $e");
    }
  }

  void toggleAudio(bool enabled) {
    _audioEnabled = enabled;
    localStream?.getAudioTracks().forEach((track) => track.enabled = enabled);
  }

  void toggleVideo(bool enabled) {
    _videoEnabled = enabled;
    localStream?.getVideoTracks().forEach((track) => track.enabled = enabled);
  }

  Future<RTCPeerConnection> _createPeerConnection(String userId) async {
    final Map<String, dynamic> config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(config);

    pc.onIceCandidate = (candidate) {
      debugPrint("[WebRTC] Sending ICE candidate to $userId");
      LiveService.sendSignal(spaceId, {
        "target": userId,
        "type": "ice-candidate",
        "payload": {
          "candidate": candidate.candidate,
          "sdpMid": candidate.sdpMid,
          "sdpMLineIndex": candidate.sdpMLineIndex,
        }
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
        await pc.addTrack(track, localStream!);
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
    final String type = event['type'];
    final String from = event['from'] ?? event['user'] ?? '';
    if (from.isEmpty) return;

    final payload = event['payload'] ?? {};

    switch (type) {
      case 'offer':
        debugPrint("[WebRTC] Received offer from $from, length: ${payload['sdp']?.length}");
        final pc = await _createPeerConnection(from);
        peers[from] = pc;
        try {
          await pc.setRemoteDescription(RTCSessionDescription(payload['sdp'], 'offer'));
          debugPrint("[WebRTC] Remote description set successfully.");
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          
          await LiveService.sendSignal(spaceId, {
            "target": from,
            "type": "answer",
            "payload": {"sdp": answer.sdp}
          });
        } catch (e) {
          debugPrint("[WebRTC] Error setting remote description or creating answer: $e");
        }
        break;

      case 'answer':
        final pc = peers[from];
        if (pc != null) {
          await pc.setRemoteDescription(RTCSessionDescription(payload['sdp'], 'answer'));
        }
        break;

      case 'ice':
      case 'ice-candidate':
        final pc = peers[from];
        if (pc != null) {
          await pc.addCandidate(RTCIceCandidate(
            payload['candidate'],
            payload['sdpMid'],
            payload['sdpMLineIndex'],
          ));
        }
        break;
        
      case 'user-joined':
        // Optional: Send offer to newcomers
        final pc = await _createPeerConnection(from);
        peers[from] = pc;
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        await LiveService.sendSignal(spaceId, {
          "target": from,
          "type": "offer",
          "payload": {"sdp": offer.sdp}
        });
        break;
    }
  }

  void dispose() {
    localStream?.dispose();
    for (var pc in peers.values) {
      pc.dispose();
    }
    peers.clear();
  }
}
