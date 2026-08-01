import 'package:bloret_launcher/services/bloriko.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:flutter/material.dart';

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
  }

  @override
  void dispose() {
    _agentController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void askBlora() {
    // TODO
  }

  void searchModrinth() {
    // TODO
  }

  void openMod(dynamic mod) {
    // TODO
  }

  void downloadMod(dynamic mod) {
    // TODO
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;
    final agentName = Bloriko.type == "bloriko" ? "络可" : "Blora Agent";

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(32, 16, 16, 16),
        children: [
          const Text(
            "Mod",
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 16),

          _buildAgentCard(isPortrait, agentName),

          const SizedBox(height: 8),

          Text(
            isPortrait 
                ? "$agentName 依靠 AI，请核实重要信息。"
                : "$agentName 依靠 AI，$agentName 也可能犯错，请核实重要信息。",
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

          ...mods.map((mod) => _buildModCard(mod, isPortrait)),
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
                      isPortrait ? "让 $agentName 帮你找 Mod" : "让 $agentName 帮你挑选合适的 Mod",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      isPortrait ? "让 AI 帮你找齐 Mod。" : "无需一个一个找 Mod，让 AI 帮你找齐。",
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
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200), curve: Curves.easeInOut,
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4 - (_isFocusedBloriko ? 0.7 : 0)),
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: _isFocusedBloriko ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.surfaceContainerHighest, width: _isFocusedBloriko ? 1.5 : 1.0)),
                    child: TextField(controller: _agentController, maxLines: 1, focusNode: _focusNodeBloriko, decoration: InputDecoration(hintText: "告诉我你的需求...", border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 6)), style: const TextStyle(fontSize: 14,), onSubmitted: (_) => askBlora(),),
                  )
              ),

              const SizedBox(width: 10),

              BloretButton(
                text: "发送",
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
                    items: const [
                      Win11DropdownItem(label: "全部", value: ""),
                      Win11DropdownItem(label: "Mod", value: "mod"),
                      Win11DropdownItem(label: "资源包", value: "resourcepack"),
                      Win11DropdownItem(label: "光影包", value: "shader"),
                      Win11DropdownItem(label: "数据包", value: "datapack"),
                      Win11DropdownItem(label: "模组包", value: "modpack"),
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
                  text: "搜索",
                  onPressed: searchModrinth,
                ),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200), curve: Curves.easeInOut,
              constraints: const BoxConstraints(maxHeight: 120),
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4 - (_isFocused ? 0.5 : 0)),
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: _isFocused ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.surfaceContainerHighest, width: _isFocused ? 1.5 : 1.0)),
              child: TextField(controller: _searchController, maxLines: 1, focusNode: _focusNode, decoration: const InputDecoration(hintText: "在 Modrinth 上搜索...", border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6)), style: const TextStyle(fontSize: 14,), onSubmitted: (_) => searchModrinth(),),
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
              items: const [
                Win11DropdownItem(label: "全部", value: ""),
                Win11DropdownItem(label: "Mod", value: "mod"),
                Win11DropdownItem(label: "资源包", value: "resourcepack"),
                Win11DropdownItem(label: "光影包", value: "shader"),
                Win11DropdownItem(label: "数据包", value: "datapack"),
                Win11DropdownItem(label: "模组包", value: "modpack"),
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200), curve: Curves.easeInOut,
              constraints: const BoxConstraints(maxHeight: 120),
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4 - (_isFocused ? 0.5 : 0)),
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: _isFocused ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.surfaceContainerHighest, width: _isFocused ? 1.5 : 1.0)),
              child: TextField(controller: _searchController, maxLines: 1, focusNode: _focusNode, decoration: const InputDecoration(hintText: "在 Modrinth 上搜索...", border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6)), style: const TextStyle(fontSize: 14,), onSubmitted: (_) => searchModrinth(),),
            )
          ),

          const SizedBox(width: 8),

          BloretButton(
            text: "搜索",
            onPressed: searchModrinth,
          ),
        ],
      ),
    );
  }

  Widget _buildModCard(dynamic mod, bool isPortrait) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FluentCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Image.network(
                mod["icon_url"] ?? "",
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return const SizedBox(
                    width: 64,
                    height: 64,
                    child: Icon(Icons.image),
                  );
                },
              ),
            ),

            const SizedBox(width: 15),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mod["name"] ?? "",
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
                    Text(
                      mod["description"] ?? "",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                  const SizedBox(height: 6),

                  Row(
                    children: [
                      Text(
                        "⬇ ${mod["downloads"] ?? 0}",
                        style: const TextStyle(fontSize: 12),
                      ),

                      const SizedBox(width: 15),

                      Text(
                        "♥ ${mod["followers"] ?? 0}",
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Column(
              children: [
                BloretButton(
                  text: "查看",
                  onPressed: () => openMod(mod),
                ),
                if (!isPortrait)
                  BloretButton(
                    text: "下载",
                    onPressed: () => downloadMod(mod),
                  ),
              ],
            ),
            if (isPortrait)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: BloretIconButton(
                  icon: Icons.download,
                  tooltip: "下载",
                  onPressed: () => downloadMod(mod),
                ),
              ),
          ],
        ),
      ),
    );
  }
}