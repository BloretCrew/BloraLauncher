import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/global.dart';
import '../core/i18n.dart';
import '../models/plugin.dart';
import 'plugin_service.dart';

class PluginInstallServer {
  static HttpServer? _server;

  static Future<void> start() async {
    if (_server != null) return;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 25253);
      _server!.listen((HttpRequest request) async {
        // Handle CORS
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Accept');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        if (request.method == 'POST' && request.uri.path == '/plugin/store/propose') {
          try {
            final content = await utf8.decoder.bind(request).join();
            final payload = json.decode(content);
            
            _handlePropose(payload);

            request.response
              ..statusCode = HttpStatus.ok
              ..write(json.encode({'success': true}));
          } catch (e) {
            request.response
              ..statusCode = HttpStatus.badRequest
              ..write(json.encode({'error': e.toString()}));
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
    } catch (e) {
      debugPrint('Failed to start PluginInstallServer: $e');
    }
  }

  static void _handlePropose(Map<String, dynamic> payload) {
    if (globalShellContext == null) return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: globalShellContext!,
        barrierDismissible: false,
        builder: (context) => _PluginProposeDialog(payload: payload),
      );
    });
  }
}

class _PluginProposeDialog extends StatelessWidget {
  final Map<String, dynamic> payload;

  const _PluginProposeDialog({required this.payload});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manifest = payload['manifest'] ?? payload;
    final String name = manifest['name'] ?? "Unknown Plugin";
    final String version = manifest['version'] ?? "1.0.0";
    final String author = manifest['author'] ?? "Unknown";
    final String description = manifest['description'] ?? "";
    final List<dynamic> permissions = manifest['permissions'] ?? [];

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.extension_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text("Plugin Proposal".tl)),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              Text("${"Version".tl}: $version | ${"Author".tl}: $author", style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              if (description.isNotEmpty) ...[
                Text(description, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
              ],
              Text("Requested Permissions:".tl, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (permissions.isEmpty)
                Text("No permissions requested".tl, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: permissions.map((p) {
                    final pStr = p.toString();
                    final risk = PluginPermissions.getRisk(pStr);
                    final label = PluginPermissions.getLabel(pStr);
                    return Chip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      backgroundColor: risk == PermissionRisk.high 
                          ? Colors.redAccent.withValues(alpha: 0.1) 
                          : Colors.greenAccent.withValues(alpha: 0.1),
                      side: BorderSide(
                        color: risk == PermissionRisk.high ? Colors.redAccent : Colors.greenAccent,
                        width: 0.5,
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Please ensure you trust the source of this plugin.".tl,
                        style: const TextStyle(fontSize: 12, color: Colors.amber),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text("Cancel".tl),
        ),
        FilledButton(
          onPressed: () async {
            final List<String> requestedPermissions = List<String>.from(manifest['permissions'] ?? []);
            await PluginService.instance.installPlugin(manifest, grantedPermissions: requestedPermissions);
            if (context.mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Plugin installed successfully".tl)),
              );
            }
          },
          child: Text("Install".tl),
        ),
      ],
    );
  }
}
