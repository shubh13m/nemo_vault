import 'dart:async'; // Required for Timer
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
  final FocusNode _passphraseFocusNode = FocusNode();

  bool _isObscured = true;
  String _errorMessage = "";
  String? _savedHint;

  // Security state variables
  Duration _lockoutRemaining = Duration.zero;
  int _attemptsRemaining = 5;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    if (!widget.isSetup) {
      _loadHint();
      _checkLockoutStatus(); // Check security status immediately on load
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_lockoutRemaining == Duration.zero) {
        _passphraseFocusNode.requestFocus();
      }
    });
  }

  /// 🔱 Checks security status and triggers countdown if locked
  Future<void> _checkLockoutStatus() async {
    final remaining = await AuthService.getRemainingLockoutTime();
    final failed = await AuthService.getFailedAttempts();

    if (mounted) {
      setState(() {
        _lockoutRemaining = remaining;
        
        // 🔱 Logic: After 4 fails (1st lock), user is on their final shot
        if (failed >= 4) {
          _attemptsRemaining = 1;
        } else {
          _attemptsRemaining = 5 - failed;
        }

        // Show remaining attempts immediately if not locked
        if (_lockoutRemaining == Duration.zero && failed > 0) {
          _errorMessage = "$_attemptsRemaining attempts remaining.";
        }
      });

      if (_lockoutRemaining > Duration.zero) {
        _startCountdown();
      }
    }
  }

  /// 🔱 Logic to refresh UI the moment the timer hits zero
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lockoutRemaining.inSeconds > 0) {
        setState(() {
          _lockoutRemaining = _lockoutRemaining - const Duration(seconds: 1);
        });
      } else {
        timer.cancel();
        _handleLockoutLifted();
      }
    });
  }

  /// 🔱 Restoration logic: Re-enables UI and updates message
  void _handleLockoutLifted() async {
    final failed = await AuthService.getFailedAttempts();
    if (mounted) {
      setState(() {
        _lockoutRemaining = Duration.zero;
        if (failed >= 4) {
          _attemptsRemaining = 1;
          _errorMessage = "System restored. Final attempt remaining.";
        } else {
          _attemptsRemaining = 5 - failed;
          _errorMessage = "System restored. $_attemptsRemaining attempts remaining.";
        }
      });
      // Auto-focus the field so user can type immediately
      _passphraseFocusNode.requestFocus();
    }
  }

  Future<void> _loadHint() async {
    final hint = await AuthService.getHint();
    if (mounted) {
      setState(() => _savedHint = hint);
    }
  }

  void _handleAction() async {
    FocusManager.instance.primaryFocus?.unfocus();
    String input = _controller.text.trim();
    setState(() => _errorMessage = "");

    if (input.isEmpty) {
      setState(() => _errorMessage = "Phrase cannot be empty");
      return;
    }

    if (widget.isSetup) {
      String confirmInput = _confirmController.text.trim();
      String hintInput = _hintController.text.trim();

      if (confirmInput.isEmpty || hintInput.isEmpty) {
        setState(() => _errorMessage = "Please fill all fields");
        return;
      }
      if (input != confirmInput) {
        setState(() => _errorMessage = "Passphrases do not match");
        return;
      }

      await AuthService.setupPassphrase(input, hintInput);
      _navigateToDashboard();
    } else {
      bool success = await AuthService.verifyAndUnlock(input);
      
      if (success) {
        _navigateToDashboard();
      } else {
        final failed = await AuthService.getFailedAttempts();
        final lockout = await AuthService.getRemainingLockoutTime();

        setState(() {
          _lockoutRemaining = lockout;
          
          if (failed >= 4) {
            _attemptsRemaining = 1;
          } else {
            _attemptsRemaining = 5 - failed;
          }
          
          if (_lockoutRemaining > Duration.zero) {
            _errorMessage = "Security breach protocol active.";
            _startCountdown();
          } else {
            _errorMessage = "Incorrect Passphrase. $_attemptsRemaining attempts remaining.";
          }
        });

        if (_lockoutRemaining == Duration.zero) {
          _passphraseFocusNode.requestFocus();
        }
      }
    }
  }

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
    _countdownTimer?.cancel();
    _controller.dispose();
    _confirmController.dispose();
    _hintController.dispose();
    _passphraseFocusNode.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String minutes = d.inMinutes.toString().padLeft(2, '0');
    String seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    bool isUIEnabled = _lockoutRemaining <= Duration.zero;

    return Scaffold(
      backgroundColor: NemoPalette.systemSlate,
      body: Stack(
        children: [
          Positioned(
            top: -100, right: -50,
            child: CircleAvatar(radius: 150, backgroundColor: NemoPalette.electricBlue.withValues(alpha: 0.1)),
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
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/shield.png',
                          height: 80,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            widget.isSetup ? Icons.security : (isUIEnabled ? Icons.lock_open : Icons.lock_clock),
                            color: isUIEnabled ? NemoPalette.electricBlue : Colors.redAccent,
                            size: 50,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.isSetup ? "INITIALIZE VAULT" : "SECURED ACCESS",
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.isSetup 
                            ? "Set your secret phrase. Typos will lock you out forever!" 
                            : (isUIEnabled 
                                ? "Enter your secret phrase to decrypt your files."
                                : "Security Lockdown: Please wait for timer."),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                        const SizedBox(height: 30),
                        
                        _buildTextField(
                          controller: _controller,
                          focusNode: _passphraseFocusNode,
                          hint: isUIEnabled ? (widget.isSetup ? "Choose Passphrase..." : "Enter Passphrase...") : "Locked out...",
                          icon: Icons.vpn_key,
                          obscure: _isObscured,
                          enabled: isUIEnabled,
                          toggleObscure: () => setState(() => _isObscured = !_isObscured),
                        ),

                        if (widget.isSetup) ...[
                          const SizedBox(height: 15),
                          _buildTextField(
                            controller: _confirmController,
                            hint: "Confirm Passphrase...",
                            icon: Icons.check_circle_outline,
                            obscure: _isObscured,
                            enabled: true,
                          ),
                          const SizedBox(height: 15),
                          _buildTextField(
                            controller: _hintController,
                            hint: "Security Hint (e.g. Pet name)",
                            icon: Icons.help_outline,
                            obscure: false,
                            enabled: true,
                          ),
                        ],

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
                            child: Text(
                              _errorMessage, 
                              textAlign: TextAlign.center,
                              style: TextStyle(color: isUIEnabled ? Colors.redAccent : Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.w500)
                            ),
                          ),

                        const SizedBox(height: 30),

                        ElevatedButton(
                          onPressed: isUIEnabled ? _handleAction : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isUIEnabled ? NemoPalette.electricBlue : Colors.white10,
                            minimumSize: const Size(double.infinity, 55),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: Text(
                            isUIEnabled 
                              ? (widget.isSetup ? "CREATE VAULT" : "OPEN VAULT") 
                              : "RETRY IN ${_formatDuration(_lockoutRemaining)}",
                            style: TextStyle(
                              color: isUIEnabled ? Colors.black : Colors.white24, 
                              fontWeight: FontWeight.bold, 
                              fontSize: 16
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool obscure,
    bool enabled = true,
    FocusNode? focusNode,
    VoidCallback? toggleObscure,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      enabled: enabled,
      style: TextStyle(color: enabled ? Colors.white : Colors.white24),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.black26,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
        prefixIcon: Icon(icon, color: enabled ? Colors.white38 : Colors.white10, size: 20),
        suffixIcon: toggleObscure != null 
          ? IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: enabled ? Colors.white38 : Colors.white10, size: 20),
              onPressed: enabled ? toggleObscure : null,
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