import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'vault_service.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _keyVerifier = 'nemo_passphrase_verifier';
  static const _hintKey = 'nemo_passphrase_hint'; // New key for hint

  /// Check if the user has ever set a passphrase
  static Future<bool> isFirstTimeUser() async {
    final verifier = await _storage.read(key: _keyVerifier);
    return verifier == null;
  }

  /// NEW: Retrieve the security hint
  static Future<String?> getHint() async {
    return await _storage.read(key: _hintKey);
  }

  /// SETUP: Now accepts a hint and stores it alongside the verifier
  static Future<void> setupPassphrase(String phrase, String hint) async {
    // 1. Create the fingerprint (Verifier)
    final verifier = sha256.convert(utf8.encode(phrase)).toString();
    
    // 2. Store both in secure hardware
    await _storage.write(key: _keyVerifier, value: verifier);
    await _storage.write(key: _hintKey, value: hint);
    
    // 3. Initialize the engine
    VaultService.initializeKey(phrase);
  }

  /// UNLOCK: No changes needed here, keeps existing logic intact
  static Future<bool> verifyAndUnlock(String phrase) async {
    final savedVerifier = await _storage.read(key: _keyVerifier);
    
    if (savedVerifier == null) return false;

    final inputHash = sha256.convert(utf8.encode(phrase)).toString();
    
    if (inputHash == savedVerifier) {
      VaultService.initializeKey(phrase);
      return true;
    }
    return false;
  }
}