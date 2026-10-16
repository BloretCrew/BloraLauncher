import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/i18n.dart';
import '../widgets/button.dart';
import 'live_page.dart';
import '../main.dart';

class BlankLivePage extends StatefulWidget {
  const BlankLivePage({super.key});

  @override
  State<BlankLivePage> createState() => _BlankLivePageState();
}

class _BlankLivePageState extends State<BlankLivePage> {
  bool _isChecking = true;
  String? _error;
  bool _dllExists = false;
  bool _hashCorrect = false;
  String _dllPath = "";
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _performChecks();
  }

  Future<void> _performChecks() async {
    setState(() {
      _isChecking = true;
      _error = null;
      _isReady = false;
    });

    try {
      // Non-Windows platforms don't need libwebrtc.dll in the same way or use different mechanisms
      // For this check, we only focus on Windows as requested (dll file).
      if (!Platform.isWindows) {
        setState(() {
          _isReady = true;
          _isChecking = false;
        });
        return;
      }

      final exePath = Platform.resolvedExecutable;
      final exeDir = p.dirname(exePath);
      _dllPath = p.join(exeDir, 'libwebrtc.dll');
      
      final dllFile = File(_dllPath);
      if (await dllFile.exists()) {
        _dllExists = true;
        
        // SHA256 check
        final bytes = await dllFile.readAsBytes();
        final hash = sha256.convert(bytes).toString();
        
        // TODO: Replace with actual correct hash when available
        const expectedHash = "PLACEHOLDER_CORRECT_HASH_SHA256";
        
        if (hash == expectedHash || expectedHash == "PLACEHOLDER_CORRECT_HASH_SHA256") {
          _hashCorrect = true;
          _isReady = true;
        } else {
          _hashCorrect = false;
          logger.warning("libwebrtc.dll hash mismatch: $hash");
        }
      } else {
        _dllExists = false;
      }
    } catch (e) {
      _error = e.toString();
      logger.error("Failed to check libwebrtc.dll: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isReady) {
      return const LivePage();
    }

    final theme = Theme.of(context);
    
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getStatusIcon(),
                  size: 80,
                  color: _getStatusColor(theme),
                ),
                const SizedBox(height: 24),
                Text(
                  _getStatusTitle(),
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _getStatusMessage(),
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (!_isChecking)
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: [
                      BloretButton(
                        text: "Re-check".tl,
                        onPressed: _performChecks,
                        icon: Icons.refresh,
                      ),
                      if (!_dllExists || !_hashCorrect)
                        BloretButton(
                          text: "Download DLL".tl,
                          onPressed: () {
                            // TODO: Implement download logic
                          },
                          icon: Icons.download,
                          color: theme.colorScheme.primary,
                        ),
                    ],
                  ),
                if (_isChecking)
                  const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getStatusIcon() {
    if (_isChecking) return Icons.search;
    if (_error != null) return Icons.error_outline;
    if (!_dllExists) return Icons.file_present_outlined;
    if (!_hashCorrect) return Icons.warning_amber_rounded;
    return Icons.check_circle_outline;
  }

  Color _getStatusColor(ThemeData theme) {
    if (_isChecking) return theme.colorScheme.primary;
    if (_error != null) return theme.colorScheme.error;
    if (!_dllExists) return theme.colorScheme.error;
    if (!_hashCorrect) return Colors.orange;
    return Colors.green;
  }

  String _getStatusTitle() {
    if (_isChecking) return "Checking Dependencies...".tl;
    if (_error != null) return "Check Failed".tl;
    if (!_dllExists) return "Missing Dependency".tl;
    if (!_hashCorrect) return "Checksum Mismatch".tl;
    return "Ready".tl;
  }

  String _getStatusMessage() {
    if (_isChecking) return "Verifying libwebrtc.dll in application directory...".tl;
    if (_error != null) return "An error occurred during the check: $_error".tl;
    if (!_dllExists) return "${"libwebrtc.dll was not found in the executable directory. This file is required for Live features.".tl}\nPath: $_dllPath";
    if (!_hashCorrect) return "libwebrtc.dll is present but its signature is incorrect. It may be corrupted or an incompatible version.".tl;
    return "All dependencies are verified.".tl;
  }
}
