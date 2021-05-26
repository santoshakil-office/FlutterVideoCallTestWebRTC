import 'dart:async';
import 'dart:core';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_webrtc_example/model/peer_offer.dart';

class LoopBackSample extends StatefulWidget {
  static String tag = 'loopback_sample';

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<LoopBackSample> {
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  MediaStream? _localStream;
  RTCPeerConnection? _peerConnection;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _inCalling = false;
  Timer? _timer;

  String get sdpSemantics =>
      WebRTC.platformIsWindows ? 'plan-b' : 'unified-plan';

  @override
  void initState() {
    super.initState();
    initRenderers();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      print('Message data: ${message.data}');

      if (message.notification != null) {
        print('Message also contained a notification: ${message.notification}');
      }
    });
    initF();
  }

  Future<void> initF() async {
    var token = await FirebaseMessaging.instance.getToken();
    print('Token: ' + token!);
    await saveTokenToDatabase(token);
    FirebaseMessaging.instance.onTokenRefresh.listen(saveTokenToDatabase);
  }

  Future<void> saveTokenToDatabase(String token) async {
    print('Token: ' + token);
    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
    // Assume user is logged in for this example
    String? userId = user!.uid;

    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'tokens': FieldValue.arrayUnion([token]),
    });
  }

  @override
  void deactivate() {
    super.deactivate();
    if (_inCalling) {
      _hangUp();
    }
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  void initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void handleStatsReport(Timer timer) async {
    if (_peerConnection != null) {
/*
      var reports = await _peerConnection.getStats();
      reports.forEach((report) {
        print('report => { ');
        print('    id: ' + report.id + ',');
        print('    type: ' + report.type + ',');
        print('    timestamp: ${report.timestamp},');
        print('    values => {');
        report.values.forEach((key, value) {
          print('        ' + key + ' : ' + value.toString() + ', ');
        });
        print('    }');
        print('}');
      });
*/
      /*
      var senders = await _peerConnection.getSenders();
      var canInsertDTMF = await senders[0].dtmfSender.canInsertDtmf();
      print(canInsertDTMF);
      await senders[0].dtmfSender.insertDTMF('1');
      var receivers = await _peerConnection.getReceivers();
      print(receivers[0].track.id);
      var transceivers = await _peerConnection.getTransceivers();
      print(transceivers[0].sender.parameters);
      print(transceivers[0].receiver.parameters);
      */
    }
  }

  void _onSignalingState(RTCSignalingState state) {
    print(state);
  }

  void _onIceGatheringState(RTCIceGatheringState state) {
    print(state);
  }

  void _onIceConnectionState(RTCIceConnectionState state) {
    print(state);
  }

  void _onPeerConnectionState(RTCPeerConnectionState state) {
    print(state);
  }

  void _onAddStream(MediaStream stream) {
    print('New stream: ' + stream.id);
    _remoteRenderer.srcObject = stream;
  }

  void _onRemoveStream(MediaStream stream) {
    _remoteRenderer.srcObject = null;
  }

  void _onCandidate(RTCIceCandidate candidate) {
    print('onCandidate: ${candidate.candidate}');
    _peerConnection?.addCandidate(candidate);
  }

  void _onTrack(RTCTrackEvent event) {
    print('onTrack');
    if (event.track.kind == 'video') {
      _remoteRenderer.srcObject = event.streams[0];
    }
  }

  void _onAddTrack(MediaStream stream, MediaStreamTrack track) {
    if (track.kind == 'video') {
      _remoteRenderer.srcObject = stream;
    }
  }

  void _onRemoveTrack(MediaStream stream, MediaStreamTrack track) {
    if (track.kind == 'video') {
      _remoteRenderer.srcObject = null;
    }
  }

  void _onRenegotiationNeeded() {
    print('RenegotiationNeeded');
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  void _makeCall() async {
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth':
              '720', // Provide your own width, height and frame rate here
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      }
    };

    var configuration = <String, dynamic>{
      'iceServers': [
        {'url': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': sdpSemantics
    };

    final offerSdpConstraints = <String, dynamic>{
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': true,
      },
      'optional': [],
    };

    final loopbackConstraints = <String, dynamic>{
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': false},
      ],
    };

    if (_peerConnection != null) return;

    try {
      _peerConnection =
          await createPeerConnection(configuration, loopbackConstraints);

      _peerConnection!.onSignalingState = _onSignalingState;
      _peerConnection!.onIceGatheringState = _onIceGatheringState;
      _peerConnection!.onIceConnectionState = _onIceConnectionState;
      _peerConnection!.onConnectionState = _onPeerConnectionState;
      _peerConnection!.onIceCandidate = _onCandidate;
      _peerConnection!.onRenegotiationNeeded = _onRenegotiationNeeded;

      _localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;

      switch (sdpSemantics) {
        case 'plan-b':
          _peerConnection!.onAddStream = _onAddStream;
          _peerConnection!.onRemoveStream = _onRemoveStream;
          await _peerConnection!.addStream(_localStream!);
          break;
        case 'unified-plan':
          _peerConnection!.onTrack = _onTrack;
          _peerConnection!.onAddTrack = _onAddTrack;
          _peerConnection!.onRemoveTrack = _onRemoveTrack;
          _localStream!.getTracks().forEach((track) {
            _peerConnection!.addTrack(track, _localStream!);
          });
          break;
      }

      /*
      await _peerConnection.addTransceiver(
        track: _localStream.getAudioTracks()[0],
        init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendRecv, streams: [_localStream]),
      );
      */
      /*
      // ignore: unused_local_variable
      var transceiver = await _peerConnection.addTransceiver(
        track: _localStream.getVideoTracks()[0],
        init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendRecv, streams: [_localStream]),
      );
      */

      /*
      // Unified-Plan Simulcast
      await _peerConnection.addTransceiver(
          track: _localStream.getVideoTracks()[0],
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendOnly,
            streams: [_localStream],
            sendEncodings: [
              // for firefox order matters... first high resolution, then scaled resolutions...
              RTCRtpEncoding(
                rid: 'f',
                maxBitrate: 900000,
                numTemporalLayers: 3,
              ),
              RTCRtpEncoding(
                rid: 'h',
                numTemporalLayers: 3,
                maxBitrate: 300000,
                scaleResolutionDownBy: 2.0,
              ),
              RTCRtpEncoding(
                rid: 'q',
                numTemporalLayers: 3,
                maxBitrate: 100000,
                scaleResolutionDownBy: 4.0,
              ),
            ],
          ));
      
      await _peerConnection.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo);
      await _peerConnection.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo);
      await _peerConnection.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init:
              RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
      */
      var description = await _peerConnection!.createOffer(offerSdpConstraints);
      var sdp = description.sdp;
      print('sdp = $sdp');

      // var user = FirebaseAuth.instance.currentUser;
      // String? userId = user!.uid;

      var remPeerL = FirebaseFirestore.instance
          .collection('users')
          .doc('2')
          .collection('data')
          .doc('123')
          .withConverter<PeerOfferModel>(
            fromFirestore: (snapshot, _) =>
                PeerOfferModel.fromJson(snapshot.data()!),
            toFirestore: (model, _) => model.toJson(),
          );
      var remPeerR = FirebaseFirestore.instance
          .collection('users')
          .doc('1')
          .collection('data')
          .doc('123')
          .withConverter<PeerOfferModel>(
            fromFirestore: (snapshot, _) =>
                PeerOfferModel.fromJson(snapshot.data()!),
            toFirestore: (model, _) => model.toJson(),
          );
      await remPeerL
          .set(PeerOfferModel(sdp: description.sdp!, type: description.type!));
      var _desRem = await remPeerR.get();
      print('Rem SDP: ' + _desRem.data()!.sdp);

      try {
        await _peerConnection!.setLocalDescription(description);
        // description.type = 'answer';
        await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(_desRem.data()!.sdp, 'answer'));
      } catch (e) {
        print('Rem Peer Error: ' + e.toString());
      }

      // _peerConnection!.getStats();
      /* Unfied-Plan replaceTrack
      var stream = await MediaDevices.getDisplayMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      await transceiver.sender.replaceTrack(stream.getVideoTracks()[0]);
      // do re-negotiation ....
      */
    } catch (e) {
      print(e.toString());
    }
    if (!mounted) return;

    _timer = Timer.periodic(Duration(seconds: 1), handleStatsReport);

    setState(() {
      _inCalling = true;
    });
  }

  void _hangUp() async {
    try {
      await _localStream?.dispose();
      await _peerConnection?.close();
      _peerConnection = null;
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    } catch (e) {
      print(e.toString());
    }
    setState(() {
      _inCalling = false;
    });
    _timer?.cancel();
  }

  void _sendDtmf() async {
    var dtmfSender =
        _peerConnection?.createDtmfSender(_localStream!.getAudioTracks()[0]);
    await dtmfSender?.insertDTMF('123#');
  }

  @override
  Widget build(BuildContext context) {
    var widgets = <Widget>[
      Expanded(
        child: RTCVideoView(_localRenderer, mirror: true),
      ),
      Expanded(
        child: RTCVideoView(_remoteRenderer),
      )
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('LoopBack example'),
        actions: _inCalling
            ? <Widget>[
                IconButton(
                  icon: Icon(Icons.keyboard),
                  onPressed: _sendDtmf,
                ),
              ]
            : null,
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Center(
            child: Container(
              decoration: BoxDecoration(color: Colors.black54),
              child: orientation == Orientation.portrait
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: widgets)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: widgets),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _inCalling ? _hangUp : _makeCall,
        tooltip: _inCalling ? 'Hangup' : 'Call',
        child: Icon(_inCalling ? Icons.call_end : Icons.phone),
      ),
    );
  }
}