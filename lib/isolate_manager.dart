import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; 

// 🔱 Flattened imports
import 'staged_item.dart';
import 'vault_service.dart';

/// 🔱 The Isolate Manager: The bridge between UI and the Background Worker.
class IsolateManager {
  static Isolate? _workerIsolate;
  static SendPort? _sendPort;
  
  static final _receivePort = ReceivePort();
  static final _progressController = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get progressStream => _progressController.stream;

  // 🔱 Request Tracker for On-Demand Decryption
  static final Map<String, Completer<Uint8List?>> _pendingRequests = {};

  static Future<void> start() async {
    if (_workerIsolate != null) return; 

    RootIsolateToken rootToken = RootIsolateToken.instance!;
    final handshakeCompleter = Completer<void>();

    _workerIsolate = await Isolate.spawn(_isolateEntryPoint, {
      'port': _receivePort.sendPort,
      'token': rootToken,
    });
    
    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        if (!handshakeCompleter.isCompleted) handshakeCompleter.complete();
        debugPrint("🔱 IsolateManager: Worker Handshake Complete.");
      } 
      // 🔱 Handle Decryption Responses
      else if (message is Map<String, dynamic> && message.containsKey('decrypted_bytes')) {
        final String path = message['path'];
        final Uint8List? bytes = message['decrypted_bytes'];
        if (_pendingRequests.containsKey(path)) {
          _pendingRequests[path]!.complete(bytes);
          _pendingRequests.remove(path);
        }
      }
      // 🔱 Handle Progress/Status Updates
      else if (message is Map<String, dynamic>) {
        if (message['status'] == 'batch_start') {
          VaultService.isProcessing = true;
        } else if (message['status'] == 'batch_end') {
          // 🔱 BUFFER: Wait 300ms for OS file handles to release before lifting the VETO
          Future.delayed(const Duration(milliseconds: 300), () {
            VaultService.isProcessing = false;
            if (!VaultService.isUnlocked()) {
              VaultService.clearStaging();
            }
          });
        }

        if (!_progressController.isClosed) {
          _progressController.add(message);
        }
      }
    });

    return handshakeCompleter.future;
  }

  /// 🔱 Reveal Logic: Requests the isolate to decrypt a specific file into RAM.
  static Future<Uint8List?> decryptFileOnDemand(File file, String keyMaterial) async {
    if (_sendPort == null) return null;

    final completer = Completer<Uint8List?>();
    _pendingRequests[file.path] = completer;

    _sendPort!.send({
      'command': 'reveal',
      'path': file.path,
      'key': keyMaterial,
    });

    return completer.future;
  }

  /// Sends a list of StagedItems to be encrypted (Sealed) in the background.
  static void processVaultLock(List<StagedItem> items, String keyMaterial) {
    if (_sendPort == null || items.isEmpty) return;

    VaultService.isProcessing = true;

    final serializedItems = items.map((item) => item.toMap()).toList();

    _sendPort!.send({
      'command': 'seal',
      'items': serializedItems,
      'key': keyMaterial,
    });
  }

  /// 🔱 The Background Worker
  static void _isolateEntryPoint(Map<String, dynamic> initData) {
    final SendPort mainSendPort = initData['port'];
    final RootIsolateToken token = initData['token'];

    BackgroundIsolateBinaryMessenger.ensureInitialized(token);

    final workerReceivePort = ReceivePort();
    mainSendPort.send(workerReceivePort.sendPort);

    workerReceivePort.listen((message) async {
      final String command = message['command'] ?? 'seal';
      final String key = message['key'];
      
      VaultService.initializeKey(key);

      if (command == 'reveal') {
        final String path = message['path'];
        try {
          final file = File(path);
          // 🔱 SHIELD: Ensure file exists before trying to read it
          if (!file.existsSync()) {
            mainSendPort.send({'path': path, 'decrypted_bytes': null});
            return;
          }
          final bytes = await VaultService.decryptFileData(file);
          mainSendPort.send({
            'path': path,
            'decrypted_bytes': bytes,
          });
        } catch (e) {
          mainSendPort.send({'path': path, 'decrypted_bytes': null});
        }
      } 
      else {
        try {
          final List<dynamic> itemsData = message['items'];
          mainSendPort.send({'status': 'batch_start'});

          for (var data in itemsData) {
            final item = StagedItem.fromMap(data as Map<String, dynamic>);
            
            // 🔱 THE GHOST KILLER: Check if file was deleted before isolate started
            if (!item.file.existsSync()) {
              debugPrint("🔱 Isolate: Skipping Ghost (File missing) -> ${item.fileName}");
              // Send a "sealed" status so the UI progress counter keeps moving
              mainSendPort.send({'id': item.id, 'status': 'sealed', 'progress': 1.0});
              continue; 
            }

            try {
              mainSendPort.send({'id': item.id, 'status': 'encrypting', 'progress': 0.1});
              await VaultService.encryptAndStoreSpecific(item);
              mainSendPort.send({'id': item.id, 'status': 'sealed', 'progress': 1.0});
            } catch (e) {
              mainSendPort.send({
                'id': item.id, 
                'status': 'error', 
                'message': e.toString()
              });
            }
          }
        } finally {
          mainSendPort.send({'status': 'batch_end'});
        }
      }
    });
  }

  static void stop() {
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _sendPort = null;
  }
}