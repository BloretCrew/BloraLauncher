import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/grammer_candy.dart';
import '../core/i18n.dart';
import '../services/external_app_service.dart';
import '../widgets/button.dart';
import '../widgets/process_picker_dialog.dart';
import '../widgets/windows_widgets.dart';

class ExternalAppEditorView extends StatefulWidget {
  final CustomApp? app;
  final VoidCallback onBack;
  final VoidCallback onSaved;

  const ExternalAppEditorView({
    super.key,
    this.app,
    required this.onBack,
    required this.onSaved,
  });

  @override
  State<ExternalAppEditorView> createState() => _ExternalAppEditorViewState();
}

class _ExternalAppEditorViewState extends State<ExternalAppEditorView> {
  final _nameController = TextEditingController();
  final _pathController = TextEditingController();
  final _argsController = TextEditingController();
  final _workingDirController = TextEditingController();
  final _envVarsController = TextEditingController();
  bool _runAsAdmin = false;
  bool _killOnExit = false;
  String _priority = "Normal";
  String? _currentIconPath;

  bool _isAttachMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.app != null) {
      final app = widget.app!;
      _nameController.text = app.name;
      _pathController.text = app.exePath;
      _argsController.text = app.args;
      _workingDirController.text = app.workingDir ?? "";
      _envVarsController.text = app.envVars;
      _runAsAdmin = app.runAsAdmin;
      _killOnExit = app.killOnExit;
      _priority = app.priority;
      _currentIconPath = app.iconPath;
    }
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['exe', 'bat', 'cmd', 'sh', 'zip', 'jar'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() {
        _pathController.text = path;
        if (_nameController.text.isEmpty) {
          _nameController.text = p.basenameWithoutExtension(path);
        }
        if (_workingDirController.text.isEmpty) {
          _workingDirController.text = p.dirname(path);
        }
      });

      final String? iconPath = await ExternalAppService.instance.extractIcon(
        path,
      );
      if (iconPath != null) {
        setState(() => _currentIconPath = iconPath);
      }
    }
  }

  Future<void> _showProcessPicker() async {
    showDialog(
      context: context,
      builder: (context) => ProcessPickerDialog(
        onSelected: (proc) async {
          final pid = proc['ProcessId'];
          final name = proc['Name'];
          final exePath = proc['ExecutablePath'];

          setState(() {
            _pathController.text = pid.toString();
            _nameController.text = name;
            _workingDirController.text = exePath != null
                ? p.dirname(exePath)
                : "";
          });

          if (exePath != null) {
            final icon = await ExternalAppService.instance.extractIcon(exePath);
            if (mounted) setState(() => _currentIconPath = icon);
          }
        },
      ),
    );
  }

  Future<void> _saveApp() async {
    if (_nameController.text.isEmpty || _pathController.text.isEmpty) {
      showWarning("Name and Path are required".tl);
      return;
    }

    final apps = ExternalAppService.instance.getCustomApps();
    if (widget.app == null) {
      // Check for duplicate name only when adding new
      if (apps.any((e) => e.name == _nameController.text)) {
        showWarning("An application with this name already exists".tl);
        return;
      }
    }

    final appData = CustomApp(
      id: widget.app?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      exePath: _pathController.text,
      iconPath: _currentIconPath,
      args: _argsController.text,
      workingDir: _workingDirController.text,
      runAsAdmin: _runAsAdmin,
      priority: _priority,
      envVars: _envVarsController.text,
      killOnExit: _killOnExit,
    );

    if (widget.app != null) {
      final apps = ExternalAppService.instance.getCustomApps();
      final index = apps.indexWhere((e) => e.id == widget.app!.id);
      if (index != -1) {
        apps[index] = appData;
        await ExternalAppService.instance.saveCustomApps(apps);
      }
    } else {
      await ExternalAppService.instance.addApp(appData);
    }

    widget.onSaved();
    showSuccess("Application saved".tl);
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
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 8),
              Text(
                widget.app == null
                    ? "Add Custom App".tl
                    : "Edit Application".tl,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              BloretButton(
                onPressed: _saveApp,
                text: "Save Configuration".tl,
                icon: Icons.check,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                // Top section mimicking JavaSelectorView Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          FilePickerResult? result = await FilePicker.platform
                              .pickFiles(type: FileType.image);
                          if (result != null) {
                            setState(
                              () => _currentIconPath = result.files.single.path,
                            );
                          }
                        },
                        child: Container(
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
                              _currentIconPath != null &&
                                  File(_currentIconPath!).existsSync()
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(11),
                                  child: Image.file(
                                    File(_currentIconPath!),
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_a_photo_outlined,
                                      size: 48,
                                      color: theme.colorScheme.outline,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Change Icon".tl,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.outline,
                                      ),
                                    ),
                                  ],
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
                                  ? "New Custom Application".tl
                                  : _nameController.text,
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "A standalone core that doesn't follow Minecraft versioning."
                                  .tl,
                              style: TextStyle(
                                color: theme.colorScheme.outline,
                              ),
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
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.blue.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    (_pathController.text
                                                .toLowerCase()
                                                .endsWith(".zip") ||
                                            _pathController.text
                                                .toLowerCase()
                                                .endsWith(".jar")
                                        ? "MODPACK".tl
                                        : "EXTERNAL".tl),
                                    style: TextStyle(
                                      color:
                                          _pathController.text
                                                  .toLowerCase()
                                                  .endsWith(".zip") ||
                                              _pathController.text
                                                  .toLowerCase()
                                                  .endsWith(".jar")
                                          ? Colors.green
                                          : Colors.blue,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Configuration Rows mimicking JavaSelectorView List
                _buildConfigRow(
                  theme: theme,
                  icon: _isAttachMode
                      ? Icons.add_link_rounded
                      : Icons.terminal_rounded,
                  title: _isAttachMode ? "Attached PID".tl : "Program Path".tl,
                  subtitle: _isAttachMode
                      ? "Track existing process".tl
                      : "Executable or Archive (.exe, .bat, .zip, .jar)".tl,
                  child: Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: TextField(
                        key: ValueKey(_isAttachMode),
                        controller: _pathController,
                        onChanged: (v) => setState(() {}),
                        keyboardType: _isAttachMode
                            ? TextInputType.number
                            : TextInputType.text,
                        decoration: InputDecoration(
                          hintText: _isAttachMode
                              ? "Enter PID...".tl
                              : "Select or enter path...".tl,
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          _isAttachMode
                              ? Icons.search_rounded
                              : Icons.folder_open,
                        ),
                        onPressed: _isAttachMode
                            ? _showProcessPicker
                            : _pickFile,
                        color: theme.colorScheme.primary,
                        tooltip: _isAttachMode
                            ? "Pick from running processes".tl
                            : "Browse file".tl,
                      ),
                      Container(
                        width: 1,
                        height: 20,
                        color: theme.dividerColor.withValues(alpha: 0.1),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      IconButton(
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Icon(
                            _isAttachMode
                                ? Icons.edit_note_rounded
                                : Icons.link_rounded,
                            key: ValueKey(_isAttachMode),
                          ),
                        ),
                        onPressed: () => setState(() {
                          _isAttachMode = !_isAttachMode;
                          _pathController.clear();
                        }),
                        tooltip: _isAttachMode
                            ? "Switch to Path mode".tl
                            : "Switch to Attach mode".tl,
                      ),
                    ],
                  ),
                ),

                if (_pathController.text.isNotEmpty) ...[
                  _buildConfigRow(
                    theme: theme,
                    icon: Icons.title_rounded,
                    title: "Display Name".tl,
                    subtitle: "The name shown in the launcher".tl,
                    child: Expanded(
                      child: TextField(
                        controller: _nameController,
                        onChanged: (v) => setState(() {}),
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
                    icon: Icons.code_rounded,
                    title: "Launch Arguments".tl,
                    subtitle: "Command line parameters for the app".tl,
                    child: Expanded(
                      child: TextField(
                        controller: _argsController,
                        decoration: InputDecoration(
                          hintText: "e.g. --windowed --server 127.0.0.1".tl,
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),

                  _buildConfigRow(
                    theme: theme,
                    icon: Icons.folder_open_rounded,
                    title: "Working Directory".tl,
                    subtitle: "Folder where the process starts".tl,
                    child: Expanded(
                      child: TextField(
                        controller: _workingDirController,
                        decoration: InputDecoration(
                          hintText: "Default: program directory".tl,
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    action: IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: () async {
                        String? path = await FilePicker.platform
                            .getDirectoryPath();
                        if (path != null)
                          setState(() => _workingDirController.text = path);
                      },
                      color: theme.colorScheme.primary,
                    ),
                  ),

                  _buildConfigRow(
                    theme: theme,
                    icon: Icons.settings_input_component_rounded,
                    title: "Env Variables".tl,
                    subtitle: "e.g. KEY=VAL;PATH=%PATH%".tl,
                    child: Expanded(
                      child: TextField(
                        controller: _envVarsController,
                        decoration: InputDecoration(
                          hintText:
                              "Semi-colon separated environment variables".tl,
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),

                  _buildConfigRow(
                    theme: theme,
                    icon: Icons.speed_rounded,
                    title: "Process Priority".tl,
                    subtitle: "System scheduling priority".tl,
                    child: Win11Dropdown(
                      width: 160,
                      initialValue: _priority,
                      items: ["Idle", "Normal", "High", "Realtime"]
                          .map((e) => Win11DropdownItem(label: e.tl, value: e))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _priority = v);
                      },
                    ),
                  ),

                  _buildConfigRow(
                    theme: theme,
                    icon: Icons.admin_panel_settings_rounded,
                    title: "Run as Administrator".tl,
                    subtitle: "Elevate process privileges on launch".tl,
                    child: Switch(
                      value: _runAsAdmin,
                      onChanged: (v) => setState(() => _runAsAdmin = v),
                    ),
                  ),

                  _buildConfigRow(
                    theme: theme,
                    icon: Icons.link_rounded,
                    title: "Strongly Attached Process".tl,
                    subtitle:
                        "Automatically terminate this process when Blora Launcher closes"
                            .tl,
                    child: Switch(
                      value: _killOnExit,
                      onChanged: (v) => setState(() => _killOnExit = v),
                    ),
                  ),

                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        if (widget.app != null)
                          TextButton.icon(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text("Delete App".tl),
                                  content: Text(
                                    "Are you sure you want to delete this custom application?"
                                        .tl,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: Text("Cancel".tl),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: Text(
                                        "Delete".tl,
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await ExternalAppService.instance.removeApp(
                                  widget.app!.id,
                                );
                                widget.onSaved();
                              }
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                            label: Text(
                              "Delete Application".tl,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: widget.onBack,
                          child: Text("Discard changes".tl),
                        ),
                      ],
                    ),
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
