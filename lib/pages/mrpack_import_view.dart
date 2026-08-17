import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/grammer_candy.dart';
import '../core/i18n.dart';
import '../services/launch_service.dart';
import '../services/modpack_service.dart';
import '../widgets/button.dart';

class MrpackImportView extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onImported;

  const MrpackImportView({
    super.key,
    required this.onBack,
    required this.onImported,
  });

  @override
  State<MrpackImportView> createState() => _MrpackImportViewState();
}

class _MrpackImportViewState extends State<MrpackImportView> {
  final _nameController = TextEditingController();
  final _pathController = TextEditingController();
  final _mcDirController = TextEditingController();

  bool _isImporting = false;
  double _progress = 0.0;
  String _status = "";
  Map<String, dynamic>? _metadata;

  @override
  void initState() {
    super.initState();
    _mcDirController.text = LaunchService.instance.getPreferredDownloadDir();
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mrpack'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() {
        _pathController.text = path;
        _status = "Analyzing modpack...".tl;
      });

      final meta = await ModpackService.getMrpackMetadata(File(path));
      if (mounted) {
        setState(() {
          _metadata = meta;
          if (_nameController.text.isEmpty && meta['name'] != null) {
            _nameController.text = meta['name'];
          } else if (_nameController.text.isEmpty) {
            _nameController.text = p.basenameWithoutExtension(path);
          }
          _status = "";
        });
      }
    }
  }

  Future<void> _startImport() async {
    if (_pathController.text.isEmpty || _nameController.text.isEmpty) {
      showWarning("Please select a file and enter a name".tl);
      return;
    }

    setState(() {
      _isImporting = true;
      _progress = 0.0;
    });

    try {
      await ModpackService.importMrpack(
        File(_pathController.text),
        _mcDirController.text,
        onProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _status = status;
              _progress = progress;
            });
          }
        },
      );
      if (mounted) {
        showSuccess("Modpack imported successfully".tl);
        widget.onImported();
      }
    } catch (e) {
      if (mounted) {
        showError("Import failed: $e".tl);
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _isImporting ? null : widget.onBack,
              ),
              const SizedBox(width: 8),
              Text(
                "Import Modrinth Modpack".tl,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (!_isImporting)
                BloretButton(
                  onPressed: _startImport,
                  text: "Start Import".tl,
                  icon: Icons.download_rounded,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                // Header section
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.dividerColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child:
                            _metadata?['iconPath'] != null &&
                                File(_metadata!['iconPath']).existsSync()
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: Image.file(
                                  File(_metadata!['iconPath']),
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Center(
                                child: Icon(
                                  Icons.inventory_2_rounded,
                                  size: 64,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nameController.text.isEmpty
                                  ? "New Modpack".tl
                                  : _nameController.text,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _metadata?['summary'] ??
                                  "Select an .mrpack file to begin importing."
                                      .tl,
                              style: TextStyle(
                                color: theme.colorScheme.outline,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.green.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    "MRPACK".tl,
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (_metadata?['minecraft'] != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    "MC ${_metadata!['minecraft']}",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (_isImporting) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: _progress,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 8),
                        Text(_status, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                _buildConfigRow(
                  theme: theme,
                  icon: Icons.file_present_rounded,
                  title: "Modpack File".tl,
                  subtitle: "The .mrpack file you want to import".tl,
                  child: Expanded(
                    child: TextField(
                      controller: _pathController,
                      readOnly: true,
                      decoration: InputDecoration(
                        hintText: "Select .mrpack file...".tl,
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  action: IconButton(
                    icon: const Icon(Icons.folder_open),
                    onPressed: _isImporting ? null : _pickFile,
                    color: theme.colorScheme.primary,
                  ),
                ),

                _buildConfigRow(
                  theme: theme,
                  icon: Icons.title_rounded,
                  title: "Instance Name".tl,
                  subtitle: "The name of the folder in versions/".tl,
                  child: Expanded(
                    child: TextField(
                      controller: _nameController,
                      onChanged: (v) => setState(() {}),
                      enabled: !_isImporting,
                      decoration: InputDecoration(
                        hintText: "Enter name...".tl,
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),

                _buildConfigRow(
                  theme: theme,
                  icon: Icons.folder_shared_rounded,
                  title: "Target Directory".tl,
                  subtitle: "The .minecraft folder location".tl,
                  child: Expanded(
                    child: TextField(
                      controller: _mcDirController,
                      enabled: !_isImporting,
                      decoration: InputDecoration(
                        hintText: "Default: .minecraft".tl,
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  action: IconButton(
                    icon: const Icon(Icons.folder_open),
                    onPressed: _isImporting
                        ? null
                        : () async {
                            String? path = await FilePicker.platform
                                .getDirectoryPath();
                            if (path != null) {
                              setState(() => _mcDirController.text = path);
                            }
                          },
                    color: theme.colorScheme.primary,
                  ),
                ),

                if (_metadata != null) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      "Modpack Contents".tl,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildContentDropdown(
                    title: "Mods".tl,
                    icon: Icons.extension_rounded,
                    items: List<String>.from(_metadata!['mods'] ?? []),
                    theme: theme,
                  ),
                  _buildContentDropdown(
                    title: "Resource Packs".tl,
                    icon: Icons.palette_rounded,
                    items: List<String>.from(_metadata!['resourcePacks'] ?? []),
                    theme: theme,
                  ),
                  _buildContentDropdown(
                    title: "Shader Packs".tl,
                    icon: Icons.wb_sunny_rounded,
                    items: List<String>.from(_metadata!['shaderPacks'] ?? []),
                    theme: theme,
                  ),
                ],

                const SizedBox(height: 64),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentDropdown({
    required String title,
    required IconData icon,
    required List<String> items,
    required ThemeData theme,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 18),
            ),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            subtitle: Text(
              "${items.length} ${"items".tl}",
              style: TextStyle(fontSize: 10, color: theme.colorScheme.outline),
            ),
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _buildItemTile(items[index], icon, theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemTile(String name, IconData icon, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigRow({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 160,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          child,
          if (action != null) ...[const SizedBox(width: 8), action],
        ],
      ),
    );
  }
}
