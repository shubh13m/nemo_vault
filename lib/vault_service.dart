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

  /// Returns the current passphrase so the Dashboard/Archive can pass it to the Isolate
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

  /// 🔱 INTERNAL STAGING: Persistent folder to prevent OS Cache expiration
  static Future<Directory> get _internalStagingDir async {
    final root = await getApplicationDocumentsDirectory();
    final path = p.join(root.path, 'staging_internal');
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 🔱 PEEK & REVEAL: Decrypts file directly into RAM for viewing.
  static Future<Uint8List?> decryptFileData(File encryptedFile) async {
    if (!isUnlocked()) return null;
    try {
      final fileBytes = await encryptedFile.readAsBytes();
      if (fileBytes.length < 12) return null; 

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
    
    try {
      return Uint8List.fromList(
        encrypter.decryptBytes(encrypt.Encrypted(encryptedData), iv: iv)
      );
    } catch (e) {
      debugPrint("🔱 AES Decryption Failure: $e");
      rethrow;
    }
  }

  /// 🔱 SECURE PURGE: Overwrites and deletes a file from the vault.
  static Future<void> secureDeleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final length = await file.length();
        final sink = file.openWrite(mode: FileMode.write);
        sink.add(Uint8List(length)); 
        await sink.flush();
        await sink.close();
        
        await file.delete();
        debugPrint("🔱 Abyss: File Purged & Zeroed -> ${p.basename(filePath)}");
      }
    } catch (e) {
      debugPrint("🔱 Purge Error: $e");
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    }
  }

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

  /// 🔱 Updated encryptAndStore with Safety-Copy and Path-Based Duplicate Filter
  static Future<bool> encryptAndStore() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      
      if (result != null) {
        final stagingDir = await _internalStagingDir;
        
        for (var fileData in result.files) {
          if (fileData.path != null) {
            // 🔱 SHIELD: Check duplication based on the target secure path
            final String securePath = p.join(stagingDir.path, fileData.name);
            
            bool isAlreadyStaged = _stagingArea.any((item) => item.file.path == securePath);
            if (isAlreadyStaged) {
              debugPrint("🔱 Staging: Ghost Blocked (Already in list) -> ${fileData.name}");
              continue; 
            }

            final originalFile = File(fileData.path!);
            
            // 🔱 SAFETY COPY: Ensure the file is physically present in staging
            if (await originalFile.exists()) {
               final persistentFile = await originalFile.copy(securePath);
               _stagingArea.add(StagedItem(file: persistentFile));
               debugPrint("🔱 Staging: Safety copy secured -> ${fileData.name}");
            }
          }
        }
        return true;
      }
    } catch (e) {
      debugPrint("🔱 Picker Error: $e");
    }
    return false;
  }

  /// 🔱 ATOMIC REMOVAL: Removes from RAM and kills physical ghost instantly
  static void removeFromStaging(StagedItem item) {
    _stagingArea.removeWhere((i) => i.id == item.id);
    try {
      if (item.file.existsSync()) {
        item.file.deleteSync();
        debugPrint("🔱 Staging: Physical Ghost Purged -> ${item.fileName}");
      }
    } catch (e) {
      debugPrint("🔱 Staging: Deletion failed (file may be locked) -> $e");
    }
  }

  static void deepSeal() {
    // 🔱 VETO: Do not purge physical files if the system is busy (Picker or Isolate)
    if (isProcessing || isSystemDialogActive) {
      debugPrint("🔱 Data Integrity Guard: deepSeal (Physical Purge) vetoed");
      return; 
    }
    _currentKey = null; 
    _rawPassphrase = null; 
    _clearStagingFiles(); 
    _stagingArea.clear();
    debugPrint("🔱 Abyss Protocol: RAM & Staging Purged.");
  }

  static void lockVault() => deepSeal();

  static void clearStaging() {
    if (!isProcessing && !isSystemDialogActive) {
      _clearStagingFiles();
      _stagingArea.clear();
      debugPrint("🔱 Staging Area Purged.");
    }
  }

  /// 🔱 Hardened cleanup: Deletes files individually to avoid race conditions
  static Future<void> _clearStagingFiles() async {
    try {
      final dir = await _internalStagingDir;
      if (await dir.exists()) {
        final List<FileSystemEntity> entities = dir.listSync();
        for (var entity in entities) {
          if (entity is File) {
            // 🔱 SHIELD: Only delete if the file is NOT tracked in the active list
            // This prevents PathNotFoundException during background processing
            bool isTracked = _stagingArea.any((item) => item.file.path == entity.path);
            if (!isTracked) {
              await entity.delete();
            }
          }
        }
      }
    } catch (e) {
      debugPrint("🔱 Staging Cleanup Error: $e");
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

    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  static String getCleanName(String path) {
    String name = p.basename(path);
    if (name.endsWith('.nemo')) {
      return name.substring(0, name.length - 5);
    }
    return name;
  }
}