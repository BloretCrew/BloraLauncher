import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:share_plus/share_plus.dart';
import '../core/i18n.dart';
import '../models/bbbs_post.dart';
import '../services/bbbs.dart';
import '../services/config_service.dart';
import '../widgets/button.dart';
import '../main.dart';
import '../core/logger.dart';
import '../core/grammer_candy.dart';

class BbbsDetailPage extends StatefulWidget {
  final BbbsPost post;

  const BbbsDetailPage({super.key, required this.post});

  @override
  State<BbbsDetailPage> createState() => _BbbsDetailPageState();
}

class _BbbsDetailPageState extends State<BbbsDetailPage> {
  late BbbsPost _currentPost;
  bool _isLoading = false;
  
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  bool _isSubmitting = false;
  BbbsComment? _replyTo;
  
  String? _aiText;
  bool _isAiProcessing = false;
  String? _aiTargetId;

  @override
  void initState() {
    super.initState();
    _currentPost = widget.post;
    _refreshPost();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _refreshPost() async {
    setState(() => _isLoading = true);
    try {
      final data = await BbbsService.fetchPostDetail(_currentPost.filename);
      if (data != null && mounted) {
        setState(() {
          _currentPost = BbbsPost.fromJson(data);
          _isLoading = false;
        });
        logger.info("[BBBS] Detail refreshed. Comments: ${_currentPost.comments.length}", LogSource.network);
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      logger.error("[BBBS] Refresh error: $e", LogSource.network);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _insertMd(String tag) {
    final text = _commentController.text;
    final selection = _commentController.selection;
    
    String newText;
    if (selection.isValid) {
      newText = text.replaceRange(selection.start, selection.end, tag);
    } else {
      newText = text + tag;
    }
    _commentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.baseOffset + tag.length),
    );
    _focusNode.requestFocus();
  }

  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    
    final res = await BbbsService.addComment(
      filename: _currentPost.filename,
      content: content,
      parentId: _replyTo?.parentId ?? _replyTo?.id,
      replyToId: _replyTo?.id,
    );

    if (res['success'] == true) {
      _commentController.clear();
      setState(() {
        _replyTo = null;
        _isSubmitting = false;
      });
      if (mounted) showSuccess("Comment successful".tl);
      await _refreshPost();
      _scrollToBottom();
    } else {
      setState(() => _isSubmitting = false);
      if (mounted) showError("${"Comment failed".tl}: ${res['message']}");
    }
  }

  Future<void> _handleAiAction(String mode, String content, {String targetId = "post"}) async {
    setState(() {
      _aiText = "";
      _isAiProcessing = true;
      _aiTargetId = targetId;
    });

    BbbsService.streamAiAction(mode: mode, content: content, targetLang: (ConfigService.get('language') ?? "zh_cn").toString().substring(0, 2)).listen(
      (chunk) {
        setState(() {
          _aiText = (_aiText ?? "") + chunk;
        });
      },
      onDone: () => setState(() => _isAiProcessing = false),
      onError: (e) => setState(() {
        _isAiProcessing = false;
        _aiText = "${"AI Error".tl}: $e";
      }),
    );
  }

  Future<void> _handleLike() async {
    final userName = ConfigService.get('Bloret_PassPort_UserName') ?? "";
    bool isLiked = _currentPost.likes.contains(userName);
    
    setState(() {
      if (isLiked) {
        _currentPost.likes.remove(userName);
      } else {
        _currentPost.likes.add(userName);
      }
      _isLoading = true;
    });

    try {
      await BbbsService.likePost(
        board: _currentPost.board,
        section: _currentPost.section ?? "",
        filename: _currentPost.filename,
      );
      await _refreshPost();
    } catch (e) {
      logger.error("[BBBS] Like error: $e", LogSource.network);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleShare() async {
    final String shareUrl = "https://bbs.bloret.net/post/${_currentPost.filename}";
    final String shareText = "${_currentPost.title}\n$shareUrl";

    try {
      setState(() => _isLoading = true);
      await Share.share(shareText, subject: _currentPost.title);
      
      await BbbsService.sharePost(
        board: _currentPost.board,
        section: _currentPost.section ?? "",
        filename: _currentPost.filename,
      );
      await _refreshPost();
    } catch (e) {
      logger.error("[BBBS] Share error: $e", LogSource.network);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    });
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
        title: Text(_currentPost.boardName),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        actions: [
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.only(right: 16), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshPost,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_currentPost.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildAuthorInfo(secondaryColor),
                    const SizedBox(height: 24),
                    _buildContentSection(textColor, secondaryColor, cardColor, borderColor),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 16),
                    _buildInteractionRow(secondaryColor),
                    const SizedBox(height: 32),
                    _buildCommentsHeader(secondaryColor),
                    const SizedBox(height: 16),
                    _buildCommentsList(textColor, secondaryColor, cardColor, borderColor),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomInput(cardColor, borderColor, secondaryColor),
        ],
      ),
    );
  }

  Widget _buildAuthorInfo(Color secondaryColor) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundImage: _currentPost.authorAvatar != null && _currentPost.authorAvatar!.isNotEmpty
              ? CachedNetworkImageProvider(_currentPost.authorAvatar!) : null,
          child: _currentPost.authorAvatar == null || _currentPost.authorAvatar!.isEmpty
              ? Text(_currentPost.author[0].toUpperCase()) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_currentPost.author, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(_currentPost.authorTitle ?? "User".tl, style: TextStyle(fontSize: 12, color: secondaryColor)),
            ],
          ),
        ),
        Text(_formatTime(_currentPost.time), style: TextStyle(fontSize: 12, color: secondaryColor)),
      ],
    );
  }

  Widget _buildContentSection(Color textColor, Color secondaryColor, Color cardColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GptMarkdown(_currentPost.content, style: TextStyle(fontSize: 16, color: textColor, height: 1.6)),
        const SizedBox(height: 12),
        Row(
          children: [
            BloretButton(
              text: "Translate".tl,
              icon: Icons.translate,
              onPressed: () => _handleAiAction("translate", _currentPost.content),
              height: 48,
            ),
            const SizedBox(width: 12),
            BloretButton(
              text: "Explain".tl,
              icon: Icons.auto_awesome,
              onPressed: () => _handleAiAction("explain", _currentPost.content),
              height: 48,
            ),
          ],
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SizeTransition(sizeFactor: animation, alignment: Alignment.topCenter, child: child),
            );
          },
          child: (_aiTargetId == "post" && _aiText != null)
            ? _buildAiResultBox("post", cardColor, borderColor, textColor)
            : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildAiResultBox(String key, Color cardColor, Color borderColor, Color textColor) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Container(
        key: ValueKey("ai_box_container_$key"),
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.psychology, size: 14, color: Colors.blue),
                ),
                const SizedBox(width: 8),
                Text("AI Assistant".tl, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                const Spacer(),
                if (_isAiProcessing)
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _aiText = null),
                  child: const Icon(Icons.close_rounded, size: 16, color: Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GptMarkdown(
              _aiText!, 
              key: ValueKey("ai_text_$key"),
              style: TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.9), height: 1.5)
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractionRow(Color secondaryColor) {
    final userName = ConfigService.get('Bloret_PassPort_UserName') ?? "";
    final isLiked = _currentPost.likes.contains(userName);

    return Row(
      children: [
        BloretButton(
          icon: isLiked ? Icons.favorite : Icons.favorite_outline, 
          text: _currentPost.likes.length.toString(), 
          color: isLiked ? Colors.red : Colors.redAccent,
          onPressed: _handleLike,
          height: 38,
        ),
        const SizedBox(width: 16),
        BloretButton(
          icon: Icons.share_outlined, 
          text: _currentPost.shares.toString(), 
          color: Colors.blue,
          onPressed: _handleShare,
          height: 38,
        ),
        const Spacer(),
        Text("${_currentPost.views} ${"Views".tl}", style: TextStyle(fontSize: 13, color: secondaryColor)),
      ],
    );
  }

  Widget _buildCommentsHeader(Color secondaryColor) {
    return Row(
      children: [
        Text("Comments".tl, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Text("(${_currentPost.commentsCount})", style: TextStyle(color: secondaryColor)),
      ],
    );
  }

  Widget _buildCommentsList(Color textColor, Color secondaryColor, Color cardColor, Color borderColor) {
    if (_currentPost.comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.chat_bubble_outline, size: 40, color: secondaryColor.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text("No comments yet".tl, style: TextStyle(color: secondaryColor)),
            ],
          )
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _currentPost.comments.length,
      separatorBuilder: (context, index) => Divider(height: 32, color: borderColor.withValues(alpha: 0.05)),
      itemBuilder: (context, index) {
        final comment = _currentPost.comments[index];
        return TweenAnimationBuilder<double>(
          key: ValueKey(comment.id),
          duration: const Duration(milliseconds: 400),
          tween: Tween(begin: 0.0, end: 1.0),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: child,
              ),
            );
          },
          child: _buildCommentItem(comment, textColor, secondaryColor, cardColor, borderColor),
        );
      },
    );
  }

  Widget _buildCommentItem(BbbsComment comment, Color textColor, Color secondaryColor, Color cardColor, Color borderColor) {
    final String cId = comment.id.toString();
    if (comment.content.isEmpty && comment.author.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: comment.authorAvatar != null && comment.authorAvatar!.isNotEmpty
                    ? CachedNetworkImageProvider(comment.authorAvatar!) : null,
                child: comment.authorAvatar == null || comment.authorAvatar!.isEmpty
                    ? Text(comment.author.isNotEmpty ? comment.author[0].toUpperCase() : "?") : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(comment.author, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Spacer(),
                        Text(_formatTime(comment.time), style: TextStyle(fontSize: 11, color: secondaryColor)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    GptMarkdown(
                      comment.content, 
                      style: TextStyle(fontSize: 14, color: textColor, height: 1.4)
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.favorite_outline, size: 14, color: secondaryColor),
                        const SizedBox(width: 4),
                        Text(comment.likes.length.toString(), style: TextStyle(fontSize: 12, color: secondaryColor)),
                        const SizedBox(width: 16),
                        InkWell(
                          onTap: () {
                            setState(() => _replyTo = comment);
                            _focusNode.requestFocus();
                          },
                          child: Text("Reply".tl, style: TextStyle(fontSize: 12, color: secondaryColor)),
                        ),
                        const SizedBox(width: 16),
                        _mdBtn(Icons.translate, () => _handleAiAction("translate", comment.content, targetId: cId)),
                        const SizedBox(width: 8),
                        _mdBtn(Icons.auto_awesome, () => _handleAiAction("explain", comment.content, targetId: cId)),
                      ],
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SizeTransition(sizeFactor: animation, alignment: Alignment.topCenter, child: child),
                        );
                      },
                      child: (_aiTargetId == cId && _aiText != null)
                        ? _buildAiResultBox(cId, cardColor, borderColor, textColor)
                        : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomInput(Color cardColor, Color borderColor, Color secondaryColor) {
    final theme = Theme.of(context);
    final altColor = theme.colorScheme.surfaceContainerHighest;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              child: Row(
                children: [
                  Icon(Icons.reply_rounded, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text("${"Reply".tl} @${_replyTo!.author}", style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _replyTo = null),
                    child: Icon(Icons.close_rounded, size: 16, color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery.of(context).viewInsets.bottom + 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: altColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _focusNode.hasFocus ? theme.colorScheme.primary : borderColor,
                        width: _focusNode.hasFocus ? 2.0 : 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: TextField(
                            controller: _commentController,
                            focusNode: _focusNode,
                            maxLines: null,
                            minLines: 1,
                            onChanged: (v) => setState(() {}),
                            keyboardType: TextInputType.multiline,
                            decoration: InputDecoration(
                              hintText: "Write your comment...".tl,
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurface),
                          ),
                        ),
                        if (_focusNode.hasFocus || _commentController.text.isNotEmpty) ...[
                          const Divider(height: 24),
                          Focus(
                            canRequestFocus: false,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _mdBtn(Icons.format_bold, () => _insertMd("**")),
                                  const SizedBox(width: 12),
                                  _mdBtn(Icons.format_italic, () => _insertMd("*")),
                                  const SizedBox(width: 12),
                                  _mdBtn(Icons.link, () => _insertMd("[]()")),
                                  const SizedBox(width: 12),
                                  _mdBtn(Icons.code, () => _insertMd("`")),
                                  const SizedBox(width: 12),
                                  _mdBtn(Icons.format_quote, () => _insertMd("> ")),
                                  const SizedBox(width: 16),
                                  Text(
                                    "${_commentController.text.length} ${"chars".tl}",
                                    style: TextStyle(fontSize: 11, color: secondaryColor.withValues(alpha: 0.6)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _isSubmitting
                        ? const Padding(
                            padding: EdgeInsets.all(10.0),
                            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : BloretIconButton(
                            onPressed: _commentController.text.trim().isEmpty ? null : _submitComment,
                            icon: Icons.send,
                            tooltip: "Send".tl,
                          ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mdBtn(IconData icon, VoidCallback onTap) {
    return BloretIconButton(
      icon: icon,
      onPressed: onTap,
      tooltip: "",
    );
  }

  String _formatTime(dynamic t) {
    if (t == null) return '';
    try {
      DateTime dt;
      if (t is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(t > 10000000000 ? t : t * 1000);
      } else if (t is String) {
        final val = int.tryParse(t);
        if (val != null) {
          dt = DateTime.fromMillisecondsSinceEpoch(val > 10000000000 ? val : val * 1000);
        } else {
          dt = DateTime.parse(t);
        }
      } else {
        return '';
      }
      dt = dt.toLocal();
      return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    } catch (_) {
      return t.toString();
    }
  }
}
