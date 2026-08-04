import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../core/i18n.dart';
import '../services/bbbs.dart';
import '../widgets/button.dart';

class BlorikoPage extends StatefulWidget {
  const BlorikoPage({super.key});

  @override
  State<BlorikoPage> createState() => _BlorikoPageState();
}

class _BlorikoPageState extends State<BlorikoPage> {
  final List<Map<String, String>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isProcessing = false;
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isProcessing) return;

    _controller.clear();
    setState(() {
      _messages.add({"role": "user", "content": text});
      _messages.add({"role": "assistant", "content": ""});
      _isProcessing = true;
    });
    _scrollToBottom();

    final lastIndex = _messages.length - 1;

    BbbsService.streamBlorikoChat(content: text).listen(
      (chunk) {
        if (!mounted) return;
        setState(() {
          _messages[lastIndex]["content"] = (_messages[lastIndex]["content"] ?? "") + chunk;
        });
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _isProcessing = false);
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _isProcessing = false;
          _messages[lastIndex]["content"] = "Error: $e";
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final secondaryColor = theme.colorScheme.onSurfaceVariant;
    final cardColor = theme.cardColor;
    final borderColor = theme.dividerColor.withValues(alpha: 0.1);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.smart_toy_outlined, color: Colors.blue),
            const SizedBox(width: 8),
            Text("Bloriko".tl),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(secondaryColor)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageItem(_messages[index], theme);
                    },
                  ),
          ),
          _buildInputArea(cardColor, borderColor, secondaryColor, theme),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color secondaryColor) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 64, color: secondaryColor.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            "和 Bloriko 聊聊天吧".tl,
            style: TextStyle(color: secondaryColor, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(Map<String, String> message, ThemeData theme) {
    final isUser = message["role"] == "user";
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _buildAvatar(isUser),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  isUser ? "Me".tl : "Bloriko".tl,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUser 
                        ? theme.colorScheme.primary.withValues(alpha: 0.1)
                        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: GptMarkdown(
                    message["content"] ?? "...",
                    style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isUser) _buildAvatar(isUser),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isUser) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: isUser ? Colors.blue.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
      child: Icon(
        isUser ? Icons.person_outline : Icons.smart_toy_outlined,
        size: 18,
        color: isUser ? Colors.blue : Colors.green,
      ),
    );
  }

  Widget _buildInputArea(Color cardColor, Color borderColor, Color secondaryColor, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery.of(context).viewInsets.bottom + 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isFocused ? theme.colorScheme.primary : borderColor,
                    width: _isFocused ? 1.8 : 1.0,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: 5,
                  minLines: 1,
                  onChanged: (v) => setState(() {}),
                  onSubmitted: (_) => _sendMessage(),
                  decoration: InputDecoration(
                    hintText: "向 Bloriko 提问...".tl,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _isProcessing
                ? const Padding(
                    padding: EdgeInsets.all(10.0),
                    child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : BloretIconButton(
                    onPressed: _controller.text.trim().isEmpty ? null : _sendMessage,
                    icon: Icons.send,
                    tooltip: "发送".tl,
                  ),
          ],
        ),
      ),
    );
  }
}
