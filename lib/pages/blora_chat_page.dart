import 'package:flutter/material.dart';

class BloraChatPage extends StatefulWidget {
  const BloraChatPage({super.key});

  @override
  State<BloraChatPage> createState() => _BloraChatPageState();
}

class _BloraChatPageState extends State<BloraChatPage> {
  bool _historyPanelOpen = true;
  bool _isBusy = false;
  String _conversationTitle = "";
  String _currentEmotion = "normal";
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _msgScrollController = ScrollController();

  final List<Map<String, dynamic>> _historyList = [];
  final List<Map<String, dynamic>> _messages = [];

  @override
  void dispose() {
    _inputController.dispose();
    _msgScrollController.dispose();
    super.dispose();
  }

  void _loadHistoryList() {
    // TODO: 加载历史列表
  }

  String _tr(String text) {
    // TODO: 实现翻译方法
    return text;
  }

  String _getEmotionDisplay(String emotion) {
    // TODO: 情感状态显示
    return emotion;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    final borderColor = theme.dividerColor;
    final altColor = theme.colorScheme.surfaceContainerHighest;
    final textColor = theme.colorScheme.onSurface;
    final secondaryTextColor = theme.colorScheme.onSurfaceVariant;
    final accentColor = theme.colorScheme.primary;

    return SizedBox.expand(
      child: Row(
        children: [
          // ========== 左侧聊天区 ==========
          Expanded(
            child: Column(
              children: [
                // ===== 顶部栏 =====
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: borderColor)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 24,
                          height: 24,
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.smart_toy, size: 16),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _tr("Blora Agent"),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                      ),
                      if (_conversationTitle.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          "— $_conversationTitle",
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: secondaryTextColor),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          color: altColor,
                          border: Border.all(color: borderColor),
                        ),
                        child: Text(
                          _getEmotionDisplay(_currentEmotion),
                          style: TextStyle(fontSize: 10, color: textColor),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isBusy ? _tr("思考中...") : _tr("就绪"),
                        style: TextStyle(fontSize: 11, color: _isBusy ? accentColor : secondaryTextColor),
                      ),
                      const Spacer(),
                      TextButton(
                        child: Text(_tr("新对话"), style: TextStyle(fontSize: 11)),
                        onPressed: _isBusy ? null : () {
                          setState(() {
                            _messages.clear();
                            // TODO: clearHistory()
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.menu, size: 18),
                        onPressed: () {
                          setState(() {
                            _historyPanelOpen = !_historyPanelOpen;
                            if (_historyPanelOpen) _loadHistoryList();
                          });
                        },
                      ),
                    ],
                  ),
                ),

                // ===== 消息列表 =====
                Expanded(
                  child: Stack(
                    children: [
                      ListView.builder(
                        controller: _msgScrollController,
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final role = msg['role'];

                          if (role == 'user') {
                            return Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                                padding: const EdgeInsets.all(8),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
                                decoration: BoxDecoration(
                                  color: accentColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  msg['content'] ?? '',
                                  style: const TextStyle(fontSize: 13, color: Colors.white),
                                ),
                              ),
                            );
                          } else if (role == 'assistant') {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(11),
                                    child: Container(width: 22, height: 22, color: Colors.grey.shade300, child: const Icon(Icons.smart_toy, size: 14)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SelectableText(
                                      msg['content'] ?? '...',
                                      style: TextStyle(fontSize: 13, color: textColor),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          } else if (role == 'error') {
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 16),
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning, size: 14, color: Colors.amber),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      msg['content'] ?? '',
                                      style: const TextStyle(fontSize: 12, color: Colors.amber),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          } else if (role == 'system') {
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
                              child: Row(
                                children: [
                                  Text("ℹ", style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      msg['content'] ?? '',
                                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: secondaryTextColor),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      if (_messages.isEmpty)
                        Center(
                          child: SizedBox(
                            width: 280,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(32),
                                  child: Container(width: 64, height: 64, color: Colors.grey.shade300, child: const Icon(Icons.smart_toy, size: 32)),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _tr("Blora Agent"),
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _tr("哥哥好呀！ Blora Agent 在这里等你很久啦~(开心地挥挥小手)\n\n试试跟 Blora Agent 说：\n• 帮我创建一个文件\n• 搜索一下项目里的 TODO\n• 执行一个命令看看\n• 记住我的偏好是..."),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11, height: 1.4, color: secondaryTextColor),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ===== 输入栏 =====
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    border: Border(top: BorderSide(color: borderColor)),
                  ),
                  child: Column(
                    children: [
                      if (_isBusy) const LinearProgressIndicator(minHeight: 2),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: altColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: borderColor),
                                ),
                                child: TextField(
                                  controller: _inputController,
                                  maxLines: null,
                                  enabled: !_isBusy,
                                  decoration: InputDecoration(
                                    hintText: _tr("向 Blora Agent 说些什么... (Enter 发送, Shift+Enter 换行)"),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                  style: TextStyle(fontSize: 13, color: textColor),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              icon: Icon(_isBusy ? Icons.stop : Icons.send, size: 18),
                              onPressed: () {
                                if (_isBusy) {
                                  // TODO: cancelAgent()
                                  setState(() => _isBusy = false);
                                  return;
                                }
                                final text = _inputController.text.trim();
                                if (text.isEmpty) return;
                                setState(() {
                                  _messages.add({'role': 'user', 'content': text});
                                });
                                _inputController.clear();
                                // TODO: sendMessage(text)
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ========== 右侧历史栏 ==========
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOutQuad,
            width: _historyPanelOpen ? 220 : 0,
            child: OverflowBox(
              minWidth: 220,
              maxWidth: 220,
              alignment: Alignment.topLeft,
              child: ClipRect(
                child: Column(
                  children: [
                    // 标题栏
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: borderColor)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _tr("历史对话"),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Text("＋", style: TextStyle(fontSize: 14)),
                            onPressed: () {
                              setState(() {
                                _messages.clear();
                                // TODO: clearHistory()
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    // 历史列表
                    Expanded(
                      child: Stack(
                        children: [
                          ListView.builder(
                            itemCount: _historyList.length,
                            itemBuilder: (context, index) {
                              final item = _historyList[index];
                              return InkWell(
                                onTap: () {
                                  // TODO: loadSession(item['filename'])
                                },
                                child: Container(
                                  height: 52,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  alignment: Alignment.centerLeft,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['displayText'] ?? '',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: item['displayText'] != item['subText'] ? FontWeight.bold : FontWeight.normal,
                                          color: textColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item['subText'] ?? '',
                                        style: TextStyle(fontSize: 10, color: secondaryTextColor),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          if (_historyList.isEmpty)
                            Center(
                              child: Text(
                                _tr("暂无历史记录"),
                                style: TextStyle(fontSize: 11, color: secondaryTextColor),
                              ),
                            ),
                        ],
                      ),
                    ),

                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: borderColor)),
                      ),
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: _loadHistoryList,
                        child: Text(_tr("刷新列表"), style: TextStyle(fontSize: 11, color: textColor)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}