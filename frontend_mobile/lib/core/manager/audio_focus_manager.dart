import 'package:flutter/material.dart';

enum AppAudioMode { feedsActive, studioActive, mutedAll }

class AudioFocusManager extends ChangeNotifier {
  // Singleton Pattern để truy cập toàn cục
  static final AudioFocusManager instance = AudioFocusManager._internal();
  AudioFocusManager._internal();

  AppAudioMode _currentMode = AppAudioMode.feedsActive;
  AppAudioMode get currentMode => _currentMode;

  void requestMode(AppAudioMode mode) {
    if (_currentMode != mode) {
      _currentMode = mode;
      notifyListeners();
    }
  }

  bool get shouldFeedsPlay => _currentMode == AppAudioMode.feedsActive;
  bool get shouldStudioPlay => _currentMode == AppAudioMode.studioActive;
}