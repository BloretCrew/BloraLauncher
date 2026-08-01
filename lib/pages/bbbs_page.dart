import 'package:flutter/material.dart';
import '../core/i18n.dart';
import '../services/bbbs.dart';

class BbbsPage extends StatefulWidget {
  const BbbsPage({super.key});

  @override
  State<BbbsPage> createState() => _BbbsPageState();
}

class _BbbsPageState extends State<BbbsPage> with TickerProviderStateMixin {
  Map<String, dynamic> _summaryData = {};
  List<dynamic> _leaderboardData = [];
  List<dynamic> _allPostsData = [];
  bool _isLoading = true;
  bool _isAuthenticated = false;
  int _currentTab = 0;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentTab = _tabController.index;
        });
      }
    });

    _initData();
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

      if (!mounted) return;
      setState(() {
        _summaryData = summary ?? {};
        _leaderboardData = leaderboard;
        _allPostsData = allPosts;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("[BBBS] Error: $e");
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
                            if (_isAuthenticated)
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                tooltip: "刷新".tl,
                                onPressed: _isLoading ? null : _fetchAllData,
                              ),
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
                            final bool isCompact = constraints.maxWidth < 500;
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
                                  icon: isCompact ? null : const Icon(Icons.auto_awesome),
                                  label: isCompact ? Text("摘要".tl) : Text("每日摘要".tl),
                                ),
                                ButtonSegment(
                                  value: 1,
                                  icon: isCompact ? null : const Icon(Icons.local_fire_department),
                                  label: isCompact ? Text("热帖".tl) : Text("热帖排行".tl),
                                ),
                                ButtonSegment(
                                  value: 2,
                                  icon: isCompact ? null : const Icon(Icons.schedule),
                                  label: isCompact ? Text("最新".tl) : Text("最新帖子".tl),
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

      case 1:
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

      case 2:
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
                  key: ValueKey("post_${item['id'] ?? index}"),
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
      Map<String, dynamic> item,
      Color textColor,
      Color secondaryColor,
      Color cardColor,
      Color borderColor,
      Color tagColor
      ) {
    final author = item['author'] ?? item['username'] ?? '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
              CircleAvatar(
                radius: 16,
                child: Text(
                  author.toString().isEmpty ? '?' : author.toString().substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author.toString(),
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
                            _formatTime(item['time'] ?? item['created_at'] ?? item['date']),
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
              if (item['board'] != null)
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: tagColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item['board'],
                      style: TextStyle(fontSize: 11, color: secondaryColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item['title'] ?? '',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          if (item['content'] != null || item['excerpt'] != null) ...[
            const SizedBox(height: 6),
            Text(
              _truncate(item['content'] ?? item['excerpt'] ?? '', 120),
              style: TextStyle(fontSize: 13, color: secondaryColor),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _statItemIconOnly(
                Icons.favorite_outline,
                _formatCount(item['likesCount'] ?? item['likes']),
                secondaryColor,
              ),
              const SizedBox(width: 15),
              _statItemIconOnly(
                Icons.chat_bubble_outline,
                _formatCount(item['commentsCount'] ?? item['comments']),
                secondaryColor,
              ),
              const SizedBox(width: 15),
              _statItemIconOnly(
                Icons.visibility_outlined,
                "${item['views'] ?? 0}",
                secondaryColor,
              ),
            ],
          ),
        ],
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
        if (t > 10000000000) {
          dt = DateTime.fromMillisecondsSinceEpoch(t);
        } else {
          dt = DateTime.fromMillisecondsSinceEpoch(t * 1000);
        }
      } else if (t is String) {
        dt = DateTime.parse(t);
      } else {
        return t.toString();
      }
      dt = dt.toLocal();
      return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      String str = t.toString();
      return str.length > 16 ? str.substring(0, 16) : str;
    }
  }

  String _truncate(String text, int limit) {
    if (text.length > limit) {
      return '${text.substring(0, limit)}...';
    }
    return text;
  }
}
