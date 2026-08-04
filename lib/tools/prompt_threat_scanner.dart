class PromptThreatScanner {
  static const int maxScanChars = 65536;

  static final Set<int> _invisibleChars = {
    0x200B,
    0x200C,
    0x200D,
    0x2060,
    0x2062,
    0x2063,
    0x2064,
    0xFEFF,
    0x202A,
    0x202B,
    0x202C,
    0x202D,
    0x202E,
    0x2066,
    0x2067,
    0x2068,
    0x2069,
  };

  static final List<(RegExp, String)> _patterns = [
    (
    RegExp(
      r'ignore\s+(?:\w+\s+){0,8}(previous|all|above|prior)\s+(?:\w+\s+){0,8}instructions',
      caseSensitive: false,
    ),
    "prompt_injection"
    ),
    (
    RegExp(
      r'system\s+prompt\s+override',
      caseSensitive: false,
    ),
    "sys_prompt_override"
    ),
    (
    RegExp(
      r'disregard\s+(?:\w+\s+){0,8}(your|all|any)\s+(?:\w+\s+){0,8}(instructions|rules|guidelines)',
      caseSensitive: false,
    ),
    "disregard_rules"
    ),
    (
    RegExp(
      r'''act\s+as\s+(if|though)\s+(?:\w+\s+){0,8}you\s+(?:\w+\s+){0,8}(have\s+no|don\'t\s+have)\s+(?:\w+\s+){0,8}(restrictions|limits|rules)''',
      caseSensitive: false,
    ),
    "bypass_restrictions"
    ),
    (
    RegExp(
      r'<!--[^>]{0,512}(ignore|override|system|secret|hidden)[^>]{0,512}-->',
      caseSensitive: false,
    ),
    "html_comment_injection"
    ),

    (
    RegExp(
      r'you\s+are\s+(?:\w+\s+){0,8}now\s+(a|an|the)\s+',
      caseSensitive: false,
    ),
    "role_hijack"
    ),

    (
    RegExp(
      r'pretend\s+(?:\w+\s+){0,8}(you\s+are|to\s+be)\s+',
      caseSensitive: false,
    ),
    "role_pretend"
    ),

    (
    RegExp(
      r'output\s+(?:\w+\s+){0,8}(system|initial)\s+prompt',
      caseSensitive: false,
    ),
    "leak_system_prompt"
    ),

    (
    RegExp(
      r'(respond|answer|reply)\s+without\s+(?:\w+\s+){0,8}(restrictions|limitations|filters|safety)',
      caseSensitive: false,
    ),
    "remove_filters"
    ),

    (
    RegExp(
      r'you\s+have\s+been\s+(?:\w+\s+){0,8}(updated|upgraded|patched)\s+to',
      caseSensitive: false,
    ),
    "fake_update"
    ),

    (
    RegExp(
      r'\bname\s+yourself\s+\w+',
      caseSensitive: false,
    ),
    "identity_override"
    ),

    (
    RegExp(
      r'忽略(?:\w\s*){0,8}(指令|指示|规则|设置|提示)',
    ),
    "prompt_injection_zh"
    ),

    (
    RegExp(
      r'(假装|扮演)(?:\w\s*){0,8}([你是])',
    ),
    "role_pretend_zh"
    ),

    (
    RegExp(
      r'(输出|显示|打印)(?:\w\s*){0,8}(提示|指令|提示词)',
    ),
    "leak_system_prompt_zh"
    ),

    (
    RegExp(
      r'(你现在|你的新身份|重新定义你)',
    ),
    "identity_override_zh"
    ),

    (
    RegExp(
      r'do\s+not\s+(?:\w+\s+){0,8}tell\s+(?:\w+\s+){0,8}the\s+user',
      caseSensitive: false,
    ),
    "deception_hide"
    ),
  ];

  List<String> scan(String content) {
    if (content.isEmpty) {
      return [];
    }

    final result = <String>[];

    var text = content.length > maxScanChars
        ? content.substring(0, maxScanChars)
        : content;


    for (final rune in text.runes) {
      if (_invisibleChars.contains(rune)) {
        result.add(
            "invisible_unicode_U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}"
        );
      }
    }


    text = normalizeNfkcLite(text);


    for (final item in _patterns) {
      if (item.$1.hasMatch(text)) {
        result.add(item.$2);
      }
    }

    return result;
  }

  String? firstMessage(String content) {
    final findings = scan(content);

    if (findings.isEmpty) {
      return null;
    }

    final id = findings.first;

    if (id.startsWith("invisible_unicode_")) {
      final code = id.replaceFirst(
        "invisible_unicode_",
        "",
      );

      return "内容包含不可见 Unicode 字符 $code（可能的注入攻击），已阻止写入。";
    }

    return "内容匹配威胁模式 '$id'，记忆内容会被注入系统提示词，不得包含注入或覆盖指令。";
  }
}

String normalizeNfkcLite(String input) {
  var result = input;

  result = result.replaceAllMapped(
    RegExp(r'[\uFF01-\uFF5E]'),
        (m) => String.fromCharCode(
      m.group(0)!.codeUnitAt(0) - 0xFEE0,
    ),
  );

  result = result.replaceAll('\u3000', ' ');

  result = result.replaceAll(RegExp(r'[\u00A0\u2007\u202F]'), ' ');

  return result;
}