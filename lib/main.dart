import 'dart:io';
import 'dart:ui'; // Required for ImageFilter
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'auth_service.dart';
import 'passphrase_screen.dart';
import 'inactivity_wrapper.dart';
import 'session_observer.dart';
import 'vault_service.dart';
import 'package:window_manager/window_manager.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class NemoPalette {
  static const Color electricBlue = Color(0xFF00E5FF);
  static const Color systemSlate = Color(0xFF172A45);
  static const Color pureWhite = Color(0xFFE6F1FF);
  static const Color deepOcean = Color(0xFF0A192F);
  
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
    _sessionObserver = SessionObserver(onTriggerSeal: _sealVault);
    WidgetsBinding.instance.addObserver(_sessionObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_sessionObserver);
    _sessionObserver.dispose();
    super.dispose();
  }

  void _sealVault() {
    VaultService.deepSeal();
    bool isAlreadyAtEntry = false;
    navigatorKey.currentState?.popUntil((route) {
      if (route.settings.name == 'entry') isAlreadyAtEntry = true;
      return true;
    });

    if (!isAlreadyAtEntry) {
      navigatorKey.currentState?.pushNamedAndRemoveUntil('entry', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Nemo Vault',
      theme: NemoPalette.theme,
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
    VaultService.isSystemDialogActive = true;
    bool authenticated = false;
    try {
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
      body: Stack(
        children: [
          // 1. Ambient Glow Styling
          Positioned(
            top: -100,
            right: -50,
            child: CircleAvatar(
              radius: 150,
              backgroundColor: NemoPalette.electricBlue.withValues(alpha: 0.1),
            ),
          ),
          
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              // 2. Glassmorphism Styling
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 30),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min, // Keep it tight inside the glass box
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: screenHeight * 0.25, 
                            maxWidth: screenWidth * 0.5,
                          ),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.tsunami,
                                size: 120,
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            child: const Text(
                              "ACCESS VAULT",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}