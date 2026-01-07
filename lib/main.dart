import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'auth_service.dart';
import 'passphrase_screen.dart';
import 'inactivity_wrapper.dart';
import 'session_observer.dart';
import 'vault_service.dart';

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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    // 🔱 The observer triggers _sealVault on Pause/Hide
    _sessionObserver = SessionObserver(onTriggerSeal: _sealVault);
    WidgetsBinding.instance.addObserver(_sessionObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_sessionObserver);
    super.dispose();
  }

  /// 🔱 The "Deep Seal" logic: Purges RAM and resets UI
  void _sealVault() {
    if (!VaultService.isUnlocked()) {
      debugPrint("🔱 Nemo Vault: Memory already purged. Ignoring signal.");
      return;
    }

    debugPrint("🔱 Nemo Vault: Emergency Seal Triggered. Wiping RAM.");
    
    // Purge key and staging area
    VaultService.deepSeal();
    
    // Redirect to login screen
    navigatorKey.currentState?.pushNamedAndRemoveUntil('entry', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return InactivityWrapper(
      onInactivity: _sealVault, 
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Nemo Vault',
        theme: NemoPalette.theme,
        initialRoute: 'entry',
        routes: {
          'entry': (context) => const VaultEntry(),
        },
      ),
    );
  }
}

class VaultEntry extends StatefulWidget {
  const VaultEntry({super.key});

  @override
  State<VaultEntry> createState() => _VaultEntryState();
}

class _VaultEntryState extends State<VaultEntry> {
  final LocalAuthentication auth = LocalAuthentication();

  Future<void> _unsealVault() async {
    bool authenticated = false;
    try {
      // 🔱 Raise flag to prevent locking during biometric dialog
      VaultService.isSystemDialogActive = true;

      await Future.delayed(const Duration(milliseconds: 100));
      
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
      // 🔱 BUFFER: Wait 800ms before lowering flag.
      // This allows the OS Focus to return fully so the app doesn't lock itself
      // the moment the biometric window disappears.
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