import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart'; // 🔱 Required for Windows 5/5
import 'vault_service.dart';

/// 🔱 Nemo Vault: Session Observer (v5/5 Architecture)
/// Orchestrates the 'Abyss Protocol' for Windows and Android.
/// 
/// WINDOWS 5/5:
/// 1. Instant Lock on Minimize (via windowManager).
/// 2. No Lock on Focus Loss/Multitasking (via inactive ignore).
/// 3. 1-Min Inactivity backup (via InactivityWrapper).
/// 
/// ANDROID 5/5:
/// 1. Instant Lock on Home/Switch (via paused/hidden).
/// 2. No Lock on Notification Shade (via inactive ignore).
/// 3. Veto logic for File Pickers/Biometrics.
class SessionObserver extends WidgetsBindingObserver with WindowListener {
  final VoidCallback onTriggerSeal;
  
  // 🔱 Debouncer to prevent race conditions during rapid state changes
  Timer? _sealTimer;

  SessionObserver({required this.onTriggerSeal}) {
    // 🔱 Register for Native Windows Events (Condition 5: Instant Minimize)
    if (Platform.isWindows) {
      windowManager.addListener(this);
    }
  }

  // ==========================================
  // 🔱 WINDOWS SPECIFIC: CONDITION 5 (MINIMIZE)
  // ==========================================
  @override
  void onWindowMinimize() {
    debugPrint("🔱 Abyss Protocol: Windows Minimize Detected. Executing Seal.");
    _executeInstantSeal();
  }

  // ==========================================
  // 🔱 ANDROID & SHARED: LIFECYCLE LOGIC
  // ==========================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint("🔱 Lifecycle Event: ${state.name}");

    // CONDITION 1: KILL SWITCH (App Resumed)
    // If user returns quickly (e.g. accidental minimize), cancel the seal.
    if (state == AppLifecycleState.resumed) {
      if (_sealTimer != null) {
        _sealTimer!.cancel();
        _sealTimer = null;
        debugPrint("🔱 Abyss Protocol: App Resumed. Pending Seal Cancelled.");
      }
      return;
    }

    // CONDITION 3: MULTITASKING FRIENDLY (App Inactive)
    // Windows: Clicking another window. Android: Pulling down notification shade.
    // We do NOT lock here. We let the 1-minute timer handle idle security.
    if (state == AppLifecycleState.inactive) {
      debugPrint("🔱 Abyss Protocol: App Inactive. Focus Lost - Multitasking Mode.");
      return;
    }

    // CONDITION 2 & 5 (Android): TRUE BACKGROUNDING
    // 'hidden' is for Flutter 3.13+; 'paused' is the classic background state.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _sealTimer?.cancel();

      // DEBOUNCER: 500ms safety window.
      // Allows OS animations to finish and 'isSystemDialogActive' to settle.
      _sealTimer = Timer(const Duration(milliseconds: 500), () {
        _executeInstantSeal();
        _sealTimer = null;
      });
    }
  }

  /// 🔱 Core Seal Execution
  /// Wipes keys and triggers the navigation callback defined in main.dart.
  void _executeInstantSeal() {
    // CONDITION 4: SYSTEM DIALOG VETO (File Picker / Biometrics)
    if (!VaultService.isSystemDialogActive) {
      debugPrint("🔱 Abyss Protocol: Security conditions met. Sealing Vault.");
      
      // 1. Immediate RAM Purge
      VaultService.deepSeal();
      
      // 2. Trigger Navigation to Entry Screen
      onTriggerSeal();
    } else {
      debugPrint("🔱 Abyss Protocol: Seal Vetoed - System Dialog currently active.");
    }
  }

  // Cleanup native listeners to prevent memory leaks
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    _sealTimer?.cancel();
  }
}