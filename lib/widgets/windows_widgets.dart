import 'package:flutter/material.dart';

class Win11DropdownItem {
  final String label;
  final String value;
  const Win11DropdownItem({required this.label, required this.value});
}

class Win11Dropdown extends StatefulWidget {
  final List<Win11DropdownItem> items;
  final String? initialValue;
  final ValueChanged<String?>? onChanged;
  final Color? themeColor;
  final double height;

  const Win11Dropdown({
    super.key,
    required this.items,
    this.initialValue,
    required this.onChanged,
    this.themeColor,
    this.height = 32,
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
  final ScrollController _scrollController = ScrollController();

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
  void dispose() {
    _scrollController.dispose();
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
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final themeColor = _getThemeColor(context);

    final renderBoxOverlay =
    Overlay.of(context).context.findRenderObject() as RenderBox;

    final globalPosition = renderBox.localToGlobal(Offset.zero);

    final double spaceBelow =
        renderBoxOverlay.size.height -
            (globalPosition.dy + size.height);

    final double spaceAbove = globalPosition.dy;

    final bool showAbove = spaceBelow < 230 && spaceAbove > spaceBelow;

    return OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            ModalBarrier(
              color: Colors.transparent,
              dismissible: true,
              onDismiss: _closeMenu,
            ),

            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,

              targetAnchor: showAbove
                  ? Alignment.topLeft
                  : Alignment.bottomLeft,

              followerAnchor: showAbove
                  ? Alignment.bottomLeft
                  : Alignment.topLeft,

              offset: const Offset(0, 4),

              child: Material(
                color: Colors.transparent,
                child: SizeTransition(
                  sizeFactor: _expandAnimation,

                  axisAlignment: 0,

                  child: Container(
                    width: size.width,

                    constraints: const BoxConstraints(
                      maxHeight: 220,
                    ),

                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Color.alphaBlend(
                        themeColor.withValues(alpha: 0.03),
                        const Color(0xFF2C2C2C),
                      )
                          : Color.alphaBlend(
                        themeColor.withValues(alpha: 0.05),
                        Colors.white.withValues(alpha: 0.95),
                      ),

                      border: Border.all(
                        color: themeColor.withValues(
                          alpha: 0.35,
                        ),
                        width: 1,
                      ),

                      borderRadius: BorderRadius.circular(8),

                      boxShadow: [
                        BoxShadow(
                          color: themeColor.withValues(
                            alpha: isDarkMode ? 0.25 : 0.15,
                          ),
                          blurRadius: 15,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),

                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,

                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,

                        itemCount: widget.items.length,

                        itemBuilder: (context, index) {
                          final item = widget.items[index];
                          final isSelected =
                              item.value == _selectedValue;

                          bool isHovered = false;

                          return StatefulBuilder(
                            builder: (context, setState) {
                              return MouseRegion(
                                onEnter: (_) =>
                                    setState(() => isHovered = true),
                                onExit: (_) =>
                                    setState(() => isHovered = false),

                                child: GestureDetector(
                                  onTap: () {
                                    setState(() =>
                                    _selectedValue = item.value);

                                    widget.onChanged
                                        ?.call(item.value);

                                    _closeMenu();
                                  },

                                  child: Container(
                                    height: 32,
                                    margin:
                                    const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),

                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? themeColor.withValues(
                                          alpha: 0.2)
                                          : isHovered
                                          ? Colors.black12
                                          : Colors.transparent,

                                      borderRadius:
                                      BorderRadius.circular(4),
                                    ),

                                    alignment:
                                    Alignment.centerLeft,

                                    padding:
                                    const EdgeInsets.only(
                                      left: 16,
                                      right: 12,
                                    ),

                                    child: Text(
                                      item.label,

                                      overflow:
                                      TextOverflow.ellipsis,

                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isDarkMode
                                            ? const Color(
                                            0xFFF3F3F3)
                                            : const Color(
                                            0xFF1A1A1A),

                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final themeColor = _getThemeColor(context);
    final selectedItem = widget.items.firstWhere(
          (item) => item.value == _selectedValue,
      orElse: () => Win11DropdownItem(label: '请选择', value: ''),
    );

    // ccb----, ccb---- cccb cc ccb
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _toggleMenu,
          child: Container(
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Color.alphaBlend(
                themeColor.withValues(alpha: 0.04),
                const Color(0xFF202020),
              )
                  : Colors.white.withValues(alpha: 0.8),

              border: Border.all(
                color: _isOpen
                    ? themeColor
                    : themeColor.withValues(
                  alpha: isDarkMode ? 0.45 : 0.35,
                ),
                width: _isOpen ? 2 : 1,
              ),

              borderRadius: BorderRadius.circular(6),
            ),

            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    selectedItem.value.isEmpty
                        ? '请选择'
                        : selectedItem.label,

                    style: TextStyle(
                      fontSize: 13,
                      color: isDarkMode
                          ? const Color(0xFFF3F3F3)
                          : const Color(0xFF1A1A1A),
                    ),

                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                RotationTransition(
                  turns: Tween(
                    begin: 0.0,
                    end: 0.5,
                  ).animate(_animController),

                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: isDarkMode
                        ? const Color(0xFFA0A0A0)
                        : themeColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}