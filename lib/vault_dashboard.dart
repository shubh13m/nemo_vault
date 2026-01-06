import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'vault_service.dart';
import 'main.dart'; 

class VaultDashboard extends StatefulWidget {
  const VaultDashboard({super.key});

  @override
  State<VaultDashboard> createState() => _VaultDashboardState();
}

class _VaultDashboardState extends State<VaultDashboard> {
  late Future<List<FileSystemEntity>> _fileList;
  final List<File> _stagedFiles = []; 
  // Removed AppLifecycleListener to prevent context errors during navigation

  @override
  void initState() {
    super.initState();
    _refreshFiles();
  }

  void _refreshFiles() {
    setState(() {
      _fileList = VaultService.listEncryptedFiles();
    });
  }

  void _logout() {
    VaultService.lockVault(); 
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const VaultEntry()),
      (route) => false, 
    );
  }

  void _pickFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      setState(() {
        _stagedFiles.addAll(result.paths.map((path) => File(path!)).toList());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. REMOVED SecureGate wrapper that was causing the Null Check error
    return Scaffold(
      backgroundColor: NemoPalette.systemSlate,
      appBar: AppBar(
        title: const Text("NEMO VAULT", 
          style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: NemoPalette.deepOcean,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _logout,
          )
        ],
      ),
      body: Column(
        children: [
          _buildStatsHeader(), 
          
          if (_stagedFiles.isNotEmpty) _buildStagingArea(),
    
          Expanded(
            child: FutureBuilder<List<FileSystemEntity>>(
              future: _fileList,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: NemoPalette.electricBlue));
                }
    
                final files = snapshot.data ?? [];
                if (files.isEmpty && _stagedFiles.isEmpty) {
                  return _buildEmptyState();
                }
    
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index] as File;
                    final fileName = p.basename(file.path).replaceAll('.nemo', '');
    
                    return Card(
                      color: NemoPalette.deepOcean,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: _buildEncryptedThumbnail(file),
                        title: Text(fileName, style: const TextStyle(color: Colors.white, fontSize: 14)),
                        onTap: () => _showPreview(file),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white30),
                          onPressed: () async {
                            await file.delete();
                            _refreshFiles();
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NemoPalette.electricBlue,
        onPressed: _pickFiles,
        label: const Text("SELECT FILES", 
          style: TextStyle(color: NemoPalette.systemSlate, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add_photo_alternate, color: NemoPalette.systemSlate),
      ),
    );
  }

  // --- UI COMPONENTS ---

  Widget _buildStatsHeader() {
    return FutureBuilder<List<FileSystemEntity>>(
      future: _fileList,
      builder: (context, snapshot) {
        int count = snapshot.data?.length ?? 0;
        return Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NemoPalette.deepOcean,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NemoPalette.electricBlue.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem("TOTAL SECURED", "$count", Icons.lock_outline),
              Container(width: 1, height: 40, color: Colors.white10),
              _statItem("VAULT STATUS", "ENCRYPTED", Icons.verified_user_outlined),
            ],
          ),
        );
      },
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: NemoPalette.electricBlue, size: 20),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildStagingArea() {
    return Container(
      height: 180,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("STAGING AREA", style: TextStyle(color: NemoPalette.electricBlue, fontWeight: FontWeight.bold, fontSize: 12)),
              TextButton(
                onPressed: _handleVaultCommit,
                child: const Text("COMMIT TO ABYSS", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
              )
            ],
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _stagedFiles.length,
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(image: FileImage(_stagedFiles[index]), fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 0, right: 10,
                      child: GestureDetector(
                        onTap: () => setState(() => _stagedFiles.removeAt(index)),
                        child: const CircleAvatar(
                          radius: 12, backgroundColor: Colors.red,
                          child: Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    )
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEncryptedThumbnail(File file) {
    return SizedBox(
      width: 45, height: 45,
      child: FutureBuilder<Uint8List?>(
        future: VaultService.decryptFileData(file),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(snapshot.data!, fit: BoxFit.cover),
            );
          }
          return const Icon(Icons.lock, color: NemoPalette.electricBlue, size: 20);
        },
      ),
    );
  }

  void _showPreview(File file) async {
    final bytes = await VaultService.decryptFileData(file);
    if (bytes != null && mounted) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: NemoPalette.deepOcean,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.7,
                    maxWidth: MediaQuery.of(context).size.width * 0.8,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CLOSE", 
                    style: TextStyle(color: NemoPalette.electricBlue, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _handleVaultCommit() async {
    for (var file in _stagedFiles) {
      await VaultService.encryptAndStoreSpecific(file);
      await file.delete(); 
    }
    setState(() => _stagedFiles.clear());
    _refreshFiles();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vault Sealed & Originals Cleaned!"), backgroundColor: Colors.green),
      );
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 80, color: NemoPalette.electricBlue.withOpacity(0.2)),
          const SizedBox(height: 16),
          const Text("Your abyss is empty.", style: TextStyle(color: Colors.white24, letterSpacing: 1)),
        ],
      ),
    );
  }
}