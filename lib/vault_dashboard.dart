import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

// 🔱 Flattened Imports
import 'vault_service.dart';
import 'isolate_manager.dart';
import 'staged_item.dart';
import 'main.dart';
import 'archive_panel.dart';

class VaultDashboard extends StatefulWidget {
  const VaultDashboard({super.key});

  @override
  State<VaultDashboard> createState() => _VaultDashboardState();
}

class _VaultDashboardState extends State<VaultDashboard> with WidgetsBindingObserver {
  late Future<List<FileSystemEntity>> _fileList = VaultService.listEncryptedFiles();
  final List<StagedItem> _stagedFiles = [];
  final ScrollController _stagingScrollController = ScrollController();

  // 🔱 Trigger key to force FutureBuilder refresh
  Key _statsKey = UniqueKey();

  bool _isCommitting = false;
  bool _showSuccess = false;
  int _totalToCommit = 0;
  int _currentCommit = 0;
  String _currentlyProcessing = ""; 
  int _selectedNavIndex = 0; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _initVault();
  }

  void _initVault() async {
    await IsolateManager.start();
    _checkPermissions();
    _listenToProgress();
    _refreshFiles();
    _updateStagedList(); // Initial sync
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 🔱 PHYSICAL SYNC: If we resume and files were purged by auto-lock/background logic, 
      // refresh the list immediately to remove black boxes.
      _updateStagedList();
    }

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (VaultService.isProcessing || VaultService.isSystemDialogActive) return;
      if (VaultService.isUnlocked()) _forceLockout();
    }
  }

  /// 🔱 Reality Filter: Ensures UI only holds items that actually exist on disk
  void _updateStagedList() {
    if (!mounted) return;
    setState(() {
      _stagedFiles.clear();
      // Only add items if the physical file is still in staging_internal
      _stagedFiles.addAll(
        VaultService.stagingArea.where((item) => item.file.existsSync())
      );
    });
  }

  void _forceLockout() {
    VaultService.lockVault();
    if (mounted) Navigator.pushReplacementNamed(context, 'entry');
  }

  void _checkPermissions() async {
    if (Platform.isAndroid) {
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) await Permission.manageExternalStorage.request();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stagingScrollController.dispose();
    super.dispose();
  }

  void _refreshFiles() {
    setState(() {
      _statsKey = UniqueKey(); 
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
          if (_currentCommit >= _totalToCommit && _isCommitting) _finalizeCommit();
        }
      });
    });
  }

  void _scrollStagingArea(bool forward) {
    if (!_stagingScrollController.hasClients) return;
    double target = _stagingScrollController.offset + (forward ? 300 : -300);
    _stagingScrollController.animateTo(
      target.clamp(0.0, _stagingScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  void _pickFiles() async {
    setState(() => VaultService.isSystemDialogActive = true); 
    try {
      bool success = await VaultService.encryptAndStore();
      if (success && mounted) {
        _updateStagedList();
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) setState(() => VaultService.isSystemDialogActive = false);
    }
  }

  Future<void> _handleVaultLock() async {
    // 🔱 Re-verify list before locking to skip ghosts
    _updateStagedList();
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
    final int count = _totalToCommit;
    VaultService.clearStaging();
    setState(() {
      _isCommitting = false;
      _showSuccess = true;
      _stagedFiles.clear(); 
    });
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      setState(() => _showSuccess = false);
      _refreshFiles();
      _showAbyssToast(context, count); 
    }
  }

  void _showAbyssToast(BuildContext context, int count) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 120, 
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.amber[900]?.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "$count items moved to Abyss. Delete originals manually.",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 4), () => overlayEntry.remove());
  }

  void _openArchive() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: ArchivePanel(
          onContentChanged: _updateDashboardStats,
        ),
      ),
    );
  }

  void _updateDashboardStats() {
    setState(() {
      _statsKey = UniqueKey();
      _fileList = VaultService.listEncryptedFiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NemoPalette.systemSlate,
      body: Stack(
        alignment: Alignment.center,
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildCustomAppBar(),
                _buildStatsHeader(),
                const SizedBox(height: 15),
                Expanded(child: _buildMainStagingArea()),
                const SizedBox(height: 100), 
              ],
            ),
          ),
          Positioned(
            bottom: 30,
            child: _buildFloatingBottomNav(),
          ),
          if (_isCommitting || _showSuccess) _buildLoadingOverlay(),
        ],
      ),
    );
  }

