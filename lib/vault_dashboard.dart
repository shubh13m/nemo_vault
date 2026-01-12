import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

// 🔱 Flattened Imports (Matches your /lib structure)
import 'vault_service.dart';
import 'isolate_manager.dart';
import 'staged_item.dart';
import 'main.dart';

class VaultDashboard extends StatefulWidget {
  const VaultDashboard({super.key});

  @override
  State<VaultDashboard> createState() => _VaultDashboardState();
}

/// 🔱 Added WidgetsBindingObserver to handle the Inactivity Lockout Fix
class _VaultDashboardState extends State<VaultDashboard> with WidgetsBindingObserver {
  late Future<List<FileSystemEntity>> _fileList = VaultService.listEncryptedFiles();
  final List<StagedItem> _stagedFiles = [];
  final ScrollController _stagingScrollController = ScrollController();

  bool _isCommitting = false;
  bool _showSuccess = false;
  int _totalToCommit = 0;
  int _currentCommit = 0;
  String _currentlyProcessing = ""; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 🔱 Monitor App Lifecycle
    _initVault();
  }

  void _initVault() async {
    await IsolateManager.start();
    _checkPermissions();
    _listenToProgress();
    _refreshFiles();
  }

  /// 🔱 VETO LOCK LOGIC: Synchronized with VaultService & InactivityWrapper
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint("🔱 Dashboard Lifecycle: $state");
    
    // 🔱 Logic Barrier: If we are encrypting OR picking files, do NOT lock.
    // We now check VaultService.isSystemDialogActive for the File Picker veto.
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (VaultService.isProcessing || VaultService.isSystemDialogActive) {
        debugPrint("🔱 Security Bypass: Vetoing auto-lock (Processing: ${VaultService.isProcessing}, DialogActive: ${VaultService.isSystemDialogActive})");
        return;
      }

      // Standard Auto-Lock: Wipe RAM and navigate to Entry
      if (VaultService.isUnlocked()) {
        _forceLockout();
      }
    }
  }

  void _forceLockout() {
    VaultService.lockVault();
    if (mounted) {
      Navigator.pushReplacementNamed(context, 'entry');
    }
  }

  void _checkPermissions() async {
    if (Platform.isAndroid) {
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 🔱 Cleanup observer
    _stagingScrollController.dispose();
    super.dispose();
  }

  void _refreshFiles() {
    setState(() {
      _fileList = VaultService.listEncryptedFiles();
    });
  }

  void _listenToProgress() {
    IsolateManager.progressStream.listen((data) {
      if (!mounted) return;
      
      final String? id = data['id'];
      final String? status = data['status'];
      
      setState(() {
        if (status == 'encrypting' && id != null) {
          if (_stagedFiles.any((e) => e.id == id)) {
            final item = _stagedFiles.firstWhere((e) => e.id == id);
            _currentlyProcessing = item.fileName;
          }
        }

        if (status == 'sealed' && id != null) {
          _currentCommit++;
          if (_currentCommit >= _totalToCommit && _isCommitting) {
            _finalizeCommit();
          }
        }

        if (status == 'error') {
          debugPrint("🔱 Isolate Error: ${data['message']}");
        }
      });
    });
  }

  void _scrollStagingArea(bool forward) {
    if (!_stagingScrollController.hasClients) return;
    double scrollOffset = 220.0;
    double target = _stagingScrollController.offset + (forward ? scrollOffset : -scrollOffset);
    _stagingScrollController.animateTo(
      target.clamp(0.0, _stagingScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  /// 🔱 Updated to use the Global Veto Protection in VaultService
  void _pickFiles() async {
    // 🔱 Raise the Veto flag BEFORE the OS dialog opens
    setState(() => VaultService.isSystemDialogActive = true); 

    try {
      bool success = await VaultService.encryptAndStore();
      if (success && mounted) {
        setState(() {
          _stagedFiles.clear();
          _stagedFiles.addAll(VaultService.stagingArea);
        });
      }
    } finally {
      // 🔱 Small delay allows the OS to fully return focus to the app 
      // before we re-enable security lockout checks.
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() => VaultService.isSystemDialogActive = false); // Lower Veto flag
      }
    }
  }

  Future<void> _handleVaultLock() async {
    if (_stagedFiles.isEmpty) return;

    setState(() {
      _isCommitting = true;
      _showSuccess = false;
      _totalToCommit = _stagedFiles.length;
      _currentCommit = 0;
      _currentlyProcessing = "Initializing Abyss...";
    });

    IsolateManager.processVaultLock(_stagedFiles, VaultService.activeKey ?? "MEM_KEY_ACTIVE");
  }

  void _finalizeCommit() async {
    VaultService.clearStaging();
    
    setState(() {
      _isCommitting = false;
      _showSuccess = true;
      _stagedFiles.clear(); 
      _currentlyProcessing = "";
    });

    await Future.delayed(const Duration(milliseconds: 1500));
    
    if (mounted) {
      setState(() => _showSuccess = false);
      _refreshFiles();
    }
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: (_isCommitting || _showSuccess) ? null : _forceLockout,
          )
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildStatsHeader(),
              if (_stagedFiles.isNotEmpty) _buildStagingArea(),
              Expanded(
                child: _buildVaultList(),
              ),
            ],
          ),
          if (_isCommitting || _showSuccess) _buildLoadingOverlay(),
        ],
      ),
      floatingActionButton: (_isCommitting || _showSuccess)
          ? null
          : FloatingActionButton.extended(
              backgroundColor: NemoPalette.electricBlue,
              onPressed: _pickFiles,
              label: const Text("SELECT FILES", style: TextStyle(color: NemoPalette.systemSlate, fontWeight: FontWeight.bold)),
              icon: const Icon(Icons.add_circle_outline, color: NemoPalette.systemSlate),
            ),
    );
  }

  // --- UI COMPONENTS ---

  Widget _buildVaultList() {
    return FutureBuilder<List<FileSystemEntity>>(
      future: _fileList,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: NemoPalette.electricBlue));
        }
        final files = snapshot.data ?? [];
        if (files.isEmpty && _stagedFiles.isEmpty) return _buildEmptyState();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: files.length,
          itemBuilder: (context, index) {
            final file = files[index] as File;
            final fileName = p.basename(file.path).replaceAll('.nemo', '');
            return Card(
              color: NemoPalette.deepOcean,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.white10,
                  child: Icon(Icons.lock_outline, color: NemoPalette.electricBlue, size: 20),
                ),
                title: Text(fileName, style: const TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text("ENCRYPTED ABYSS FILE", style: TextStyle(color: Colors.white24, fontSize: 10)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white30),
                  onPressed: () => _confirmDelete(file),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStagingArea() {
    return Container(
      height: 260,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("CARGO BAY / STAGING",
                    style: TextStyle(color: NemoPalette.electricBlue, fontWeight: FontWeight.bold, fontSize: 11)),
                _buildGhostToggle(),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                if (Platform.isWindows)
                  IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white24), onPressed: () => _scrollStagingArea(false)),
                Expanded(
                  child: ListView.builder(
                    controller: _stagingScrollController,
                    scrollDirection: Axis.horizontal,
                    itemCount: _stagedFiles.length,
                    itemBuilder: (context, index) => _buildStagedCard(_stagedFiles[index], index),
                  ),
                ),
                if (Platform.isWindows)
                  IconButton(icon: const Icon(Icons.arrow_forward_ios, color: Colors.white24), onPressed: () => _scrollStagingArea(true)),
              ],
            ),
          ),
          _buildStagingActions(),
        ],
      ),
    );
  }

  Widget _buildStagedCard(StagedItem item, int index) {
    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: NemoPalette.deepOcean.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(child: _buildTypeSpecificPreview(item)),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.fileName, style: const TextStyle(color: Colors.white, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(item.readableSize, style: const TextStyle(color: Colors.white38, fontSize: 9)),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 5, right: 5,
            child: GestureDetector(
              onTap: () => setState(() {
                VaultService.removeFromStaging(item);
                _stagedFiles.removeAt(index);
              }),
              child: const CircleAvatar(radius: 10, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 12, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSpecificPreview(StagedItem item) {
    switch (item.fileType) {
      case NemoFileType.image:
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Image.file(item.file, fit: BoxFit.cover, width: double.infinity, cacheWidth: 200),
        );
      case NemoFileType.video:
        return const Center(child: Icon(Icons.play_circle_outline, color: Colors.white30, size: 40));
      case NemoFileType.document:
        return const Center(child: Icon(Icons.description_outlined, color: NemoPalette.electricBlue, size: 40));
      default:
        return const Center(child: Icon(Icons.insert_drive_file_outlined, color: Colors.white10, size: 40));
    }
  }

  Widget _buildGhostToggle() {
    return Row(
      children: [
        const Icon(Icons.auto_fix_high, size: 14, color: Colors.white38),
        const SizedBox(width: 4),
        const Text("GHOST STRIP", style: TextStyle(color: Colors.white38, fontSize: 9)),
        Transform.scale(
          scale: 0.7,
          child: Switch(
            value: _stagedFiles.isNotEmpty && _stagedFiles.first.shouldStripMetadata,
            onChanged: (val) => setState(() {
              for (var item in _stagedFiles) {
                item.shouldStripMetadata = val;
              }
            }),
            activeThumbColor: NemoPalette.electricBlue,
          ),
        ),
      ],
    );
  }

  Widget _buildStagingActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => setState(() { _stagedFiles.clear(); VaultService.clearStaging(); }),
            child: const Text("PURGE ALL", style: TextStyle(color: Colors.redAccent, fontSize: 11)),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _handleVaultLock,
            icon: const Icon(Icons.lock, size: 14),
            label: const Text("COMMIT TO ABYSS", style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent.withOpacity(0.2), foregroundColor: Colors.greenAccent),
          ),
        ],
      ),
    );
  }

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

  Widget _buildLoadingOverlay() {
    double progress = _totalToCommit > 0 ? _currentCommit / _totalToCommit : 0;
    return Container(
      color: Colors.black.withOpacity(0.9),
      child: Center(
        child: _showSuccess ? _buildSuccessView() : _buildProgressView(progress),
      ),
    );
  }

  Widget _buildProgressView(double progress) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: NemoPalette.electricBlue),
        const SizedBox(height: 20),
        Text("SECURING $_currentCommit / $_totalToCommit FILES", 
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_currentlyProcessing, 
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
          child: LinearProgressIndicator(value: progress, backgroundColor: Colors.white10, color: NemoPalette.electricBlue),
        ),
      ],
    );
  }

  Widget _buildSuccessView() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 80),
        SizedBox(height: 20),
        Text("ABYSS SEALED", style: TextStyle(color: Colors.white, letterSpacing: 2, fontSize: 18)),
      ],
    );
  }

  void _confirmDelete(File file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NemoPalette.systemSlate,
        title: const Text("PURGE FILE?", style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          TextButton(onPressed: () async { 
            await file.delete(); 
            Navigator.pop(context); 
            _refreshFiles(); 
          }, 
            child: const Text("PURGE", style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(child: Text("THE ABYSS IS EMPTY", style: TextStyle(color: Colors.white24, letterSpacing: 2)));
  }
}