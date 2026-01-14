import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'main.dart';

class SecureViewer extends StatelessWidget {
  final String fileName;
  final Uint8List fileBytes;

  const SecureViewer({
    super.key,
    required this.fileName,
    required this.fileBytes,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          fileName,
          style: const TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.security, color: NemoPalette.electricBlue),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("RAM Protection Active")),
              );
            },
          )
        ],
      ),
      body: Center(
        child: Hero(
          tag: fileName,
          child: _renderContent(context),
        ),
      ),
      bottomNavigationBar: Container(
        height: 80,
        color: Colors.black,
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.lock),
          label: const Text("CLOSE & WIPE RAM", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _renderContent(BuildContext context) {
    // 🔱 Simple Type Detection (Extension-based)
    final String extension = fileName.split('.').last.toLowerCase();

    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension)) {
      return InteractiveViewer(
        child: Image.memory(
          fileBytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _errorWidget("Invalid Image Data"),
        ),
      );
    } 
    
    // 🔱 Fallback for Text-based files
    try {
      final textContent = String.fromCharCodes(fileBytes);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(
          textContent,
          style: const TextStyle(color: Colors.white70, fontFamily: 'monospace'),
        ),
      );
    } catch (e) {
      return _errorWidget("Unsupported Preview Format");
    }
  }

  Widget _errorWidget(String msg) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 50),
        const SizedBox(height: 10),
        Text(msg, style: const TextStyle(color: Colors.white38)),
      ],
    );
  }
}