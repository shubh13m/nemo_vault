import 'dart:async';
import 'package:flutter/material.dart';
import 'vault_service.dart';

class SessionObserver extends WidgetsBindingObserver {
  final VoidCallback onTriggerSeal;
  
  // 🔱 The Kill Switch: Physically stops a pending lock command
  Timer? _sealTimer;

  SessionObserver({required this.onTriggerSeal});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint("🔱 Lifecycle Event: ${state.name}");

    // 1. IF RESUMED: The Ultimate Kill Switch.
    // If the app comes back within 500ms (File Picker closed), we destroy the timer.
    if (state == AppLifecycleState.resumed) {
      if (_sealTimer != null) {
        _sealTimer!.cancel();
        _sealTimer = null;
        debugPrint("🔱 Abyss Protocol: App Resumed. Seal Timer Destroyed.");
      }
      return;
    }

    // 2. IF INACTIVE: 
    // On Windows, clicking away makes the app 'inactive'. 
    // On Android, the transition to 'hidden' passes through 'inactive'.
    // We stay neutral here to avoid accidental locks.
    if (state == AppLifecycleState.inactive) {
      debugPrint("🔱 Abyss Protocol: App Inactive. Standing by...");
      return;
    }

    // 3. IF HIDDEN or PAUSED: Start the countdown to wipe RAM.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      
      // Cancel any ghost timers already running
      _sealTimer?.cancel();

      // 🔱 DEBOUNCER: Wait 500ms.
      // This window allows the 'resumed' event to fire if it was just a File Picker.
      _sealTimer = Timer(const Duration(milliseconds: 500), () {
        // Double Check: Only seal if a system dialog (Picker/Biometrics) IS NOT active.
        if (!VaultService.isSystemDialogActive) {
          debugPrint("🔱 Abyss Protocol: Security condition met. Sealing Vault.");
          onTriggerSeal();
        } else {
          debugPrint("🔱 Abyss Protocol: Seal Vetoed - System Dialog currently active.");
        }
        
        // Clean up timer reference after execution
        _sealTimer = null;
      });
    }
  }
}