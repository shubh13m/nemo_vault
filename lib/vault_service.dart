import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart'; 
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 🔱 Nemo Vault: Core Security Service
/// Manages the RAM-only Encryption Key and the Staging Area.
class VaultService {
  // 1. Holds the key in memory ONLY while the app is unlocked.
  static encrypt.Key? _currentKey;

  // 2. The Staging Area (Cargo Bay) list
  static final List<File> _stagingArea = [];

  // 🔱 Safety flag to prevent auto-locking during System Dialogs (Picker/Biometrics)
  static bool isSystemDialogActive = false;

  static List<File> get stagingArea => List.unmodifiable(_stagingArea);

  static void initializeKey(String passphrase) {
    final bytes = utf8.encode(passphrase);
    final digest = sha256.convert(bytes);
    _currentKey = encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  // 🔱 Used by InactivityWrapper to decide if it should be counting
  static bool isUnlocked() => _currentKey != null;

  static encrypt.Key _getKey() {
    if (_currentKey == null) {
      throw Exception("Vault is locked. No encryption key initialized.");
    }
    return _currentKey!;
  }

  static Future<Directory> get _vaultDirectory async {
    final root = await getApplicationDocumentsDirectory();
    final path = p.join(root.path, 'vault_storage');
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Uint8List?> decryptFileData(File encryptedFile) async {
    // 🔱 Guard: If the vault was just sealed, abort immediately to prevent UI crashes
    if (!isUnlocked()) return null;

    try {
      final fileBytes = await encryptedFile.readAsBytes();
      return await compute(_decryptWork, {
        'bytes': fileBytes,
        'key': _getKey(),
      });
    } catch (e) {
      // Catching the "Vault is locked" exception if it happens mid-compute
      debugPrint("🔱 Decryption Halted: Vault was sealed during processing.");
      return null;
    }
  }

  static Uint8List _decryptWork(Map<String, dynamic> map) {
    final Uint8List fileBytes = map['bytes'];
    final encrypt.Key key = map['key'];
    final ivBytes = fileBytes.sublist(0, 12);
    final encryptedData = fileBytes.sublist(12);
    final iv = encrypt.IV(ivBytes);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
    final decrypted = encrypter.decryptBytes(encrypt.Encrypted(encryptedData), iv: iv);
    return Uint8List.fromList(decrypted);
  }

  static Future<void> encryptAndStoreSpecific(File sourceFile) async {
    try {
      final bytes = await sourceFile.readAsBytes();
      final iv = encrypt.IV.fromSecureRandom(12);
      final encrypter = encrypt.Encrypter(encrypt.AES(_getKey(), mode: encrypt.AESMode.gcm));
      final encrypted = encrypter.encryptBytes(bytes, iv: iv);
      final combinedData = Uint8List.fromList(iv.bytes + encrypted.bytes);
      final dir = await _vaultDirectory;
      final fileName = p.basename(sourceFile.path);
      final encryptedFile = File(p.join(dir.path, '$fileName.nemo'));
      await encryptedFile.writeAsBytes(combinedData);
      _stagingArea.removeWhere((f) => f.path == sourceFile.path);
    } catch (e) {
      debugPrint("Encryption Error: $e");
      rethrow;
    }
  }

  static void removeFromStaging(File file) {
    _stagingArea.removeWhere((f) => f.path == file.path);
    debugPrint("🔱 VaultService: Removed ${p.basename(file.path)}");
  }

  static Future<bool> encryptAndStore() async {
    try {
      isSystemDialogActive = true; 
      debugPrint("🔱 Safety Flag: Raised. Preventing seal for Picker.");

      // Delay to ensure OS registers the app is still "active" before picker opens
      await Future.delayed(const Duration(milliseconds: 50));
      
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any, 
      );
      
      if (result != null) {
        for (var path in result.paths) {
          if (path != null) {
            _stagingArea.add(File(path));
          }
        }
        return true;
      }
    } catch (e) {
      debugPrint("Picker Error: $e");
    } finally {
      // 🔱 Logic Fix: We use a slightly shorter buffer here but ensure it 
      // ALWAYS clears, even if the user cancels the picker instantly.
      Future.delayed(const Duration(milliseconds: 800), () {
        isSystemDialogActive = false;
        debugPrint("🔱 Safety Flag: Lowered. Observer re-armed.");
      });
    }
    return false;
  }

  static Future<List<FileSystemEntity>> listEncryptedFiles() async {
    final dir = await _vaultDirectory;
    if (!await dir.exists()) return [];
    return dir.listSync();
  }
  
  /// 🔱 The Core Purge (Abyss Protocol)
  /// Wipes the key from RAM and clears the staging area.
  static void deepSeal() {
    // SECURITY: Nullify the key immediately. 
    // Dart's Garbage Collector will handle the memory cleanup.
    _currentKey = null; 
    _stagingArea.clear();
    
    // Safety: Reset the system dialog flag so we don't stay "unlocked" by mistake
    isSystemDialogActive = false;

    debugPrint("🔱 Abyss Protocol: RAM Purged. Staging Area Cleared. Vault Sealed.");
  }

  static void lockVault() => deepSeal();

  static void clearStaging() {
    _stagingArea.clear();
    debugPrint("🔱 VaultService: Staging Area Purged.");
  }
}