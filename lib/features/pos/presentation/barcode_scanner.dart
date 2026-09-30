import 'dart:async';

import 'package:flutter/services.dart';

/// Captures keyboard-wedge barcode scanner input while no text field has
/// focus.
///
/// Scanners type a code in a few milliseconds and finish with Enter. Every
/// printable key is buffered; Enter delivers the buffer to [onScan]. If Enter
/// does not follow within [humanTimeout] the buffer is treated as ordinary
/// typing and handed to [onTyped] (so the user can "type anywhere" to search).
class ScannerKeyBuffer {
  ScannerKeyBuffer({
    required this.onScan,
    required this.onTyped,
    required this.isActive,
    this.humanTimeout = const Duration(milliseconds: 350),
    this.minLength = 3,
  });

  final void Function(String code) onScan;
  final void Function(String text) onTyped;

  /// Whether key events should be captured right now.
  final bool Function() isActive;
  final Duration humanTimeout;
  final int minLength;

  final _buffer = StringBuffer();
  Timer? _timer;

  bool get hasPending => _buffer.isNotEmpty;

  void attach() => HardwareKeyboard.instance.addHandler(handle);

  void detach() {
    HardwareKeyboard.instance.removeHandler(handle);
    _timer?.cancel();
  }

  /// Returns true when the event was consumed.
  bool handle(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    if (!isActive()) {
      _reset();
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_buffer.isEmpty) return false;
      final code = _buffer.toString().trim();
      _reset();
      if (code.length >= minLength) {
        onScan(code);
      } else if (code.isNotEmpty) {
        onTyped(code);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      final hadInput = _buffer.isNotEmpty;
      _reset();
      return hadInput;
    }
    final character = event.character;
    if (character == null ||
        character.isEmpty ||
        character.codeUnitAt(0) < 0x20 ||
        character.codeUnitAt(0) == 0x7F) {
      return false;
    }
    _buffer.write(character);
    _timer?.cancel();
    _timer = Timer(humanTimeout, () {
      if (_buffer.isEmpty) return;
      final text = _buffer.toString();
      _reset();
      onTyped(text);
    });
    return true;
  }

  void _reset() {
    _timer?.cancel();
    _buffer.clear();
  }
}
