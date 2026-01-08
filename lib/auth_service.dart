import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'vault_service.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _keyVerifier = 'nemo_passphrase_verifier';
  static const _hintKey = 'nemo_passphrase_hint';
  
  // New keys for security persistence
  static const _failedAttemptsKey = 'nemo_failed_attempts';
  static const _lockoutUntilKey = 'nemo_lockout_until';
  static const int maxAttemptsBeforeLock = 5;

  /// Check if the user has ever set a passphrase
  static Future<bool> isFirstTimeUser() async {
    final verifier = await _storage.read(key: _keyVerifier);
    return verifier == null;
  }

  /// Retrieve the security hint
  static Future<String?> getHint() async {
    return await _storage.read(key: _hintKey);
  }

  /// New: Get current failed attempts count
  static Future<int> getFailedAttempts() async {
    String? attempts = await _storage.read(key: _failedAttemptsKey);
    return attempts != null ? int.parse(attempts) : 0;
  }

  /// New: Check if user is currently locked out and return remaining Duration
  static Future<Duration> getRemainingLockoutTime() async {
    String? lockoutStr = await _storage.read(key: _lockoutUntilKey);
    if (lockoutStr == null) return Duration.zero;

    DateTime lockoutUntil = DateTime.parse(lockoutStr);
    DateTime now = DateTime.now();

    if (now.isBefore(lockoutUntil)) {
      return lockoutUntil.difference(now);
    }
    return Duration.zero;
  }

  /// SETUP: Stores verifier and hint, resets security state
  static Future<void> setupPassphrase(String phrase, String hint) async {
    final verifier = sha256.convert(utf8.encode(phrase)).toString();
    
    await _storage.write(key: _keyVerifier, value: verifier);
    await _storage.write(key: _hintKey, value: hint);
    
    // Reset security counters on new setup
    await _resetSecurityState();
    
    VaultService.initializeKey(phrase);
  }

  /// UNLOCK: Now handles failed attempt increments and lockout logic
  static Future<bool> verifyAndUnlock(String phrase) async {
    // 1. Check if we are currently locked out
    Duration remainingLock = await getRemainingLockoutTime();
    if (remainingLock > Duration.zero) return false;

    final savedVerifier = await _storage.read(key: _keyVerifier);
    if (savedVerifier == null) return false;

    final inputHash = sha256.convert(utf8.encode(phrase)).toString();
    
    if (inputHash == savedVerifier) {
      // SUCCESS: Clear failures and unlock
      await _resetSecurityState();
      VaultService.initializeKey(phrase);
      return true;
    } else {
      // FAILURE: Handle backoff logic
      await _handleFailedAttempt();
      return false;
    }
  }

  /// Internal: Increments failures and sets lockout timestamps
  static Future<void> _handleFailedAttempt() async {
    int currentFailures = await getFailedAttempts() + 1;
    await _storage.write(key: _failedAttemptsKey, value: currentFailures.toString());

    DateTime? lockoutTime;
    if (currentFailures == 4) {
      lockoutTime = DateTime.now().add(const Duration(minutes: 1));
    } else if (currentFailures >= 5) {
      lockoutTime = DateTime.now().add(const Duration(minutes: 10));
    }

    if (lockoutTime != null) {
      await _storage.write(key: _lockoutUntilKey, value: lockoutTime.toIso8601String());
    }
  }

  /// Internal: Resets all security counters
  static Future<void> _resetSecurityState() async {
    await _storage.delete(key: _failedAttemptsKey);
    await _storage.delete(key: _lockoutUntilKey);
  }
}