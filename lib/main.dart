import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'auth_service.dart';
import 'passphrase_screen.dart';
import 'inactivity_wrapper.dart';
import 'session_observer.dart';
import 'vault_service.dart';
import 'package:window_manager/window_manager.dart';

// --- Global Navigator Key for forced redirection ---
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class NemoPalette {
  static const Color electricBlue = Color(0xFF4DB6FF);
  static const Color systemSlate = Color(0xFF2F3942);
  static const Color pureWhite = Colors.white;
  static const Color deepOcean = Color(0xFF1C2B35);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: systemSlate,
        colorScheme: const ColorScheme.dark(
          primary: electricBlue,
          onPrimary: systemSlate,
          surface: deepOcean,
          onSurface: pureWhite,
        ),
      );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🔱 Initialize Window Manager for Condition 5 (Windows Minimize)
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
  }
  
  runApp(const NemoApp());
}

class NemoApp extends StatefulWidget {
  const NemoApp({super.key});

  @override
  State<NemoApp> createState() => _NemoAppState();
}

class _NemoAppState extends State<NemoApp> {
  late SessionObserver _sessionObserver;

  @override
  void initState() {
    super.initState();
    // 🔱 The observer triggers _sealVault on Pause/Hide/Minimize
    _sessionObserver = SessionObserver(onTriggerSeal: _sealVault);
    WidgetsBinding.instance.addObserver(_sessionObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_sessionObserver);
    // 🔱 Clean up native Windows listeners
    _sessionObserver.dispose();
    super.dispose();
  }

  /// 🔱 THE MASTER SEAL: Forces UI reset and RAM purge.
  void _sealVault() {
    debugPrint("🔱 Nemo Vault: Master Seal Triggered. Redirection sequence started.");

    // 1. Wipe RAM Keys and Staging Area (Idempotent: safe to call multiple times)
    VaultService.deepSeal();
    
    // 2. Check current route to prevent unnecessary "push" if already at Entry.
    bool isAlreadyAtEntry = false;
    navigatorKey.currentState?.popUntil((route) {
      if (route.settings.name == 'entry') isAlreadyAtEntry = true;
      return true;
    });

    if (!isAlreadyAtEntry) {
      debugPrint("🔱 Nemo Vault: Redirecting to Entry Screen.");
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        'entry', 
        (route) => false,
      );
    } else {
      debugPrint("🔱 Nemo Vault: Already at Entry. Skipping navigation.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Nemo Vault',
      theme: NemoPalette.theme,
      // 🔱 THE WRAPPER: Handles the 1-minute idle countdown
      builder: (context, child) {
        return InactivityWrapper(
          onInactivity: _sealVault,
          child: child ?? const SizedBox.shrink(),
        );
      },
      initialRoute: 'entry',
      routes: {
        'entry': (context) => const VaultEntry(settings: RouteSettings(name: 'entry')),
      },
    );
  }
}

class VaultEntry extends StatefulWidget {
  final RouteSettings? settings;
  const VaultEntry({super.key, this.settings});

  @override
  State<VaultEntry> createState() => _VaultEntryState();
}

class _VaultEntryState extends State<VaultEntry> {
  final LocalAuthentication auth = LocalAuthentication();

  Future<void> _unsealVault() async {
    // 🔱 PRIORITY FIX: Raise flag SYNCHRONOUSLY before any async calls.
    // This blocks the SessionObserver from firing deepSeal() if the OS 
    // triggers an 'inactive' state while bringing up the biometric dialog.
    VaultService.isSystemDialogActive = true;

    bool authenticated = false;
    try {
      // Small buffer to ensure flag propagation before the native view takes over
      await Future.delayed(const Duration(milliseconds: 50));
      
      authenticated = await auth.authenticate(
        localizedReason: 'Unsealing Nemo Vault',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, 
        ),
      );
    } catch (e) {
      debugPrint("Auth Error: $e");
    } finally {
      // 🔱 Buffer allows biometric overlay to fully close and the app 
      // to return to 'resumed' state before we re-arm the security logic.
      await Future.delayed(const Duration(milliseconds: 800));
      VaultService.isSystemDialogActive = false;
    }

    if (authenticated && mounted) {
      final bool isFirstTime = await AuthService.isFirstTimeUser();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: 'passphrase'),
            builder: (context) => PassphraseScreen(isSetup: isFirstTime),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: screenHeight * 0.40, 
                maxWidth: screenWidth * 0.8,
              ),
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.tsunami,
                    size: 150,
                    color: NemoPalette.electricBlue,
                  );
                },
              ),
            ),
            const SizedBox(height: 50),
            SizedBox(
              width: 220,
              height: 54,
              child: ElevatedButton(
                onPressed: _unsealVault,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NemoPalette.electricBlue,
                  foregroundColor: NemoPalette.systemSlate,
                  elevation: 3,
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  "ACCESS VAULT",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}