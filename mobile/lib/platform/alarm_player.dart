import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

/// Giao dien am thanh de co the thay bang ban gia trong test.
abstract class AlarmSound {
  Future<void> start();
  Future<void> stop();
}

/// Phat am bao dong lap lai (am luong toi da) va rung theo mau lap.
class AlarmPlayer implements AlarmSound {
  AlarmPlayer();

  static const List<int> _vibrationPattern = [0, 700, 400, 700, 400];

  final AudioPlayer _player = AudioPlayer(playerId: 'baonga_alarm');
  bool _playing = false;

  bool get isPlaying => _playing;

  @override
  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    try {
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gain,
          ),
          iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
        ),
      );
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource('sounds/alarm.wav'));
    } catch (e) {
      debugPrint('AlarmPlayer audio loi: $e');
    }
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: _vibrationPattern, repeat: 0);
      }
    } catch (e) {
      debugPrint('AlarmPlayer rung loi: $e');
    }
  }

  @override
  Future<void> stop() async {
    _playing = false;
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await Vibration.cancel();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _player.dispose();
    } catch (_) {}
  }
}

/// Giu app song o nen tren iOS: lap file im lang am luong 0, khong chiem am thanh cua app khac.
class KeepAlivePlayer implements AlarmSound {
  KeepAlivePlayer();

  final AudioPlayer _player = AudioPlayer(playerId: 'baonga_keepalive');
  bool _running = false;

  bool get isRunning => _running;

  @override
  Future<void> start() async {
    if (_running || !Platform.isIOS) return;
    _running = true;
    try {
      await _player.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0);
      await _player.play(AssetSource('sounds/silence.wav'));
    } catch (e) {
      _running = false;
      debugPrint('KeepAlivePlayer loi: $e');
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    try {
      await _player.stop();
    } catch (_) {}
  }
}
