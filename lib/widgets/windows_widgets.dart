import 'dart:async';
import 'package:bloret_launcher/core/i18n.dart';
import 'package:flutter/material.dart';

class Win11DropdownItem {
  final String label;
  final String value;
  final IconData? icon;
  final List<Win11DropdownItem>? children;
  const Win11DropdownItem({
    required this.label,
    required this.value,
    this.icon,
    this.children,
  });
}

class Win11Dropdown extends StatefulWidget {
  final List<Win11DropdownItem> items;
  final String? initialValue;
  final ValueChanged<String?>? onChanged;
  final Color? themeColor;
  final double height;
  final double? width;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final BoxDecoration? decoration;
  final BoxDecoration? overlayDecoration;
  final TextStyle? textStyle;
  final TextStyle? overlayTextStyle;
  final Widget? dropdownIcon;

  const Win11Dropdown({
    super.key,
    required this.items,
    this.initialValue,
    required this.onChanged,
    this.themeColor,
    this.height = 32,
    this.width,
    this.padding,
    this.borderRadius,
    this.decoration,
    this.overlayDecoration,
    this.textStyle,
    this.overlayTextStyle,
    this.dropdownIcon,
  });

  @override
  State<Win11Dropdown> createState() => _Win11DropdownState();
}

class _Win11DropdownState extends State<Win11Dropdown> with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  String? _selectedValue;
  late AnimationController _animController;
  late Animation<double> _expandAnimation;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.initialValue;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(Win11Dropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      _selectedValue = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (_isOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
    _animController.forward();
  }

  void _closeMenu() {
    if (!_isOpen) return;
    _animController.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      if (mounted) setState(() => _isOpen = false);
    });
  }

  Color _getThemeColor(BuildContext context) {
    return widget.themeColor ?? Theme.of(context).primaryColor;
  }

  OverlayEntry _createOverlayEntry() {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final RenderBox overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox;
    final globalPosition = renderBox.localToGlobal(Offset.zero);

    final double spaceBelow = overlayBox.size.height - (globalPosition.dy + size.height);
    final double spaceAbove = globalPosition.dy;
    final bool showAbove = spaceBelow < 280 && spaceAbove > spaceBelow;

    // 水平空间检查：如果右侧空间不足 240px，则菜单向左展开（右对齐）
    final double spaceRight = overlayBox.size.width - globalPosition.dx;
    final bool alignRight = spaceRight < 240;

    return OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            GestureDetector(
              onTap: _closeMenu,
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: showAbove 
                  ? (alignRight ? Alignment.topRight : Alignment.topLeft)
                  : (alignRight ? Alignment.bottomRight : Alignment.bottomLeft),
              followerAnchor: showAbove 
                  ? (alignRight ? Alignment.bottomRight : Alignment.bottomLeft)
                  : (alignRight ? Alignment.topRight : Alignment.topLeft),
              offset: Offset(0, showAbove ? -1 : 1), // 减小偏移使边框更好衔接
              child: Material(
                color: Colors.transparent,
                child: IntrinsicWidth(
                  child: SizeTransition(
                    sizeFactor: _expandAnimation,
                    alignment: showAbove ? Alignment.bottomCenter : Alignment.topCenter,
                    child: _Win11MenuContent(
                      items: widget.items,
                      width: widget.width ?? size.width, // 确保菜单宽度与基底一致
                      selectedValue: _selectedValue,
                      themeColor: _getThemeColor(context),
                      onChanged: (val) {
                        setState(() => _selectedValue = val);
                        widget.onChanged?.call(val);
                        _closeMenu();
                      },
                      decoration: widget.overlayDecoration,
                      textStyle: widget.overlayTextStyle,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final themeColor = _getThemeColor(context);
    
    Win11DropdownItem? findSelected(List<Win11DropdownItem> items) {
      for (var item in items) {
        if (item.value == _selectedValue) return item;
        if (item.children != null) {
          var found = findSelected(item.children!);
          if (found != null) return found;
        }
      }
      return null;
    }

    final selectedItem = findSelected(widget.items);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _toggleMenu,
        child: CompositedTransformTarget(
          link: _layerLink,
          child: Container(
            height: widget.height,
            width: widget.width,
            padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 12),
            decoration: widget.decoration ?? BoxDecoration(
              color: isDarkMode
                  ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.95),
              border: Border.all(
                color: _isOpen 
                    ? themeColor 
                    : (isDarkMode ? Colors.white.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.25)),
                width: _isOpen ? 1.5 : 1.0,
              ),
              borderRadius: widget.borderRadius ?? BorderRadius.circular(6),
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      selectedItem?.label ?? 'Choose one'.tl,
                      style: widget.textStyle ?? TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDarkMode ? const Color(0xFFF3F3F3) : const Color(0xFF1A1A1A),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  RotationTransition(
                    turns: Tween(begin: 0.0, end: 0.5).animate(_animController),
                    child: widget.dropdownIcon ?? Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: isDarkMode ? Colors.white70 : themeColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Win11MenuContent extends StatelessWidget {
  final List<Win11DropdownItem> items;
  final double? width;
  final String? selectedValue;
  final Color themeColor;
  final ValueChanged<String?> onChanged;
  final BoxDecoration? decoration;
  final TextStyle? textStyle;

  const _Win11MenuContent({
    required this.items,
    this.width,
    this.selectedValue,
    required this.themeColor,
    required this.onChanged,
    this.decoration,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return Container(
      width: width,
      constraints: const BoxConstraints(maxHeight: 300, minWidth: 120),
      decoration: decoration ?? BoxDecoration(
        color: isDarkMode 
            ? Color.alphaBlend(themeColor.withValues(alpha: 0.05), theme.colorScheme.surfaceContainer)
            : Color.alphaBlend(themeColor.withValues(alpha: 0.03), Colors.white),
        border: Border.all(
          color: themeColor, // 颜色与基底完全一致
          width: 1.5,        // 宽度与基底完全一致
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.6 : 0.15),
            blurRadius: 30,  // 增加模糊半径使阴影更柔和
            spreadRadius: -2, // 负扩张使阴影更聚拢在下方，避免边缘过硬
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6.5), // 8 - 1.5 = 6.5，确保内圆角完美贴合边框
        child: Material(
          color: Colors.transparent,
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: items.map((item) {
                  if (item.children != null && item.children!.isNotEmpty) {
                    return _Win11SubmenuItem(
                      item: item,
                      themeColor: themeColor,
                      selectedValue: selectedValue,
                      onChanged: onChanged,
                      textStyle: textStyle,
                    );
                  }
                  return _Win11MenuItem(
                    item: item,
                    isSelected: item.value == selectedValue,
                    themeColor: themeColor,
                    onTap: () => onChanged(item.value),
                    textStyle: textStyle,
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Win11MenuItem extends StatefulWidget {
  final Win11DropdownItem item;
  final bool isSelected;
  final Color themeColor;
  final VoidCallback onTap;
  final TextStyle? textStyle;

  const _Win11MenuItem({
    required this.item,
    required this.isSelected,
    required this.themeColor,
    required this.onTap,
    this.textStyle,
  });

  @override
  State<_Win11MenuItem> createState() => _Win11MenuItemState();
}

class _Win11MenuItemState extends State<_Win11MenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.themeColor.withValues(alpha: isDarkMode ? 0.28 : 0.15)
                : _isHovered 
                    ? (isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)) 
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (widget.item.icon != null) ...[
                Icon(widget.item.icon, size: 16, color: isDarkMode ? Colors.white70 : Colors.black54),
                const SizedBox(width: 8),
              ] else if (widget.isSelected) ...[
                Icon(
                  Icons.check, 
                  size: 16, 
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.9) : widget.themeColor,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  widget.item.label,
                  style: widget.textStyle ?? TextStyle(
                    fontSize: 13,
                    color: isDarkMode ? const Color(0xFFF3F3F3) : const Color(0xFF1A1A1A),
                    fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Win11SubmenuItem extends StatefulWidget {
  final Win11DropdownItem item;
  final Color themeColor;
  final String? selectedValue;
  final ValueChanged<String?> onChanged;
  final TextStyle? textStyle;

  const _Win11SubmenuItem({
    required this.item,
    required this.themeColor,
    this.selectedValue,
    required this.onChanged,
    this.textStyle,
  });

  @override
  State<_Win11SubmenuItem> createState() => _Win11SubmenuItemState();
}

class _Win11SubmenuItemState extends State<_Win11SubmenuItem> with SingleTickerProviderStateMixin {
  OverlayEntry? _submenuEntry;
  bool _isHovered = false;
  bool _isMouseInSubmenu = false;
  final LayerLink _submenuLink = LayerLink();
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
  }

  void _showSubmenu() {
    _closeTimer?.cancel();
    if (_submenuEntry != null) {
      _animController.forward();
      return;
    }
    
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final RenderBox overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox;
    final globalPosition = renderBox.localToGlobal(Offset.zero);

    // 检查右侧是否有足够空间容纳约 180px 宽的子菜单
    final bool canShowRight = globalPosition.dx + size.width + 180 < overlayBox.size.width - 20;

    _submenuEntry = OverlayEntry(
      builder: (context) {
        return Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _submenuLink,
            showWhenUnlinked: false,
            targetAnchor: canShowRight ? Alignment.topRight : Alignment.topLeft,
            followerAnchor: canShowRight ? Alignment.topLeft : Alignment.topRight,
            offset: Offset(canShowRight ? 4 : -4, -4),
            child: MouseRegion(
              onEnter: (_) {
                if (mounted) setState(() => _isMouseInSubmenu = true);
                _closeTimer?.cancel();
              },
              onExit: (_) {
                if (mounted) setState(() => _isMouseInSubmenu = false);
                _handleMouseExit();
              },
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Material(
                  color: Colors.transparent,
                  child: IntrinsicWidth(
                    child: _Win11MenuContent(
                      items: widget.item.children!,
                      selectedValue: widget.selectedValue,
                      themeColor: widget.themeColor,
                      onChanged: (val) {
                        widget.onChanged(val);
                        _hideSubmenu();
                      },
                      textStyle: widget.textStyle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_submenuEntry!);
    _animController.forward();
  }

  void _handleMouseExit() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted && !_isHovered && !_isMouseInSubmenu) {
        _hideSubmenu();
      }
    });
  }

  void _hideSubmenu() {
    if (_submenuEntry == null) return;
    _animController.reverse().then((_) {
      if (mounted && _submenuEntry != null) {
        _submenuEntry?.remove();
        _submenuEntry = null;
      }
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _animController.dispose();
    _submenuEntry?.remove();
    _submenuEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return CompositedTransformTarget(
      link: _submenuLink,
      child: GestureDetector(
        onTap: () {
          if (_submenuEntry == null) {
            _showSubmenu();
          } else {
            _hideSubmenu();
          }
        },
        child: MouseRegion(
          onEnter: (_) {
            setState(() => _isHovered = true);
            _showSubmenu();
          },
          onExit: (event) {
            setState(() => _isHovered = false);
            _handleMouseExit();
          },
          child: Container(
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: _isHovered || _isMouseInSubmenu
                  ? (isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (widget.item.icon != null) ...[
                  Icon(widget.item.icon, size: 16, color: isDarkMode ? Colors.white70 : Colors.black54),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: widget.textStyle ?? TextStyle(
                      fontSize: 13,
                      color: isDarkMode ? const Color(0xFFF3F3F3) : const Color(0xFF1A1A1A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.keyboard_arrow_right, size: 16, color: isDarkMode ? Colors.white38 : Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