Widget _buildCustomAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              // 🔱 Custom Shield Asset replacement
              Image.asset(
                'assets/images/shield.png',
                width: 48,
                height: 48,
                fit: BoxFit.contain,
                // Optional: If your png is white/grayscale and you want to keep the electricBlue theme
                // color: NemoPalette.electricBlue, 
              ),
              const SizedBox(width: 12),
              const Text(
                "NEMO VAULT",
                style: TextStyle(
                  letterSpacing: 3,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: (_isCommitting || _showSuccess) ? null : _forceLockout,
          )
        ],
      ),
    );
  }

  Widget _buildStatsHeader() {
    return FutureBuilder<List<FileSystemEntity>>(
      key: _statsKey, 
      future: _fileList,
      builder: (context, snapshot) {
        int count = snapshot.data?.length ?? 0;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: NemoPalette.deepOcean.withAlpha(204),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NemoPalette.electricBlue.withAlpha(51)),
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
        Icon(icon, color: NemoPalette.electricBlue, size: 18),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildMainStagingArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: NemoPalette.deepOcean.withAlpha(204),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NemoPalette.electricBlue.withAlpha(51)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 10, top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("STAGING AREA", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
                _buildGhostToggle(),
              ],
            ),
          ),
          Expanded(
            child: _stagedFiles.isEmpty 
              ? const Center(child: Icon(Icons.move_to_inbox_outlined, size: 40, color: Colors.white10))
              : Stack(
                  children: [
                    GridView.builder(
                      controller: _stagingScrollController,
                      padding: const EdgeInsets.all(15),
                      scrollDirection: Axis.horizontal,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, 
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.1,
                      ),
                      itemCount: _stagedFiles.length,
                      itemBuilder: (context, index) {
                        final item = _stagedFiles[index];
                        // 🔱 GHOST SHIELD: Double-check physical presence before building the card
                        if (!item.file.existsSync()) {
                           return const SizedBox.shrink();
                        }
                        return _buildStagedCard(item, index);
                      },
                    ),
                    if (Platform.isWindows || Platform.isMacOS) ...[
                      Positioned(left: 0, top: 0, bottom: 0, child: Center(child: IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white30), onPressed: () => _scrollStagingArea(false)))),
                      Positioned(right: 0, top: 0, bottom: 0, child: Center(child: IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white30), onPressed: () => _scrollStagingArea(true)))),
                    ]
                  ],
                ),
          ),
          if (_stagedFiles.isNotEmpty) _buildStagingActions(),
        ],
      ),
    );
  }

  Widget _buildStagedCard(StagedItem item, int index) {
    return Container(
      decoration: BoxDecoration(
        color: NemoPalette.deepOcean,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildTypeSpecificPreview(item)),
              Padding(
                padding: const EdgeInsets.all(6.0),
                child: Text(item.fileName, style: const TextStyle(color: Colors.white70, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          Positioned(
            top: 5, 
            right: 5, 
            child: GestureDetector(
              onTap: () {
                // 🔱 ATOMIC FIX: Remove from service (Physical) then refresh UI (RAM)
                VaultService.removeFromStaging(item); 
                _updateStagedList();
              },
              child: const CircleAvatar(
                radius: 10,
                backgroundColor: Colors.white,
                child: Icon(Icons.cancel, size: 18, color: Colors.redAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSpecificPreview(StagedItem item) {
    // 🔱 Check if file is still there before trying to build a preview
    if (item.fileType == NemoFileType.image && item.file.existsSync()) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), 
        child: Image.file(item.file, fit: BoxFit.cover, errorBuilder: (c, e, s) => _errorPreview())
      );
    }
    return _errorPreview();
  }

  Widget _errorPreview() {
    return Center(child: Icon(Icons.insert_drive_file, color: NemoPalette.electricBlue.withAlpha(127)));
  }

  Widget _buildGhostToggle() {
    return Row(
      children: [
        const Text("GHOST", style: TextStyle(color: Colors.white38, fontSize: 10)),
        Transform.scale(
          scale: 0.7,
          child: Switch(
            value: _stagedFiles.isNotEmpty && _stagedFiles.first.shouldStripMetadata,
            onChanged: (val) => setState(() { for (var item in _stagedFiles) { item.shouldStripMetadata = val; } }),
            activeThumbColor: NemoPalette.electricBlue,
            activeTrackColor: NemoPalette.electricBlue.withOpacity(0.3),
          ),
        ),
      ],
    );
  }

  Widget _buildStagingActions() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: _handleVaultLock,
            child: const Text("SEAL ABYSS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          )),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () { 
              VaultService.clearStaging(); 
              _updateStagedList();
            }, 
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent)
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingBottomNav() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.75,
      height: 65,
      decoration: BoxDecoration(
        color: NemoPalette.deepOcean.withAlpha(242),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navItem(Icons.person_outline, 0),
          FloatingActionButton(
            mini: true,
            elevation: 0,
            backgroundColor: NemoPalette.electricBlue,
            onPressed: _pickFiles,
            child: const Icon(Icons.add, color: Colors.black),
          ),
          _navItem(Icons.grid_view_rounded, 2),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, int index) {
    bool isSelected = _selectedNavIndex == index;
    return IconButton(
      icon: Icon(icon, color: isSelected ? NemoPalette.electricBlue : Colors.white24),
      onPressed: () {
        setState(() => _selectedNavIndex = index);
        if (index == 2) {
          _openArchive();
        }
      },
    );
  }

  Widget _buildLoadingOverlay() {
    double progress = _totalToCommit > 0 ? _currentCommit / _totalToCommit : 0.0;

    return Container(
      color: Colors.black.withAlpha(230),
      child: Center(
        child: _showSuccess 
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 80),
                SizedBox(height: 20),
                Text("ABYSS SEALED", style: TextStyle(color: Colors.white, letterSpacing: 2)),
              ],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: NemoPalette.electricBlue),
                  const SizedBox(height: 30),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.white10,
                      color: NemoPalette.electricBlue,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text("SECURING $_currentCommit / $_totalToCommit", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_currentlyProcessing, style: const TextStyle(color: Colors.white38, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
      ),
    );
  }
}