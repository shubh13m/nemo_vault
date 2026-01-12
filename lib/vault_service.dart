import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart'; 
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// 🔱 Flattened import for lib structure
import 'staged_item.dart';

/// 🔱 Nemo Vault: Advanced Security Engine
class VaultService {
  static encrypt.Key? _currentKey;
  static String? _rawPassphrase; 
  
  static final List<StagedItem> _stagingArea = [];

  /// 🔱 VETO FLAGS: 
  /// isSystemDialogActive: Prevents lock during File Picking/Biometrics.
  /// isProcessing: Prevents lock during Isolate encryption.
  static bool isSystemDialogActive = false;
  static bool isProcessing = false;

  static List<StagedItem> get stagingArea => List.unmodifiable(_stagingArea);

  /// Returns the current passphrase so the Dashboard can pass it to the Isolate
  static String? get activeKey => _rawPassphrase;

  static void initializeKey(String passphrase) {
    _rawPassphrase = passphrase;
    final bytes = utf8.encode(passphrase);
    final digest = sha256.convert(bytes);
    _currentKey = encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  static bool isUnlocked() => _currentKey != null;

  static encrypt.Key _getKey() {
    if (_currentKey == null) throw Exception("Vault locked.");
    return _currentKey!;
  }

  static Future<Directory> get _vaultDirectory async {
    final root = await getApplicationDocumentsDirectory();
    final path = p.join(root.path, 'vault_storage');
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 🔱 PERFORMANCE FIX: Metadata-only decryption for thumbnails.
  static Future<Uint8List?> decryptFileData(File encryptedFile) async {
    if (!isUnlocked()) return null;
    try {
      final fileBytes = await encryptedFile.readAsBytes();
      return await compute(_decryptWork, {
        'bytes': fileBytes,
        'key': _getKey(),
      });
    } catch (e) {
      debugPrint("🔱 Decryption Error: $e");
      return null;
    }
  }

  static Uint8List _decryptWork(Map<String, dynamic> map) {
    final Uint8List fileBytes = map['bytes'];
    final encrypt.Key key = map['key'];
    final iv = encrypt.IV(fileBytes.sublist(0, 12));
    final encryptedData = fileBytes.sublist(12);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
    return Uint8List.fromList(encrypter.decryptBytes(encrypt.Encrypted(encryptedData), iv: iv));
  }

  /// Handles Isolate-specific pathing and Android file locking.
  static Future<void> encryptAndStoreSpecific(StagedItem item) async {
    final key = _getKey();
    final sourceFile = item.file;
    final dir = await _vaultDirectory;
    final encryptedFile = File(p.join(dir.path, '${item.fileName}.nemo'));

    try {
      final iv = encrypt.IV.fromSecureRandom(12);
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
      
      final bytes = await sourceFile.readAsBytes();
      final encrypted = encrypter.encryptBytes(bytes, iv: iv);
      
      final sink = encryptedFile.openWrite();
      sink.add(iv.bytes);
      sink.add(encrypted.bytes);
      await sink.flush();
      await sink.close();

      await _purgeOriginalFile(sourceFile);

      if (!kIsWeb) {
        _stagingArea.removeWhere((i) => i.id == item.id);
      }
    } catch (e) {
      debugPrint("🔱 Encryption/Purge Failure: ${item.fileName} -> $e");
      rethrow;
    }
  }

  static Future<void> _purgeOriginalFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
        
        if (Platform.isAndroid && await file.exists()) {
          final sink = file.openWrite(mode: FileMode.write);
          sink.add([0, 0, 0, 0]); 
          await sink.flush();
          await sink.close();
          await file.delete(recursive: true);
        }
      }
    } catch (e) {
      try {
        if (await file.exists()) {
          await file.writeAsBytes(Uint8List(0));
          await file.delete();
        }
      } catch (_) {}
    }
  }

  /// 🔱 Simplified: Flag management is now delegated to the caller (Dashboard)
  /// to ensure the Veto gate stays open long enough for the OS focus to return.
  static Future<bool> encryptAndStore() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      
      if (result != null) {
        for (var path in result.paths) {
          if (path != null) {
            _stagingArea.add(StagedItem(file: File(path)));
          }
        }
        return true;
      }
    } catch (e) {
      debugPrint("🔱 Picker Error: $e");
    }
    return false;
  }

  static void removeFromStaging(StagedItem item) {
    _stagingArea.removeWhere((i) => i.id == item.id);
  }

  /// 🔱 Abyss Protocol: Final Wipe
  /// Respects both background processing and active system dialogs.
  static void deepSeal() {
    if (isProcessing || isSystemDialogActive) {
      debugPrint("🔱 Data Integrity Guard: deepSeal vetoed (Proc: $isProcessing, Dialog: $isSystemDialogActive)");
      return; 
    }
    _currentKey = null; 
    _rawPassphrase = null; 
    _stagingArea.clear();
    debugPrint("🔱 Abyss Protocol: RAM Purged.");
  }

  /// 🔱 Logic Gate: Controlled lock.
  static void lockVault() => deepSeal();

  /// 🔱 Clean-up: Call this after Isolate finishes to wipe the list if locked.
  static void clearStaging() {
    if (!isProcessing) {
      _stagingArea.clear();
      debugPrint("🔱 Staging Area Purged.");
    }
  }

  static Future<List<FileSystemEntity>> listEncryptedFiles() async {
    final dir = await _vaultDirectory;
    if (!await dir.exists()) return [];
    
    final List<FileSystemEntity> files = [];
    await for (var entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.nemo')) {
        files.add(entity);
      }
    }

    files.sort((a, b) {
      return b.statSync().modified.compareTo(a.statSync().modified);
    });

    return files;
  }
}