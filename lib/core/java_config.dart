class JavaConfig {
  static const Map<String, Map<String, Map<String, String>>> versions = {
    "25": {"Windows": {"x64": "https://cdn.azul.com/zulu/bin/zulu25.30.17-ca-jdk25.0.1-win_x64.msi"}},
    "24": {"Windows": {"x64": "https://cdn.azul.com/zulu/bin/zulu24.32.13-ca-jdk24.0.2-win_x64.msi"}},
    "21": {"Windows": {"x64": "https://cdn.azul.com/zulu/bin/zulu21.44.17-ca-jdk21.0.8-win_x64.msi"}},
    "17": {"Windows": {"x64": "https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-win_x64.msi"}},
    "11": {"Windows": {"x64": "https://cdn.azul.com/zulu/bin/zulu11.82.19-ca-jdk11.0.28-win_x64.msi"}},
    "8": {"Windows": {"x64": "https://cdn.azul.com/zulu/bin/zulu8.88.0.19-ca-jdk8.0.462-win_x64.msi"}},
  };

  static List<String> get versionList => versions.keys.toList()..sort((a, b) => int.parse(b).compareTo(int.parse(a)));
}
