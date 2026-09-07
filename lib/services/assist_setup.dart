import 'package:flutter/services.dart';

/// Opens the system "Digital assistant app" picker so the user can set Logic
/// Legends as the assistant — then a power-button hold opens it hands-free.
class AssistSetup {
  static const _channel = MethodChannel('aiforall/phone');

  /// Returns false if no settings screen could be opened.
  static Future<bool> openSettings() async {
    try {
      return (await _channel.invokeMethod<bool>('openAssistSettings')) ?? false;
    } catch (_) {
      return false;
    }
  }
}
