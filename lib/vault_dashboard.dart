import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'vault_service.dart';
import 'main.dart'; 
import 'package:path_provider/path_provider.dart';

class VaultDashboard extends StatefulWidget {
  const VaultDashboard({super.key});

  @override
  State<VaultDashboard> createState() => _VaultDashboardState();
}

class _VaultDashboardState extends State<VaultDashboard> {
  late Future<List<FileSystemEntity>> _fileList;
  final List<File> _stagedFiles = []; 
  
  // 🔱 Windows/Desktop Scroll Control
  final ScrollController _stagingScrollController = ScrollController();

  // 🔱 Loading & Success States
  bool _isCommitting = false;
  bool _showSuccess = false; 
  int _totalToCommit = 0;
  int _currentCommit = 0;

  @override
  void initState() {
    super.initState();
    _refreshFiles();
    findMyPhotos();
  }

  @override
  void dispose() {
    _stagingScrollController.dispose();
    super.dispose();
  }

  void _refreshFiles() {
    setState(() {
      _fileList = VaultService.listEncryptedFiles();
    });
  }

  // 🔱 Scroll Helper for Mouse/Windows Users
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

  // 🔱 Clear Staging Confirmation with Service Sync
  void _confirmClearStaging() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NemoPalette.systemSlate,
        title: const Text("PURGE STAGING AREA?", 
          style: TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 1, fontWeight: FontWeight.bold)),
        content: const Text("This will remove all selected files from the buffer. Original files will not be deleted.",
          style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _stagedFiles.clear(); 
                VaultService.clearStaging(); // 🔱 FIX: Clear the Service-level list!
              });
              Navigator.pop(context);
            },
            child: const Text("PURGE ALL", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _logout() {
    VaultService.lockVault(); 
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'entry'),
        builder: (context) => const VaultEntry(),
      ),
      (route) => false, 
    );
  }

  void _pickFiles() async {
    bool success = await VaultService.encryptAndStore();
    
    if (success && mounted) {
      setState(() {
        _stagedFiles.clear();
        _stagedFiles.addAll(VaultService.stagingArea);
      });
      debugPrint("🔱 Dashboard: Staging Area synced.");
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
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: (_isCommitting || _showSuccess) ? null : _logout,
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
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: _buildEncryptedThumbnail(file),
                            title: Text(fileName, style: const TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: const Text("SECURED", style: TextStyle(color: Colors.white24, fontSize: 10)),
                            onTap: () => _showPreview(file),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.white30, size: 20),
                              onPressed: () => (_isCommitting || _showSuccess) ? null : _confirmDelete(file),
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

          if (_isCommitting || _showSuccess) _buildLoadingOverlay(),
        ],
      ),
      floatingActionButton: (_isCommitting || _showSuccess) 
        ? null 
        : FloatingActionButton.extended(
            backgroundColor: NemoPalette.electricBlue,
            onPressed: _pickFiles,
            label: const Text("SELECT FILES", 
              style: TextStyle(color: NemoPalette.systemSlate, fontWeight: FontWeight.bold)),
            icon: const Icon(Icons.add_photo_alternate, color: NemoPalette.systemSlate),
          ),
    );
  }

  // --- 🔱 UPDATED INTERACTIVE STAGING AREA ---

  Widget _buildStagingArea() {
    // 🔱 Check for Windows to show navigation arrows
    bool isWindows = Platform.isWindows;

    return Container(
      height: 235, 
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔱 HEADER: Title (Left) and Count Tag (Right)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("STAGING AREA", 
                  style: TextStyle(color: NemoPalette.electricBlue, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
                
                // 🔱 File Count Badge (Moved to Right)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: NemoPalette.electricBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: NemoPalette.electricBlue.withOpacity(0.3))
                  ),
                  child: Text(
                    "${_stagedFiles.length} FILES SELECTED", 
                    style: const TextStyle(color: NemoPalette.electricBlue, fontSize: 9, fontWeight: FontWeight.bold)
                  ),
                ),
              ],
            ),
          ),

          // 🔱 LIST AREA
          Expanded(
            child: Row(
              children: [
                if (isWindows)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white24, size: 18),
                    onPressed: () => _scrollStagingArea(false),
                  ),
                
                Expanded(
                  child: ListView.builder(
                    controller: _stagingScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _stagedFiles.length,
                    itemBuilder: (context, index) {
                      final file = _stagedFiles[index];
                      final fileName = p.basename(file.path);

                      return Container(
                        width: 110,
                        margin: const EdgeInsets.only(right: 12),
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  height: 100, width: 110,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white10),
                                    image: DecorationImage(image: FileImage(file), fit: BoxFit.cover),
                                  ),
                                ),
                                Positioned(
                                  top: 5, right: 5,
                                  child: GestureDetector(
                                    // Locate this inside your ListView.builder inside _buildStagingArea
                                    onTap: (_isCommitting || _showSuccess) 
                                      ? null 
                                      : () => setState(() {
                                          // 🔱 Identify the file first
                                          final fileToRemove = _stagedFiles[index];
                                          
                                          // 🔱 Remove from Service FIRST using the object, not index
                                          VaultService.removeFromStaging(fileToRemove);
                                          
                                          // 🔱 Then remove from UI list
                                          _stagedFiles.removeAt(index);
                                        }),
                                    child: const CircleAvatar(
                                      radius: 12, backgroundColor: Colors.black87,
                                      child: Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                )
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              fileName, 
                              style: const TextStyle(color: Colors.white70, fontSize: 10), 
                              maxLines: 1, 
                              overflow: TextOverflow.ellipsis, 
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                if (isWindows)
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 18),
                    onPressed: () => _scrollStagingArea(true),
                  ),
              ],
            ),
          ),

          // 🔱 BOTTOM ACTIONS: Clear All and Commit moved to Bottom Right
          Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 8, top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: (_isCommitting || _showSuccess) ? null : _confirmClearStaging,
                  icon: const Icon(Icons.layers_clear, size: 14, color: Colors.redAccent),
                  label: const Text("CLEAR ALL", 
                    style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.withOpacity(0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    side: const BorderSide(color: Colors.greenAccent, width: 0.5),
                  ),
                  onPressed: (_isCommitting || _showSuccess) ? null : _handleVaultCommit,
                  icon: const Icon(Icons.security, size: 16, color: Colors.greenAccent),
                  label: const Text("COMMIT", 
                    style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
        ],
      ),
    );
  }

  // --- 🔱 LOADING & SUCCESS OVERLAY ---

  Widget _buildLoadingOverlay() {
    double progress = _totalToCommit > 0 ? _currentCommit / _totalToCommit : 0;
    
    return Container(
      color: Colors.black.withOpacity(0.9),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(opacity: animation, child: ScaleTransition(scale: animation, child: child));
          },
          child: _showSuccess 
            ? _buildSuccessView() 
            : _buildProgressView(progress),
        ),
      ),
    );
  }

  Widget _buildProgressView(double progress) {
    return Column(
      key: const ValueKey("progress_view"),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: NemoPalette.electricBlue, strokeWidth: 2),
        const SizedBox(height: 24),
        const Text("COMMITTING TO ABYSS", 
          style: TextStyle(color: Colors.white, letterSpacing: 2, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text("Securing $_currentCommit of $_totalToCommit files...", 
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 25),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 50),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white10,
                  color: NemoPalette.electricBlue,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              Text("${(progress * 100).toInt()}%", 
                style: const TextStyle(color: NemoPalette.electricBlue, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView() {
    return const Column(
      key: ValueKey("success_view"),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 100),
        SizedBox(height: 24),
        Text("VAULT SEALED", 
          style: TextStyle(color: Colors.white, letterSpacing: 4, fontWeight: FontWeight.bold, fontSize: 20)),
        SizedBox(height: 8),
        Text("Original files have been purged.", 
          style: TextStyle(color: Colors.white54, fontSize: 13)),
      ],
    );
  }

  Future<void> _handleVaultCommit() async {
    final targets = List<File>.from(_stagedFiles);
    
    setState(() {
      _isCommitting = true;
      _showSuccess = false;
      _totalToCommit = targets.length;
      _currentCommit = 0;
    });

    for (var file in targets) {
      await VaultService.encryptAndStoreSpecific(file);
      if (await file.exists()) await file.delete(); 
      setState(() => _currentCommit++);
    }
    
    setState(() {
      _isCommitting = false;
      _showSuccess = true;
      _stagedFiles.clear();
      VaultService.clearStaging(); // 🔱 Clear service after commit
    });

    await Future.delayed(const Duration(milliseconds: 1800));
    
    if (mounted) {
      setState(() => _showSuccess = false);
      _refreshFiles();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Abyss Updated Successfully"), 
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // --- 🔱 UI COMPONENTS (UNCHANGED) ---

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: const Icon(Icons.remove_red_eye, color: Colors.white38),
                title: Text(p.basename(file.path), style: const TextStyle(fontSize: 14, color: Colors.white)),
                actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))],
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _confirmDelete(File file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NemoPalette.systemSlate,
        title: const Text("PURGE FILE?"),
        content: const Text("This action is irreversible. The file will be deleted from the abyss."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          TextButton(
            onPressed: () async {
              await file.delete();
              Navigator.pop(context);
              _refreshFiles();
            },
            child: const Text("PURGE", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 80, color: NemoPalette.electricBlue.withOpacity(0.1)),
          const SizedBox(height: 16),
          const Text("THE ABYSS IS EMPTY", 
            style: TextStyle(color: Colors.white24, letterSpacing: 2, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> findMyPhotos() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory.listSync();
    for (var file in files) {
      if (file.path.endsWith('.nemo')) debugPrint("✅ Found Encrypted File: ${file.path}");
    }
  }
}