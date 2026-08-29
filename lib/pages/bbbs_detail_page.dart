import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
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
  
  bool _isMdEnabled = false;
  bool _isPreviewMode = false;
  
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
      final data = await BbbsService.fetchPostsByBoard(
        _currentPost.board, 
        _currentPost.section ?? ""
      );
      
      if (mounted) {
        setState(() {
          dynamic postJson;
          postJson = data.firstWhere(
            (element) => element['filename'] == _currentPost.filename,
            orElse: () => null,
          );

          if (postJson == null) {
            _fetchSinglePost();
            return;
          }

          _currentPost = BbbsPost.fromJson(Map<String, dynamic>.from(postJson));
          _isLoading = false;
        });
        logger.info("[BBBS] Detail refreshed via Board API. Comments: ${_currentPost.comments.length}", LogSource.network);
      } else {
        _fetchSinglePost();
      }
    } catch (e) {
      logger.error("[BBBS] Refresh error: $e", LogSource.network);
      _fetchSinglePost();
    }
  }

  Future<void> _fetchSinglePost() async {
    try {
      final data = await BbbsService.fetchPostDetail(_currentPost.filename);
      if (data != null && mounted) {
        setState(() {
          final postJson = data is Map && data.containsKey('post') ? data['post'] : data;
          if (postJson != null) {
            _currentPost = BbbsPost.fromJson(Map<String, dynamic>.from(postJson));
          }
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _insertMd(String tagStart, [String? tagEnd]) {
    final text = _commentController.text;
    final selection = _commentController.selection;
    final actualTagEnd = tagEnd ?? tagStart;
    
    if (!selection.isValid) {
      final newText = text + tagStart + actualTagEnd;
      _commentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length - actualTagEnd.length),
      );
    } else {
      final selectedText = selection.textInside(text);
      final newText = text.replaceRange(selection.start, selection.end, "$tagStart$selectedText$actualTagEnd");
      _commentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: selection.start + tagStart.length,
          extentOffset: selection.end + tagStart.length,
        ),
      );
    }
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

  String? _getReplyAuthor(int? replyToId) {
    if (replyToId == null) return null;
    try {
      final reply = _currentPost.comments.firstWhere((c) => c.id == replyToId);
      return reply.authorNickname ?? reply.author;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final secondaryColor = theme.colorScheme.onSurfaceVariant;
    final cardColor = theme.cardColor;
    final borderColor = theme.dividerColor.withValues(alpha: 0.1);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
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
              ? Text(_currentPost.authorNickname?[0].toUpperCase() ?? _currentPost.author[0].toUpperCase()) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_currentPost.authorNickname ?? _currentPost.author, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(_currentPost.authorTitle ?? "User".tl, style: TextStyle(fontSize: 12, color: secondaryColor)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_formatTime(_currentPost.time), style: TextStyle(fontSize: 12, color: secondaryColor)),
            if (_currentPost.ipLocation != null && _currentPost.ipLocation!.isNotEmpty)
              Text("IP: ${_currentPost.ipLocation}", style: TextStyle(fontSize: 10, color: secondaryColor.withValues(alpha: 0.7))),
          ],
        ),
      ],
    );
  }

  Widget _buildContentSection(Color textColor, Color secondaryColor, Color cardColor, Color borderColor) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildParsedContent(_currentPost.content, textColor, theme),
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

  Widget _buildParsedContent(String content, Color textColor, ThemeData theme) {
    final combinedRegex = RegExp(
      r'(<!DOCTYPE html>[\s\S]*?</html>|<iframe[\s\S]*?</iframe>)|```投票\s*\n([\s\S]*?)\n```', 
      caseSensitive: false
    );
    final List<Widget> widgets = [];
    int lastMatchEnd = 0;

    for (final match in combinedRegex.allMatches(content)) {
      if (match.start > lastMatchEnd) {
        final text = content.substring(lastMatchEnd, match.start).trim();
        if (text.isNotEmpty) {
          widgets.add(GptMarkdown(text, style: TextStyle(fontSize: 16, color: textColor, height: 1.6)));
        }
      }

      final matchText = match.group(0)!;
      if (matchText.toLowerCase().contains('<!doctype html>') || matchText.toLowerCase().contains('<iframe')) {
        widgets.add(_buildHtmlCard(matchText, theme));
      } else if (match.group(2) != null) {
        widgets.add(_buildVoteCard(match.group(2)!, theme));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < content.length) {
      final text = content.substring(lastMatchEnd).trim();
      if (text.isNotEmpty) {
        widgets.add(GptMarkdown(text, style: TextStyle(fontSize: 16, color: textColor, height: 1.6)));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildHtmlCard(String htmlContent, ThemeData theme) {
    try {
      final document = html_parser.parse(htmlContent);
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _parseHtmlNodes(document.body?.nodes ?? [], theme),
        ),
      );
    } catch (e) {
      return Text("HTML Render Error: $e", style: const TextStyle(color: Colors.red));
    }
  }

  List<Widget> _parseHtmlNodes(Iterable<dom.Node> nodes, ThemeData theme) {
    List<Widget> widgets = [];
    for (var node in nodes) {
      if (node is dom.Element) {
        widgets.add(_buildElementWidget(node, theme));
      } else if (node is dom.Text) {
        final text = node.text.trim();
        if (text.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(text, style: TextStyle(color: theme.colorScheme.onSurface)),
          ));
        }
      }
    }
    return widgets;
  }

  Widget _buildElementWidget(dom.Element element, ThemeData theme) {
    final tag = element.localName?.toLowerCase();
    
    switch (tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        double fontSize = 16;
        if (tag == 'h1') {
          fontSize = 24;
        } else if (tag == 'h2') {
          fontSize = 20;
        } else if (tag == 'h3') {
          fontSize = 18;
        }
        
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text.rich(_parseToTextSpan(element, theme, baseStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold))),
        );
      case 'p':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text.rich(_parseToTextSpan(element, theme, baseStyle: const TextStyle(fontSize: 15, height: 1.5))),
        );
      case 'div':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _parseHtmlNodes(element.nodes, theme),
        );
      case 'img':
        final src = element.attributes['src'];
        if (src != null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: CachedNetworkImage(
                  imageUrl: src,
                  placeholder: (context, url) => Container(color: theme.dividerColor.withValues(alpha: 0.1), height: 100, width: double.infinity),
                  errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      case 'ul':
      case 'ol':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: element.children.where((e) => e.localName == 'li').map((li) => Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tag == 'ul' ? "• " : "${element.children.indexOf(li) + 1}. ", style: const TextStyle(fontWeight: FontWeight.bold)),
                Expanded(child: Text.rich(_parseToTextSpan(li, theme))),
              ],
            ),
          )).toList(),
        );
      case 'br':
        return const SizedBox(height: 8);
      case 'hr':
        return const Divider(height: 24);
      case 'iframe':
        final src = element.attributes['src'];
        if (src != null) {
          return _buildVideoPlaceholder(src, theme);
        }
        return const SizedBox.shrink();
      default:
        // Try to treat as inline if it contains text or just render children
        if (element.children.isEmpty) {
          return Text.rich(_parseToTextSpan(element, theme));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _parseHtmlNodes(element.nodes, theme),
        );
    }
  }

  InlineSpan _parseToTextSpan(dom.Node node, ThemeData theme, {TextStyle? baseStyle}) {
    if (node is dom.Text) {
      return TextSpan(text: node.text, style: baseStyle);
    }
    
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      TextStyle style = baseStyle ?? TextStyle(color: theme.colorScheme.onSurface);
      
      if (tag == 'b' || tag == 'strong') {
        style = style.copyWith(fontWeight: FontWeight.bold);
      } else if (tag == 'i' || tag == 'em') {
        style = style.copyWith(fontStyle: FontStyle.italic);
      } else if (tag == 'u') {
        style = style.copyWith(decoration: TextDecoration.underline);
      } else if (tag == 'a') {
        style = style.copyWith(color: theme.colorScheme.primary, decoration: TextDecoration.underline);
      } else if (tag == 'code') {
        style = style.copyWith(backgroundColor: theme.dividerColor.withValues(alpha: 0.1), fontFamily: 'monospace');
      }

      return TextSpan(
        style: style,
        children: node.nodes.map((child) => _parseToTextSpan(child, theme, baseStyle: style)).toList(),
      );
    }
    
    return const TextSpan(text: "");
  }

  Widget _buildVideoPlaceholder(String src, ThemeData theme) {
    String finalUrl = src;
    if (src.startsWith('//')) {
      finalUrl = 'https:$src';
    }

    final bool isBilibili = finalUrl.contains('bilibili.com');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () async {
            final uri = Uri.parse(finalUrl);
            try {
              await launchUrl(uri,);
            } catch (e) {
              logger.error("[BBBS] Failed to launch video URL: $e");
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.live_tv_outlined,
                  size: 64,
                  color: isBilibili ? Colors.pinkAccent.withValues(alpha: 0.8) : theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
                const SizedBox(height: 16),
                Text(
                  isBilibili ? "Bilibili Video".tl : "External Video".tl,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  "Click to play in browser".tl,
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoteCard(String voteContent, ThemeData theme) {
    final lines = voteContent.split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
        
    if (lines.isEmpty) return const SizedBox.shrink();

    String question = "";
    List<String> options = [];

    if (lines[0].toLowerCase().startsWith('title:')) {
      question = lines[0].substring(6).trim();
      options = lines.skip(1).toList();
    } else {
      question = lines[0];
      options = lines.skip(1).toList();
    }

    final votes = _currentPost.votes ?? {};
    final hasVoted = _currentPost.userHasVoted ?? false;
    
    int totalVotes = 0;
    votes.forEach((key, value) {
      if (value is List) totalVotes += value.length;
    });

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.poll_rounded, color: theme.colorScheme.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text("Vote".tl, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 13), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: hasVoted ? 1.0 : 0.0,
                child: Text("${"Total".tl}: $totalVotes", style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(question, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          ...options.map((opt) {
            final optionKey = opt.trim();
            final voteList = votes[optionKey] is List ? List<String>.from(votes[optionKey]) : [];
            final count = voteList.length;
            final percent = totalVotes > 0 ? count / totalVotes : 0.0;
            final optionText = optionKey.replaceFirst('- ', '').trim();

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return InkWell(
                    onTap: hasVoted ? null : () => _handleVote(optionKey),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: hasVoted 
                            ? theme.dividerColor.withValues(alpha: 0.1) 
                            : theme.colorScheme.primary.withValues(alpha: 0.4)
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.easeOutCubic,
                              width: hasVoted ? constraints.maxWidth * percent : 0,
                              height: double.infinity,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                              ),
                            ),
                            Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        optionText, 
                                        style: TextStyle(
                                          color: hasVoted ? theme.colorScheme.onSurface : theme.colorScheme.primary,
                                          fontWeight: hasVoted ? FontWeight.normal : FontWeight.w500,
                                          fontSize: 15,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    ),
                                    if (hasVoted)
                                      AnimatedOpacity(
                                        duration: const Duration(milliseconds: 600),
                                        opacity: 1.0,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const SizedBox(width: 8),
                                            Text(
                                              "${(percent * 100).toStringAsFixed(0)}%", 
                                              style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.bold)
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              "$count", 
                                              style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _handleVote(String optionKey) async {
    final userName = ConfigService.get('Bloret_PassPort_UserName') ?? "Guest";
    
    setState(() {
      final newVotes = Map<String, dynamic>.from(_currentPost.votes ?? {});
      final list = newVotes[optionKey] is List ? List<String>.from(newVotes[optionKey]) : [];
      if (!list.contains(userName)) {
        list.add(userName);
      }
      newVotes[optionKey] = list;
      
      _currentPost = _currentPost.copyWith(
        votes: newVotes,
        userHasVoted: true,
      );
    });
    
    showSuccess("Vote recorded".tl);
    
    // In actual implementation, call BbbsService to persist
    try {
      // await BbbsService.votePost(filename: _currentPost.filename, option: optionKey);
    } catch (e) {
      logger.error("[BBBS] Vote error: $e", LogSource.network);
    }
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
    final userName = ConfigService.get('Bloret_PassPort_NickName') ?? ConfigService.get('Bloret_PassPort_UserName') ?? "";
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
        Text("(${_currentPost.comments.length})", style: TextStyle(color: secondaryColor)),
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
          key: ValueKey("comment_${comment.id}"),
          duration: const Duration(milliseconds: 400),
          tween: Tween(begin: 0.0, end: 1.0),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - value)),
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
    if (comment.content.isEmpty && (comment.authorNickname?.isEmpty ?? true) && comment.author.isEmpty) return const SizedBox.shrink();

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
                    ? comment.authorNickname?.isNotEmpty == true ? Text(comment.authorNickname![0].toUpperCase()) : Text(comment.author.isNotEmpty ? comment.author[0].toUpperCase() : "?") : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(comment.authorNickname ?? comment.author, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        if (comment.replyToId != null) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.play_arrow_rounded, size: 12, color: secondaryColor.withValues(alpha: 0.5)),
                          const SizedBox(width: 4),
                          Text(
                            "@${_getReplyAuthor(comment.replyToId) ?? "User".tl}",
                            style: TextStyle(
                              fontSize: 13, 
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w500
                            ),
                          ),
                        ],
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_formatTime(comment.time), style: TextStyle(fontSize: 11, color: secondaryColor)),
                            if (comment.ipLocation != null && comment.ipLocation!.isNotEmpty)
                              Text("IP: ${comment.ipLocation}", style: TextStyle(fontSize: 9, color: secondaryColor.withValues(alpha: 0.7))),
                          ],
                        ),
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

    return GestureDetector(
      onTap: () {},
      child: Container(
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
              padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (!_isPreviewMode) {
                          _focusNode.requestFocus();
                        }
                      },
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isPreviewMode)
                              Container(
                                constraints: const BoxConstraints(minHeight: 40, maxHeight: 200),
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: SingleChildScrollView(
                                  child: GptMarkdown(
                                    _commentController.text.isEmpty ? "*${"Preview Content".tl}*" : _commentController.text,
                                    style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurface),
                                  ),
                                ),
                              )
                            else
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 150),
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

                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: _isMdEnabled
                                  ? Column(
                                      children: [
                                        const Divider(height: 16),
                                        Focus(
                                          canRequestFocus: false,
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              children: [
                                                _mdBtn(Icons.format_bold, () => _insertMd("**")),
                                                const SizedBox(width: 8),
                                                _mdBtn(Icons.format_italic, () => _insertMd("*")),
                                                const SizedBox(width: 8),
                                                _mdBtn(Icons.link, () => _insertMd("[", "](url)")),
                                                const SizedBox(width: 8),
                                                _mdBtn(Icons.code, () => _insertMd("`")),
                                                const SizedBox(width: 8),
                                                _mdBtn(Icons.format_quote, () => _insertMd("> ")),
                                                const SizedBox(width: 8),
                                                _mdBtn(Icons.format_list_bulleted, () => _insertMd("- ")),
                                                const SizedBox(width: 12),
                                                Text(
                                                  "${_commentController.text.length} ${"chars".tl}",
                                                  style: TextStyle(fontSize: 11, color: secondaryColor.withValues(alpha: 0.6)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    child: (_focusNode.hasFocus || _commentController.text.isNotEmpty)
                        ? Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                BloretIconButton(
                                  icon: _isMdEnabled ? Icons.edit : Icons.edit_note,
                                  color: _isMdEnabled ? theme.colorScheme.primary : secondaryColor,
                                  onPressed: () => setState(() => _isMdEnabled = !_isMdEnabled),
                                  tooltip: "Markdown Tools".tl,
                                ),
                                const SizedBox(height: 4),
                                BloretIconButton(
                                  icon: _isPreviewMode ? Icons.visibility : Icons.visibility_off,
                                  color: _isPreviewMode ? theme.colorScheme.primary : secondaryColor,
                                  onPressed: () => setState(() => _isPreviewMode = !_isPreviewMode),
                                  tooltip: "Preview".tl,
                                ),
                                const SizedBox(height: 4),
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
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
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
