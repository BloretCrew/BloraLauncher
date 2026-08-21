import 'dart:io';
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
      return _buildAssetIcon(selectedIcon, size);
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
      if (loaderType == "fabric") return _buildAssetIcon("fabric", size);
      if (loaderType == "neoforge") return _buildAssetIcon("neoforge", size);
      if (loaderType == "forge") return _buildAssetIcon("forge", size);
      if (loaderType == "quilt") return _buildGenericIcon(Icons.grid_view, Colors.purple, size);
    }

    // Fallback to name-based detection if loaderType is missing
    final lowerId = id.toLowerCase();
    if (lowerId.contains("fabric")) return _buildAssetIcon("fabric", size);
    if (lowerId.contains("neoforge")) return _buildAssetIcon("neoforge", size);
    if (lowerId.contains("forge")) return _buildAssetIcon("forge", size);
    if (lowerId.contains("quilt")) {
      return _buildGenericIcon(Icons.grid_view, Colors.purple, size);
    }

    return _buildCategoryIcon(theme, category, size);
  }

  Widget _buildAssetIcon(String iconKey, double size) {
    String assetPath;
    switch (iconKey) {
      case "bloret_dark":
        assetPath = "assets/bloret_dark.png";
        break;
      case "bloret_light":
        assetPath = "assets/bloret_light.png";
        break;
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
