import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart'; 
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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
    try {
      final fileBytes = await encryptedFile.readAsBytes();
      return await compute(_decryptWork, {
        'bytes': fileBytes,
        'key': _getKey(),
      });
    } catch (e) {
      debugPrint("Decryption Error: $e");
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

  // 🔱 Safe removal by file path
  static void removeFromStaging(File file) {
    _stagingArea.removeWhere((f) => f.path == file.path);
    debugPrint("🔱 VaultService: Removed ${p.basename(file.path)}");
  }

  /// 🔱 FINALIZED: Picker logic for Android and Windows stability.
  static Future<bool> encryptAndStore() async {
    try {
      // STEP 1: Raise flag BEFORE any async gaps.
      isSystemDialogActive = true; 
      debugPrint("🔱 Safety Flag: Raised. Preventing seal for Picker.");

      // STEP 2: The 50ms Sync Buffer. 
      // This ensures the flag is registered in the app state BEFORE 
      // Android switches focus to the File Picker activity.
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
      // STEP 3: The 1200ms Cooldown Shield.
      // We keep the flag raised while the app transitions from 'hidden' back to 'resumed'.
      // This prevents a "delayed lock" from firing during the return animation.
      Future.delayed(const Duration(milliseconds: 1200), () {
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
  
  static void deepSeal() {
    _currentKey = null;
    _stagingArea.clear();
    debugPrint("🔱 Abyss Protocol: RAM Purged. Staging Area Cleared.");
  }

  static void lockVault() => deepSeal();

  // 🔱 Clear ONLY the staging area without locking the vault
  static void clearStaging() {
    _stagingArea.clear();
    debugPrint("🔱 VaultService: Staging Area Purged.");
  }
}