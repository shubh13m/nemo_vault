import 'dart:ui';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'vault_dashboard.dart';
import 'main.dart'; // To access NemoPalette

class PassphraseScreen extends StatefulWidget {
  final bool isSetup; // True for first time, False for unlocking
  const PassphraseScreen({super.key, required this.isSetup});

  @override
  State<PassphraseScreen> createState() => _PassphraseScreenState();
}

class _PassphraseScreenState extends State<PassphraseScreen> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final TextEditingController _hintController = TextEditingController();
  
  // 🔱 FIX: Added FocusNode to manually manage keyboard focus after biometric dialogs
  final FocusNode _passphraseFocusNode = FocusNode();

  bool _isObscured = true;
  String _errorMessage = "";
  String? _savedHint;

  @override
  void initState() {
    super.initState();
    // If unlocking, load the hint from secure storage in the background
    if (!widget.isSetup) {
      _loadHint();
    }

    // 🔱 FIX: Request focus after the first frame is rendered.
    // This solves the Windows issue where the text field is visible but not "active"
    // after returning from a system biometric prompt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _passphraseFocusNode.requestFocus();
    });
  }

  Future<void> _loadHint() async {
    final hint = await AuthService.getHint();
    if (mounted) {
      setState(() => _savedHint = hint);
    }
  }

  void _handleAction() async {
    // 1. Force the keyboard to dismiss immediately
    FocusManager.instance.primaryFocus?.unfocus();

    String input = _controller.text.trim();
    
    // Reset error message
    setState(() => _errorMessage = "");

    if (input.isEmpty) {
      setState(() => _errorMessage = "Phrase cannot be empty");
      return;
    }

    if (widget.isSetup) {
      String confirmInput = _confirmController.text.trim();
      String hintInput = _hintController.text.trim();

      // Validation for Setup
      if (confirmInput.isEmpty || hintInput.isEmpty) {
        setState(() => _errorMessage = "Please fill all fields");
        return;
      }
      if (input != confirmInput) {
        setState(() => _errorMessage = "Passphrases do not match");
        return;
      }

      // Save everything via AuthService
      await AuthService.setupPassphrase(input, hintInput);
      _navigateToDashboard();
    } else {
      // Logic for Unlocking
      bool success = await AuthService.verifyAndUnlock(input);
      if (success) {
        _navigateToDashboard();
      } else {
        setState(() => _errorMessage = "Incorrect Passphrase. Access Denied.");
        // Re-focus on error so user can try again immediately
        _passphraseFocusNode.requestFocus();
      }
    }
  }

  /// 🔱 FIX: Added RouteSettings name 'dashboard'.
  /// This tells the security logic in main.dart that we are now in 
  /// a protected area so it knows when to trigger the lock screen.
  void _navigateToDashboard() {
    Navigator.pushReplacement(
      context, 
      MaterialPageRoute(
        settings: const RouteSettings(name: 'dashboard'),
        builder: (context) => const VaultDashboard(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    _hintController.dispose();
    // 🔱 FIX: Always dispose your focus nodes
    _passphraseFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NemoPalette.systemSlate,
      body: Stack(
        children: [
          // Background "Deep Sea" Glow
          Positioned(
            top: -100, right: -50,
            child: CircleAvatar(radius: 150, backgroundColor: NemoPalette.electricBlue.withOpacity(0.1)),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // --- SHIELD LOGO REPLACED ICON HERE ---
                        Image.asset(
                          'assets/images/shield.png',
                          height: 80,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            widget.isSetup ? Icons.security : Icons.lock_open,
                            color: NemoPalette.electricBlue,
                            size: 50,
                          ),
                        ),
                        // --------------------------------------
                        const SizedBox(height: 20),
                        Text(
                          widget.isSetup ? "INITIALIZE VAULT" : "SECURED ACCESS",
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.isSetup 
                            ? "Set your secret phrase. Typos will lock you out forever!" 
                            : "Enter your secret phrase to decrypt your files.",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                        const SizedBox(height: 30),
                        
                        // Primary Passphrase Input
                        _buildTextField(
                          controller: _controller,
                          focusNode: _passphraseFocusNode, // 🔱 FIX: Linked FocusNode
                          hint: widget.isSetup ? "Choose Passphrase..." : "Enter Passphrase...",
                          icon: Icons.vpn_key,
                          obscure: _isObscured,
                          toggleObscure: () => setState(() => _isObscured = !_isObscured),
                        ),

                        // Extra fields for SETUP mode
                        if (widget.isSetup) ...[
                          const SizedBox(height: 15),
                          _buildTextField(
                            controller: _confirmController,
                            hint: "Confirm Passphrase...",
                            icon: Icons.check_circle_outline,
                            obscure: _isObscured,
                          ),
                          const SizedBox(height: 15),
                          _buildTextField(
                            controller: _hintController,
                            hint: "Security Hint (e.g. Pet name)",
                            icon: Icons.help_outline,
                            obscure: false,
                          ),
                        ],

                        // Show hint if unlocking and hint exists
                        if (!widget.isSetup && _savedHint != null && _savedHint!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 15),
                            child: Text(
                              "Hint: $_savedHint",
                              style: const TextStyle(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic),
                            ),
                          ),

                        if (_errorMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 15),
                            child: Text(_errorMessage, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                          ),

                        const SizedBox(height: 30),

                        // Action Button
                        ElevatedButton(
                          onPressed: _handleAction,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NemoPalette.electricBlue,
                            minimumSize: const Size(double.infinity, 55),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: Text(
                            widget.isSetup ? "CREATE VAULT" : "OPEN VAULT",
                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
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

  // Helper to keep the build method clean
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool obscure,
    FocusNode? focusNode, // 🔱 FIX: Added focusNode parameter
    VoidCallback? toggleObscure,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode, // 🔱 FIX: Attach the focus node here
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.black26,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: toggleObscure != null 
          ? IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white38, size: 20),
              onPressed: toggleObscure,
            ) 
          : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: NemoPalette.electricBlue, width: 1),
        ),
      ),
    );
  }
}