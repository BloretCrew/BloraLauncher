import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../pages/mods_page.dart';
import '../services/config_service.dart';

class CoreIcon extends StatelessWidget {
  final Map<String, dynamic> item;
  final double size;

  const CoreIcon({
    super.key,
    required this.item,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = item['id']?.toString() ?? '';
    final directory = item['directory']?.toString() ?? '';
    final type = item['type']?.toString() ?? 'minecraft';
    final uniqueId = item['unique_id']?.toString() ?? id;
    final loaderType = item['loader_type']?.toString();

    final String selectedIcon =
        item['bl_instance_icon']?.toString() ?? ConfigService.get('instance_icon_$uniqueId') ?? "Auto";
    final String category =
        item['bl_instance_category']?.toString() ?? ConfigService.get('instance_category_$uniqueId') ?? "Standard";

    if (selectedIcon != "Auto") {
      return _buildAssetIcon(theme, selectedIcon, size);
    }

    if (item['force_accelerated'] == true || item['force_accelerated'] == "true") {
      return _buildAssetIcon(theme, "bloret_light", size);
    }

    if (type == "minecraft") {
      final iconPath = p.join(directory, "versions", id, "icon.png");
      final iconFile = File(iconPath);
      if (iconFile.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.2),
          child: Image.file(
            iconFile,
            fit: BoxFit.cover,
            width: size,
            height: size,
          ),
        );
      }
    } else if (type == "custom_app") {
      final icon = item['icon']?.toString();
      if (icon != null && icon.isNotEmpty && File(icon).existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.2),
          child: Image.file(
            File(icon),
            fit: BoxFit.cover,
            width: size,
            height: size,
          ),
        );
      }
    }

    // Loader auto-detection (Absolute Path based via LaunchService)
    if (loaderType != null) {
      if (loaderType == "fabric") return _buildAssetIcon(theme, "fabric", size);
      if (loaderType == "neoforge") return _buildAssetIcon(theme, "neoforge", size);
      if (loaderType == "forge") return _buildAssetIcon(theme, "forge", size);
      if (loaderType == "quilt") return _buildGenericIcon(Icons.grid_view, Colors.purple, size);
    }

    final lowerId = id.toLowerCase();
    if (lowerId.contains("fabric")) return _buildAssetIcon(theme, "fabric", size);
    if (lowerId.contains("neoforge")) return _buildAssetIcon(theme, "neoforge", size);
    if (lowerId.contains("forge")) return _buildAssetIcon(theme, "forge", size);
    if (lowerId.contains("quilt")) return _buildGenericIcon(Icons.grid_view, Colors.purple, size);

    if (lowerId.startsWith("1.21")) return _buildGenericIcon(CupertinoIcons.cube, Colors.orange, size);
    if (lowerId.startsWith("1.20")) return _buildGenericIcon(Icons.bakery_dining, Colors.pinkAccent, size);
    if (lowerId.startsWith("1.19")) return _buildGenericIcon(Icons.forest, Colors.green, size);
    if (lowerId.startsWith("1.18")) return _buildGenericIcon(Icons.landscape, Colors.blue, size);
    if (lowerId.startsWith("1.17")) return _buildGenericIcon(Icons.diamond_outlined, Colors.purpleAccent, size);
    if (lowerId.startsWith("1.16")) return _buildGenericIcon(Icons.whatshot, Colors.redAccent, size);
    if (lowerId.startsWith("1.12")) return _buildGenericIcon(Icons.history, Colors.brown, size);
    if (lowerId.startsWith("1.8")) return _buildGenericIcon(Icons.verified, Colors.cyan, size);

    final jokes = {'26w14a', '25w14craftmine', '23w13a_or_b', '24w14spoiler', '24w14potato', '22w13oneblockatatime', '20w14infinite', '3D Shareware v1.34', '1.RV-Pre1', '15w14a', '2.0'};
    if (jokes.contains(id) || lowerId.contains('love') || lowerId.contains('joke') || lowerId.contains('spoiler')) {
      return _buildGenericIcon(Icons.celebration_outlined, Colors.purple, size);
    }

    final versionType = item['version_type']?.toString();
    if (versionType == "old_beta" || lowerId.startsWith("b1.") || lowerId.startsWith("beta")) {
      return _buildGenericIcon(Icons.history, Colors.brown, size);
    }
    if (versionType == "old_alpha" || lowerId.startsWith("a1.") || lowerId.startsWith("alpha") || lowerId.startsWith("inf-") || lowerId.startsWith("rd-")) {
      return _buildGenericIcon(Icons.hourglass_empty, Colors.blueGrey, size);
    }
    
    if (lowerId.contains("snapshot") || lowerId.contains("pre") || lowerId.contains("rc") || RegExp(r'^\d+w').hasMatch(lowerId)) {
      return _buildGenericIcon(Icons.bug_report_outlined, Colors.deepOrange, size);
    }

    return _buildCategoryIcon(theme, category, size);
  }

  Widget _buildAssetIcon(ThemeData theme, String iconKey, double size) {
    if (iconKey == "bloret_dark" || iconKey == "bloret_light") {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(size * 0.2),
        ),
        child: Center(
          child: CustomPaint(
            size: Size(size * 0.7, size * 0.7),
            painter: BloretIcon(color: theme.colorScheme.primary),
          ),
        ),
      );
    }

    String assetPath;
    switch (iconKey) {
      case "bloriko":
        assetPath = "assets/bloriko.png";
        break;
      default:
        assetPath = "assets/icons/$iconKey.png";
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.2),
        image: DecorationImage(image: AssetImage(assetPath), fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildCategoryIcon(ThemeData theme, String category, double size) {
    Widget iconWidget;
    switch (category) {
      case "Exclusive":
        iconWidget = CustomPaint(
          size: Size(size * 0.7, size * 0.7),
          painter: BloretIcon(color: theme.colorScheme.primary),
        );
        break;
      case "Moddable":
        iconWidget = Icon(
          Icons.extension,
          color: theme.colorScheme.primary,
          size: size * 0.6,
        );
        break;
      case "RarelyUsed":
        iconWidget = Icon(
          Icons.archive_outlined,
          color: theme.colorScheme.primary,
          size: size * 0.6,
        );
        break;
      case "Hidden":
        iconWidget = Icon(
          Icons.visibility_off_outlined,
          color: theme.colorScheme.primary,
          size: size * 0.6,
        );
        break;
      default:
        iconWidget = Icon(
          Icons.apps,
          color: theme.colorScheme.primary,
          size: size * 0.6,
        );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: Center(child: iconWidget),
    );
  }

  Widget _buildGenericIcon(IconData icon, Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: Center(
        child: Icon(icon, color: color, size: size * 0.6),
      ),
    );
  }
}
