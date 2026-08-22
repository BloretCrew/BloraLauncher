import 'dart:io';

import 'package:bloret_launcher/core/i18n.dart';
import 'package:bloret_launcher/core/grammer_candy.dart';
import 'package:bloret_launcher/core/translate_api.dart';
import 'package:bloret_launcher/services/bloriko.dart';
import 'package:bloret_launcher/services/mod_service.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../widgets/windows_widgets.dart';

class ModsPage extends StatefulWidget {
  const ModsPage({super.key});

  @override
  State<ModsPage> createState() => _ModsPageState();
}

class _ModsPageState extends State<ModsPage> {
  final TextEditingController _agentController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ModService _modService = ModService();

  final Map<String, String> _translatedDescriptions = {};
  final Set<String> _translatingSlugs = {};

  bool _apiAvailable = true;
  String category = "";
  bool searching = false;

  final FocusNode _focusNode = FocusNode();
  final FocusNode _focusNodeBloriko = FocusNode();
  bool _isFocused = false;
  bool _isFocusedBloriko = false;
  List<dynamic> mods = [];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
    _focusNodeBloriko.addListener(() {
      if (mounted) setState(() => _isFocusedBloriko = _focusNodeBloriko.hasFocus);
    });
    _checkApiStatus();
    searchModrinth();
  }

  Future<void> _checkApiStatus() async {
    final available = await TranslateApi.checkApiStatus();
    if (mounted) {
      setState(() {
        _apiAvailable = available;
      });
    }
  }

  @override
  void dispose() {
    _agentController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    _focusNodeBloriko.dispose();
    super.dispose();
  }

  void askBlora() {
    final prompt = _agentController.text.trim();
    if (prompt.isEmpty) return;
    
    Bloriko.instance.initialPrompt = "Help me find these mods: $prompt".tl;
    _agentController.clear();
    showInfo("Calling Blora Agent...".tl);
  }

  Future<void> searchModrinth() async {
    setState(() {
      searching = true;
      mods = [];
    });

    final keyword = _searchController.text.trim();
    List<List<String>> facets = [];
    if (category.isNotEmpty) {
      facets.add(["project_type:$category"]);
    } else {
      facets.add(["project_type:mod"]);
    }

    try {
      final res = await _modService.searchMods(keyword, facets: facets.isEmpty ? null : facets);
      if (mounted) {
        setState(() {
          mods = res?['hits'] ?? [];
          searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => searching = false);
        showError("Search failed".tl);
      }
      logger.error("Modrinth search error: $e", .network);
    }
  }

  void openMod(dynamic mod) {
    final slug = mod['slug'];
    if (slug != null) {
      launchUrl(Uri.parse("https://modrinth.com/mod/$slug"));
    }
  }

  void downloadMod(dynamic mod) async {
    final slug = mod['slug'];
    if (slug == null) return;

    showInfo("Fetching download link...".tl);
    try {
      final url = await _modService.getDownloadUrl(slug);
      
      if (!mounted) return;
      if (url != null) {
        launchUrl(Uri.parse(url));
        showSuccess("Download link retrieved".tl);
      } else {
        showError("No suitable download found".tl);
      }
    } catch (e) {
      showError("Download error".tl);
      logger.error("Mod download error: $e", .network);
    }
  }

  Future<void> _translateDescription(dynamic mod) async {
    final slug = mod['slug'];
    final desc = mod['description'];
    if (slug == null || desc == null || desc.isEmpty) return;
    if (_translatedDescriptions.containsKey(slug)) return;

    setState(() => _translatingSlugs.add(slug));

    try {
      final result = await TranslateApi.googleTranslate(desc);
      if (mounted) {
        setState(() {
          _translatedDescriptions[slug] = result;
        });
      }
    } catch (e) {
      debugPrint("Translation failed: $e");
    } finally {
      if (mounted) setState(() => _translatingSlugs.remove(slug));
    }
  }

  String _formatCount(dynamic count) {
    if (count == null) return "0";
    int num = 0;
    if (count is int) {
      num = count;
    } else if (count is String) {
      num = int.tryParse(count) ?? 0;
    }
    
    if (num >= 1000000) {
      return "${(num / 1000000).toStringAsFixed(1)}M";
    } else if (num >= 1000) {
      return "${(num / 1000).toStringAsFixed(1)}K";
    }
    return num.toString();
  }

  Widget _buildLoaderChip(String loader) {
    Color color = Colors.grey;
    String label = loader;
    
    if (loader == "fabric") {
      color = Colors.orange.shade700;
      label = "Fabric";
    } else if (loader == "forge") {
      color = Colors.brown.shade400;
      label = "Forge";
    } else if (loader == "quilt") {
      color = Colors.purple.shade400;
      label = "Quilt";
    } else if (loader == "neoforge") {
      color = Colors.blue.shade400;
      label = "NeoForge";
    }

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;
    final agentName = Bloriko.type == "bloriko" ? "Bloriko".tl : "Blora Agent".tl;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(Platform.isAndroid ? 16 : 32, 16, 16, 16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Mod".tl,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!_apiAvailable)
                Tooltip(
                  message: "Translation API unavailable".tl,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Icon(Icons.error_outline, color: Colors.red),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          _buildAgentCard(isPortrait, agentName),

          const SizedBox(height: 8),

          Text(
            isPortrait 
                ? "$agentName ${"Powered by AI, please verify important information.".tl}"
                : "$agentName ${"Powered by AI, ".tl}$agentName ${"may also make mistakes, please verify important information.".tl}",
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),

          const SizedBox(height: 20),

          _buildSearchBar(isPortrait),

          const SizedBox(height: 16),

          if (searching)
            const Center(
              child: CircularProgressIndicator(),
            ),

          ...mods.asMap().entries.map((entry) {
            final index = entry.key;
            final mod = entry.value;
            return TweenAnimationBuilder<double>(
              key: ValueKey(mod['slug'] ?? index),
              duration: Duration(milliseconds: 300 + (index % 5 * 100)),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(20 * (1 - value), 30 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: _buildModCard(mod, isPortrait),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAgentCard(bool isPortrait, String agentName) {
    return FluentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                "assets/icons/mc_be.png",
                width: 35,
                height: 35,
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPortrait ? "Let %s help you find mods".tl.format(agentName) : "Let %s help you pick suitable mods".tl.format(agentName),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      isPortrait ? "Let AI find all mods for you.".tl : "No need to find mods one by one, let AI do it for you.".tl,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          Row(
            children: [
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.text,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isFocusedBloriko 
                          ? Theme.of(context).colorScheme.primary 
                          : Theme.of(context).colorScheme.surfaceContainerHighest, 
                        width: _isFocusedBloriko ? 1.5 : 1.0
                      ),
                    ),
                    alignment: Alignment.centerLeft,
                    child: TextField(
                      controller: _agentController,
                      maxLines: 1,
                      focusNode: _focusNodeBloriko,
                      decoration: InputDecoration(
                    hintText: "Tell me what you need...".tl,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onSubmitted: (_) => askBlora(),
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          BloretButton(
            text: "Send".tl,
            onPressed: askBlora,
          ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isPortrait) {
    if (isPortrait) {
      return FluentCard(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Win11Dropdown(
                    items: [
                      Win11DropdownItem(label: "All".tl, value: ""),
                      Win11DropdownItem(label: "Mod".tl, value: "mod"),
                      Win11DropdownItem(label: "Resource Pack".tl, value: "resourcepack"),
                      Win11DropdownItem(label: "Shader Pack".tl, value: "shader"),
                      Win11DropdownItem(label: "Data Pack".tl, value: "datapack"),
                      Win11DropdownItem(label: "Modpack".tl, value: "modpack"),
                    ],
                    initialValue: category,
                    onChanged: (value) {
                      setState(() {
                        category = value ?? "";
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                BloretButton(
                  text: "Search".tl,
                  onPressed: searchModrinth,
                ),
              ],
            ),
            const SizedBox(height: 10),
            MouseRegion(
              cursor: SystemMouseCursors.text,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isFocused 
                      ? Theme.of(context).colorScheme.primary 
                      : Theme.of(context).colorScheme.surfaceContainerHighest, 
                    width: _isFocused ? 1.5 : 1.0
                  )
                ),
                alignment: Alignment.centerLeft,
                child: TextField(
                  controller: _searchController,
                  maxLines: 1,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: "Search on Modrinth...".tl,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onSubmitted: (_) => searchModrinth(),
                ),
              ),
            )
          ],
        ),
      );
    }

    return FluentCard(
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Win11Dropdown(
              items: [
                Win11DropdownItem(label: "All".tl, value: ""),
                Win11DropdownItem(label: "Mod".tl, value: "mod"),
                Win11DropdownItem(label: "Resource Pack".tl, value: "resourcepack"),
                Win11DropdownItem(label: "Shader Pack".tl, value: "shader"),
                Win11DropdownItem(label: "Data Pack".tl, value: "datapack"),
                Win11DropdownItem(label: "Modpack".tl, value: "modpack"),
              ],
              initialValue: category,
              onChanged: (value) {
                setState(() {
                  category = value ?? "";
                });
              },
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.text,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isFocused 
                      ? Theme.of(context).colorScheme.primary 
                      : Theme.of(context).colorScheme.surfaceContainerHighest, 
                    width: _isFocused ? 1.5 : 1.0
                  )
                ),
                alignment: Alignment.centerLeft,
                child: TextField(
                  controller: _searchController,
                  maxLines: 1,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: "Search on Modrinth...".tl,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onSubmitted: (_) => searchModrinth(),
                ),
              ),
            )
          ),

          const SizedBox(width: 8),

          BloretButton(
            text: "搜索".tl,
            onPressed: searchModrinth,
          ),
        ],
      ),
    );
  }

  Widget _buildModCard(dynamic mod, bool isPortrait) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FluentCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: mod["icon_url"] ?? "",
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    child: Center(
                      child: CustomPaint(
                        size: const Size(56, 56),
                        painter: BloretIcon(
                          color: theme.colorScheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    child: Center(
                      child: CustomPaint(
                        size: const Size(56, 56),
                        painter: BloretIcon(
                          color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 15),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mod["title"] ?? mod["name"] ?? "",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  Text(
                    "by ${mod["author"] ?? "Unknown"}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),

                  const SizedBox(height: 4),

                  if (!isPortrait)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _translatedDescriptions[mod['slug']] ?? mod["description"] ?? "",
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        if (!_translatedDescriptions.containsKey(mod['slug']) && _apiAvailable)
                          GestureDetector(
                            onTap: () => _translateDescription(mod),
                            child: _translatingSlugs.contains(mod['slug'])
                              ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5))
                              : Text(
                                  "Translate Description".tl,
                                  style: TextStyle(
                                    fontSize: 10, 
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                          ),
                      ],
                    ),

                  const SizedBox(height: 6),

                  Row(
                    children: [
                      const Icon(Icons.download, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        _formatCount(mod["downloads"]),
                        style: const TextStyle(fontSize: 12),
                      ),

                      const SizedBox(width: 15),

                      const Icon(Icons.favorite, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        _formatCount(mod["follows"] ?? mod["followers"]),
                        style: const TextStyle(fontSize: 12),
                      ),

                      const SizedBox(width: 15),

                      if (mod["categories"] is List)
                        ...((mod["categories"] as List)
                          .where((c) => ["fabric", "forge", "quilt", "neoforge"].contains(c.toString().toLowerCase()))
                          .map((c) => _buildLoaderChip(c.toString().toLowerCase()))),
                    ],
                  ),
                ],
              ),
            ),

            Column(
              children: [
                BloretButton(
                  text: "View".tl,
                  onPressed: () => openMod(mod),
                ),
                const SizedBox(height: 8),
                if (!isPortrait)
                  BloretButton(
                    text: "Download".tl,
                    onPressed: () => downloadMod(mod),
                  ),
              ],
            ),
            if (isPortrait)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: BloretIconButton(
                  icon: Icons.download,
                  tooltip: "Download".tl,
                  onPressed: () => downloadMod(mod),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Path buildPath() {
  final Path path = Path();
  path.moveTo(0.0, 0.0);
  path.cubicTo(0.70962891, -0.03287109, 1.41925781, -0.06574219, 2.15039062, -0.09960938);
  path.cubicTo(14.87066907, -0.22224133, 27.17739137, 6.988931, 38.38778687, 12.39178467);
  path.cubicTo(41.56477301, 13.9227516, 44.74907513, 15.43822953, 47.9329071, 16.95489502);
  path.cubicTo(49.53671207, 17.71907206, 51.14015956, 18.4839998, 52.74324036, 19.24969482);
  path.cubicTo(59.17997001, 22.3229871, 65.64284237, 25.33615683, 72.125, 28.3125);
  path.cubicTo(74.17190556, 29.2538398, 76.21877914, 30.19524914, 78.265625, 31.13671875);
  path.cubicTo(79.91981445, 31.89734619, 79.91981445, 31.89734619, 81.60742188, 32.67333984);
  path.cubicTo(88.96647006, 36.06063892, 96.31689473, 39.46664217, 103.6678772, 42.87139893);
  path.cubicTo(105.43543328, 43.68991008, 107.20314683, 44.50808131, 108.97103882, 45.3258667);
  path.cubicTo(113.96305186, 47.63505563, 118.95089418, 49.95294079, 123.93588257, 52.2772522);
  path.cubicTo(126.51224683, 53.47216751, 129.09519308, 54.6519877, 131.67895508, 55.83081055);
  path.cubicTo(133.37464922, 56.6134717, 135.0702106, 57.39642055, 136.765625, 58.1796875);
  path.cubicTo(137.53732529, 58.52742722, 138.30902557, 58.87516693, 139.10411072, 59.23344421);
  path.cubicTo(149.95210372, 64.28120824, 158.42298619, 72.48472149, 163.4375, 83.4375);
  path.cubicTo(166.09534887, 90.96333588, 166.8811756, 98.03076052, 166.86987305, 105.9675293);
  path.cubicTo(166.8800647, 107.06153549, 166.89025635, 108.15554169, 166.90075684, 109.28269958);
  path.cubicTo(166.93068514, 112.85909277, 166.94012198, 116.43521723, 166.94921875, 120.01171875);
  path.cubicTo(166.96608036, 122.50707373, 166.98423258, 125.00242029, 167.00361633, 127.49775696);
  path.cubicTo(167.05096123, 134.03572967, 167.08087093, 140.57366824, 167.10705566, 147.11175537);
  path.cubicTo(167.13535012, 153.79527805, 167.18344297, 160.47868335, 167.22851562, 167.16210938);
  path.cubicTo(167.31437227, 180.25384219, 167.3823611, 193.34560359, 167.4375, 206.4375);
  path.cubicTo(168.38512711, 205.87477135, 168.38512711, 205.87477135, 169.35189819, 205.30067444);
  path.cubicTo(172.24158237, 203.58576717, 175.1324978, 201.87294606, 178.0234375, 200.16015625);
  path.cubicTo(179.01722412, 199.56996704, 180.01101074, 198.97977783, 181.03491211, 198.3717041);
  path.cubicTo(203.68067205, 184.96364839, 226.37258061, 177.45767821, 252.72265625, 183.40234375);
  path.cubicTo(271.23839308, 188.56182878, 287.55174348, 199.01093423, 303.98828125, 208.66015625);
  path.cubicTo(310.4520237, 212.45304452, 316.94220406, 216.19897651, 323.4375, 219.9375);
  path.cubicTo(336.78793927, 227.62817929, 350.09483505, 235.39233181, 363.39648438, 243.16699219);
  path.cubicTo(375.81832591, 250.42603142, 388.25908421, 257.65054171, 400.72607422, 264.83178711);
  path.cubicTo(408.96719191, 269.58164532, 417.1861691, 274.36845041, 425.3984375, 279.16796875);
  path.cubicTo(432.73033723, 283.44972122, 440.08017238, 287.69960939, 447.4375, 291.9375);
  path.cubicTo(456.77613207, 297.3166408, 466.09390317, 302.73009447, 475.3984375, 308.16796875);
  path.cubicTo(482.73033723, 312.44972122, 490.08017238, 316.69960939, 497.4375, 320.9375);
  path.cubicTo(506.77613207, 326.3166408, 516.09390317, 331.73009447, 525.3984375, 337.16796875);
  path.cubicTo(532.73033723, 341.44972122, 540.08017238, 345.69960939, 547.4375, 349.9375);
  path.cubicTo(556.77613207, 355.3166408, 566.09390317, 360.73009447, 575.3984375, 366.16796875);
  path.cubicTo(582.73033723, 370.44972122, 590.08017238, 374.69960939, 597.4375, 378.9375);
  path.cubicTo(606.77613207, 384.3166408, 616.09390317, 389.73009447, 625.3984375, 395.16796875);
  path.cubicTo(632.73033723, 399.44972122, 640.08017238, 403.69960939, 647.4375, 407.9375);
  path.cubicTo(656.77613207, 413.3166408, 666.09390317, 418.73009447, 675.3984375, 424.16796875);
  path.cubicTo(682.73033723, 428.44972122, 690.08017238, 432.69960939, 697.4375, 436.9375);
  path.cubicTo(706.77613207, 442.3166408, 716.09390317, 447.73009447, 725.3984375, 453.16796875);
  path.cubicTo(732.73033723, 457.44972122, 740.08017238, 461.69960939, 747.4375, 465.9375);
  path.cubicTo(756.77613207, 471.3166408, 766.09390317, 476.73009447, 775.3984375, 482.16796875);
  path.cubicTo(782.73033806, 486.4497217, 790.08024377, 490.69948442, 797.4375, 494.9375);
  path.cubicTo(808.81406464, 501.49282624, 820.16925559, 508.08349139, 831.49853516, 514.72021484);
  path.cubicTo(834.49867211, 516.47324386, 837.50486201, 518.21555804, 840.51171875, 519.95703125);
  path.cubicTo(842.46630215, 521.09608598, 844.42073508, 522.23539896, 846.375, 523.375);
  path.cubicTo(847.25639648, 523.88240723, 848.13779297, 524.38981445, 849.04589844, 524.91259766);
  path.cubicTo(854.88760307, 528.3335268, 860.1985757, 532.15395112, 865.4375, 536.4375);
  path.cubicTo(866.345, 537.17355469, 867.2525, 537.90960937, 868.1875, 538.66796875);
  path.cubicTo(882.8997724, 551.46458068, 891.37700323, 567.5758376, 895.4375, 586.4375);
  path.cubicTo(895.61471704, 587.2600203, 895.79193408, 588.0825406, 895.97452134, 588.92998576);
  path.cubicTo(896.63525196, 593.9356637, 896.57859081, 598.88885978, 896.57172108, 603.93272781);
  path.cubicTo(896.57407331, 605.10261273, 896.57642554, 606.27249765, 896.57884905, 607.47783363);
  path.cubicTo(896.58436668, 610.73103386, 896.58541148, 613.98420031, 896.58457164, 617.23740399);
  path.cubicTo(896.58474134, 620.77461842, 896.59064976, 624.31182405, 896.5958125, 627.84903407);
  path.cubicTo(896.60513554, 634.86753262, 896.60906005, 641.88602487, 896.61133147, 648.90452884);
  path.cubicTo(896.61429436, 657.31053448, 896.62299235, 665.71653176, 896.63174575, 674.12253301);
  path.cubicTo(896.65258881, 694.44209569, 896.66306017, 714.76165982, 896.67187535, 735.0812307);
  path.cubicTo(896.67608251, 744.69569116, 896.68130445, 754.310151, 896.68655988, 763.92461094);
  path.cubicTo(896.70445096, 796.84122504, 896.71944614, 829.75783932, 896.72688007, 862.67445755);
  path.cubicTo(896.72735483, 864.74097083, 896.72783072, 866.8074841, 896.72830774, 868.87399738);
  path.cubicTo(896.7286623, 870.41119474, 896.7286623, 870.41119474, 896.72902403, 871.9794466);
  path.cubicTo(896.73022522, 877.17151909, 896.73144067, 882.36359158, 896.73266602, 887.55566406);
  path.cubicTo(896.73290617, 888.58604423, 896.73314632, 889.61642439, 896.73339374, 890.67802819);
  path.cubicTo(896.74128432, 924.07538301, 896.76471073, 957.47270228, 896.79722196, 990.87004158);
  path.cubicTo(896.83153781, 1026.18573705, 896.85123289, 1061.50141172, 896.85452431, 1096.81712413);
  path.cubicTo(896.85494185, 1100.6958801, 896.85542141, 1104.57463607, 896.85594749, 1108.45339203);
  path.cubicTo(896.85607069, 1109.40843955, 896.85619388, 1110.36348706, 896.8563208, 1111.34747541);
  path.cubicTo(896.85865076, 1126.70259311, 896.87429943, 1142.05766948, 896.89478934, 1157.41277246);
  path.cubicTo(896.91506884, 1172.8555445, 896.92051461, 1188.29826702, 896.91101871, 1203.74104992);
  path.cubicTo(896.90581185, 1212.90888714, 896.91164258, 1222.07655918, 896.93355338, 1231.24437255);
  path.cubicTo(896.94710152, 1237.37815277, 896.94594919, 1243.51181979, 896.93315142, 1249.64560124);
  path.cubicTo(896.92628131, 1253.13416084, 896.92549285, 1256.62240559, 896.94271151, 1260.11093655);
  path.cubicTo(897.04382825, 1285.23194163, 894.53457589, 1307.16710814, 878.4375, 1327.4375);
  path.cubicTo(877.85613281, 1328.18257812, 877.27476563, 1328.92765625, 876.67578125, 1329.6953125);
  path.cubicTo(865.90694039, 1342.65404343, 851.12952568, 1350.38242237, 836.70947266, 1358.57568359);
  path.cubicTo(831.27061572, 1361.67049952, 825.8560334, 1364.80728771, 820.4375, 1367.9375);
  path.cubicTo(818.25000368, 1369.19792306, 816.06250369, 1370.45833974, 813.875, 1371.71875);
  path.cubicTo(807.71722262, 1375.27131388, 801.57521723, 1378.85041724, 795.4375, 1382.4375);
  path.cubicTo(786.0275967, 1387.93695536, 776.59279437, 1393.39199196, 767.1484375, 1398.83203125);
  path.cubicTo(759.8979851, 1403.01099128, 752.66261731, 1407.21490506, 745.4375, 1411.4375);
  path.cubicTo(736.0275967, 1416.93695536, 726.59279437, 1422.39199196, 717.1484375, 1427.83203125);
  path.cubicTo(709.8979851, 1432.01099128, 702.66261731, 1436.21490506, 695.4375, 1440.4375);
  path.cubicTo(686.0275967, 1445.93695536, 676.59279437, 1451.39199196, 667.1484375, 1456.83203125);
  path.cubicTo(659.8979851, 1461.01099128, 652.66261731, 1465.21490506, 645.4375, 1469.4375);
  path.cubicTo(637.11998208, 1474.2985296, 628.78544347, 1479.12891103, 620.4375, 1483.9375);
  path.cubicTo(608.07727482, 1491.05836408, 595.75282673, 1498.23933378, 583.4375, 1505.4375);
  path.cubicTo(570.02991282, 1513.27407983, 556.60590721, 1521.08028608, 543.14892578, 1528.83178711);
  path.cubicTo(535.89828014, 1533.01077594, 528.66277414, 1537.2148134, 521.4375, 1541.4375);
  path.cubicTo(512.0275967, 1546.93695536, 502.59279437, 1552.39199196, 493.1484375, 1557.83203125);
  path.cubicTo(485.8979851, 1562.01099128, 478.66261731, 1566.21490506, 471.4375, 1570.4375);
  path.cubicTo(462.0275967, 1575.93695536, 452.59279437, 1581.39199196, 443.1484375, 1586.83203125);
  path.cubicTo(435.8979851, 1591.01099128, 428.66261731, 1595.21490506, 421.4375, 1599.4375);
  path.cubicTo(412.0275967, 1604.93695536, 402.59279437, 1610.39199196, 393.1484375, 1615.83203125);
  path.cubicTo(385.8979851, 1620.01099128, 378.66261731, 1624.21490506, 371.4375, 1628.4375);
  path.cubicTo(362.0275967, 1633.93695536, 352.59279437, 1639.39199196, 343.1484375, 1644.83203125);
  path.cubicTo(335.89798186, 1649.01099315, 328.66289869, 1653.215383, 321.4375, 1657.4375);
  path.cubicTo(318.46597583, 1659.17177033, 315.49410868, 1660.90545034, 312.52197266, 1662.63867188);
  path.cubicTo(310.40412515, 1663.8737756, 308.28663088, 1665.10948514, 306.16943359, 1666.34570312);
  path.cubicTo(298.61575539, 1670.75155601, 291.04146183, 1675.11898608, 283.4375, 1679.4375);
  path.cubicTo(282.54095703, 1679.94893555, 281.64441406, 1680.46037109, 280.72070312, 1680.98730469);
  path.cubicTo(258.22858619, 1693.71560228, 235.0406894, 1699.43218576, 209.4375, 1692.4375);
  path.cubicTo(192.42693253, 1687.12223652, 177.14364194, 1677.17156208, 161.88671875, 1668.21484375);
  path.cubicTo(155.42297685, 1664.4219558, 148.93282736, 1660.67596816, 142.4375, 1656.9375);
  path.cubicTo(133.09866967, 1651.55870559, 123.78109461, 1646.14490424, 114.4765625, 1640.70703125);
  path.cubicTo(107.14466277, 1636.42527878, 99.79482762, 1632.17539061, 92.4375, 1627.9375);
  path.cubicTo(83.09886793, 1622.5583592, 73.78109683, 1617.14490553, 64.4765625, 1611.70703125);
  path.cubicTo(57.14466277, 1607.42527878, 49.79482762, 1603.17539061, 42.4375, 1598.9375);
  path.cubicTo(33.09886793, 1593.5583592, 23.78109683, 1588.14490553, 14.4765625, 1582.70703125);
  path.cubicTo(7.14466236, 1578.42527854, -0.20520807, 1574.17545309, -7.5625, 1569.9375);
  path.cubicTo(-20.91265665, 1562.24632531, -34.21983128, 1554.4826704, -47.52148438, 1546.70800781);
  path.cubicTo(-59.94332591, 1539.44896858, -72.38408421, 1532.22445829, -84.85107422, 1525.04321289);
  path.cubicTo(-93.09219191, 1520.29335468, -101.3111691, 1515.50654959, -109.5234375, 1510.70703125);
  path.cubicTo(-116.85533723, 1506.42527878, -124.20517238, 1502.17539061, -131.5625, 1497.9375);
  path.cubicTo(-140.90113207, 1492.5583592, -150.21890317, 1487.14490553, -159.5234375, 1481.70703125);
  path.cubicTo(-166.85533723, 1477.42527878, -174.20517238, 1473.17539061, -181.5625, 1468.9375);
  path.cubicTo(-190.90113207, 1463.5583592, -200.21890317, 1458.14490553, -209.5234375, 1452.70703125);
  path.cubicTo(-216.85533723, 1448.42527878, -224.20517238, 1444.17539061, -231.5625, 1439.9375);
  path.cubicTo(-240.90113207, 1434.5583592, -250.21890317, 1429.14490553, -259.5234375, 1423.70703125);
  path.cubicTo(-266.85533723, 1419.42527878, -274.20517238, 1415.17539061, -281.5625, 1410.9375);
  path.cubicTo(-290.90113207, 1405.5583592, -300.21890317, 1400.14490553, -309.5234375, 1394.70703125);
  path.cubicTo(-316.85533806, 1390.4252783, -324.20524377, 1386.17551558, -331.5625, 1381.9375);
  path.cubicTo(-342.94539957, 1375.37852348, -354.30607345, 1368.78294496, -365.64111328, 1362.14160156);
  path.cubicTo(-368.58609954, 1360.42373393, -371.54017861, 1358.72241857, -374.49609375, 1357.0234375);
  path.cubicTo(-399.17565521, 1342.76722004, -420.53846472, 1326.34763442, -428.27832031, 1297.45825195);
  path.cubicTo(-431.00144632, 1286.83830944, -431.7122406, 1276.60185706, -431.69392776, 1265.6559);
  path.cubicTo(-431.6959804, 1264.50364816, -431.69803303, 1263.35139632, -431.70014787, 1262.16422775);
  path.cubicTo(-431.70481275, 1258.97912119, -431.70504941, 1255.79405066, -431.70337028, 1252.60894229);
  path.cubicTo(-431.70263562, 1249.13857661, -431.70767042, 1245.66821835, -431.7119453, 1242.19785589);
  path.cubicTo(-431.71950594, 1235.32070612, -431.72171737, 1228.44356411, -431.72227435, 1221.56641061);
  path.cubicTo(-431.72318991, 1213.326314, -431.72986312, 1205.08622453, -431.73662117, 1196.84613101);
  path.cubicTo(-431.75266369, 1176.93262278, -431.75858243, 1157.01911533, -431.76336992, 1137.1056018);
  path.cubicTo(-431.76570758, 1127.68121276, -431.76931042, 1118.25682432, -431.7730653, 1108.83243576);
  path.cubicTo(-431.78589915, 1076.55789044, -431.79661856, 1044.28334546, -431.8000679, 1012.00879765);
  path.cubicTo(-431.80028953, 1009.98366921, -431.80051132, 1007.95854077, -431.80073325, 1005.93341234);
  path.cubicTo(-431.80095389, 1003.90345784, -431.80117437, 1001.87350334, -431.8013947, 999.84354883);
  path.cubicTo(-431.80183725, 995.77126888, -431.80228436, 991.69898893, -431.80273438, 987.62670898);
  path.cubicTo(-431.80284377, 986.61702408, -431.80295316, 985.60733918, -431.80306586, 984.56705776);
  path.cubicTo(-431.80669584, 951.83395525, -431.82261451, 919.10087489, -431.84592474, 886.36778086);
  path.cubicTo(-431.87053729, 851.74247089, -431.8842414, 817.11717358, -431.88543582, 782.49185461);
  path.cubicTo(-431.88560727, 778.68869141, -431.88582269, 774.88552823, -431.88607025, 771.08236504);
  path.cubicTo(-431.88612602, 770.1459519, -431.88618179, 769.20953877, -431.88623925, 768.24474947);
  path.cubicTo(-431.88738843, 753.1950429, -431.89839909, 738.14535911, -431.91295731, 723.09566022);
  path.cubicTo(-431.92734489, 707.96030075, -431.93054653, 692.8249704, -431.92251733, 677.68960596);
  path.cubicTo(-431.91807179, 668.70639413, -431.92187851, 659.72327653, -431.93775584, 650.74007714);
  path.cubicTo(-431.94754593, 644.7282254, -431.94628937, 638.71643928, -431.93631961, 632.70458806);
  path.cubicTo(-431.93095641, 629.2865589, -431.93180971, 625.86885565, -431.94282833, 622.45081878);
  path.cubicTo(-432.02676959, 594.6399236, -430.05937834, 569.60978397, -411.5625, 547.4375);
  path.cubicTo(-410.39847656, 545.97763672, -410.39847656, 545.97763672, -409.2109375, 544.48828125);
  path.cubicTo(-399.39379815, 532.77508836, -384.77773808, 525.63028785, -371.71484375, 518.23144531);
  path.cubicTo(-366.67943636, 515.36588045, -361.68585425, 512.42954278, -356.6875, 509.5);
  path.cubicTo(-347.23591357, 503.98025495, -337.75828563, 498.50640132, -328.27392578, 493.04321289);
  path.cubicTo(-321.02328014, 488.86422406, -313.78777414, 484.6601866, -306.5625, 480.4375);
  path.cubicTo(-297.1525967, 474.93804464, -287.71779437, 469.48300804, -278.2734375, 464.04296875);
  path.cubicTo(-271.0229851, 459.86400872, -263.78761731, 455.66009494, -256.5625, 451.4375);
  path.cubicTo(-247.1525967, 445.93804464, -237.71779437, 440.48300804, -228.2734375, 435.04296875);
  path.cubicTo(-221.02298288, 430.86400743, -213.78780739, 426.65977222, -206.5625, 422.4375);
  path.cubicTo(-198.38187019, 417.66095503, -190.19909113, 412.88812986, -182.00170898, 408.14038086);
  path.cubicTo(-180.28326053, 407.14427952, -178.56641831, 406.14540881, -176.84960938, 405.14648438);
  path.cubicTo(-175.80998047, 404.54513672, -174.77035156, 403.94378906, -173.69921875, 403.32421875);
  path.cubicTo(-172.77842529, 402.79014404, -171.85763184, 402.25606934, -170.90893555, 401.70581055);
  path.cubicTo(-168.5625, 400.4375, -168.5625, 400.4375, -165.5625, 399.4375);
  path.cubicTo(-165.56420874, 398.4794528, -165.56420874, 398.4794528, -165.565952, 397.50205112);
  path.cubicTo(-165.63312777, 359.62367153, -165.68458067, 321.74530077, -165.71569599, 283.86687379);
  path.cubicTo(-165.71944798, 279.31587149, -165.72333096, 274.76486931, -165.72729492, 270.21386719);
  path.cubicTo(-165.72808185, 269.30786802, -165.72886878, 268.40186886, -165.72967956, 267.46841517);
  path.cubicTo(-165.74272334, 252.81042116, -165.76637152, 238.15246255, -165.79395839, 223.49448952);
  path.cubicTo(-165.8220412, 208.44718866, -165.83868234, 193.3999063, -165.84476548, 178.35258031);
  path.cubicTo(-165.84887596, 169.0721711, -165.86184527, 159.79186197, -165.8862494, 150.51148358);
  path.cubicTo(-165.9021421, 144.142278, -165.90689237, 137.77312395, -165.90300413, 131.4039);
  path.cubicTo(-165.90108807, 127.73256172, -165.90396612, 124.06139797, -165.92011642, 120.39009094);
  path.cubicTo(-165.93753786, 116.40047113, -165.931434, 112.41121928, -165.92326355, 108.42156982);
  path.cubicTo(-165.93200207, 107.27367564, -165.9407406, 106.12578146, -165.94974393, 104.9431026);
  path.cubicTo(-165.87531728, 91.45062857, -162.68986967, 79.80201763, -153.375, 69.75);
  path.cubicTo(-145.5599773, 62.579295, -136.02288924, 57.99914613, -126.4375, 53.6875);
  path.cubicTo(-124.60964702, 52.85165076, -122.78180913, 52.01576812, -120.95437622, 51.17900085);
  path.cubicTo(-118.94589314, 50.26041018, -116.93589125, 49.34520019, -114.92578125, 48.43017578);
  path.cubicTo(-107.62361517, 45.10098976, -100.34579082, 41.71888105, -93.06509399, 38.34307861);
  path.cubicTo(-90.43010704, 37.12157283, -87.7945549, 35.90129292, -85.15893555, 34.68115234);
  path.cubicTo(-74.55486698, 29.76937609, -63.97045148, 24.81767871, -53.40255737, 19.82858276);
  path.cubicTo(-33.65420845, 10.50666772, -33.65420845, 10.50666772, -23.875, 6.0625);
  path.cubicTo(-23.10953857, 5.71106934, -22.34407715, 5.35963867, -21.55541992, 4.99755859);
  path.cubicTo(-14.4036468, 1.77872777, -7.8429935, 0.06175585, 0.0, 0.0);
  path.close();
  path.moveTo(-5.58203125, 81.82421875);
  path.cubicTo(-7.18800171, 82.60357788, -7.18800171, 82.60357788, -8.82641602, 83.39868164);
  path.cubicTo(-9.99744873, 83.9683667, -11.16848145, 84.53805176, -12.375, 85.125);
  path.cubicTo(-22.08803854, 89.83087078, -31.83169323, 94.46281631, -41.625, 99.0);
  path.cubicTo(-42.76727051, 99.52980469, -43.90954102, 100.05960938, -45.08642578, 100.60546875);
  path.cubicTo(-50.44773125, 103.08723313, -55.81450587, 105.55621458, -61.19367981, 107.99897766);
  path.cubicTo(-63.03742125, 108.83661947, -64.88005986, 109.67664175, -66.72241211, 110.51733398);
  path.cubicTo(-69.03060078, 111.56926993, -71.34122763, 112.61587637, -73.65454102, 113.65649414);
  path.cubicTo(-74.67990967, 114.12434326, -75.70527832, 114.59219238, -76.76171875, 115.07421875);
  path.cubicTo(-77.66752686, 115.48373779, -78.57333496, 115.89325684, -79.5065918, 116.31518555);
  path.cubicTo(-81.71502708, 117.26690043, -81.71502708, 117.26690043, -82.5625, 119.4375);
  path.cubicTo(-81.97799072, 119.71722656, -81.39348145, 119.99695313, -80.79125977, 120.28515625);
  path.cubicTo(-68.90126577, 125.97789272, -57.021719, 131.69120659, -45.16333008, 137.44946289);
  path.cubicTo(-42.34561312, 138.81756548, -39.52638979, 140.18248631, -36.70581055, 141.54467773);
  path.cubicTo(-30.31318842, 144.63384585, -23.93386994, 147.74172691, -17.59375, 150.9375);
  path.cubicTo(-16.54396973, 151.45948975, -15.49418945, 151.98147949, -14.41259766, 152.51928711);
  path.cubicTo(-12.49355333, 153.47439985, -10.58114572, 154.44302284, -8.67724609, 155.42797852);
  path.cubicTo(-7.83242676, 155.84490967, -6.98760742, 156.26184082, -6.1171875, 156.69140625);
  path.cubicTo(-5.40030762, 157.05564697, -4.68342773, 157.4198877, -3.94482422, 157.79516602);
  path.cubicTo(2.502378, 159.53349242, 8.23501919, 156.42280052, 13.88671875, 153.640625);
  path.cubicTo(14.68941193, 153.25522552, 15.4921051, 152.86982605, 16.31912231, 152.4727478);
  path.cubicTo(18.92526081, 151.2194657, 21.52497874, 149.95341634, 24.125, 148.6875);
  path.cubicTo(26.83077701, 147.38331959, 29.53817736, 146.08254921, 32.24559021, 144.7817688);
  path.cubicTo(34.05600125, 143.91154498, 35.86586717, 143.04018617, 37.67518616, 142.16769409);
  path.cubicTo(45.50115207, 138.39513501, 53.36439604, 134.70845587, 61.25, 131.0625);
  path.cubicTo(62.88038208, 130.30694824, 62.88038208, 130.30694824, 64.54370117, 129.53613281);
  path.cubicTo(71.16186583, 126.47430024, 77.79522927, 123.44665116, 84.4375, 120.4375);
  path.cubicTo(84.4375, 119.7775, 84.4375, 119.1175, 84.4375, 118.4375);
  path.cubicTo(65.24956224, 109.31265944, 46.03279692, 100.26565684, 26.66625977, 91.52514648);
  path.cubicTo(25.39599539, 90.95166172, 24.1257317, 90.37817542, 22.85546875, 89.8046875);
  path.cubicTo(22.24854691, 89.53102859, 21.64162506, 89.25736969, 21.01631165, 88.97541809);
  path.cubicTo(15.68070726, 86.56305252, 10.37688241, 84.08418359, 5.085495, 81.5763855);
  path.cubicTo(-0.00280734, 79.17948389, -0.5508113, 79.37212456, -5.58203125, 81.82421875);
  path.close();
  path.moveTo(-88.5625, 201.4375);
  path.cubicTo(-88.64816312, 289.55356181, -88.72766521, 377.66962865, -88.7742157, 465.78572083);
  path.cubicTo(-88.77490598, 467.08903777, -88.77559627, 468.39235471, -88.77630747, 469.7351661);
  path.cubicTo(-88.79090624, 497.3673375, -88.80450396, 524.9995093, -88.81689839, 552.63168177);
  path.cubicTo(-88.82312545, 566.51185432, -88.82955032, 580.39202676, -88.83616221, 594.27219912);
  path.cubicTo(-88.83715845, 596.36599498, -88.83814904, 598.45979083, -88.8391394, 600.55358669);
  path.cubicTo(-88.85444266, 632.8021703, -88.87399301, 665.05074448, -88.90582275, 697.29931641);
  path.cubicTo(-88.90650725, 697.99289993, -88.90719174, 698.68648346, -88.90789698, 699.40108466);
  path.cubicTo(-88.91895909, 710.58398885, -88.93037704, 721.76689268, -88.9418422, 732.94979647);
  path.cubicTo(-88.97485254, 765.15274563, -89.00523973, 797.35568754, -89.01819897, 829.55865192);
  path.cubicTo(-89.01846664, 830.22062288, -89.01873432, 830.88259383, -89.0190101, 831.56462451);
  path.cubicTo(-89.0245767, 845.44268867, -89.02901428, 859.32075297, -89.03207495, 873.19881791);
  path.cubicTo(-89.03351581, 879.69746447, -89.035144, 886.19611097, -89.03688622, 892.69475746);
  path.cubicTo(-89.03722333, 893.97383454, -89.03756045, 895.25291162, -89.03790778, 896.57074861);
  path.cubicTo(-89.04382554, 917.1934852, -89.0670405, 937.81616809, -89.09666017, 958.43888275);
  path.cubicTo(-89.1260423, 979.15161627, -89.13735351, 999.86429635, -89.13000689, 1020.57704999);
  path.cubicTo(-89.12619247, 1032.89587297, -89.13644495, 1045.21450097, -89.16648772, 1057.53328889);
  path.cubicTo(-89.18516688, 1065.75104085, -89.18586819, 1073.96866441, -89.17165907, 1082.18642506);
  path.cubicTo(-89.16407371, 1086.87604335, -89.16458157, 1091.56529165, -89.18691591, 1096.25487103);
  path.cubicTo(-89.207057, 1100.51608977, -89.20444093, 1104.77664765, -89.18319988, 1109.0378555);
  path.cubicTo(-89.17961083, 1110.57472016, -89.18451569, 1112.11163247, -89.19867622, 1113.64843608);
  path.cubicTo(-89.21663415, 1115.72823231, -89.20397896, 1117.80565962, -89.18349248, 1119.88538045);
  path.cubicTo(-89.18427238, 1121.03885716, -89.18505229, 1122.19233388, -89.18585582, 1123.38076444);
  path.cubicTo(-88.18951076, 1128.26651874, -85.01851442, 1130.45992428, -81.02075195, 1133.14404297);
  path.cubicTo(-80.12316162, 1133.65080566, -79.22557129, 1134.15756836, -78.30078125, 1134.6796875);
  path.cubicTo(-77.27791016, 1135.26298828, -76.25503906, 1135.84628906, -75.20117188, 1136.44726562);
  path.cubicTo(-74.10353516, 1137.06279297, -73.00589844, 1137.67832031, -71.875, 1138.3125);
  path.cubicTo(-70.71240346, 1138.97244982, -69.55030293, 1139.63327411, -68.38867188, 1140.29492188);
  path.cubicTo(-65.97797653, 1141.66712386, -63.56520308, 1143.03556082, -61.15087891, 1144.40136719);
  path.cubicTo(-55.60123932, 1147.54499864, -50.0836281, 1150.74415794, -44.5625, 1153.9375);
  path.cubicTo(-42.39859782, 1155.18647571, -40.23453475, 1156.43517273, -38.0703125, 1157.68359375);
  path.cubicTo(-36.99813477, 1158.30218262, -35.92595703, 1158.92077148, -34.82128906, 1159.55810547);
  path.cubicTo(-31.54550434, 1161.44730166, -28.26894107, 1163.33514109, -24.9921875, 1165.22265625);
  path.cubicTo(-13.5080118, 1171.83972892, -2.04053106, 1178.48383977, 9.40332031, 1185.17041016);
  path.cubicTo(19.96370282, 1191.33669054, 30.55876766, 1197.4424595, 41.15527344, 1203.54638672);
  path.cubicTo(46.58409942, 1206.67430148, 52.01069281, 1209.80608448, 57.4375, 1212.9375);
  path.cubicTo(59.60415583, 1214.18751879, 61.7708225, 1215.43751878, 63.9375, 1216.6875);
  path.cubicTo(76.9375, 1224.1875, 89.9375, 1231.6875, 102.9375, 1239.1875);
  path.cubicTo(104.01016113, 1239.80633057, 105.08282227, 1240.42516113, 106.18798828, 1241.06274414);
  path.cubicTo(108.35307071, 1242.31185518, 110.51810982, 1243.56104129, 112.68310547, 1244.81030273);
  path.cubicTo(118.12365706, 1247.94952309, 123.56497216, 1251.08740563, 129.0078125, 1254.22265625);
  path.cubicTo(139.75058669, 1260.41260888, 150.48205382, 1266.62067248, 161.1875, 1272.875);
  path.cubicTo(171.0179057, 1278.61675322, 171.0179057, 1278.61675322, 180.875, 1284.3125);
  path.cubicTo(182.48181641, 1285.23675781, 182.48181641, 1285.23675781, 184.12109375, 1286.1796875);
  path.cubicTo(186.14465441, 1287.51703166, 186.14465441, 1287.51703166, 187.4375, 1287.4375);
  path.cubicTo(187.75797018, 1246.57007956, 188.0046473, 1205.70282294, 188.15241461, 1164.83439693);
  path.cubicTo(188.16992443, 1160.00914343, 188.18804495, 1155.18389239, 188.20654297, 1150.35864258);
  path.cubicTo(188.21021531, 1149.39802542, 188.21388766, 1148.43740825, 188.21767129, 1147.44768148);
  path.cubicTo(188.27858429, 1131.89491404, 188.38896381, 1116.34287133, 188.51763915, 1100.79053379);
  path.cubicTo(188.6485788, 1084.83137043, 188.72632623, 1068.8725865, 188.75473893, 1052.91290802);
  path.cubicTo(188.77394625, 1043.06505111, 188.83459281, 1033.21924252, 188.94833054, 1023.37201624);
  path.cubicTo(189.02235909, 1016.6185634, 189.04469749, 1009.8661687, 189.02651928, 1003.11233962);
  path.cubicTo(189.01755292, 999.21523254, 189.03124364, 995.32170193, 189.10637665, 991.42523193);
  path.cubicTo(190.10814895, 976.7908897, 190.10814895, 976.7908897, 186.08786821, 963.3474586);
  path.cubicTo(182.43145, 959.70331967, 178.27922858, 958.14203175, 173.4375, 956.4375);
  path.cubicTo(171.32660449, 955.18950824, 169.23893478, 953.90022196, 167.19140625, 952.55078125);
  path.cubicTo(165.12857642, 951.28227175, 163.06475176, 950.01537878, 161.0, 948.75);
  path.cubicTo(159.8860083, 948.06574951, 158.7720166, 947.38149902, 157.62426758, 946.67651367);
  path.cubicTo(149.3523864, 941.59799921, 141.06053671, 936.55243425, 132.76513672, 931.51245117);
  path.cubicTo(125.67139701, 927.19875675, 118.6054154, 922.84183601, 111.55029297, 918.46533203);
  path.cubicTo(104.62596738, 914.17036652, 97.69035926, 909.89400491, 90.75, 905.625);
  path.cubicTo(89.65840576, 904.95355957, 88.56681152, 904.28211914, 87.44213867, 903.59033203);
  path.cubicTo(85.21749176, 902.22209668, 82.99280079, 900.85393296, 80.76806641, 899.48583984);
  path.cubicTo(76.4034502, 896.80154649, 72.03957103, 894.11605651, 67.67578125, 891.43041992);
  path.cubicTo(65.51569208, 890.10104659, 63.35553575, 888.77178239, 61.1953125, 887.44262695);
  path.cubicTo(55.73981959, 884.08587398, 50.28515559, 880.72778709, 44.83203125, 877.3671875);
  path.cubicTo(42.63807533, 876.01553654, 40.44406514, 874.66397366, 38.25, 873.3125);
  path.cubicTo(36.63399902, 872.31694092, 36.63399902, 872.31694092, 34.98535156, 871.30126953);
  path.cubicTo(28.85467197, 867.52818734, 22.71064899, 863.77832687, 16.55322266, 860.04907227);
  path.cubicTo(7.77963296, 854.73244733, -0.95337175, 849.35661485, -9.625, 843.875);
  path.cubicTo(-10.53540039, 843.30313965, -11.44580078, 842.7312793, -12.38378906, 842.14208984);
  path.cubicTo(-24.34881798, 834.53475063, -32.38859167, 826.45828482, -36.10144085, 812.39632827);
  path.cubicTo(-36.76156374, 808.16001656, -36.70590472, 803.9830506, -36.7011652, 799.70171642);
  path.cubicTo(-36.70400742, 798.70993697, -36.70684964, 797.71815752, -36.70977798, 796.69632414);
  path.cubicTo(-36.71814043, 793.35265078, -36.71939441, 790.009012, -36.72071838, 786.66532898);
  path.cubicTo(-36.72528268, 784.25212945, -36.7302825, 781.83893071, -36.73568195, 779.42573291);
  path.cubicTo(-36.74644239, 774.16856556, -36.75411131, 768.91140707, -36.75908089, 763.65423203);
  path.cubicTo(-36.76648712, 755.83698692, -36.77957033, 748.01975855, -36.79382664, 740.2025233);
  path.cubicTo(-36.81764588, 727.05316377, -36.8368464, 713.90380126, -36.85342598, 700.75443077);
  path.cubicTo(-36.86985985, 687.73255696, -36.8883396, 674.71068872, -36.90955925, 661.68882179);
  path.cubicTo(-36.91087686, 660.87953897, -36.91219446, 660.07025615, -36.913552, 659.23644961);
  path.cubicTo(-36.92025397, 655.12660812, -36.92699256, 651.0167667, -36.93374526, 646.9069253);
  path.cubicTo(-36.9815242, 617.78748358, -37.02470466, 588.66803668, -37.06518555, 559.54858398);
  path.cubicTo(-37.10452574, 531.257239, -37.14594591, 502.96589831, -37.19018555, 474.67456055);
  path.cubicTo(-37.19222934, 473.36675401, -37.19222934, 473.36675401, -37.19431442, 472.03252715);
  path.cubicTo(-37.20799965, 463.27693963, -37.2217272, 454.52135218, -37.23548577, 445.76576478);
  path.cubicTo(-37.26351325, 427.92919615, -37.29125822, 410.09262708, -37.3188324, 392.25605774);
  path.cubicTo(-37.3201006, 391.43593866, -37.3213688, 390.61581958, -37.32267542, 389.7708484);
  path.cubicTo(-37.40734917, 334.99307258, -37.48541639, 280.21528697, -37.5625, 225.4375);
  path.cubicTo(-40.12880065, 224.15353626, -42.69518873, 222.86974779, -45.2616272, 221.58605957);
  path.cubicTo(-45.98441644, 221.22441334, -46.70720568, 220.86276711, -47.45189762, 220.4901619);
  path.cubicTo(-54.53292332, 216.94867892, -61.63851957, 213.45987097, -68.75878906, 209.99804688);
  path.cubicTo(-70.23716411, 209.27840756, -71.71467627, 208.55699342, -73.19140625, 207.83398438);
  path.cubicTo(-75.36276543, 206.77096244, -77.53652774, 205.7130151, -79.7109375, 204.65625);
  path.cubicTo(-80.37225677, 204.33136597, -81.03357605, 204.00648193, -81.7149353, 203.67175293);
  path.cubicTo(-84.98809809, 201.98828348, -84.98809809, 201.98828348, -88.5625, 201.4375);
  path.close();
  path.moveTo(81.9921875, 204.91015625);
  path.cubicTo(81.23011993, 205.2708873, 80.46805237, 205.63161835, 79.68289185, 206.00328064);
  path.cubicTo(77.22523364, 207.16704682, 74.76882624, 208.33342547, 72.3125, 209.5);
  path.cubicTo(69.90592289, 210.64107044, 67.49908214, 211.78158196, 65.09207153, 212.92173767);
  path.cubicTo(63.59443053, 213.63134772, 62.09706585, 214.34154147, 60.60006714, 215.05250549);
  path.cubicTo(55.61755936, 217.41600098, 50.62340482, 219.75395649, 45.6255188, 222.08470154);
  path.cubicTo(44.93261025, 222.40794261, 44.23970171, 222.73118369, 43.52579594, 223.06421995);
  path.cubicTo(41.82974249, 223.85541021, 40.1336275, 224.64646851, 38.4375, 225.4375);
  path.cubicTo(37.99227765, 278.50449817, 37.57836065, 331.57165816, 37.33657837, 384.64001465);
  path.cubicTo(37.33298889, 385.42584902, 37.3293994, 386.21168339, 37.32570115, 387.02133093);
  path.cubicTo(37.24787959, 404.10097879, 37.17585572, 421.1806465, 37.10980143, 438.26034382);
  path.cubicTo(37.07737161, 446.63662033, 37.04366109, 455.01289146, 37.00927734, 463.38916016);
  path.cubicTo(37.00587761, 464.22268508, 37.00247787, 465.05621, 36.99897511, 465.91499325);
  path.cubicTo(36.88824316, 492.91642692, 36.69300071, 519.91644291, 36.45377226, 546.91701823);
  path.cubicTo(36.20831285, 574.67136456, 36.04843092, 602.42492688, 35.99571026, 630.18034028);
  path.cubicTo(35.9882186, 634.10346961, 35.97975205, 638.02659628, 35.97069168, 641.94972229);
  path.cubicTo(35.96893868, 642.72182464, 35.96718568, 643.49392699, 35.96537957, 644.28942638);
  path.cubicTo(35.9346921, 656.70253803, 35.81421517, 669.11322045, 35.65986712, 681.52534258);
  path.cubicTo(35.5064917, 694.01418926, 35.44840358, 706.50063642, 35.48646419, 718.99039125);
  path.cubicTo(35.50446522, 725.75561865, 35.47772512, 732.51332202, 35.33815765, 739.2773571);
  path.cubicTo(33.31599266, 764.77918286, 33.31599266, 764.77918286, 40.92139864, 788.08460808);
  path.cubicTo(46.46769914, 793.83157785, 53.51515056, 796.68411156, 61.00015187, 799.14905071);
  path.cubicTo(66.99291146, 801.39536576, 72.09507448, 804.94905285, 77.4375, 808.4375);
  path.cubicTo(79.5924914, 809.78128975, 81.75878984, 811.10521456, 83.92578125, 812.4296875);
  path.cubicTo(88.29911829, 815.1208707, 92.67140634, 817.81374761, 97.04296875, 820.5078125);
  path.cubicTo(107.42925629, 826.90688506, 117.82376217, 833.29118857, 128.25, 839.625);
  path.cubicTo(136.29891126, 844.51502591, 144.32158677, 849.44509252, 152.32470703, 854.40966797);
  path.cubicTo(159.24903262, 858.70463348, 166.18463988, 862.98099648, 173.125, 867.25);
  path.cubicTo(174.20716797, 867.91563965, 175.28933594, 868.5812793, 176.40429688, 869.26708984);
  path.cubicTo(178.61942314, 870.62946446, 180.83459283, 871.99176848, 183.04980469, 873.35400391);
  path.cubicTo(188.78395516, 876.88061389, 194.51691432, 880.40915939, 200.25, 883.9375);
  path.cubicTo(204.80423259, 886.7403531, 204.80423259, 886.7403531, 209.36743164, 889.52856445);
  path.cubicTo(211.57446569, 890.90087453, 213.73873818, 892.29731509, 215.89624023, 893.74291992);
  path.cubicTo(216.47439987, 894.1214209, 217.05255951, 894.49992187, 217.64823914, 894.88989258);
  path.cubicTo(219.27040251, 895.9533881, 220.88117448, 897.03420002, 222.49121094, 898.1159668);
  path.cubicTo(225.35688451, 899.73214691, 225.35688451, 899.73214691, 228.34863281, 898.92651367);
  path.cubicTo(230.9214323, 897.72837677, 233.2181852, 896.30331361, 235.5546875, 894.69628906);
  path.cubicTo(238.50234604, 892.72557752, 241.58161798, 890.98972285, 244.64819336, 889.21191406);
  path.cubicTo(247.48734352, 887.55961967, 250.30927101, 885.88067633, 253.12890625, 884.1953125);
  path.cubicTo(260.00203147, 880.09348551, 266.90556615, 876.04451498, 273.8125, 872.0);
  path.cubicTo(275.05982617, 871.26914435, 276.30714061, 870.53826867, 277.55444336, 869.80737305);
  path.cubicTo(286.14289869, 864.77584434, 294.73943908, 859.75825282, 303.33935547, 854.74633789);
  path.cubicTo(311.21290974, 850.15615376, 319.0762568, 845.54872, 326.9375, 840.9375);
  path.cubicTo(340.7231755, 832.85151223, 354.52640191, 824.79587162, 368.33496094, 816.74902344);
  path.cubicTo(380.83340801, 809.46491001, 393.32199894, 802.16430275, 405.79989624, 794.84506226);
  path.cubicTo(414.97198913, 789.46515105, 424.1526275, 784.10015113, 433.33984375, 778.74609375);
  path.cubicTo(441.82567324, 773.79884389, 450.2995113, 768.83129349, 458.77206421, 763.86135864);
  path.cubicTo(470.98193862, 756.69956399, 483.20641499, 749.56301934, 495.4375, 742.4375);
  path.cubicTo(492.50774778, 740.1499904, 489.49749635, 738.23771208, 486.2734375, 736.390625);
  path.cubicTo(485.24734375, 735.80087891, 484.22125, 735.21113281, 483.1640625, 734.60351562);
  path.cubicTo(482.05804687, 733.97123047, 480.95203125, 733.33894531, 479.8125, 732.6875);
  path.cubicTo(478.64567378, 732.01785607, 477.47900991, 731.34792916, 476.3125, 730.67773438);
  path.cubicTo(473.88962488, 729.28601231, 471.46605654, 727.89550896, 469.04199219, 726.50585938);
  path.cubicTo(463.50059989, 723.32778979, 457.96956414, 720.13176919, 452.4375, 716.9375);
  path.cubicTo(445.9152824, 713.1736615, 439.3923622, 709.41105368, 432.8671875, 705.65234375);
  path.cubicTo(421.3830118, 699.03527108, 409.91553106, 692.39116023, 398.47167969, 685.70458984);
  path.cubicTo(387.91129718, 679.53830946, 377.31623234, 673.4325405, 366.71972656, 667.32861328);
  path.cubicTo(361.29090058, 664.20069852, 355.86430719, 661.06891552, 350.4375, 657.9375);
  path.cubicTo(348.27084417, 656.68748121, 346.1041775, 655.43748122, 343.9375, 654.1875);
  path.cubicTo(339.60416667, 651.6875, 335.27083333, 649.1875, 330.9375, 646.6875);
  path.cubicTo(329.86483887, 646.06866943, 328.79217773, 645.44983887, 327.68701172, 644.81225586);
  path.cubicTo(325.52192929, 643.56314482, 323.35689018, 642.31395871, 321.19189453, 641.06469727);
  path.cubicTo(315.75134294, 637.92547691, 310.31002784, 634.78759437, 304.8671875, 631.65234375);
  path.cubicTo(294.37517603, 625.60694667, 283.89292923, 619.54598025, 273.4375, 613.4375);
  path.cubicTo(264.81877202, 608.40584008, 256.1968606, 603.37978581, 247.5625, 598.375);
  path.cubicTo(245.96728516, 597.4459082, 245.96728516, 597.4459082, 244.33984375, 596.49804688);
  path.cubicTo(241.38467487, 594.78824384, 238.41646041, 593.10545267, 235.4375, 591.4375);
  path.cubicTo(234.52452148, 590.91687988, 233.61154297, 590.39625977, 232.67089844, 589.85986328);
  path.cubicTo(231.37587402, 589.15772705, 231.37587402, 589.15772705, 230.0546875, 588.44140625);
  path.cubicTo(229.30558105, 588.02834229, 228.55647461, 587.61527832, 227.78466797, 587.18969727);
  path.cubicTo(223.794899, 585.91109542, 220.64590103, 586.8695963, 216.93408203, 588.61401367);
  path.cubicTo(215.70214111, 589.35228394, 215.70214111, 589.35228394, 214.4453125, 590.10546875);
  path.cubicTo(213.03475586, 590.9404187, 213.03475586, 590.9404187, 211.59570312, 591.79223633);
  path.cubicTo(210.09426758, 592.69945435, 210.09426758, 592.69945435, 208.5625, 593.625);
  path.cubicTo(206.40898057, 594.90385872, 204.25533097, 596.18249825, 202.1015625, 597.4609375);
  path.cubicTo(200.99973633, 598.11932617, 199.89791016, 598.77771484, 198.76269531, 599.45605469);
  path.cubicTo(190.5869746, 604.32787182, 182.35051723, 609.0973084, 174.12011719, 613.87597656);
  path.cubicTo(171.65096676, 615.31324323, 169.18847322, 616.76132211, 166.7265625, 618.2109375);
  path.cubicTo(153.83409552, 625.73951427, 142.88270639, 629.52328878, 127.640625, 626.96875);
  path.cubicTo(114.2547727, 623.38782136, 102.88488186, 615.24384722, 95.7265625, 603.41796875);
  path.cubicTo(91.46063046, 593.55461679, 91.00219297, 583.97551325, 91.03877258, 573.38471985);
  path.cubicTo(91.03332551, 571.77479891, 91.0265708, 570.16488197, 91.01863068, 568.5549714);
  path.cubicTo(91.00068072, 564.15596647, 91.00115315, 559.75713102, 91.00476015, 555.35809815);
  path.cubicTo(91.00538582, 550.60498169, 90.98874691, 545.85192119, 90.97424316, 541.09883118);
  path.cubicTo(90.95148461, 532.87203363, 90.93957678, 524.64527835, 90.93511391, 516.41845131);
  path.cubicTo(90.9286456, 504.52396471, 90.90569621, 492.62955442, 90.87877061, 480.73509862);
  path.cubicTo(90.83552734, 461.43547037, 90.80554653, 442.13584534, 90.78393555, 422.83618164);
  path.cubicTo(90.76291849, 404.09235045, 90.73563703, 385.34854558, 90.69995117, 366.60473633);
  path.cubicTo(90.69775235, 365.448672, 90.69555352, 364.29260768, 90.69328807, 363.1015111);
  path.cubicTo(90.68221823, 357.30166823, 90.67102546, 351.50182561, 90.65977156, 345.70198309);
  path.cubicTo(90.56662129, 297.61384534, 90.49500717, 249.52569268, 90.4375, 201.4375);
  path.cubicTo(87.71435703, 201.4375, 84.47332902, 203.72939906, 81.9921875, 204.91015625);
  path.close();
  path.moveTo(226.22265625, 271.33984375);
  path.cubicTo(225.15716553, 271.97486816, 224.0916748, 272.60989258, 222.99389648, 273.26416016);
  path.cubicTo(221.82915297, 273.96758909, 220.66452376, 274.67120732, 219.5, 275.375);
  path.cubicTo(218.2985502, 276.09472551, 217.09680386, 276.8139562, 215.89477539, 277.53271484);
  path.cubicTo(212.06936733, 279.8238906, 208.25265345, 282.1292998, 204.4375, 284.4375);
  path.cubicTo(203.80034058, 284.82274841, 203.16318115, 285.20799683, 202.50671387, 285.60491943);
  path.cubicTo(194.9002195, 290.20490861, 187.30279983, 294.81959692, 179.71459961, 299.44970703);
  path.cubicTo(176.4375, 301.4375, 176.4375, 301.4375, 173.96988201, 302.20050049);
  path.cubicTo(170.59273853, 303.51683804, 168.80820584, 304.66242759, 166.4375, 307.4375);
  path.cubicTo(164.41052466, 314.14475439, 165.17875122, 321.67134092, 165.30224609, 328.58935547);
  path.cubicTo(165.30506722, 330.78725556, 165.30348274, 332.98516508, 165.29782104, 335.18305969);
  path.cubicTo(165.29495033, 341.1482154, 165.35376238, 347.11136262, 165.42356062, 353.07605124);
  path.cubicTo(165.48605111, 359.30996627, 165.49194608, 365.54392678, 165.5038147, 371.77810669);
  path.cubicTo(165.53137013, 382.24109013, 165.5938413, 392.70338571, 165.68310547, 403.16601562);
  path.cubicTo(165.77493916, 413.94104332, 165.84570136, 424.71587075, 165.88818359, 435.49121094);
  path.cubicTo(165.89081083, 436.15573461, 165.89343806, 436.82025828, 165.89614491, 437.50491904);
  path.cubicTo(165.90919558, 440.8387419, 165.92181003, 444.17256613, 165.93426394, 447.50639129);
  path.cubicTo(166.03880536, 475.15060743, 166.21471051, 502.79400187, 166.4375, 530.4375);
  path.cubicTo(167.18298096, 530.02984406, 167.92846191, 529.62218811, 168.6965332, 529.20217896);
  path.cubicTo(169.67968506, 528.66511322, 170.66283691, 528.12804749, 171.67578125, 527.57470703);
  path.cubicTo(172.64813721, 527.04330109, 173.62049316, 526.51189514, 174.62231445, 525.96438599);
  path.cubicTo(197.36390604, 513.62991747, 220.0588874, 505.64303962, 245.95703125, 512.921875);
  path.cubicTo(260.19698693, 517.44654205, 273.27762547, 525.27142698, 285.99023438, 532.97265625);
  path.cubicTo(290.91469984, 535.92026128, 295.89993048, 538.76395877, 300.875, 541.625);
  path.cubicTo(303.12112758, 542.91921213, 305.36722094, 544.21348363, 307.61328125, 545.5078125);
  path.cubicTo(309.88799125, 546.8177597, 312.16273069, 548.12765579, 314.4375, 549.4375);
  path.cubicTo(328.1132895, 557.31369333, 341.77711286, 565.20870284, 355.40332031, 573.17041016);
  path.cubicTo(365.96370282, 579.33669054, 376.55876766, 585.4424595, 387.15527344, 591.54638672);
  path.cubicTo(392.58409942, 594.67430148, 398.01069281, 597.80608448, 403.4375, 600.9375);
  path.cubicTo(405.60415583, 602.18751879, 407.7708225, 603.43751878, 409.9375, 604.6875);
  path.cubicTo(429.4375, 615.9375, 429.4375, 615.9375, 448.9375, 627.1875);
  path.cubicTo(450.01016113, 627.80633057, 451.08282227, 628.42516113, 452.18798828, 629.06274414);
  path.cubicTo(454.35307071, 630.31185518, 456.51810982, 631.56104129, 458.68310547, 632.81030273);
  path.cubicTo(464.12365706, 635.94952309, 469.56497216, 639.08740563, 475.0078125, 642.22265625);
  path.cubicTo(486.4919882, 648.83972892, 497.95946894, 655.48383977, 509.40332031, 662.17041016);
  path.cubicTo(516.69372739, 666.42732927, 523.99914902, 670.65763245, 531.3125, 674.875);
  path.cubicTo(532.38330811, 675.4932666, 533.45411621, 676.1115332, 534.55737305, 676.74853516);
  path.cubicTo(539.58266525, 679.64798834, 544.61176078, 682.54014244, 549.65493774, 685.40840149);
  path.cubicTo(574.17698723, 699.35679197, 574.17698723, 699.35679197, 583.4375, 706.4375);
  path.cubicTo(584.16066406, 706.97890625, 584.88382813, 707.5203125, 585.62890625, 708.078125);
  path.cubicTo(595.83616374, 716.30785119, 602.68473111, 727.37399357, 607.4375, 739.4375);
  path.cubicTo(607.91123047, 740.60539063, 607.91123047, 740.60539063, 608.39453125, 741.796875);
  path.cubicTo(612.57785402, 753.08978574, 612.73182484, 765.1300416, 612.69819641, 777.02243042);
  path.cubicTo(612.70122352, 778.55738736, 612.70511578, 780.0923428, 612.70978898, 781.62729561);
  path.cubicTo(612.7200056, 785.81037674, 612.71790347, 789.99337155, 612.71360838, 794.17645955);
  path.cubicTo(612.71112958, 798.7014502, 612.72016955, 803.22642067, 612.72764587, 807.75140381);
  path.cubicTo(612.74036266, 816.60266654, 612.74219037, 825.45389888, 612.73984561, 834.30516921);
  path.cubicTo(612.73805902, 841.50296052, 612.7398194, 848.70074265, 612.74407005, 855.89853287);
  path.cubicTo(612.74466524, 856.92487504, 612.74526043, 857.95121721, 612.74587366, 859.00866065);
  path.cubicTo(612.74708547, 861.09399874, 612.7482996, 863.17933683, 612.74951603, 865.26467492);
  path.cubicTo(612.7603798, 884.79872975, 612.75823451, 904.33276729, 612.75213119, 923.86682309);
  path.cubicTo(612.74696228, 941.716431, 612.75821886, 959.56598433, 612.77722941, 977.41558145);
  path.cubicTo(612.79662544, 995.768602, 612.80486076, 1014.12159675, 612.80110615, 1032.47462761);
  path.cubicTo(612.79919689, 1042.76844144, 612.80165491, 1053.06220881, 612.81582069, 1063.35601425);
  path.cubicTo(612.82775793, 1072.11863857, 612.8291131, 1080.88118784, 612.81703053, 1089.64381324);
  path.cubicTo(612.81115847, 1094.10949826, 612.8099959, 1098.57504616, 612.82203293, 1103.04072189);
  path.cubicTo(612.83294789, 1107.13791184, 612.82972237, 1111.2348511, 612.81577124, 1115.3320296);
  path.cubicTo(612.81313968, 1116.80498015, 612.81544173, 1118.27795072, 612.82350711, 1119.75088154);
  path.cubicTo(612.94173957, 1142.97649121, 606.60505312, 1164.24699984, 590.4375, 1181.4375);
  path.cubicTo(582.96378108, 1188.57833776, 574.7675345, 1193.98101997, 565.83349609, 1199.07080078);
  path.cubicTo(563.08626158, 1200.63784977, 560.34963698, 1202.2226261, 557.61328125, 1203.80859375);
  path.cubicTo(552.03619612, 1207.03772518, 546.4514506, 1210.25336666, 540.86474609, 1213.46582031);
  path.cubicTo(535.38594203, 1216.61775232, 529.91188887, 1219.77790797, 524.4375, 1222.9375);
  path.cubicTo(522.27085774, 1224.1875423, 520.10419103, 1225.43754224, 517.9375, 1226.6875);
  path.cubicTo(516.32875, 1227.615625, 516.32875, 1227.615625, 514.6875, 1228.5625);
  path.cubicTo(504.9375, 1234.1875, 504.9375, 1234.1875, 501.68701172, 1236.06274414);
  path.cubicTo(499.52192929, 1237.31185518, 497.35689018, 1238.56104129, 495.19189453, 1239.81030273);
  path.cubicTo(489.75134294, 1242.94952309, 484.31002784, 1246.08740563, 478.8671875, 1249.22265625);
  path.cubicTo(468.37517906, 1255.26805159, 457.89268324, 1261.32860219, 447.4375, 1267.4375);
  path.cubicTo(435.89020484, 1274.18451194, 424.30847973, 1280.87089318, 412.71972656, 1287.54638672);
  path.cubicTo(407.29090058, 1290.67430148, 401.86430719, 1293.80608448, 396.4375, 1296.9375);
  path.cubicTo(394.27084417, 1298.18751879, 392.1041775, 1299.43751878, 389.9375, 1300.6875);
  path.cubicTo(388.865, 1301.30625, 387.7925, 1301.925, 386.6875, 1302.5625);
  path.cubicTo(376.93750001, 1308.18749999, 376.93750001, 1308.18749999, 373.68701172, 1310.06274414);
  path.cubicTo(371.52192929, 1311.31185518, 369.35689018, 1312.56104129, 367.19189453, 1313.81030273);
  path.cubicTo(361.75134294, 1316.94952309, 356.31002784, 1320.08740563, 350.8671875, 1323.22265625);
  path.cubicTo(340.37517754, 1329.26805246, 329.89280616, 1335.32881082, 319.4375, 1341.4375);
  path.cubicTo(237.02719668, 1389.56932091, 237.02719668, 1389.56932091, 205.92773438, 1382.19335938);
  path.cubicTo(196.74305022, 1379.70243456, 188.26021627, 1375.48698905, 179.875, 1371.0625);
  path.cubicTo(179.06619385, 1370.63606201, 178.2573877, 1370.20962402, 177.42407227, 1369.77026367);
  path.cubicTo(167.65422938, 1364.56134469, 158.14259589, 1358.91197713, 148.60400391, 1353.29492188);
  path.cubicTo(143.27332945, 1350.16803126, 137.91791574, 1347.08426242, 132.5625, 1344.0);
  path.cubicTo(131.48427979, 1343.37851074, 130.40605957, 1342.75702148, 129.29516602, 1342.11669922);
  path.cubicTo(126.00959228, 1340.22308559, 122.72361022, 1338.33018247, 119.4375, 1336.4375);
  path.cubicTo(105.76195686, 1328.56087411, 92.09789042, 1320.66629908, 78.47167969, 1312.70458984);
  path.cubicTo(67.91129718, 1306.53830946, 57.31623234, 1300.4325405, 46.71972656, 1294.32861328);
  path.cubicTo(41.29090058, 1291.20069852, 35.86430719, 1288.06891552, 30.4375, 1284.9375);
  path.cubicTo(28.27084417, 1283.68748121, 26.1041775, 1282.43748122, 23.9375, 1281.1875);
  path.cubicTo(10.9375, 1273.6875, -2.0625, 1266.1875, -15.0625, 1258.6875);
  path.cubicTo(-16.13516113, 1258.06866943, -17.20782227, 1257.44983887, -18.31298828, 1256.81225586);
  path.cubicTo(-20.47807071, 1255.56314482, -22.64310982, 1254.31395871, -24.80810547, 1253.06469727);
  path.cubicTo(-30.24865706, 1249.92547691, -35.68997216, 1246.78759437, -41.1328125, 1243.65234375);
  path.cubicTo(-52.61045062, 1237.03903798, -64.0721644, 1230.39998753, -75.50854492, 1223.71557617);
  path.cubicTo(-82.9902286, 1219.34586865, -90.49222173, 1215.01218933, -98.0, 1210.6875);
  path.cubicTo(-101.21086856, 1208.8344284, -104.42140939, 1206.98079038, -107.63183594, 1205.12695312);
  path.cubicTo(-110.30653456, 1203.58505755, -112.98497922, 1202.04988297, -115.6640625, 1200.515625);
  path.cubicTo(-123.04829799, 1196.26335902, -130.04493411, 1191.97049742, -136.5625, 1186.4375);
  path.cubicTo(-137.44035156, 1185.77427734, -137.44035156, 1185.77427734, -138.3359375, 1185.09765625);
  path.cubicTo(-153.82433505, 1173.00829617, -161.25923375, 1153.70728157, -164.09924358, 1134.87909365);
  path.cubicTo(-164.71490036, 1129.78201276, -164.70644703, 1124.71117805, -164.7011652, 1119.58293915);
  path.cubicTo(-164.70400742, 1118.50665622, -164.70684964, 1117.4303733, -164.70977798, 1116.32147574);
  path.cubicTo(-164.71811203, 1112.70840935, -164.71939219, 1109.09537507, -164.72071838, 1105.4822998);
  path.cubicTo(-164.72528461, 1102.86852076, -164.73028472, 1100.25474244, -164.73568195, 1097.64096498);
  path.cubicTo(-164.74672393, 1091.95484326, -164.75410485, 1086.26872596, -164.75908089, 1080.58259583);
  path.cubicTo(-164.76649668, 1072.12754919, -164.77958209, 1063.67251796, -164.79382664, 1055.21748041);
  path.cubicTo(-164.81762861, 1040.99426999, -164.83683639, 1026.77105682, -164.85342598, 1012.5478363);
  path.cubicTo(-164.86986679, 998.46503829, -164.88834947, 984.3822454, -164.90955925, 970.29945374);
  path.cubicTo(-164.91087686, 969.42383249, -164.91219446, 968.54821124, -164.913552, 967.64605602);
  path.cubicTo(-164.92025408, 963.19921925, -164.92699265, 958.75238255, -164.93374526, 954.30554587);
  path.cubicTo(-164.98150849, 922.80851992, -165.02469347, 891.31148919, -165.06518555, 859.81445312);
  path.cubicTo(-165.10453355, 829.21549126, -165.14595563, 798.61653334, -165.19018555, 768.01757812);
  path.cubicTo(-165.19154808, 767.074387, -165.19291061, 766.13119587, -165.19431442, 765.15942319);
  path.cubicTo(-165.2079998, 755.68751135, -165.22172734, 746.21559956, -165.23548577, 736.74368781);
  path.cubicTo(-165.26351232, 717.44830688, -165.29125745, 698.15292553, -165.3188324, 678.85754395);
  path.cubicTo(-165.3201006, 677.97037327, -165.3213688, 677.08320259, -165.32267542, 676.16914795);
  path.cubicTo(-165.40733152, 616.92527173, -165.48542721, 557.68138651, -165.5625, 498.4375);
  path.cubicTo(-167.28639692, 499.3759665, -169.010066, 500.31485154, -170.73364258, 501.25390625);
  path.cubicTo(-172.17348259, 502.03809937, -172.17348259, 502.03809937, -173.64241028, 502.83813477);
  path.cubicTo(-178.19936507, 505.33402899, -182.72721577, 507.88032746, -187.25, 510.4375);
  path.cubicTo(-188.23766357, 510.9958252, -189.22532715, 511.55415039, -190.24291992, 512.12939453);
  path.cubicTo(-198.32269995, 516.70978605, -206.35252478, 521.37251451, -214.36791992, 526.06445312);
  path.cubicTo(-221.74936392, 530.38483367, -229.1506684, 534.66948033, -236.5625, 538.9375);
  path.cubicTo(-248.92283241, 546.05817622, -261.24717466, 553.23933459, -273.5625, 560.4375);
  path.cubicTo(-277.52035474, 562.75082038, -281.47861894, 565.0634364, -285.4375, 567.375);
  path.cubicTo(-286.91065674, 568.23532837, -286.91065674, 568.23532837, -288.41357422, 569.11303711);
  path.cubicTo(-294.75860618, 572.81421971, -301.11854387, 576.48862336, -307.48681641, 580.1496582);
  path.cubicTo(-316.70448832, 585.45140974, -325.9128472, 590.76901736, -335.0625, 596.1875);
  path.cubicTo(-335.89942383, 596.67686035, -336.73634766, 597.1662207, -337.59863281, 597.67041016);
  path.cubicTo(-338.36014648, 598.12464355, -339.12166016, 598.57887695, -339.90625, 599.046875);
  path.cubicTo(-340.56818359, 599.43842773, -341.23011719, 599.82998047, -341.91210938, 600.23339844);
  path.cubicTo(-343.85908431, 601.50837487, -343.85908431, 601.50837487, -345.5625, 604.4375);
  path.cubicTo(-345.86272916, 606.62696004, -345.86272916, 606.62696004, -345.81549966, 609.08872837);
  path.cubicTo(-345.82101915, 610.05196804, -345.82653864, 611.01520771, -345.83222538, 612.00763646);
  path.cubicTo(-345.82811475, 613.07031478, -345.82400411, 614.13299311, -345.81976891, 615.2278738);
  path.cubicTo(-345.82327498, 616.35797057, -345.82678105, 617.48806734, -345.83039337, 618.65240946);
  path.cubicTo(-345.83977435, 622.47872421, -345.83476686, 626.30488898, -345.82992554, 630.13121033);
  path.cubicTo(-345.83255303, 632.88631948, -345.8381782, 635.64142068, -345.84365618, 638.39652544);
  path.cubicTo(-345.85398407, 644.40704458, -345.85679516, 650.41753149, -345.85474396, 656.42805862);
  path.cubicTo(-345.85170121, 665.36576479, -345.86000175, 674.30343514, -345.87049321, 683.24113436);
  path.cubicTo(-345.8898636, 700.13013618, -345.89546255, 717.01912588, -345.89660732, 733.90813749);
  path.cubicTo(-345.89752535, 746.94674651, -345.90163648, 759.98535074, -345.90800858, 773.02395821);
  path.cubicTo(-345.90980358, 776.77300486, -345.9115832, 780.52205153, -345.91335833, 784.2710982);
  path.cubicTo(-345.91380043, 785.20303921, -345.91424252, 786.13498022, -345.91469802, 787.09516187);
  path.cubicTo(-345.92701115, 813.3187073, -345.93489866, 839.54225108, -345.93401146, 865.76579952);
  path.cubicTo(-345.9339803, 866.75505125, -345.93394914, 867.74430299, -345.93391704, 868.76353204);
  path.cubicTo(-345.93375082, 873.77782263, -345.93355274, 878.79211322, -345.93334763, 883.80640381);
  path.cubicTo(-345.93330774, 884.8023157, -345.93326785, 885.79822758, -345.93322675, 886.82431862);
  path.cubicTo(-345.93314587, 888.83829567, -345.93306228, 890.85227272, -345.93297596, 892.86624977);
  path.cubicTo(-345.93175005, 924.21090055, -345.9467692, 955.55550808, -345.97412109, 986.90014648);
  path.cubicTo(-346.00481534, 1022.08981671, -346.02205522, 1057.27945851, -346.02019465, 1092.46914297);
  path.cubicTo(-346.02004538, 1096.21850399, -346.01994797, 1099.96786501, -346.01988602, 1103.71722603);
  path.cubicTo(-346.01986271, 1104.64046136, -346.0198394, 1105.56369668, -346.01981538, 1106.51490884);
  path.cubicTo(-346.01975374, 1121.3978091, -346.032547, 1136.28067195, -346.04975055, 1151.16356107);
  path.cubicTo(-346.06667096, 1166.11020916, -346.06870911, 1181.05680227, -346.0555319, 1196.00345462);
  path.cubicTo(-346.04811886, 1204.89205193, -346.05187056, 1213.78048264, -346.07141658, 1222.66906244);
  path.cubicTo(-346.0833588, 1228.59895234, -346.0808902, 1234.52872074, -346.06647559, 1240.45860492);
  path.cubicTo(-346.0586633, 1243.84231989, -346.05947863, 1247.22544488, -346.07339029, 1250.60918056);
  path.cubicTo(-346.08736326, 1254.24685229, -346.07704143, 1257.8836448, -346.06027794, 1261.52128506);
  path.cubicTo(-346.0702143, 1262.58162221, -346.08015066, 1263.64195937, -346.09038812, 1264.73442796);
  path.cubicTo(-346.13236289, 1270.25122197, -346.13236289, 1270.25122197, -343.68513644, 1275.01920801);
  path.cubicTo(-341.26479526, 1276.63641878, -338.86270759, 1278.18217304, -336.328125, 1279.6171875);
  path.cubicTo(-334.77351563, 1280.50470703, -334.77351563, 1280.50470703, -333.1875, 1281.41015625);
  path.cubicTo(-332.07375, 1282.03792969, -330.96, 1282.66570313, -329.8125, 1283.3125);
  path.cubicTo(-328.64019601, 1283.97971557, -327.46832746, 1284.64769675, -326.296875, 1285.31640625);
  path.cubicTo(-324.49266193, 1286.34625122, -322.68822035, 1287.37566511, -320.88244629, 1288.402771);
  path.cubicTo(-315.08258131, 1291.70242444, -309.32033777, 1295.06510724, -303.5625, 1298.4375);
  path.cubicTo(-295.24549084, 1303.29939221, -286.91047775, 1308.1289855, -278.5625, 1312.9375);
  path.cubicTo(-269.22386793, 1318.3166408, -259.90609683, 1323.73009447, -250.6015625, 1329.16796875);
  path.cubicTo(-243.26966277, 1333.44972122, -235.91982762, 1337.69960939, -228.5625, 1341.9375);
  path.cubicTo(-219.22386793, 1347.3166408, -209.90609683, 1352.73009447, -200.6015625, 1358.16796875);
  path.cubicTo(-193.26966277, 1362.44972122, -185.91982762, 1366.69960939, -178.5625, 1370.9375);
  path.cubicTo(-169.22386793, 1376.3166408, -159.90609683, 1381.73009447, -150.6015625, 1387.16796875);
  path.cubicTo(-143.26966277, 1391.44972122, -135.91982762, 1395.69960939, -128.5625, 1399.9375);
  path.cubicTo(-119.22386793, 1405.3166408, -109.90609683, 1410.73009447, -100.6015625, 1416.16796875);
  path.cubicTo(-93.26966277, 1420.44972122, -85.91982762, 1424.69960939, -78.5625, 1428.9375);
  path.cubicTo(-69.22386793, 1434.3166408, -59.90609683, 1439.73009447, -50.6015625, 1445.16796875);
  path.cubicTo(-43.26966277, 1449.44972122, -35.91982762, 1453.69960939, -28.5625, 1457.9375);
  path.cubicTo(-19.22386793, 1463.3166408, -9.90609683, 1468.73009447, -0.6015625, 1474.16796875);
  path.cubicTo(6.73033723, 1478.44972122, 14.08017238, 1482.69960939, 21.4375, 1486.9375);
  path.cubicTo(30.77613207, 1492.3166408, 40.09390317, 1497.73009447, 49.3984375, 1503.16796875);
  path.cubicTo(56.73033723, 1507.44972122, 64.08017238, 1511.69960939, 71.4375, 1515.9375);
  path.cubicTo(80.77613207, 1521.3166408, 90.09390317, 1526.73009447, 99.3984375, 1532.16796875);
  path.cubicTo(106.73033764, 1536.44972146, 114.08020807, 1540.69954691, 121.4375, 1544.9375);
  path.cubicTo(134.78765665, 1552.62867469, 148.09483128, 1560.3923296, 161.39648438, 1568.16699219);
  path.cubicTo(164.36815506, 1569.90356837, 167.34018519, 1571.63952654, 170.3125, 1573.375);
  path.cubicTo(171.78783203, 1574.23641602, 171.78783203, 1574.23641602, 173.29296875, 1575.11523438);
  path.cubicTo(178.50540189, 1578.15525552, 183.72444733, 1581.18330834, 188.953125, 1584.1953125);
  path.cubicTo(190.04415527, 1584.82381104, 191.13518555, 1585.45230957, 192.25927734, 1586.09985352);
  path.cubicTo(194.44588133, 1587.35767604, 196.63369147, 1588.61340431, 198.82275391, 1589.86694336);
  path.cubicTo(204.18070896, 1592.94337608, 209.4979404, 1596.0668921, 214.7578125, 1599.30859375);
  path.cubicTo(215.75796387, 1599.91952881, 216.75811523, 1600.53046387, 217.78857422, 1601.15991211);
  path.cubicTo(219.6714098, 1602.3144452, 221.54602807, 1603.48252755, 223.41064453, 1604.66625977);
  path.cubicTo(224.24966309, 1605.17858154, 225.08868164, 1605.69090332, 225.953125, 1606.21875);
  path.cubicTo(227.04028809, 1606.9003418, 227.04028809, 1606.9003418, 228.14941406, 1607.59570312);
  path.cubicTo(231.31332186, 1608.75971871, 233.20135395, 1608.31066043, 236.4375, 1607.4375);
  path.cubicTo(239.37293751, 1606.09637773, 239.37293751, 1606.09637773, 242.3046875, 1604.33203125);
  path.cubicTo(243.42504395, 1603.68548584, 244.54540039, 1603.03894043, 245.69970703, 1602.37280273);
  path.cubicTo(246.90408132, 1601.66538901, 248.10834281, 1600.95778322, 249.3125, 1600.25);
  path.cubicTo(250.56968264, 1599.52010957, 251.82733941, 1598.79103525, 253.08544922, 1598.06274414);
  path.cubicTo(256.27466971, 1596.21366751, 259.45756445, 1594.35400904, 262.63842773, 1592.49060059);
  path.cubicTo(265.3238833, 1590.91864882, 268.01360509, 1589.35404749, 270.703125, 1587.7890625);
  path.cubicTo(274.61976783, 1585.50829306, 278.53336968, 1583.22241379, 282.4453125, 1580.93359375);
  path.cubicTo(288.76126377, 1577.24252101, 295.09822995, 1573.58833684, 301.4375, 1569.9375);
  path.cubicTo(309.78552448, 1565.12905277, 318.11998303, 1560.29852905, 326.4375, 1555.4375);
  path.cubicTo(335.8474033, 1549.93804464, 345.28220563, 1544.48300804, 354.7265625, 1539.04296875);
  path.cubicTo(361.9770149, 1534.86400872, 369.21238269, 1530.66009494, 376.4375, 1526.4375);
  path.cubicTo(385.8474033, 1520.93804464, 395.28220563, 1515.48300804, 404.7265625, 1510.04296875);
  path.cubicTo(411.9770149, 1505.86400872, 419.21238269, 1501.66009494, 426.4375, 1497.4375);
  path.cubicTo(434.75501792, 1492.5764704, 443.08955653, 1487.74608897, 451.4375, 1482.9375);
  path.cubicTo(463.79772518, 1475.81663592, 476.12217327, 1468.63566622, 488.4375, 1461.4375);
  path.cubicTo(501.84508718, 1453.60092017, 515.26909279, 1445.79471392, 528.72607422, 1438.04321289);
  path.cubicTo(535.97671986, 1433.86422406, 543.21222586, 1429.6601866, 550.4375, 1425.4375);
  path.cubicTo(559.8474033, 1419.93804464, 569.28220563, 1414.48300804, 578.7265625, 1409.04296875);
  path.cubicTo(585.9770149, 1404.86400872, 593.21238269, 1400.66009494, 600.4375, 1396.4375);
  path.cubicTo(609.8474033, 1390.93804464, 619.28220563, 1385.48300804, 628.7265625, 1380.04296875);
  path.cubicTo(635.9770149, 1375.86400872, 643.21238269, 1371.66009494, 650.4375, 1367.4375);
  path.cubicTo(659.8474033, 1361.93804464, 669.28220563, 1356.48300804, 678.7265625, 1351.04296875);
  path.cubicTo(685.9770149, 1346.86400872, 693.21238269, 1342.66009494, 700.4375, 1338.4375);
  path.cubicTo(709.8474033, 1332.93804464, 719.28220563, 1327.48300804, 728.7265625, 1322.04296875);
  path.cubicTo(736.96464714, 1317.29476484, 745.1812574, 1312.51074142, 753.38964844, 1307.71142578);
  path.cubicTo(759.69850827, 1304.02589816, 766.02306289, 1300.36881091, 772.35742188, 1296.72729492);
  path.cubicTo(781.58703742, 1291.42026598, 790.79720585, 1286.08476224, 799.9375, 1280.625);
  path.cubicTo(800.77442383, 1280.12726074, 801.61134766, 1279.62952148, 802.47363281, 1279.11669922);
  path.cubicTo(803.23514648, 1278.65924316, 803.99666016, 1278.20178711, 804.78125, 1277.73046875);
  path.cubicTo(805.44318359, 1277.3336792, 806.10511719, 1276.93688965, 806.78710938, 1276.52807617);
  path.cubicTo(808.59766491, 1275.41074093, 808.59766491, 1275.41074093, 810.4375, 1273.4375);
  path.cubicTo(810.74940643, 1271.34884754, 810.74940643, 1271.34884754, 810.71121168, 1268.90159005);
  path.cubicTo(810.72640899, 1267.45711015, 810.72640899, 1267.45711015, 810.74191332, 1265.98344883);
  path.cubicTo(810.74346524, 1264.38213021, 810.74346524, 1264.38213021, 810.74504852, 1262.74846172);
  path.cubicTo(810.75394733, 1261.61715005, 810.76284615, 1260.48583837, 810.77201462, 1259.32024452);
  path.cubicTo(810.79478274, 1256.15660763, 810.80850821, 1252.99307598, 810.81846233, 1249.82937732);
  path.cubicTo(810.83136632, 1246.3962443, 810.85557653, 1242.96318801, 810.87826586, 1239.53010827);
  path.cubicTo(810.92142492, 1232.71025395, 810.95344937, 1225.8903873, 810.98196253, 1219.07045775);
  path.cubicTo(811.00596476, 1213.39818977, 811.03459329, 1207.7259607, 811.06616974, 1202.05373001);
  path.cubicTo(811.07298366, 1200.82765166, 811.07298366, 1200.82765166, 811.07993523, 1199.57680405);
  path.cubicTo(811.08450833, 1198.75421129, 811.08908142, 1197.93161853, 811.09379309, 1197.08409872);
  path.cubicTo(811.43213426, 1136.21974379, 811.60080226, 1075.35419329, 811.73498711, 1014.48908549);
  path.cubicTo(811.7550106, 1005.43225678, 811.77580066, 996.37542984, 811.796875, 987.31860352);
  path.cubicTo(811.79918593, 986.31782971, 811.80149685, 985.3170559, 811.80387781, 984.28595562);
  path.cubicTo(811.87932486, 951.84499398, 812.03134174, 919.40496689, 812.22510501, 886.96451294);
  path.cubicTo(812.42389498, 853.62180052, 812.55099642, 820.27959483, 812.5858138, 786.93628749);
  path.cubicTo(812.59075252, 782.22657531, 812.59648152, 777.51686439, 812.60267639, 772.8071537);
  path.cubicTo(812.60446185, 771.41676699, 812.60446185, 771.41676699, 812.60628338, 769.99829166);
  path.cubicTo(812.62748888, 755.08022512, 812.72373121, 740.16354314, 812.84772716, 725.24601641);
  path.cubicTo(812.97070263, 710.24836361, 813.01309426, 695.25218129, 812.9735567, 680.2540616);
  path.cubicTo(812.95247699, 671.34318248, 812.99257638, 662.43750121, 813.12077236, 653.52749289);
  path.cubicTo(813.20039585, 647.57147972, 813.19970509, 641.61892465, 813.13444823, 635.66274692);
  path.cubicTo(813.09951198, 632.26642903, 813.11095741, 628.88791517, 813.19628757, 625.49131133);
  path.cubicTo(813.94118394, 611.86268211, 813.94118394, 611.86268211, 808.26447546, 600.10536601);
  path.cubicTo(802.96738142, 595.9709391, 797.19841612, 593.13291348, 791.02256447, 590.54906384);
  path.cubicTo(787.6316515, 589.09098947, 784.59243513, 587.30221316, 781.4453125, 585.37890625);
  path.cubicTo(779.48499302, 584.25152884, 777.52406525, 583.12520844, 775.5625, 582.0);
  path.cubicTo(767.17148528, 577.17291089, 758.79475733, 572.32280344, 750.4375, 567.4375);
  path.cubicTo(742.12003329, 562.5763845, 733.78548337, 557.74601774, 725.4375, 552.9375);
  path.cubicTo(716.09886793, 547.5583592, 706.78109683, 542.14490553, 697.4765625, 536.70703125);
  path.cubicTo(690.14466277, 532.42527878, 682.79482762, 528.17539061, 675.4375, 523.9375);
  path.cubicTo(666.09886793, 518.5583592, 656.78109683, 513.14490553, 647.4765625, 507.70703125);
  path.cubicTo(640.14466277, 503.42527878, 632.79482762, 499.17539061, 625.4375, 494.9375);
  path.cubicTo(616.09886793, 489.5583592, 606.78109683, 484.14490553, 597.4765625, 478.70703125);
  path.cubicTo(590.14466277, 474.42527878, 582.79482762, 470.17539061, 575.4375, 465.9375);
  path.cubicTo(566.09886793, 460.5583592, 556.78109683, 455.14490553, 547.4765625, 449.70703125);
  path.cubicTo(540.14466277, 445.42527878, 532.79482762, 441.17539061, 525.4375, 436.9375);
  path.cubicTo(516.09886793, 431.5583592, 506.78109683, 426.14490553, 497.4765625, 420.70703125);
  path.cubicTo(490.14466277, 416.42527878, 482.79482762, 412.17539061, 475.4375, 407.9375);
  path.cubicTo(466.09886793, 402.5583592, 456.78109683, 397.14490553, 447.4765625, 391.70703125);
  path.cubicTo(440.14466277, 387.42527878, 432.79482762, 383.17539061, 425.4375, 378.9375);
  path.cubicTo(416.09886793, 373.5583592, 406.78109683, 368.14490553, 397.4765625, 362.70703125);
  path.cubicTo(390.14466277, 358.42527878, 382.79482762, 354.17539061, 375.4375, 349.9375);
  path.cubicTo(366.09886793, 344.5583592, 356.78109683, 339.14490553, 347.4765625, 333.70703125);
  path.cubicTo(340.14466277, 329.42527878, 332.79482762, 325.17539061, 325.4375, 320.9375);
  path.cubicTo(316.09886793, 315.5583592, 306.78109683, 310.14490553, 297.4765625, 304.70703125);
  path.cubicTo(289.06825169, 299.79666601, 280.63505197, 294.93018417, 272.19677734, 290.0715332);
  path.cubicTo(263.44278232, 285.02745142, 254.71402355, 279.94094494, 246.0, 274.828125);
  path.cubicTo(245.06414063, 274.28027344, 244.12828125, 273.73242188, 243.1640625, 273.16796875);
  path.cubicTo(242.34502441, 272.68739014, 241.52598633, 272.20681152, 240.68212891, 271.71166992);
  path.cubicTo(234.72884159, 268.33226961, 232.33339495, 267.67487135, 226.22265625, 271.33984375);
  path.close();
  path.moveTo(530.93359375, 809.0078125);
  path.cubicTo(529.97815674, 809.56702393, 529.02271973, 810.12623535, 528.03833008, 810.70239258);
  path.cubicTo(526.47248169, 811.62314575, 526.47248169, 811.62314575, 524.875, 812.5625);
  path.cubicTo(522.65889311, 813.86074357, 520.44274622, 815.15891885, 518.2265625, 816.45703125);
  path.cubicTo(517.0912207, 817.12299316, 515.95587891, 817.78895508, 514.78613281, 818.47509766);
  path.cubicTo(510.74156377, 820.84534015, 506.691598, 823.20622346, 502.64086914, 825.56591797);
  path.cubicTo(492.10795815, 831.70188791, 481.58955054, 837.86241105, 471.07510376, 844.02993774);
  path.cubicTo(461.90301087, 849.40984895, 452.7223725, 854.77484887, 443.53515625, 860.12890625);
  path.cubicTo(435.66180632, 864.71907972, 427.79855255, 869.32631408, 419.9375, 873.9375);
  path.cubicTo(410.14474127, 879.68179835, 400.34420978, 885.41245917, 390.53515625, 891.12890625);
  path.cubicTo(382.66180632, 895.71907972, 374.79855255, 900.32631408, 366.9375, 904.9375);
  path.cubicTo(357.14474127, 910.68179835, 347.34420978, 916.41245917, 337.53515625, 922.12890625);
  path.cubicTo(329.66180621, 926.71907978, 321.79856682, 931.32633826, 313.9375, 935.9375);
  path.cubicTo(302.91399208, 942.40357047, 291.88123255, 948.85355563, 280.83984375, 955.2890625);
  path.cubicTo(280.02139772, 955.78164297, 279.20295168, 956.27422344, 278.35970426, 956.78173059);
  path.cubicTo(275.4375, 958.4375, 275.4375, 958.4375, 272.33565974, 959.81952721);
  path.cubicTo(266.08020497, 962.70695376, 266.08020497, 962.70695376, 262.33758402, 968.1784333);
  path.cubicTo(261.91872223, 971.64575507, 261.89479489, 974.93617372, 261.9944458, 978.42771912);
  path.cubicTo(261.9841927, 979.74043685, 261.9739396, 981.05315457, 261.96337581, 982.40565163);
  path.cubicTo(261.93659419, 986.03994055, 261.98444208, 989.66997014, 262.04471254, 993.30371606);
  path.cubicTo(262.0966078, 997.22523411, 262.07899288, 1001.14651819, 262.06988525, 1005.06828308);
  path.cubicTo(262.06359722, 1011.85953508, 262.10119685, 1018.64940212, 262.16873932, 1025.44030571);
  path.cubicTo(262.26632785, 1035.25852123, 262.29752251, 1045.07606809, 262.31259522, 1054.89471603);
  path.cubicTo(262.33884936, 1070.82496561, 262.41868141, 1086.75447722, 262.53222656, 1102.68432617);
  path.cubicTo(262.6424002, 1118.15727042, 262.7273283, 1133.63001411, 262.77832031, 1149.10327148);
  path.cubicTo(262.78147299, 1150.057271, 262.78462568, 1151.01127053, 262.78787389, 1151.99417912);
  path.cubicTo(262.80353451, 1156.78018622, 262.81869897, 1161.56619474, 262.83361673, 1166.3522042);
  path.cubicTo(262.95798789, 1206.04781948, 263.16931871, 1245.74261101, 263.4375, 1285.4375);
  path.cubicTo(266.39528514, 1284.26889604, 269.23827516, 1283.09119481, 272.01953125, 1281.546875);
  path.cubicTo(272.69113281, 1281.17473877, 273.36273437, 1280.80260254, 274.0546875, 1280.41918945);
  path.cubicTo(274.77914062, 1280.01273193, 275.50359375, 1279.60627441, 276.25, 1279.1875);
  path.cubicTo(277.02988281, 1278.75203857, 277.80976562, 1278.31657715, 278.61328125, 1277.86791992);
  path.cubicTo(287.17103842, 1273.06504585, 295.63367718, 1268.09956012, 304.1015625, 1263.140625);
  path.cubicTo(310.49031992, 1259.40115411, 316.89866076, 1255.69624966, 323.3125, 1252.0);
  path.cubicTo(324.39208984, 1251.37778564, 325.47167969, 1250.75557129, 326.58398438, 1250.11450195);
  path.cubicTo(328.7743252, 1248.85238483, 330.96475502, 1247.59042215, 333.15527344, 1246.32861328);
  path.cubicTo(338.58409942, 1243.20069852, 344.01069281, 1240.06891552, 349.4375, 1236.9375);
  path.cubicTo(351.60415583, 1235.68748121, 353.7708225, 1234.43748122, 355.9375, 1233.1875);
  path.cubicTo(357.01, 1232.56875, 358.0825, 1231.95, 359.1875, 1231.3125);
  path.cubicTo(394.9375, 1210.6875, 394.9375, 1210.6875, 398.18798828, 1208.81225586);
  path.cubicTo(400.35307071, 1207.56314482, 402.51810982, 1206.31395871, 404.68310547, 1205.06469727);
  path.cubicTo(410.12365706, 1201.92547691, 415.56497216, 1198.78759437, 421.0078125, 1195.65234375);
  path.cubicTo(431.49982094, 1189.60694841, 441.98231676, 1183.54639781, 452.4375, 1177.4375);
  path.cubicTo(466.20543216, 1169.39298383, 480.02265596, 1161.43451391, 493.84130859, 1153.47753906);
  path.cubicTo(500.40210476, 1149.69934467, 506.95929126, 1145.91502477, 513.51269531, 1142.12402344);
  path.cubicTo(516.25087322, 1140.54511417, 518.99548719, 1138.97808318, 521.7421875, 1137.4140625);
  path.cubicTo(523.28661034, 1136.52630607, 524.8308926, 1135.63830498, 526.375, 1134.75);
  path.cubicTo(527.06086182, 1134.36416748, 527.74672363, 1133.97833496, 528.45336914, 1133.58081055);
  path.cubicTo(531.92320513, 1131.57129637, 534.36860555, 1129.88434341, 536.4375, 1126.4375);
  path.cubicTo(536.88150751, 1123.8331165, 536.88150751, 1123.8331165, 536.80664349, 1120.94775009);
  path.cubicTo(536.81261663, 1119.82509931, 536.81858978, 1118.70244853, 536.82474393, 1117.54577804);
  path.cubicTo(536.8160054, 1116.31232595, 536.80726688, 1115.07887386, 536.79826355, 1113.80804443);
  path.cubicTo(536.80082682, 1112.49788998, 536.8033901, 1111.18773552, 536.80603105, 1109.83787942);
  path.cubicTo(536.81274855, 1106.19831394, 536.80072615, 1102.55901262, 536.78569686, 1098.9194808);
  path.cubicTo(536.7727589, 1094.99586075, 536.77712437, 1091.07225598, 536.77940369, 1087.14862061);
  path.cubicTo(536.78097784, 1080.34967257, 536.7715538, 1073.5508108, 536.75469017, 1066.75188446);
  path.cubicTo(536.73032398, 1056.92175474, 536.72249734, 1047.09166681, 536.7187262, 1037.26151016);
  path.cubicTo(536.71215797, 1021.31331385, 536.69218675, 1005.36516353, 536.66381836, 989.41699219);
  path.cubicTo(536.63628739, 973.92350495, 536.6150491, 958.43003019, 536.60229492, 942.93652344);
  path.cubicTo(536.60150675, 941.98173575, 536.60071858, 941.02694806, 536.59990653, 940.0432274);
  path.cubicTo(536.59599146, 935.25340722, 536.59220032, 930.46358695, 536.58847082, 925.67376661);
  path.cubicTo(536.55736336, 885.9283122, 536.50451746, 846.18290913, 536.4375, 806.4375);
  path.cubicTo(534.45338285, 806.4375, 532.58301992, 808.03970173, 530.93359375, 809.0078125);
  path.close();
  return path;
}

class BloretIcon extends CustomPainter {
  final Color color;

  BloretIcon({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = buildPath();

    final Rect bounds = path.getBounds();
    final double scaleX = size.width / bounds.width;
    final double scaleY = size.height / bounds.height;
    final double scale = scaleX < scaleY ? scaleX : scaleY;

    final double offsetX = (size.width - bounds.width * scale) / 2;
    final double offsetY = (size.height - bounds.height * scale) / 2;

    final Matrix4 matrix = Matrix4.identity()
      ..setTranslationRaw(offsetX, offsetY, 0.0)
      ..multiply(Matrix4.diagonal3Values(scale, scale, 1.0))
      ..multiply(Matrix4.translationValues(-bounds.left, -bounds.top, 0.0));

    canvas.drawPath(path.transform(matrix.storage), paint);
  }

  @override
  bool shouldRepaint(covariant BloretIcon oldDelegate) => false;
}
