import 'dart:async';
import 'package:flutter/material.dart';
import 'vault_service.dart';

/// 🔱 Nemo Vault: Inactivity Wrapper
/// Monitors user interaction. If the user is idle for [timeout], the vault seals.
class InactivityWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onInactivity;
  final Duration timeout;

  const InactivityWrapper({
    super.key,
    required this.child,
    required this.onInactivity,
    this.timeout = const Duration(minutes: 5), // Default to 5 minutes
  });

  @override
  State<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends State<InactivityWrapper> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  /// Resets the countdown. Called on every user interaction.
  void _resetTimer() {
    // 🔱 SECURITY CHECK: 
    // If the vault is already locked, don't bother restarting the timer.
    if (!VaultService.isUnlocked()) return;

    if (_timer?.isActive ?? false) {
      _timer?.cancel();
    }
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer(widget.timeout, () {
      // 🔱 Before triggering inactivity, check if the user is 
      // just busy in a system dialog (like picking a very large file).
      if (!VaultService.isSystemDialogActive) {
        debugPrint("🔱 Nautilus Idle: Inactivity timeout reached. Executing Deep Seal.");
        widget.onInactivity();
      } else {
        // If a dialog is active, give them one more 'timeout' cycle.
        _startTimer();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listener captures raw pointer events on Windows/Android
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      onPointerMove: (_) => _resetTimer(),
      onPointerHover: (_) => _resetTimer(), // 🔱 Added Hover for Windows Mouse support
      onPointerUp: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}