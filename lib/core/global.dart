import 'package:bloret_launcher/services/bloriko.dart';

import 'i18n.dart';

String serverIP = "123.129.241.101";

String get agentName => switch (Bloriko.type) {
  "bloriko" => "Bloriko".tl,
  "bloriko_r18" => "Bloriko(R18)".tl,
  _ => "Blora Agent".tl,
};

class TranslationStore {
  static bool showTranslated = false;
  static List<String>? translatedTips;
  static String? translatedServerBestTime;
  static String? translatedServerText;
  static int? lastTipsHash;
  static String? lastLang;

  static void resetCache() {
    translatedTips = null;
    translatedServerBestTime = null;
    translatedServerText = null;
    lastTipsHash = null;
    lastLang = null;
  }
}
