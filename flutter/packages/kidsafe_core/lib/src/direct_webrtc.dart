import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'family_models.dart';
import 'session_repository.dart';

typedef SessionSignalWriter = Future<void> Function(SessionSignalKind kind, Map<String, dynamic> payload);
typedef RemoteStreamListener = void Function(MediaStream stream);

/// A visible family-media connection. Capture permissions remain controlled by Android and the UI.
class DirectFamilyConnection {
  DirectFamilyConnection({required this.kind, required this.writeSignal, this.onRemoteStream});

  final FamilySessionKind kind;
  final SessionSignalWriter writeSignal;
  final RemoteStreamListener? onRemoteStream;
  final List<RTCIceCandidate> _pendingIce = [];
  final Set<String> _processedSignalIds = {};
  RTCPeerConnection? _peer;
  MediaStream? localStream;
  MediaStream? remoteStream;

  Future<void> initialize({MediaStream? providedLocalStream}) async {
    _peer = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
    });
    _peer!.onIceCandidate = (candidate) async {
      if (candidate.candidate == null) return;
      await writeSignal(SessionSignalKind.iceCandidate, {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    _peer!.onTrack = (event) {
      if (event.streams.isEmpty) return;
      remoteStream = event.streams.first;
      onRemoteStream?.call(remoteStream!);
    };
    _peer!.onAddStream = (stream) {
      remoteStream = stream;
      onRemoteStream?.call(stream);
    };
    localStream = providedLocalStream ?? await _requestLocalMedia();
    final stream = localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await _peer!.addTrack(track, stream);
      }
    }
  }

  Future<void> startOffer() async {
    final peer = _requirePeer();
    final offer = await peer.createOffer();
    await peer.setLocalDescription(offer);
    await writeSignal(SessionSignalKind.offer, {'type': offer.type, 'sdp': offer.sdp});
  }

  Future<void> applyPeerSignal(SessionSignal signal) async {
    if (!_processedSignalIds.add(signal.id)) return;
    final peer = _requirePeer();
    switch (signal.kind) {
      case SessionSignalKind.offer:
        await peer.setRemoteDescription(RTCSessionDescription(signal.payload['sdp'] as String?, signal.payload['type'] as String?));
        await _flushPendingIce();
        final answer = await peer.createAnswer();
        await peer.setLocalDescription(answer);
        await writeSignal(SessionSignalKind.answer, {'type': answer.type, 'sdp': answer.sdp});
      case SessionSignalKind.answer:
        await peer.setRemoteDescription(RTCSessionDescription(signal.payload['sdp'] as String?, signal.payload['type'] as String?));
        await _flushPendingIce();
      case SessionSignalKind.iceCandidate:
        final candidate = RTCIceCandidate(
          signal.payload['candidate'] as String?,
          signal.payload['sdpMid'] as String?,
          signal.payload['sdpMLineIndex'] as int?,
        );
        if (await peer.getRemoteDescription() == null) {
          _pendingIce.add(candidate);
        } else {
          await peer.addCandidate(candidate);
        }
      case SessionSignalKind.acknowledgement:
        break;
      case SessionSignalKind.end:
        await dispose();
    }
  }

  Future<void> dispose() async {
    for (final track in localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      track.stop();
    }
    await localStream?.dispose();
    await remoteStream?.dispose();
    await _peer?.close();
    _pendingIce.clear();
    _processedSignalIds.clear();
    localStream = null;
    remoteStream = null;
    _peer = null;
  }

  Future<MediaStream?> _requestLocalMedia() async {
    if (kind == FamilySessionKind.screen) {
      return navigator.mediaDevices.getDisplayMedia({'video': true, 'audio': false});
    }
    return navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': kind == FamilySessionKind.video ? {'facingMode': 'user'} : false,
    });
  }

  Future<void> _flushPendingIce() async {
    final peer = _requirePeer();
    for (final candidate in _pendingIce) {
      await peer.addCandidate(candidate);
    }
    _pendingIce.clear();
  }

  RTCPeerConnection _requirePeer() {
    final peer = _peer;
    if (peer == null) throw StateError('يجب تهيئة جلسة الوسائط أولاً.');
    return peer;
  }
}
