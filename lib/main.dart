import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'auth_service.dart';
import 'passphrase_screen.dart';

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

class NemoApp extends StatelessWidget {
  const NemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nemo Vault',
      theme: NemoPalette.theme,
      home: const VaultEntry(),
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
      authenticated = await auth.authenticate(
        localizedReason: 'Unsealing Nemo Vault',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      debugPrint("Auth Error: $e");
    }

    if (authenticated && mounted) {
      final bool isFirstTime = await AuthService.isFirstTimeUser();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
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
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // --- LOGO (Kept at 40% height) ---
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

            // --- RE-SIZED ACCESS BUTTON (Balanced) ---
            SizedBox(
              width: 220, // Specific width so it's not full-screen
              height: 54,  // Reduced from 65 to a comfortable touch size
              child: ElevatedButton(
                onPressed: _unsealVault,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NemoPalette.electricBlue,
                  foregroundColor: NemoPalette.systemSlate,
                  elevation: 3,
                  shape: const StadiumBorder(), // Pill shape for a softer look
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