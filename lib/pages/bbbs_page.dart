import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../core/i18n.dart';
import '../services/bbbs.dart';
import '../models/bbbs_post.dart';
import '../widgets/button.dart';
import 'bbbs_detail_page.dart';

class BbbsPage extends StatefulWidget {
  const BbbsPage({super.key});

  @override
  State<BbbsPage> createState() => _BbbsPageState();
}

class _BbbsPageState extends State<BbbsPage> with TickerProviderStateMixin {
  Map<String, dynamic> _summaryData = {};
  List<dynamic> _leaderboardData = [];
  List<BbbsPost> _allPostsData = [];
  List<BbbsPost> _todayFeedData = [];
  String? _nextCursor;
  Map<String, dynamic> _feedSettings = {};

  bool _isLoading = true;
  bool _isAuthenticated = false;
  int _currentTab = 0;

  late TabController _tabController;

  // Bloriko Chat State
  final List<Map<String, String>> _blorikoMessages = [];
  final TextEditingController _blorikoController = TextEditingController();
  final ScrollController _blorikoScrollController = ScrollController();
  bool _isBlorikoProcessing = false;
  final FocusNode _blorikoFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentTab = _tabController.index;
        });
      }
    });

    _blorikoFocusNode.addListener(() {
      if (mounted) setState(() {});
    });

    _initData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _blorikoController.dispose();
    _blorikoScrollController.dispose();
    _blorikoFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    _isAuthenticated = BbbsService.isAuthenticated();
    if (_isAuthenticated) {
      await _fetchAllData();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final summary = await BbbsService.fetchSummary();
      final leaderboard = await BbbsService.fetchLeaderboardPosts();
      final allPosts = await BbbsService.fetchAllPosts();
      final todayFeed = await BbbsService.fetchTodayFeed();

      if (!mounted) return;
      setState(() {
        _summaryData = summary ?? {};
        _leaderboardData = leaderboard;
        _allPostsData = allPosts.map((e) => BbbsPost.fromJson(e)).toList();
        
        if (todayFeed != null) {
          _todayFeedData = (todayFeed['items'] as List? ?? []).map((e) => BbbsPost.fromJson(e)).toList();
          _nextCursor = todayFeed['nextCursor'];
          _feedSettings = todayFeed['settings'] ?? {};
        }

        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("[BBBS] Error: $e");
    }
  }

  void _showFeedSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("推荐设置".tl),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _settingRow("启用推荐".tl, _feedSettings['enabled'] ?? false),
            _settingRow("AI 增强".tl, _feedSettings['aiEnabled'] ?? false),
            _settingRow("偏向多样性".tl, _feedSettings['preferDiversity'] ?? false),
            if (_feedSettings['mutedBoards']?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text("${"已屏蔽板块".tl}: ${_feedSettings['mutedBoards'].join(', ')}", style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("确定".tl)),
        ],
      ),
    );
  }

  Widget _settingRow(String label, bool value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Icon(
            value ? Icons.check_circle_outline : Icons.highlight_off,
            color: value ? Colors.green : Colors.grey,
            size: 20,
          ),
        ],
      ),
    );
  }

  Future<void> _sendBlorikoMessage() async {
    final text = _blorikoController.text.trim();
    if (text.isEmpty || _isBlorikoProcessing) return;

    _blorikoController.clear();
    setState(() {
      _blorikoMessages.add({"role": "user", "content": text});
      _blorikoMessages.add({"role": "assistant", "content": ""});
      _isBlorikoProcessing = true;
    });
    _scrollToBottom();

    final lastIndex = _blorikoMessages.length - 1;

    BbbsService.streamBlorikoChat(content: text).listen(
      (chunk) {
        if (!mounted) return;
        setState(() {
          _blorikoMessages[lastIndex]["content"] = (_blorikoMessages[lastIndex]["content"] ?? "") + chunk;
        });
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _isBlorikoProcessing = false);
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _isBlorikoProcessing = false;
          _blorikoMessages[lastIndex]["content"] = "Error: $e";
        });
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_blorikoScrollController.hasClients) {
        _blorikoScrollController.animateTo(
          _blorikoScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final secondaryColor = theme.colorScheme.onSurfaceVariant;
    final cardColor = theme.cardColor;
    final borderColor = isDark ? Colors.white24 : Colors.black12;

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            key: const PageStorageKey("bbbs_scroll"),
            controller: _currentTab == 4 ? _blorikoScrollController : null,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 400),
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: child,
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Text(
                              "BBBS",
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "百络论坛".tl,
                              style: TextStyle(
                                fontSize: 14,
                                color: secondaryColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.forum_outlined,
                                    size: 13,
                                    color: Colors.green,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    "Bloret BBS",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            if (_isAuthenticated) ...[
                              // if (_currentTab == 0 && _feedSettings.isNotEmpty)
                              //   IconButton(
                              //     icon: const Icon(Icons.settings_outlined, size: 20),
                              //     tooltip: "推荐设置".tl,
                              //     onPressed: () => _showFeedSettings(),
                              //   ),
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                tooltip: "刷新".tl,
                                onPressed: _isLoading ? null : _fetchAllData,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _isAuthenticated
                            ? const SizedBox.shrink()
                            : Container(
                          key: const ValueKey("login"),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.lock_outline,
                                size: 40,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "请先登录 Bloret PassPort".tl,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "登录后即可查看 BBBS 的每日摘要、热帖和最新内容".tl,
                                style: TextStyle(color: secondaryColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isAuthenticated) ...[
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final bool isCompact = constraints.maxWidth < 600;
                            return SegmentedButton<int>(
                              style: SegmentedButton.styleFrom(
                                padding: isCompact ? EdgeInsets.zero : null,
                                visualDensity: isCompact ? VisualDensity.compact : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              segments: [
                                ButtonSegment(
                                  value: 0,
                                  icon: isCompact ? null : const Icon(Icons.explore_outlined),
                                  label: isCompact ? Text("推荐".tl, style: TextStyle(fontSize: 10),) : Text("今日推荐".tl),
                                ),
                                ButtonSegment(
                                  value: 1,
                                  icon: isCompact ? null : const Icon(Icons.auto_awesome),
                                  label: isCompact ? Text("摘要".tl, style: TextStyle(fontSize: 10),) : Text("每日摘要".tl),
                                ),
                                ButtonSegment(
                                  value: 2,
                                  icon: isCompact ? null : const Icon(Icons.local_fire_department),
                                  label: isCompact ? Text("热帖".tl, style: TextStyle(fontSize: 10),) : Text("热帖排行".tl),
                                ),
                                ButtonSegment(
                                  value: 3,
                                  icon: isCompact ? null : const Icon(Icons.schedule),
                                  label: isCompact ? Text("最新".tl, style: TextStyle(fontSize: 10),) : Text("最新帖子".tl),
                                ),
                              ],
                              selected: {_currentTab},
                              onSelectionChanged: (value) {
                                setState(() {
                                  _currentTab = value.first;
                                });
                              },
                            );
                          }
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_isAuthenticated)
                _buildSliverContent(
                  textColor,
                  secondaryColor,
                  cardColor,
                  borderColor,
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.1),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: null,
    );
  }

  Widget _buildBlorikoInput(Color cardColor, Color borderColor, Color secondaryColor, ThemeData theme) {
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
                    color: _blorikoFocusNode.hasFocus ? theme.colorScheme.primary : borderColor,
                    width: _blorikoFocusNode.hasFocus ? 1.8 : 1.0,
                  ),
                ),
                child: TextField(
                  controller: _blorikoController,
                  focusNode: _blorikoFocusNode,
                  maxLines: 5,
                  minLines: 1,
                  onChanged: (v) => setState(() {}),
                  onSubmitted: (_) => _sendBlorikoMessage(),
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
            _isBlorikoProcessing
                ? const Padding(
                    padding: EdgeInsets.all(10.0),
                    child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : BloretIconButton(
                    onPressed: _blorikoController.text.trim().isEmpty ? null : _sendBlorikoMessage,
                    icon: Icons.send,
                    tooltip: "发送".tl,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverContent(
      Color textColor,
      Color secondaryColor,
      Color cardColor,
      Color borderColor,
      ) {
    switch (_currentTab) {
      case 0:
        if (_todayFeedData.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.recommend_outlined,
                      size: 40,
                      color: secondaryColor,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "暂无推荐内容".tl,
                      style: TextStyle(
                        color: secondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final tagColor = Theme.of(context).colorScheme.surfaceContainerHighest;
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverList(
            key: const ValueKey("today_feed_list"),
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final item = _todayFeedData[index];
                final card = _buildPostCard(item, textColor, secondaryColor, cardColor, borderColor, tagColor);
                
                return TweenAnimationBuilder<double>(
                  key: ValueKey("feed_${item.filename.isEmpty ? index : item.filename}"),
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 300 + (index < 10 ? index * 40 : 0)),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(offset: Offset(0, 20 * (1 - value)), child: child),
                  ),
                  child: card,
                );
              },
              childCount: _todayFeedData.length,
            ),
          ),
        );

      case 1:
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverToBoxAdapter(
            child: TweenAnimationBuilder<double>(
              key: ValueKey("summary_${_summaryData.hashCode}"),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 15 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "AI 每日摘要".tl,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _summaryData.isEmpty
                          ? "暂无每日摘要".tl
                          : (_summaryData['text'] ??
                          _summaryData['content'] ??
                          _summaryData['summary'] ??
                          _summaryData.toString()),
                      style: TextStyle(
                        color: textColor,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

      case 2:
        if (_leaderboardData.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.leaderboard_outlined,
                      size: 40,
                      color: secondaryColor,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "暂无热帖数据".tl,
                      style: TextStyle(
                        color: secondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverList(
            key: const ValueKey("leaderboard_list"),
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final item = _leaderboardData[index];
                final card = _buildLeaderboardItem(index, item, textColor, secondaryColor, cardColor, borderColor);
                
                return TweenAnimationBuilder<double>(
                  key: ValueKey("leaderboard_${item['id'] ?? index}"),
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 300 + (index < 10 ? index * 50 : 0)),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(offset: Offset(0, 20 * (1 - value)), child: child),
                  ),
                  child: card,
                );
              },
              childCount: _leaderboardData.length,
            ),
          ),
        );

      case 4:
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: _blorikoMessages.isEmpty
              ? SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
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
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildBlorikoMessageItem(_blorikoMessages[index], Theme.of(context)),
                    childCount: _blorikoMessages.length,
                  ),
                ),
        );

      case 3:
      default:
        if (_allPostsData.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 40,
                      color: secondaryColor,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "暂无帖子".tl,
                      style: TextStyle(
                        color: secondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final tagColor = Theme.of(context).colorScheme.surfaceContainerHighest;
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverList(
            key: const ValueKey("posts_list"),
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final item = _allPostsData[index];
                final card = _buildPostCard(item, textColor, secondaryColor, cardColor, borderColor, tagColor);
                
                return TweenAnimationBuilder<double>(
                  key: ValueKey("post_${item.filename.isEmpty ? index : item.filename}"),
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 300 + (index < 10 ? index * 40 : 0)),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(offset: Offset(0, 20 * (1 - value)), child: child),
                  ),
                  child: card,
                );
              },
              childCount: _allPostsData.length,
            ),
          ),
        );
    }
  }

  Widget _buildBlorikoMessageItem(Map<String, String> message, ThemeData theme) {
    final isUser = message["role"] == "user";
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _buildBlorikoAvatar(isUser),
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
          if (isUser) _buildBlorikoAvatar(isUser),
        ],
      ),
    );
  }

  Widget _buildBlorikoAvatar(bool isUser) {
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

  Widget _buildLeaderboardItem(int index, dynamic item, Color textColor, Color secondaryColor, Color cardColor, Color borderColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index == 0
                  ? Colors.amber
                  : index == 1
                  ? Colors.grey.shade400
                  : index == 2
                  ? Colors.brown.shade300
                  : Colors.grey.withValues(alpha: 0.2),
            ),
            child: Icon(
              index == 0
                  ? Icons.emoji_events
                  : index == 1
                  ? Icons.military_tech
                  : index == 2
                  ? Icons.workspace_premium
                  : Icons.star_outline,
              size: 20,
              color: index < 3 ? Colors.white : textColor,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title'] ?? item['name'] ?? '',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${item['board'] ?? ''}${item['section'] != null ? ' / ${item['section']}' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              _statItem(
                Icons.favorite_outline,
                item['likesCount'] ?? item['likes'] ?? 0,
                "赞".tl,
                secondaryColor,
              ),
              const SizedBox(width: 12),
              _statItem(
                Icons.chat_bubble_outline,
                item['commentsCount'] ?? item['comments'] ?? 0,
                "评论".tl,
                secondaryColor,
              ),
              const SizedBox(width: 12),
              _statItem(
                Icons.visibility_outlined,
                item['views'] ?? 0,
                "浏览".tl,
                secondaryColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(
      BbbsPost item,
      Color textColor,
      Color secondaryColor,
      Color cardColor,
      Color borderColor,
      Color tagColor
      ) {
    final author = item.author;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BbbsDetailPage(post: item),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: item.authorAvatar != null && item.authorAvatar!.isNotEmpty
                          ? CachedNetworkImageProvider(item.authorAvatar!)
                          : null,
                      child: (item.authorAvatar == null || item.authorAvatar!.isEmpty)
                          ? Text(
                              author.isEmpty ? '?' : author.substring(0, 1).toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            author,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            children: [
                              Icon(Icons.schedule, size: 12, color: secondaryColor),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _formatTime(item.time),
                                  style: TextStyle(fontSize: 11, color: secondaryColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (item.board.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: tagColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.board,
                          style: TextStyle(fontSize: 11, color: secondaryColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                if (item.recommendationReason != null && item.recommendationReason!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 12, color: Colors.blue.shade300),
                        const SizedBox(width: 4),
                        Text(
                          item.recommendationReason!,
                          style: TextStyle(fontSize: 11, color: Colors.blue.shade300, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                if (item.content.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 100),
                    child: ClipRect(
                      child: Builder(
                        builder: (context) {
                          String displayContent = item.content.trim();
                          final lines = displayContent.split('\n');
                          
                          if (lines.isNotEmpty) {
                            final String firstLine = lines.first.trim();
                            final String cleanFirstLine = firstLine.replaceFirst(RegExp(r'^#+\s*'), '').trim();
                            
                            if (cleanFirstLine == item.title.trim()) {
                              displayContent = lines.skip(1).join('\n').trim();
                            } else if (displayContent.startsWith(item.title)) {
                              displayContent = displayContent.substring(item.title.length).trim();
                            }
                          }
                          
                          if (displayContent.isEmpty) return const SizedBox.shrink();

                          return GptMarkdown(
                            displayContent,
                            style: TextStyle(fontSize: 13, color: secondaryColor.withValues(alpha: 0.8)),
                          );
                        }
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _statItemIconOnly(
                      Icons.favorite_outline,
                      _formatCount(item.likes),
                      secondaryColor,
                    ),
                    const SizedBox(width: 15),
                    _statItemIconOnly(
                      Icons.chat_bubble_outline,
                      _formatCount(item.commentsCount),
                      secondaryColor,
                    ),
                    const SizedBox(width: 15),
                    _statItemIconOnly(
                      Icons.visibility_outlined,
                      "${item.views}",
                      secondaryColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatCount(dynamic count) {
    if (count is List) return count.length.toString();
    return (count ?? 0).toString();
  }

  Widget _statItem(IconData icon, dynamic count, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatCount(count),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
            ),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ],
    );
  }

  Widget _statItemIconOnly(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
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
        return t.toString();
      }
      dt = dt.toLocal();
      return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return t.toString();
    }
  }

  String _truncate(String text, int limit) {
    if (text.length > limit) {
      return '${text.substring(0, limit)}...';
    }
    return text;
  }
}
