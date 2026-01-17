import 'dart:io';
import 'package:flutter/material.dart';
import 'vault_service.dart';
import 'isolate_manager.dart';
import 'main.dart';
import 'secure_viewer.dart';

class ArchivePanel extends StatefulWidget {
  final VoidCallback onContentChanged;
  const ArchivePanel({super.key, required this.onContentChanged});

  @override
  State<ArchivePanel> createState() => _ArchivePanelState();
}

class _ArchivePanelState extends State<ArchivePanel> {
  late Future<List<FileSystemEntity>> _vaultFiles;
  final Set<String> _selectedPaths = {};
  bool _isSelectionMode = false;
  String _activeFilter = "ALL";

  final List<String> _filters = ["ALL", "IMAGES", "VIDEOS", "DOCS"];

  @override
  void initState() {
    super.initState();
    _refreshArchive();
  }

  void _refreshArchive() {
    setState(() {
      _selectedPaths.clear();
      _isSelectionMode = false;
      _vaultFiles = VaultService.listEncryptedFiles();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onContentChanged();
      }
    });
  }

  bool _matchesFilter(String fileName) {
    if (_activeFilter == "ALL") return true;
    final ext = fileName.split('.').last.toLowerCase();
    if (_activeFilter == "IMAGES") return ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext);
    if (_activeFilter == "VIDEOS") return ['mp4', 'mkv', 'mov', 'avi'].contains(ext);
    if (_activeFilter == "DOCS") return ['pdf', 'txt', 'doc', 'docx'].contains(ext);
    return false;
  }

  Future<void> _handleDelete(Set<String> paths) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NemoPalette.systemSlate,
        title: const Text("PERMANENT WIPE", style: TextStyle(color: Colors.redAccent, letterSpacing: 2)),
        content: Text("Are you sure you want to delete ${paths.length} items? This cannot be undone.", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("DELETE"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (var path in paths) {
        await VaultService.secureDeleteFile(path);
      }
      _refreshArchive();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onContentChanged();
        }
      });
    }
  }

  Future<void> _handleReveal(File file) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: NemoPalette.electricBlue)),
    );

    try {
      final String? key = VaultService.activeKey;
      if (key == null) throw Exception("Vault Locked");
      final bytes = await IsolateManager.decryptFileOnDemand(file, key);
      if (mounted) Navigator.pop(context);
      if (bytes != null && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SecureViewer(
              fileName: VaultService.getCleanName(file.path),
              fileBytes: bytes,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showError("Abyss Breach Failed: ${e.toString()}");
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // 🔱 Mod: Background now matches the main Vault background
        color: NemoPalette.systemSlate,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
          _buildHeader(),
          _buildFilterBar(),
          const Divider(color: Colors.white10, height: 1),
          Expanded(child: _buildFileList()),
          if (_isSelectionMode) _buildSelectionActionBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_isSelectionMode ? "${_selectedPaths.length} SELECTED" : "CARGO HOLD", 
            style: TextStyle(color: _isSelectionMode ? NemoPalette.electricBlue : Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 18)),
          _isSelectionMode 
            ? IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _isSelectionMode = false))
            : IconButton(icon: const Icon(Icons.refresh, color: NemoPalette.electricBlue), onPressed: _refreshArchive),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: _filters.map((f) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            label: Text(f, style: TextStyle(fontSize: 10, color: _activeFilter == f ? Colors.black : Colors.white60)),
            selected: _activeFilter == f,
            onSelected: (val) => setState(() => _activeFilter = f),
            backgroundColor: Colors.white10,
            selectedColor: NemoPalette.electricBlue,
            showCheckmark: false,
            // 🔱 Mod: Filter side border to match staging area
            side: BorderSide(color: _activeFilter == f ? NemoPalette.electricBlue : Colors.white.withValues(alpha: 0.1)),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildFileList() {
    return FutureBuilder<List<FileSystemEntity>>(
      future: _vaultFiles,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: NemoPalette.electricBlue));
        }
        
        final filteredList = (snapshot.data ?? []).where((e) => _matchesFilter(VaultService.getCleanName(e.path))).toList();

        if (filteredList.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined, size: 64, color: Colors.white.withValues(alpha: 0.05)),
                const SizedBox(height: 16),
                const Text("CARGO HOLD EMPTY", style: TextStyle(color: Colors.white24, letterSpacing: 1.5, fontSize: 12)),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: filteredList.length,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
          itemBuilder: (context, index) {
            final file = filteredList[index] as File;
            final cleanName = VaultService.getCleanName(file.path);
            final isSelected = _selectedPaths.contains(file.path);

            return GestureDetector(
              onLongPress: () => setState(() {
                _isSelectionMode = true;
                _selectedPaths.add(file.path);
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  // 🔱 Mod: Background now matches staging area (deepOcean with alpha 204)
                  color: isSelected 
                      ? NemoPalette.electricBlue.withValues(alpha: 0.1) 
                      : NemoPalette.deepOcean.withAlpha(204),
                  borderRadius: BorderRadius.circular(12),
                  // 🔱 Mod: Border color now matches staging area
                  border: Border.all(color: isSelected ? NemoPalette.electricBlue : Colors.white.withValues(alpha: 0.1)),
                ),
                child: ListTile(
                  onTap: _isSelectionMode ? () => setState(() => isSelected ? _selectedPaths.remove(file.path) : _selectedPaths.add(file.path)) : null,
                  leading: _isSelectionMode 
                    ? Checkbox(
                        value: isSelected, 
                        onChanged: (v) => setState(() => v! ? _selectedPaths.add(file.path) : _selectedPaths.remove(file.path)),
                        activeColor: NemoPalette.electricBlue,
                        side: const BorderSide(color: Colors.white30),
                      )
                    : const Icon(Icons.insert_drive_file_outlined, color: Colors.white38),
                  title: Text(cleanName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1),
                  subtitle: Text("${(file.statSync().size / 1024).toStringAsFixed(1)} KB", style: const TextStyle(color: Colors.white30, fontSize: 10)),
                  trailing: _isSelectionMode 
                    ? null 
                    : IconButton(icon: const Icon(Icons.remove_red_eye_outlined, color: Colors.greenAccent, size: 20), onPressed: () => _handleReveal(file)),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSelectionActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        border: const Border(top: BorderSide(color: Colors.redAccent, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent, 
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _selectedPaths.isEmpty ? null : () => _handleDelete(_selectedPaths),
                icon: const Icon(Icons.delete_forever),
                label: const Text("PURGE SELECTED", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}