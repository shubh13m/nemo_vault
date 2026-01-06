import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart'; // REQUIRED for 'compute'
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class VaultService {
  // 1. Holds the key in memory ONLY while the app is unlocked.
  static encrypt.Key? _currentKey;

  // 2. Logic to turn your Passphrase into a 32-byte AES Key
  static void initializeKey(String passphrase) {
    final bytes = utf8.encode(passphrase);
    final digest = sha256.convert(bytes);
    _currentKey = encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  // Helper to ensure we don't try to encrypt without a key
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

  /// ✅ PERFORMANCE FIX: Decrypts data on a background thread (Isolate)
  /// This prevents the UI from freezing on your SM A356E when scrolling
  static Future<Uint8List?> decryptFileData(File encryptedFile) async {
    try {
      final fileBytes = await encryptedFile.readAsBytes();
      
      // We use 'compute' to run the heavy math on a separate CPU core
      return await compute(_decryptWork, {
        'bytes': fileBytes,
        'key': _getKey(),
      });
    } catch (e) {
      debugPrint("Decryption Error: $e");
      return null;
    }
  }

  /// Top-level helper function for background decryption
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

  /// Encrypts a specific file from your "Staging Area"
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
    } catch (e) {
      debugPrint("Encryption Error: $e");
      rethrow;
    }
  }

  /// Existing logic for picking and storing immediately
  static Future<bool> encryptAndStore() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        await encryptAndStoreSpecific(File(result.files.single.path!));
        return true;
      }
    } catch (e) {
      debugPrint("Encryption Error: $e");
    }
    return false;
  }

  static Future<List<FileSystemEntity>> listEncryptedFiles() async {
    final dir = await _vaultDirectory;
    if (!await dir.exists()) return [];
    return dir.listSync();
  }
  
  // Call this when logging out to wipe the key from memory
  static void lockVault() {
    _currentKey = null;
  }
}