import 'dart:async';
import 'package:flutter/material.dart';
import 'vault_service.dart';

/// 🔱 Nemo Vault: Inactivity Wrapper (v5.1 Architecture)
/// Monitors raw user interaction and OS-level suspension.
/// 
/// Satisfies:
/// 1. 1-Minute Idle Lock: Seals vault after 60s of no input.
/// 2. Background Awareness: Stops timer when app is fully minimized.
/// 3. Focus-Smart: Prevents background mouse movement from resetting the timer.
/// 4. Double-Veto Protection: Prevents lock if File Picker OR Background Encryption is active.
class InactivityWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onInactivity;
  final Duration timeout;

  const InactivityWrapper({
    super.key,
    required this.child,
    required this.onInactivity,
    // 🔱 Project Specs: 1-minute inactivity timeout
    this.timeout = const Duration(minutes: 1), 
  });

  @override
  State<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends State<InactivityWrapper> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 🔱 Register lifecycle observer to coordinate with SessionObserver
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint("🔱 Nautilus Lifecycle: $state");

    // 🔱 WINDOWS & ANDROID FIX: 
    // We only cancel the timer on 'paused' or 'hidden' (App fully minimized).
    // The timer KEEPS counting if the window is just 'inactive' (out of focus).
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      debugPrint("🔱 Nautilus Idle: App backgrounded. Suspending idle timer.");
      _timer?.cancel();
    } 
    else if (state == AppLifecycleState.resumed) {
      // 🔱 On resume, only restart if the vault hasn't been sealed by SessionObserver
      if (VaultService.isUnlocked()) {
        debugPrint("🔱 Nautilus Idle: App resumed. Resetting idle timer.");
        _resetTimer();
      }
    }
  }

  /// Resets the countdown. Called on every physical interaction.
  void _resetTimer() {
    // 🔱 SECURITY CHECK 1: If the vault is already locked, do not reset/restart.
    if (!VaultService.isUnlocked()) return;

    // 🔱 SECURITY CHECK 2: FOCUS-SMART RESET
    // If the app is INACTIVE (e.g., Windows user is clicking a browser), 
    // hovering the mouse over the vault window should NOT reset the timer.
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.inactive) {
      return; 
    }

    if (_timer?.isActive ?? false) {
      _timer?.cancel();
    }
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer(widget.timeout, () {
      
      // 🔱 DOUBLE VETO LOGIC:
      // 1. isSystemDialogActive: User is picking files or using Biometrics.
      // 2. isProcessing: The Background Isolate is busy encrypting files.
      final bool isSystemBusy = VaultService.isSystemDialogActive;
      final bool isIsolateBusy = VaultService.isProcessing;

      if (!isSystemBusy && !isIsolateBusy) {
        debugPrint("🔱 Nautilus Idle: 1-minute timeout reached. Executing Deep Seal.");
        
        // RAM WIPE: Immediately clear sensitive data from memory.
        VaultService.deepSeal(); 
        
        // UI REDIRECT: Trigger the navigation logic defined in main.dart.
        widget.onInactivity();
      } else {
        // Log the specific reason for the Veto
        String reason = isIsolateBusy ? "Background Encryption" : "System Dialog";
        debugPrint("🔱 Nautilus Idle: Timeout reached, but Vetoed by $reason. Re-cycling.");
        
        // Keep the app alive by restarting the timer loop
        _startTimer();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 🔱 Detects clicks, taps, moves, and scrolls globally.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      onPointerMove: (_) => _resetTimer(),
      onPointerHover: (_) => _resetTimer(), // Crucial for Windows Mouse support
      onPointerUp: (_) => _resetTimer(),
      onPointerSignal: (_) => _resetTimer(), // Crucial for Mouse Scroll support
      child: widget.child,
    );
  }
}