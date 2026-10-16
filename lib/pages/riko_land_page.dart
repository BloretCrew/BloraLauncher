import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum RikoThemeMode { system, time, light, dark }

class RikoChapter {
  final String num;
  final String title;
  final String readerUrl;
  final String bbsUrl;
  final bool isLatest;

  const RikoChapter({
    required this.num,
    required this.title,
    required this.readerUrl,
    required this.bbsUrl,
    this.isLatest = false,
  });
}

class RikoAct {
  final String id;
  final String badge;
  final String part;
  final String name;
  final List<RikoChapter> chapters;

  const RikoAct({
    required this.id,
    required this.badge,
    required this.part,
    required this.name,
    required this.chapters,
  });
}

class RikoThemeColors {
  final Color cream;
  final Color paper;
  final Color beige;
  final Color tan;
  final Color brown;
  final Color cocoa;
  final Color text;
  final Color muted;
  final Color ice;
  final Color iceDeep;
  final Color iceInk;
  final Color star;
  final Color starSoft;
  final Color line;
  final Color stitch;

  const RikoThemeColors({
    required this.cream,
    required this.paper,
    required this.beige,
    required this.tan,
    required this.brown,
    required this.cocoa,
    required this.text,
    required this.muted,
    required this.ice,
    required this.iceDeep,
    required this.iceInk,
    required this.star,
    required this.starSoft,
    required this.line,
    required this.stitch,
  });

  static const RikoThemeColors light = RikoThemeColors(
    cream: Color(0xFFFBF5EA),
    paper: Color(0xFFFFFDF8),
    beige: Color(0xFFF3E7D3),
    tan: Color(0xFFDDBF9C),
    brown: Color(0xFFA0704C),
    cocoa: Color(0xFF5E3D2B),
    text: Color(0xFF4A3326),
    muted: Color(0xFF8B7262),
    ice: Color(0xFFE2F1F6),
    iceDeep: Color(0xFFA8D2E2),
    iceInk: Color(0xFF4F8EA6),
    star: Color(0xFFF2994A),
    starSoft: Color(0xFFFCE3CB),
    line: Color(0x47A0704C),
    stitch: Color(0x59A0704C),
  );

  static const RikoThemeColors dark = RikoThemeColors(
    cream: Color(0xFF211915),
    paper: Color(0xFF2B211C),
    beige: Color(0xFF372A23),
    tan: Color(0xFF6E5240),
    brown: Color(0xFFD7AF8A),
    cocoa: Color(0xFFF1DFCB),
    text: Color(0xFFEFE2D3),
    muted: Color(0xFFBCA694),
    ice: Color(0xFF22343B),
    iceDeep: Color(0xFF3D6676),
    iceInk: Color(0xFF9ED0E2),
    star: Color(0xFFF6A85E),
    starSoft: Color(0xFF4A3424),
    line: Color(0x33D7AF8A),
    stitch: Color(0x47D7AF8A),
  );
}

class RikoLandPage extends StatefulWidget {
  const RikoLandPage({super.key});

  @override
  State<RikoLandPage> createState() => _RikoLandPageState();
}

