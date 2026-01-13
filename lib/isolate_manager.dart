import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; 

// 🔱 Flattened imports as all files are in /lib
import 'staged_item.dart';
import 'vault_service.dart';

/// 🔱 The Isolate Manager: The bridge between UI and the Background Worker.
/// Updated to support the "Manual Purge" workflow by ensuring status synchronization.
class IsolateManager {
  static Isolate? _workerIsolate;
  static SendPort? _sendPort;
  
  // ReceivePort for the main thread to hear from the worker
  static final _receivePort = ReceivePort();
  
  // Stream to allow the UI to listen to progress updates
  static final _progressController = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get progressStream => _progressController.stream;

  /// Initializes the background worker.
  static Future<void> start() async {
    if (_workerIsolate != null) return; 

    // Capture the Root Isolate Token from the UI thread
    RootIsolateToken rootToken = RootIsolateToken.instance!;
    final handshakeCompleter = Completer<void>();

    // Pass the token along with the port in the spawn call
    _workerIsolate = await Isolate.spawn(_isolateEntryPoint, {
      'port': _receivePort.sendPort,
      'token': rootToken,
    });
    
    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        if (!handshakeCompleter.isCompleted) handshakeCompleter.complete();
        debugPrint("🔱 IsolateManager: Worker Handshake Complete.");
      } else if (message is Map<String, dynamic>) {
        
        // 🔱 SYNCED VETO: Handle "isProcessing" state on the Main Thread
        if (message['status'] == 'batch_start') {
          VaultService.isProcessing = true;
          debugPrint("🔱 IsolateManager: Veto Lock Activated (Encryption Started).");
        } else if (message['status'] == 'batch_end') {
          VaultService.isProcessing = false;
          debugPrint("🔱 IsolateManager: Veto Lock Released (Encryption Finished).");
          
          // If the app was paused while processing, trigger the lock now
          if (!VaultService.isUnlocked()) {
            VaultService.clearStaging();
          }
        }

        // Ensure we don't flood the stream if the controller is closed
        if (!_progressController.isClosed) {
          _progressController.add(message);
        }
      }
    });

    return handshakeCompleter.future;
  }

  /// Sends a list of StagedItems to be encrypted in the background.
  static void processVaultLock(List<StagedItem> items, String keyMaterial) {
    if (_sendPort == null) {
      debugPrint("🔱 IsolateManager: Cannot process - Worker not ready.");
      return;
    }

    final serializedItems = items.map((item) => item.toMap()).toList();

    _sendPort!.send({
      'items': serializedItems,
      'key': keyMaterial,
    });
  }

  /// 🔱 The Background Worker (Runs in its own memory heap)
  static void _isolateEntryPoint(Map<String, dynamic> initData) {
    final SendPort mainSendPort = initData['port'];
    final RootIsolateToken token = initData['token'];

    // Initialize connection to Flutter Engine
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);

    final workerReceivePort = ReceivePort();
    mainSendPort.send(workerReceivePort.sendPort);

    workerReceivePort.listen((message) async {
      try {
        final List<dynamic> itemsData = message['items'];
        final String key = message['key'];

        // 🔱 Signal Main Thread to block auto-lock
        mainSendPort.send({'status': 'batch_start'});

        VaultService.initializeKey(key);

        for (var data in itemsData) {
          final item = StagedItem.fromMap(data as Map<String, dynamic>);
          
          try {
            mainSendPort.send({
              'id': item.id, 
              'status': 'encrypting', 
              'progress': 0.1
            });

            // Heavy computational work stays here
            // We NO LONGER delete the file here to prevent PathNotFound errors.
            await VaultService.encryptAndStoreSpecific(item);

            mainSendPort.send({
              'id': item.id, 
              'status': 'sealed', 
              'progress': 1.0
            });
          } catch (e) {
            mainSendPort.send({
              'id': item.id, 
              'status': 'error', 
              'message': 'File Error (${item.fileName}): ${e.toString()}'
            });
          }
        }
      } catch (globalError) {
        mainSendPort.send({
          'status': 'error', 
          'message': 'Critical Isolate Failure: ${globalError.toString()}'
        });
      } finally {
        // 🔱 CRITICAL: Always signal end to release the Veto Lock
        // This allows the UI to show the "Manual Purge" banner.
        mainSendPort.send({'status': 'batch_end'});
      }
    });
  }

  static void stop() {
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _sendPort = null;
    debugPrint("🔱 IsolateManager: Worker Terminated.");
  }
}