import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class UUIDUtils {
  /// Generates a Minecraft-style Offline UUID (Version 3 MD5) from a username.
  static String generateOfflineUUID(String username) {
    final List<int> bytes = utf8.encode("OfflinePlayer:$username");
    final List<int> hash = md5.convert(bytes).bytes;

    // Set version to 3 (clear bits 4-7 of byte 6, then set to 3)
    // In Dart, byte 6 is index 6.
    hash[6] = (hash[6] & 0x0f) | 0x30;
    // Set variant to RFC 4122 (clear bits 6-7 of byte 8, then set to 2/0x80)
    hash[8] = (hash[8] & 0x3f) | 0x80;

    return formatHyphenated(hash);
  }

  /// Formats bytes as Hyphenated hexadecimal (8-4-4-4-12)
  static String formatHyphenated(List<int> bytes) {
    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length; i++) {
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
      if (i == 3 || i == 5 || i == 7 || i == 9) {
        buffer.write('-');
      }
    }
    return buffer.toString();
  }

  /// Formats bytes as Hexadecimal (no hyphens)
  static String formatHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Returns High/Low (Most/Least Significant Bits) as a Map
  static Map<String, int> toMostLeastBits(List<int> bytes) {
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return {
      'most': data.getInt64(0),
      'least': data.getInt64(8),
    };
  }

  /// Returns Int Array (4 x 32-bit integers)
  static List<int> toIntArray(List<int> bytes) {
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return [
      data.getInt32(0),
      data.getInt32(4),
      data.getInt32(8),
      data.getInt32(12),
    ];
  }

  /// Parses a hyphenated or plain hex UUID string into bytes.
  static List<int>? parseUUID(String uuid) {
    final clean = uuid.replaceAll('-', '');
    if (clean.length != 32) return null;
    final List<int> bytes = [];
    for (int i = 0; i < 32; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }
}