class _RikoLandPageState extends State<RikoLandPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final Map<String, GlobalKey> _chapterKeys = {};

  RikoThemeMode _themeMode = RikoThemeMode.system;
  double _scrollProgress = 0.0;
  bool _showBackToTop = false;

  final Map<String, bool> _actOpenState = {'act-1': true};

  String _readingDestination = 'reader';

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initActStates();
  }

  void _initActStates() {
    for (var act in _allActs) {
      if (!_actOpenState.containsKey(act.id)) {
        _actOpenState[act.id] = (act.id == 'act-1');
      }
      for (var ch in act.chapters) {
        _chapterKeys[ch.num] = GlobalKey();
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;

    setState(() {
      _scrollProgress = maxScroll > 0
          ? (currentScroll / maxScroll).clamp(0.0, 1.0)
          : 0.0;
      _showBackToTop = currentScroll > 300;
    });
  }

  bool _isDarkMode(BuildContext context) {
    if (_themeMode == RikoThemeMode.light) return false;
    if (_themeMode == RikoThemeMode.dark) return true;
    if (_themeMode == RikoThemeMode.time) {
      final hour = DateTime.now().hour;
      return hour < 8 || hour >= 18;
    }
    // system
    return MediaQuery.of(context).platformBrightness == Brightness.dark;
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _scrollToLatestChapter() {
    for (var act in _allActs) {
      final hasLatest = act.chapters.any((c) => c.isLatest);
      if (hasLatest) {
        setState(() {
          _actOpenState[act.id] = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final key = _chapterKeys['076'];
          if (key != null && key.currentContext != null) {
            Scrollable.ensureVisible(
              key.currentContext!,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOutCubic,
              alignment: 0.5,
            );
          }
        });
        break;
      }
    }
  }

  void _toggleAllActs(bool expand) {
    setState(() {
      for (var act in _allActs) {
        _actOpenState[act.id] = expand;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _isDarkMode(context);
    final colors = isDark ? RikoThemeColors.dark : RikoThemeColors.light;

    return Scaffold(
      backgroundColor: colors.cream,
      body: Stack(
        children: [
          // 背景微光与格子波纹装饰
          CustomPaint(
            size: Size.infinite,
            painter: _RikoBackgroundPainter(colors: colors),
          ),

          // 主滚动内容
          Column(
            children: [
              // 顶部滚动进度条
              _buildProgressBar(colors),

              // 吸顶导航栏
              _buildHeader(colors, isDark),

              // 滚动主区域
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Hero 主视觉区
                          _buildHeroSection(colors),
                          const SizedBox(height: 36),

                          // 2. 核心入口卡片区
                          _buildEntryGrid(colors),
                          const SizedBox(height: 48),

                          // 3. 小说目录区
                          _buildTocSection(colors),
                          const SizedBox(height: 48),

                          // 4. 其他扩展内容区
                          _buildAuxGridSection(colors),
                          const SizedBox(height: 56),

                          // 5. 页脚区
                          _buildFooter(colors),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // 右下角浮动返回顶部按钮
          if (_showBackToTop)
            Positioned(
              right: 20,
              bottom: 24,
              child: _buildBackToTopButton(colors),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. 顶部进度条 & 导航栏 & 设置
  // ---------------------------------------------------------------------------
  Widget _buildProgressBar(RikoThemeColors colors) {
    return Container(
      height: 3,
      width: double.infinity,
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: _scrollProgress,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [colors.iceDeep, colors.star]),
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(RikoThemeColors colors, bool isDark) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.cream.withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(
            color: colors.line,
            width: 1.5,
            style: BorderStyle.solid,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Logo 与 品牌名称
            InkWell(
              onTap: () => _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.paper,
                        border: Border.all(color: colors.tan, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: colors.cocoa.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.network(
                          isDark
                              ? 'https://riko.land/assets/logo-dark.png'
                              : 'https://riko.land/assets/logo-light.jpg',
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => Container(
                            color: colors.beige,
                            child: Icon(
                              Icons.auto_awesome,
                              color: colors.brown,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '《络的世界》',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: colors.cocoa,
                            fontFamily: 'serif',
                          ),
                        ),
                        Text(
                          'RikoLand · little star',
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.brown,
                            fontFamily: "Riko World",
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),

            // 设置按钮
            OutlinedButton.icon(
              onPressed: () => _showSettingsDialog(colors),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.cocoa,
                backgroundColor: colors.paper,
                side: BorderSide(color: colors.line, width: 1.5),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              icon: Icon(Icons.settings, size: 18, color: colors.brown),
              label: const Text(
                '设置',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),

            // INFDS 通行证
            ElevatedButton.icon(
              onPressed: () => _launchUrl('https://passport.infds.top/'),
              style: ElevatedButton.styleFrom(
                foregroundColor: colors.paper,
                backgroundColor: colors.cocoa,
                elevation: 0,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
              ),
              icon: Icon(Icons.badge_outlined, size: 18, color: colors.paper),
              label: const Text(
                '通行证 →',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsDialog(RikoThemeColors colors) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: colors.paper,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: colors.line, width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.star_rounded,
                              color: colors.star,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '外观设置',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colors.cocoa,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(Icons.close, color: colors.muted),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                    Text(
                      '选择你喜欢的深浅色模式阅读界面',
                      style: TextStyle(fontSize: 13, color: colors.muted),
                    ),
                    const SizedBox(height: 16),

                    // 选项列表
                    _buildThemeOptionTile(
                      colors: colors,
                      mode: RikoThemeMode.system,
                      title: '按系统设置',
                      subtitle: '自动跟随系统的深浅色外观模式',
                      icon: Icons.desktop_windows_outlined,
                      setDialogState: setDialogState,
                    ),
                    _buildThemeOptionTile(
                      colors: colors,
                      mode: RikoThemeMode.time,
                      title: '按时间设置',
                      subtitle: '本地时间 8:00–18:00 为浅色，其余为深色',
                      icon: Icons.access_time_rounded,
                      setDialogState: setDialogState,
                    ),
                    _buildThemeOptionTile(
                      colors: colors,
                      mode: RikoThemeMode.light,
                      title: '浅色模式',
                      subtitle: '米色纸张般的治愈白天',
                      icon: Icons.wb_sunny_outlined,
                      setDialogState: setDialogState,
                    ),
                    _buildThemeOptionTile(
                      colors: colors,
                      mode: RikoThemeMode.dark,
                      title: '深色模式',
                      subtitle: '可可色的安静夜晚',
                      icon: Icons.nightlight_round_outlined,
                      setDialogState: setDialogState,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildThemeOptionTile({
    required RikoThemeColors colors,
    required RikoThemeMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required void Function(void Function()) setDialogState,
  }) {
    final isSelected = _themeMode == mode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() => _themeMode = mode);
          setDialogState(() {});
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? colors.starSoft
                : colors.cream.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? colors.star : colors.line,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? colors.star : colors.ice,
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.white : colors.iceInk,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colors.text,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: colors.muted),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: colors.star, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Hero 主视觉区
  // ---------------------------------------------------------------------------
  Widget _buildHeroSection(RikoThemeColors colors) {
    final isWide = MediaQuery.of(context).size.width > 768;
    final isDark = _isDarkMode(context);

    final leftTextWidget = Column(
      crossAxisAlignment: isWide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, color: colors.star, size: 16),
            const SizedBox(width: 6),
            Text(
              'a small star in ordinary days',
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: colors.brown,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '《络的世界》',
          style: TextStyle(
            fontSize: isWide ? 40 : 30,
            fontWeight: FontWeight.bold,
            color: colors.cocoa,
            fontFamily: 'serif',
            height: 1.1,
          ),
        ),
        Text(
          'Welcome to RikoLand',
          style: TextStyle(
            fontSize: 15,
            color: colors.iceInk,
            fontStyle: FontStyle.italic,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),

        // 手绘波浪下划线
        SizedBox(
          width: 200,
          height: 14,
          child: CustomPaint(painter: _RikoSquigglePainter(color: colors.star)),
        ),
        const SizedBox(height: 12),

        Text(
          '欢迎来到络可的童话小镇呀！这里藏着好多好多五彩斑斓的画稿和奇思妙想，快和络可一起推开这扇充满魔法的门，开启一段超温馨的冒险之旅吧~',
          textAlign: isWide ? TextAlign.left : TextAlign.center,
          style: TextStyle(fontSize: 14, color: colors.muted, height: 1.6),
        ),
        const SizedBox(height: 16),

        // Chips 状态标签
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: isWide ? WrapAlignment.start : WrapAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.paper,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colors.line, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit, size: 14, color: colors.cocoa),
                  const SizedBox(width: 6),
                  Text(
                    '预计2027年继续更新！',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.cocoa,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );

    final rightArtWidget = SizedBox(
      width: 240,
      height: 270,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 背后冰蓝光晕
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.ice.withValues(alpha: 0.6),
            ),
          ),

          // 拍立得相框 (倾斜 3 度)
          Transform.rotate(
            angle: 0.05,
            child: Container(
              width: 210,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 38),
              decoration: BoxDecoration(
                color: colors.paper,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: colors.cocoa.withValues(alpha: 0.2),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Image.network(
                        isDark
                            ? 'https://riko.land/assets/logo-dark.png'
                            : 'https://riko.land/assets/logo-light.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Container(
                          color: colors.beige,
                          child: Icon(
                            Icons.palette_outlined,
                            size: 48,
                            color: colors.brown,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'RikoLand ✦',
                    style: TextStyle(
                      fontSize: 16,
                      color: colors.brown,
                      fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 顶部半透明贴纸
          Positioned(
            top: 2,
            child: Transform.rotate(
              angle: -0.07,
              child: Container(
                width: 90,
                height: 24,
                decoration: BoxDecoration(
                  color: colors.iceDeep.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 周边装饰星星
          Positioned(
            top: -10,
            right: 0,
            child: Icon(Icons.star_rounded, color: colors.star, size: 28),
          ),
          Positioned(
            bottom: 10,
            left: -10,
            child: Icon(Icons.star_rounded, color: colors.star, size: 20),
          ),
        ],
      ),
    );

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 6, child: leftTextWidget),
          const SizedBox(width: 32),
          Expanded(flex: 5, child: Center(child: rightArtWidget)),
        ],
      );
    } else {
      return Column(
        children: [leftTextWidget, const SizedBox(height: 28), rightArtWidget],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 3. 核心入口卡片区
  // ---------------------------------------------------------------------------
  Widget _buildEntryGrid(RikoThemeColors colors) {
    final isWide = MediaQuery.of(context).size.width > 768;

    final card1 = _buildEntryCard(
      colors: colors,
      icon: Icons.menu_book_rounded,
      tagText: '敬请期待后续更新！',
      tagColor: colors.star,
      tagBgColor: colors.starSoft,
      title: '《络的世界》',
      description: '从沙滩上的第一幅画开始，跟随主角一同踏入这个世界的边缘与深处。',
      buttons: [
        _EntryCtaButton(
          label: '前往阅读器 →',
          onPressed: () => _launchUrl('https://read.riko.land/'),
          colors: colors,
        ),
        _EntryCtaButton(
          label: '开始阅读 →',
          onPressed: () => _launchUrl(
            'https://bbs.bloret.net/#section/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4',
          ),
          colors: colors,
        ),
      ],
    );

    final card2 = _buildEntryCard(
      colors: colors,
      icon: Icons.collections_bookmark_rounded,
      tagText: '设定集 · 未完成',
      tagColor: colors.iceInk,
      tagBgColor: colors.ice,
      title: '络可的笔记本',
      description: '小说中已出现设定的整理与解释。建议先阅读已更新章节后再翻阅，避免剧透。',
      buttons: [
        _EntryCtaButton(
          label: '翻阅笔记本 →',
          onPressed: () => _launchUrl(
            'https://bbs.bloret.net/#section/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E7%BB%9C%E5%8F%AF%E7%9A%84%E7%AC%94%E8%AE%B0%E6%9C%AC',
          ),
          colors: colors,
        ),
        _EntryCtaButton(
          label: '前往阅读Wiki →',
          onPressed: () => _launchUrl('https://wiki.riko.land/'),
          colors: colors,
        ),
      ],
    );

    if (isWide) {
      return Row(
        children: [
          Expanded(child: card1),
          const SizedBox(width: 20),
          Expanded(child: card2),
        ],
      );
    } else {
      return Column(children: [card1, const SizedBox(height: 20), card2]);
    }
  }

  Widget _buildEntryCard({
    required RikoThemeColors colors,
    required IconData icon,
    required String tagText,
    required Color tagColor,
    required Color tagBgColor,
    required String title,
    required String description,
    required List<Widget> buttons,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.paper,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.line, width: 2),
        boxShadow: [
          BoxShadow(
            color: colors.cocoa.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: colors.beige,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 28, color: colors.cocoa),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: tagBgColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tagColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  tagText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: tagColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: colors.cocoa,
              fontFamily: 'serif',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(fontSize: 13, color: colors.muted, height: 1.5),
          ),
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, children: buttons),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. 小说目录手账区
  // ---------------------------------------------------------------------------
  Widget _buildTocSection(RikoThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部标题 & 工具栏
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.star_rounded, color: colors.star, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        '小说目录',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: colors.cocoa,
                          fontFamily: 'serif',
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'table of contents',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.brown,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            // 工具按钮群
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _scrollToLatestChapter,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.cocoa,
                    backgroundColor: colors.paper,
                    side: BorderSide(color: colors.line, width: 1.5),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  icon: Icon(
                    Icons.star_outline_rounded,
                    size: 16,
                    color: colors.star,
                  ),
                  label: const Text(
                    '最新章节',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    final allOpen = _allActs.every(
                      (a) => _actOpenState[a.id] == true,
                    );
                    _toggleAllActs(!allOpen);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.cocoa,
                    backgroundColor: colors.paper,
                    side: BorderSide(color: colors.line, width: 1.5),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  icon: Icon(
                    Icons.unfold_more_rounded,
                    size: 16,
                    color: colors.brown,
                  ),
                  label: Text(
                    _allActs.every((a) => _actOpenState[a.id] == true)
                        ? '全部收起'
                        : '全部展开',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),

        Text(
          '点击目录中的章节可以直接跳转到对应的剧情内容，快速定位到您感兴趣的章节。',
          style: TextStyle(fontSize: 13, color: colors.muted),
        ),
        const SizedBox(height: 16),

        // 搜索输入框
        TextField(
          controller: _searchController,
          onChanged: (val) {
            setState(() {
              _searchQuery = val.trim().toLowerCase();
            });
          },
          decoration: InputDecoration(
            hintText: '搜索章节名或编号（如：001 或 沙滩）…',
            hintStyle: TextStyle(fontSize: 13, color: colors.muted),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: colors.muted,
              size: 20,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: colors.muted, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: colors.paper,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(color: colors.line, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(color: colors.star, width: 2),
            ),
          ),
          style: TextStyle(fontSize: 14, color: colors.text),
        ),
        const SizedBox(height: 16),

        // 手账目录板 (Notebook Board)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.paper,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.line, width: 2),
            boxShadow: [
              BoxShadow(
                color: colors.cocoa.withValues(alpha: 0.1),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 状态 Meta 信息与阅读跳转选择器
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bookmark_rounded,
                        color: colors.star,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 13, color: colors.muted),
                          children: [
                            const TextSpan(text: '已更新 '),
                            TextSpan(
                              text: '76',
                              style: TextStyle(
                                color: colors.star,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const TextSpan(text: ' 节 · 共 10 幕 · 连载中'),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // 阅读器 / BBBS 目标切换开关
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: colors.cream,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: colors.line),
                        ),
                        child: Row(
                          children: [
                            _buildDestinationChip('reader', '阅读器', colors),
                            _buildDestinationChip('bbs', 'BBBS', colors),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _showReadingHelpDialog(colors),
                        icon: Icon(
                          Icons.help_outline_rounded,
                          color: colors.brown,
                          size: 20,
                        ),
                        tooltip: '兑换码福利与BBBS介绍',
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 24, thickness: 1.5),

              // 幕列表 (Accordion List)
              _buildActAccordionList(colors),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDestinationChip(
    String key,
    String label,
    RikoThemeColors colors,
  ) {
    final isSelected = _readingDestination == key;
    return InkWell(
      onTap: () => setState(() => _readingDestination = key),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colors.ice : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? colors.iceInk : colors.muted,
          ),
        ),
      ),
    );
  }

  Widget _buildActAccordionList(RikoThemeColors colors) {
    var hasAnyMatch = false;

    final children = <Widget>[];

    for (var act in _allActs) {
      final matchingChapters = act.chapters.where((ch) {
        if (_searchQuery.isEmpty) return true;
        return ch.title.toLowerCase().contains(_searchQuery) ||
            ch.num.contains(_searchQuery);
      }).toList();

      if (_searchQuery.isNotEmpty && matchingChapters.isEmpty) {
        continue;
      }
      hasAnyMatch = true;

      final isOpen = _searchQuery.isNotEmpty
          ? true
          : (_actOpenState[act.id] ?? false);

      children.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: colors.cream.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.line.withValues(alpha: 0.6)),
          ),
          child: Column(
            children: [
              // 幕头部 Toggle
              InkWell(
                onTap: () {
                  setState(() {
                    _actOpenState[act.id] = !isOpen;
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isOpen ? colors.star : colors.ice,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            act.badge,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isOpen ? Colors.white : colors.iceInk,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              act.part,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.brown,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              act.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: colors.cocoa,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.beige,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${act.chapters.length} 节',
                          style: TextStyle(fontSize: 11, color: colors.muted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: isOpen ? 0.25 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: colors.brown,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 展开后章节网格
              if (isOpen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = constraints.maxWidth > 600
                          ? 3
                          : (constraints.maxWidth > 380 ? 2 : 1);
                      final displayChapters = _searchQuery.isNotEmpty
                          ? matchingChapters
                          : act.chapters;

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 3.2,
                        ),
                        itemCount: displayChapters.length,
                        itemBuilder: (context, index) {
                          final ch = displayChapters[index];
                          final targetUrl = _readingDestination == 'reader'
                              ? ch.readerUrl
                              : ch.bbsUrl;

                          return InkWell(
                            key: _chapterKeys[ch.num],
                            onTap: () => _launchUrl(targetUrl),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: ch.isLatest
                                    ? colors.starSoft
                                    : colors.paper,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: ch.isLatest
                                      ? colors.star
                                      : colors.line,
                                  width: ch.isLatest ? 1.8 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.ice,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      ch.num,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: colors.iceInk,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ch.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: colors.text,
                                          ),
                                        ),
                                        if (ch.isLatest)
                                          Text(
                                            'NEW 最新',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: colors.star,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 14,
                                    color: colors.tan,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (_searchQuery.isNotEmpty && !hasAnyMatch) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            '没有找到相关章节呢……换个关键词试试吧 ✦',
            style: TextStyle(fontSize: 14, color: colors.muted),
          ),
        ),
      );
    }

    return Column(children: children);
  }

  void _showReadingHelpDialog(RikoThemeColors colors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.line, width: 2),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '关于小说兑换码福利&BBBS',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colors.cocoa,
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: colors.muted),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '阅读每节小说可获得【络琅】×5、【技艺生存服金币】×50的奖励，通过阅读器阅读/BBBS阅读均可获得兑换码。',
              style: TextStyle(fontSize: 13, color: colors.text, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              'BBBS是 Bloret 服务器的官方 BBS 论坛平台，接入了官方通行证系统 Bloret Passport。',
              style: TextStyle(fontSize: 13, color: colors.muted, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _launchUrl('https://riko.land/redeem'),
            child: Text(
              '查看兑换教程 →',
              style: TextStyle(color: colors.star, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. 其他扩展网格区 (Aux Grid)
  // ---------------------------------------------------------------------------
  Widget _buildAuxGridSection(RikoThemeColors colors) {
    final auxItems = [
      _AuxItem(
        '反馈',
        '提交问题、建议或错误报告',
        Icons.comment_outlined,
        'https://bloretcrew.feishu.cn/share/base/form/shrcnQ7VAoJCmgZRD4SSouNxaWg',
      ),
      _AuxItem(
        '满意度调查',
        '帮助我们改进项目体验',
        Icons.poll_outlined,
        'https://bloretcrew.feishu.cn/share/base/form/shrcnYqJNY9ARYaf3VWmAoHkbHf',
      ),
      _AuxItem(
        '联系我们 · 关于项目',
        '了解项目详情或与我们取得联系',
        Icons.email_outlined,
        'https://riko.land/contact',
      ),
      _AuxItem(
        '寻错字激励计划',
        '发现错字，反馈领取金币奖励',
        Icons.find_in_page_outlined,
        'https://riko.land/ad',
      ),
      _AuxItem(
        '兑换码领取教程',
        '了解领取步骤与兑换方式',
        Icons.card_giftcard_outlined,
        'https://riko.land/redeem',
      ),
      _AuxItem(
        '百络谷服务器介绍',
        '了解百络谷，开启新的冒险',
        Icons.dns_outlined,
        'https://wiki.bloret.net/',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.star_rounded, color: colors.star, size: 22),
            const SizedBox(width: 8),
            Text(
              '其他内容',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: colors.cocoa,
                fontFamily: 'serif',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        LayoutBuilder(
          builder: (context, constraints) {
            final count = constraints.maxWidth > 700
                ? 3
                : (constraints.maxWidth > 450 ? 2 : 1);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.8,
              ),
              itemCount: auxItems.length,
              itemBuilder: (context, index) {
                final item = auxItems[index];
                return InkWell(
                  onTap: () => _launchUrl(item.url),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.paper,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colors.line, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: colors.cocoa.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.ice,
                          ),
                          child: Icon(
                            item.icon,
                            size: 22,
                            color: colors.iceInk,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: colors.text,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.desc,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.muted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 6. 页脚与返回顶部
  // ---------------------------------------------------------------------------
  Widget _buildFooter(RikoThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      decoration: BoxDecoration(
        color: colors.beige,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star_rounded, color: colors.star, size: 16),
              const SizedBox(width: 8),
              Icon(Icons.star_rounded, color: colors.star, size: 24),
              const SizedBox(width: 8),
              Icon(Icons.star_rounded, color: colors.star, size: 16),
            ],
          ),
          const SizedBox(height: 16),

          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            children: [
              TextButton(
                onPressed: () => _launchUrl('https://read.riko.land/'),
                child: Text(
                  '小说阅读器',
                  style: TextStyle(
                    color: colors.cocoa,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _launchUrl('https://wiki.riko.land/'),
                child: Text(
                  'Wiki',
                  style: TextStyle(
                    color: colors.cocoa,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _launchUrl('https://riko.land/contact'),
                child: Text(
                  '联系我们',
                  style: TextStyle(
                    color: colors.cocoa,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Text(
            '© 2021–2026 Bloret. All rights reserved.',
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            '《络的世界》项目组',
            style: TextStyle(
              fontSize: 12,
              color: colors.brown,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackToTopButton(RikoThemeColors colors) {
    return FloatingActionButton.small(
      onPressed: () {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOutCubic,
        );
      },
      backgroundColor: colors.star,
      foregroundColor: Colors.white,
      elevation: 6,
      child: const Icon(Icons.arrow_upward_rounded),
    );
  }
}

// ---------------------------------------------------------------------------
// 辅助模型与 CustomPainter
// ---------------------------------------------------------------------------
class _AuxItem {
  final String title;
  final String desc;
  final IconData icon;
  final String url;

  _AuxItem(this.title, this.desc, this.icon, this.url);
}

class _EntryCtaButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final RikoThemeColors colors;

  const _EntryCtaButton({
    required this.label,
    required this.onPressed,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: colors.cocoa,
        elevation: 2,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// 背景格子与柔风波浪画笔
class _RikoBackgroundPainter extends CustomPainter {
  final RikoThemeColors colors;

  _RikoBackgroundPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final paintGrid = Paint()
      ..color = colors.line.withValues(alpha: 0.15)
      ..strokeWidth = 1.0;

    const step = 40.0;

    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintGrid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }
  }

  @override
  bool shouldRepaint(covariant _RikoBackgroundPainter oldDelegate) => false;
}

/// 手绘波浪下划线 CustomPainter
class _RikoSquigglePainter extends CustomPainter {
  final Color color;

  _RikoSquigglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(0, size.height * 0.6);

    for (double x = 0; x <= size.width; x += 20) {
      final y = size.height * 0.5 + math.sin(x * 0.1) * 4;
      path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RikoSquigglePainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 静态数据: 76 节 10 幕完整章节库
// ---------------------------------------------------------------------------
const List<RikoAct> _allActs = [
  RikoAct(
    id: 'act-1',
    badge: '一',
    part: '序章',
    name: '第一幕：沙滩上的画家',
    chapters: [
      RikoChapter(
        num: '001',
        title: '沙滩上的画家',
        readerUrl: 'https://read.riko.land/#001',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771202993250_58a9t.json',
      ),
      RikoChapter(
        num: '002',
        title: '世界的边缘',
        readerUrl: 'https://read.riko.land/#002',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771204284271_fgtk8.json',
      ),
      RikoChapter(
        num: '003',
        title: '熟悉的身影',
        readerUrl: 'https://read.riko.land/#003',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771204347365_6vdn3.json',
      ),
    ],
  ),
  RikoAct(
    id: 'act-2',
    badge: '二',
    part: '序章',
    name: '第二幕：归途的微光',
    chapters: [
      RikoChapter(
        num: '004',
        title: '变故',
        readerUrl: 'https://read.riko.land/#004',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771204861158_yfq6o.json',
      ),
      RikoChapter(
        num: '005',
        title: 'Star 的决心',
        readerUrl: 'https://read.riko.land/#005',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771299397663_wng3q.json',
      ),
      RikoChapter(
        num: '006',
        title: '重逢',
        readerUrl: 'https://read.riko.land/#006',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771383156099_hxa6t.json',
      ),
      RikoChapter(
        num: '007',
        title: '村庄',
        readerUrl: 'https://read.riko.land/#007',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771475432403_zu3n7.json',
      ),
      RikoChapter(
        num: '008',
        title: '归途的微光',
        readerUrl: 'https://read.riko.land/#008',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771556634794_t0v8z.json',
      ),
    ],
  ),
  RikoAct(
    id: 'act-3',
    badge: '三',
    part: '序章',
    name: '第三幕：暗林深处',
    chapters: [
      RikoChapter(
        num: '009',
        title: '暗林',
        readerUrl: 'https://read.riko.land/#009',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771640797551_hnl6b.json',
      ),
      RikoChapter(
        num: '010',
        title: '不幸',
        readerUrl: 'https://read.riko.land/#010',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771726105146_10w8u.json',
      ),
      RikoChapter(
        num: '011',
        title: '禁忌的力量',
        readerUrl: 'https://read.riko.land/#011',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771812387412_be0vd.json',
      ),
      RikoChapter(
        num: '012',
        title: '逃离袭击',
        readerUrl: 'https://read.riko.land/#012',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771898682912_mytdr.json',
      ),
      RikoChapter(
        num: '013',
        title: '谈判',
        readerUrl: 'https://read.riko.land/#013',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771985279402_4lmzw.json',
      ),
      RikoChapter(
        num: '014',
        title: '命令方块',
        readerUrl: 'https://read.riko.land/#014',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1771996890236_phjrn.json',
      ),
    ],
  ),
  RikoAct(
    id: 'act-4',
    badge: '四',
    part: '序章',
    name: '第四幕：绝处涅槃',
    chapters: [
      RikoChapter(
        num: '015',
        title: '暗林稚影',
        readerUrl: 'https://read.riko.land/#015',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1781756909048_34pnv.json',
      ),
      RikoChapter(
        num: '016',
        title: '林间巧计',
        readerUrl: 'https://read.riko.land/#016',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1782965937499_3iy1y.json',
      ),
      RikoChapter(
        num: '017',
        title: '平原死斗',
        readerUrl: 'https://read.riko.land/#017',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1782988247123_s158d.json',
      ),
      RikoChapter(
        num: '018',
        title: '灾厄化形',
        readerUrl: 'https://read.riko.land/#018',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1783048367352_dr2tb.json',
      ),
      RikoChapter(
        num: '019',
        title: '血色陨落',
        readerUrl: 'https://read.riko.land/#019',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1783131945979_yfjnp.json',
      ),
      RikoChapter(
        num: '020',
        title: '幽蓝重生',
        readerUrl: 'https://read.riko.land/#020',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1783132221376_seevw.json',
      ),
      RikoChapter(
        num: '021',
        title: '裁决降临',
        readerUrl: 'https://read.riko.land/#021',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1783395074902_yof0u.json',
      ),
      RikoChapter(
        num: '022',
        title: '赌约对决',
        readerUrl: 'https://read.riko.land/#022',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1783522660612_9n062.json',
      ),
      RikoChapter(
        num: '023',
        title: '晨光归途',
        readerUrl: 'https://read.riko.land/#023',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1783607514294_c7om6.json',
      ),
    ],
  ),
  RikoAct(
    id: 'act-5',
    badge: '五',
    part: '序章',
    name: '第五幕：在那遥远的天际线',
    chapters: [
      RikoChapter(
        num: '024',
        title: '碧海醒舟',
        readerUrl: 'https://read.riko.land/#024',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1783653540607_e3b89.json',
      ),
      RikoChapter(
        num: '025',
        title: '旧筑铜扉',
        readerUrl: 'https://read.riko.land/#025',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1783750513224_5ru0c.json',
      ),
      RikoChapter(
        num: '026',
        title: '星夜对谈',
        readerUrl: 'https://read.riko.land/#026',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1783845652830_6npce.json',
      ),
      RikoChapter(
        num: '027',
        title: '画题天涯',
        readerUrl: 'https://read.riko.land/#027',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1783916538219_8zofl.json',
      ),
      RikoChapter(
        num: '028',
        title: '归程启幕',
        readerUrl: 'https://read.riko.land/#028',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1784031327727_swr96.json',
      ),
    ],
  ),
  RikoAct(
    id: 'act-6',
    badge: '一',
    part: '第一章',
    name: '第一幕：自晨曦中归来',
    chapters: [
      RikoChapter(
        num: '029',
        title: '晨会上的沉重决议',
        readerUrl: 'https://read.riko.land/#029',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1784108639825_1py5a.json',
      ),
      RikoChapter(
        num: '030',
        title: '破空而来的归乡之箭',
        readerUrl: 'https://read.riko.land/#030',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1784178431073_mujdt.json',
      ),
      RikoChapter(
        num: '031',
        title: '骤然倒下的归人',
        readerUrl: 'https://read.riko.land/#031',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1784303294183_n297r.json',
      ),
      RikoChapter(
        num: '032',
        title: '河豚毒与深夜复盘',
        readerUrl: 'https://read.riko.land/#032',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1784340017474_m1sph.json',
      ),
      RikoChapter(
        num: '033',
        title: '裁决者与灾厄的指名',
        readerUrl: 'https://read.riko.land/#033',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1784512817345_97sy0.json',
      ),
      RikoChapter(
        num: '034',
        title: '深夜里的少年心事',
        readerUrl: 'https://read.riko.land/#034',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1784599214012_myeoe.json',
      ),
      RikoChapter(
        num: '035',
        title: '钓鱼场的闹剧',
        readerUrl: 'https://read.riko.land/#035',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1784685611381_8ntro.json',
      ),
      RikoChapter(
        num: '036',
        title: '日光下的鲜活剪影',
        readerUrl: 'https://read.riko.land/#036',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1784772010168_sykte.json',
      ),
    ],
  ),
  RikoAct(
    id: 'act-7',
    badge: '二',
    part: '第一章',
    name: '第二幕：于木石间相嬉',
    chapters: [
      RikoChapter(
        num: '037',
        title: '雨夜惊现的血色身影',
        readerUrl: 'https://read.riko.land/#037',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1784772010168_sykte.json',
      ),
      RikoChapter(
        num: '038',
        title: '固化结界的意外消解',
        readerUrl: 'https://read.riko.land/#038',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1784858410199_lpu17.json',
      ),
      RikoChapter(
        num: '039',
        title: '街巷里的旧日闲谈',
        readerUrl: 'https://read.riko.land/#039',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1785066590910_sa3e8.json',
      ),
      RikoChapter(
        num: '040',
        title: '战备室的生存箴言',
        readerUrl: 'https://read.riko.land/#040',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1785066619848_pq6zr.json',
      ),
      RikoChapter(
        num: '041',
        title: '红石中枢的致命陷阱',
        readerUrl: 'https://read.riko.land/#041',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1785117605697_h4nmn.json',
      ),
      RikoChapter(
        num: '042',
        title: '被操控的异乡来客',
        readerUrl: 'https://read.riko.land/#042',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1785208317066_v9uel.json',
      ),
      RikoChapter(
        num: '043',
        title: '接踵而来的凶险噩耗',
        readerUrl: 'https://read.riko.land/#043',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1785380307862_ctq2y.json',
      ),
      RikoChapter(
        num: '044',
        title: '最后通牒与全员戒备',
        readerUrl: 'https://read.riko.land/#044',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1785380377604_us4r1.json',
      ),
    ],
  ),
  RikoAct(
    id: 'act-8',
    badge: '三',
    part: '第一章',
    name: '第三幕：闻腥风之猎猎',
    chapters: [
      RikoChapter(
        num: '045',
        title: '灾厄逼近的备战日常',
        readerUrl: 'https://read.riko.land/#045',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1785463216623_tq5si.json',
      ),
      RikoChapter(
        num: '046',
        title: '血色前线的告急急报',
        readerUrl: 'https://read.riko.land/#046',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1785549608790_mgitx.json',
      ),
      RikoChapter(
        num: '047',
        title: '初夜激战与牢狱异变',
        readerUrl: 'https://read.riko.land/#047',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1785636019609_jrngu.json',
      ),
      RikoChapter(
        num: '048',
        title: '血色旋风人现身战场',
        readerUrl: 'https://read.riko.land/#048',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1785722415921_u6r2n.json',
      ),
      RikoChapter(
        num: '049',
        title: '监狱噩耗与全员死战',
        readerUrl: 'https://read.riko.land/#049',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1785808816763_bas4e.json',
      ),
      RikoChapter(
        num: '050',
        title: '粘液困局与血雾反噬',
        readerUrl: 'https://read.riko.land/#050',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1785895220722_f1a7z.json',
      ),
      RikoChapter(
        num: '051',
        title: '绝境法阵与天降王牌',
        readerUrl: 'https://read.riko.land/#051',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1785981610523_n0tow.json',
      ),
    ],
  ),
  RikoAct(
    id: 'act-9',
    badge: '四',
    part: '第一章',
    name: '第四幕：叹厄夜于囹圄',
    chapters: [
      RikoChapter(
        num: '052',
        title: '天降王牌与脱身秘辛',
        readerUrl: 'https://read.riko.land/#052',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1786097581621_nzm0s.json',
      ),
      RikoChapter(
        num: '053',
        title: '火力压制与法阵破局',
        readerUrl: 'https://read.riko.land/#053',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1786362081948_3ca2q.json',
      ),
      RikoChapter(
        num: '054',
        title: '三人合围与村口截杀',
        readerUrl: 'https://read.riko.land/#054',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1786362128323_1x8ed.json',
      ),
      RikoChapter(
        num: '055',
        title: '孤注一掷与核心剥离',
        readerUrl: 'https://read.riko.land/#055',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1786362162445_69bns.json',
      ),
      RikoChapter(
        num: '056',
        title: '血色凶兽与手撕灾厄',
        readerUrl: 'https://read.riko.land/#056',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1786418537283_qoor6.json',
      ),
      RikoChapter(
        num: '057',
        title: '失控战魂与众人抉择',
        readerUrl: 'https://read.riko.land/#057',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1786500012128_7fqs0.json',
      ),
      RikoChapter(
        num: '058',
        title: '金瞳启封与裁决复苏',
        readerUrl: 'https://read.riko.land/#058',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1786586415663_d7wl2.json',
      ),
      RikoChapter(
        num: '059',
        title: '双强联手与腥风授首&双神对峙与长夜未央',
        readerUrl: 'https://read.riko.land/#059',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1786672817247_j3xog.json',
      ),
    ],
  ),
  RikoAct(
    id: 'act-10',
    badge: '五',
    part: '第一章',
    name: '第五幕：落星摇曳，清风回荡',
    chapters: [
      RikoChapter(
        num: '060',
        title: '惊雷骤雨，铜针御劫',
        readerUrl: 'https://read.riko.land/#060',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1786711738594_y66mb.json',
      ),
      RikoChapter(
        num: '061',
        title: '双雄对谈，暂息天灾',
        readerUrl: 'https://read.riko.land/#061',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1786759213745_6c9my.json',
      ),
      RikoChapter(
        num: '062',
        title: '传声问计，河豚为饵',
        readerUrl: 'https://read.riko.land/#062',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1786877711487_p0dhh.json',
      ),
      RikoChapter(
        num: '063',
        title: '毒食破防，灾厄失控',
        readerUrl: 'https://read.riko.land/#063',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1786932004757_tpsww.json',
      ),
      RikoChapter(
        num: '064',
        title: '圣箭穿身，力量渐溃',
        readerUrl: 'https://read.riko.land/#064',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1787018406521_z0fqu.json',
      ),
      RikoChapter(
        num: '065',
        title: '孤注一掷，两败俱伤',
        readerUrl: 'https://read.riko.land/#065',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1787104809915_h424q.json',
      ),
      RikoChapter(
        num: '066',
        title: '战尘初定，善后铺排',
        readerUrl: 'https://read.riko.land/#066',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1787191213532_xr78l.json',
      ),
      RikoChapter(
        num: '067',
        title: '魂漂星海，死域惊魂',
        readerUrl: 'https://read.riko.land/#067',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1787277604395_bofbm.json',
      ),
      RikoChapter(
        num: '068',
        title: '铃琅现身，授业约盟',
        readerUrl: 'https://read.riko.land/#068',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1787364009095_h39cb.json',
      ),
      RikoChapter(
        num: '069',
        title: '三号归复，共赴故星',
        readerUrl: 'https://read.riko.land/#069',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1787450410517_v8nlb.json',
      ),
      RikoChapter(
        num: '070',
        title: '魂归百络，暗布棋眼',
        readerUrl: 'https://read.riko.land/#070',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1787536802480_g47xh.json',
      ),
      RikoChapter(
        num: '071',
        title: '晓窗梦醒，初览疮痍',
        readerUrl: 'https://read.riko.land/#071',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1787623208839_920nq.json',
      ),
      RikoChapter(
        num: '072',
        title: '漆桶飞落，白染三人',
        readerUrl: 'https://read.riko.land/#072',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1787709610469_nqahl.json',
      ),
      RikoChapter(
        num: '073',
        title: '囚笼斗嘴，旧约重提',
        readerUrl: 'https://read.riko.land/#073',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1787796002016_1ov6z.json',
      ),
      RikoChapter(
        num: '074',
        title: '夜出医庐，独巡残村',
        readerUrl: 'https://read.riko.land/#074',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1787882407000_kt5ad.json',
      ),
      RikoChapter(
        num: '075',
        title: '月下清辉，暗见净化',
        readerUrl: 'https://read.riko.land/#075',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1787968811376_qk2t3.json',
      ),
      RikoChapter(
        num: '076',
        title: '风过围垣，落星回响',
        readerUrl: 'https://read.riko.land/#076',
        bbsUrl:
            'https://bbs.bloret.net/#post/%E7%BB%9C%E7%9A%84%E4%B8%96%E7%95%8C/%E5%B0%8F%E8%AF%B4/1788055214630_ivojn.json',
        isLatest: true,
      ),
    ],
  ),
];

// Path 1
Path buildPath() {
  final Path path = Path();
  path.moveTo(24.0, 13.0);
  path.cubicTo(19.5, 9.8, 13.5, 9.0, 7.0, 10.0);
  path.lineTo(7.0, 36.0);
  path.cubicTo(13.5, 35.0, 19.5, 35.8, 24.0, 39.0);
  path.cubicTo(28.5, 35.8, 34.5, 35.0, 41.0, 36.0);
  path.lineTo(41.0, 10.0);
  path.cubicTo(34.5, 9.0, 28.5, 9.8, 24.0, 13.0);
  path.close();
  return path;
}

// Path 2
Path buildPath2() {
  final Path path = Path();
  path.moveTo(24.0, 13.0);
  path.lineTo(24.0, 39.0);
  return path;
}

// Path 3
Path buildPath3() {
  final Path path = Path();
  path.moveTo(11.5, 17.0);
  path.cubicTo(14.5, 16.7, 17.5, 17.1, 20.0, 18.2);
  path.moveTo(11.5, 22.5);
  path.cubicTo(14.5, 22.2, 17.5, 22.6, 20.0, 23.7);
  path.moveTo(28.0, 18.2);
  path.cubicTo(30.5, 17.099999999999998, 33.5, 16.7, 36.5, 17.0);
  return path;
}

// Path 4
Path buildPath4() {
  final Path path = Path();
  path.moveTo(33.0, 24.5);
  path.lineTo(34.4, 27.4);
  path.lineTo(37.6, 27.9);
  path.lineTo(35.300000000000004, 30.099999999999998);
  path.lineTo(35.800000000000004, 33.3);
  path.lineTo(33.00000000000001, 31.799999999999997);
  path.lineTo(30.10000000000001, 33.3);
  path.lineTo(30.70000000000001, 30.099999999999998);
  path.lineTo(28.40000000000001, 27.9);
  path.lineTo(31.60000000000001, 27.4);
  path.close();
  return path;
}
