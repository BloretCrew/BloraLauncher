import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'nbt_editor.dart';

class MinecraftServer {
  final String name;
  final String ip;
  String? motd;
  List<Map<String, dynamic>>? motdParts;
  int? ping;
  String? version;
  int? playersOnline;
  int? playersMax;
  String? iconBase64;
  int? acceptTextures; // 0: prompt, 1: enabled, 2: disabled
  bool? hidden;
  bool isOnline = false;

  MinecraftServer({
    required this.name,
    required this.ip,
    this.iconBase64,
    this.acceptTextures,
    this.hidden,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'ip': ip,
    'icon': ?iconBase64,
    'acceptTextures': ?acceptTextures,
    'hidden': ?hidden,
  };
}

class MinecraftServerService {
  static const int tagEnd = 0;
  static const int tagByte = 1;
  static const int tagShort = 2;
  static const int tagInt = 3;
  static const int tagLong = 4;
  static const int tagFloat = 5;
  static const int tagDouble = 6;
  static const int tagByteArray = 7;
  static const int tagString = 8;
  static const int tagList = 9;
  static const int tagCompound = 10;
  static const int tagIntArray = 11;
  static const int tagLongArray = 12;

  static Future<List<MinecraftServer>> loadFromGame(String versionDir, String versionName) async {
    final file = File(p.join(versionDir, "versions", versionName, "servers.dat"));
    if (!await file.exists()) return [];

    try {
      final bytes = await file.readAsBytes();
      Uint8List data;
      try {
        data = Uint8List.fromList(GZipDecoder().decodeBytes(bytes));
      } catch (_) {
        data = bytes;
      }
      
      final reader = NbtReader(data);
      final root = reader.readRoot();
      if (root == null) return [];
      
      final serversList = root['servers'] as List<dynamic>?;
      if (serversList == null) return [];

      return serversList.map((s) {
        final map = s as Map<String, dynamic>;
        return MinecraftServer(
          name: map['name'] ?? "Unknown Server",
          ip: map['ip'] ?? "127.0.0.1",
          iconBase64: map['icon'],
          acceptTextures: map['acceptTextures'],
          hidden: map['hidden'] == 1 || map['hidden'] == true,
        );
      }).toList();
    } catch (e) {
      debugPrint("Failed to load servers.dat: $e");
      return [];
    }
  }

  static Future<Map<String, dynamic>?> loadLevelDat(String saveDir) async {
    final file = File(p.join(saveDir, "level.dat"));
    if (!await file.exists()) return null;

    try {
      final bytes = await file.readAsBytes();
      final decoded = GZipDecoder().decodeBytes(bytes);
      final reader = NbtReader(Uint8List.fromList(decoded));
      
      final root = reader.readRoot();
      if (root == null) return null;

      if (root.containsKey('Data')) {
        return root['Data'] as Map<String, dynamic>;
      }
      return root;
    } catch (e) {
      debugPrint("Failed to load level.dat: $e");
      return null;
    }
  }

  static Future<bool> isWorldLocked(String saveDir) async {
    final lockFile = File(p.join(saveDir, "session.lock"));
    if (!await lockFile.exists()) return false;
    
    try {
      final raf = await lockFile.open(mode: FileMode.writeOnlyAppend);
      await raf.writeByte(1);
      await raf.close();
      return false; 
    } catch (_) {
      return true;
    }
  }

  static Future<void> saveLevelDat(String saveDir, Map<String, dynamic> data) async {
    final filePath = p.join(saveDir, "level.dat");
    final writer = NbtWriter();
    final bytes = writer.writeRoot("", {'Data': data});
    final compressed = GZipEncoder().encode(bytes);
    await _safeSave(filePath, Uint8List.fromList(compressed));
  }

  static Future<void> saveToGame(String versionDir, String versionName, List<MinecraftServer> servers) async {
    final filePath = p.join(versionDir, "versions", versionName, "servers.dat");
    final List<Map<String, dynamic>> nbtData = servers.map((s) => {
      'name': s.name,
      'ip': s.ip,
      if (s.iconBase64 != null) 'icon': s.iconBase64,
      if (s.acceptTextures != null) 'acceptTextures': s.acceptTextures,
      if (s.hidden != null) 'hidden': s.hidden! ? 1 : 0,
    }).toList();
    
    final writer = NbtWriter();
    final bytes = writer.writeRoot("", {'servers': nbtData});
    await _safeSave(filePath, bytes);
  }

  static Future<void> _safeSave(String filePath, Uint8List data) async {
    final file = File(filePath);
    final randomStr = Random().nextInt(1000000).toString();
    final tempFile = File("${filePath}_$randomStr.dat");
    final oldFile = File("${filePath}_old");

    try {
      await tempFile.writeAsBytes(data);
      if (await file.exists()) {
        if (await oldFile.exists()) await oldFile.delete();
        await file.rename(oldFile.path);
      }
      await tempFile.rename(file.path);
      if (await oldFile.exists()) await oldFile.delete();
    } catch (e) {
      if (await oldFile.exists()) {
        await oldFile.rename(file.path);
      }
      rethrow;
    }
  }

  static Future<void> pingServer(MinecraftServer server, {VoidCallback? onConnected}) async {
    Socket? socket;
    try {
      final String host;
      int port = 25565;
      if (server.ip.contains(':')) {
        final parts = server.ip.split(':');
        host = parts[0];
        port = int.tryParse(parts[1]) ?? 25565;
      } else {
        host = server.ip;
      }

      final stopwatch = Stopwatch()..start();
      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 4));
      server.ping = stopwatch.elapsedMilliseconds;
      onConnected?.call();
      
      final handshakeData = BytesBuilder();
      _writeVarIntToBuilder(handshakeData, 0x00); 
      _writeVarIntToBuilder(handshakeData, 763);  
      _writeStringToBuilder(handshakeData, host);
      handshakeData.addByte(port >> 8);
      handshakeData.addByte(port & 0xFF);
      _writeVarIntToBuilder(handshakeData, 1);    

      _sendPacket(socket, handshakeData.toBytes());

      final statusRequestData = BytesBuilder();
      _writeVarIntToBuilder(statusRequestData, 0x00);
      _sendPacket(socket, statusRequestData.toBytes());

      final completer = Completer<void>();
      List<int> buffer = [];

      socket.listen((data) {
        buffer.addAll(data);
        if (buffer.length < 5) return;

        try {
          final reader = _ByteReader(Uint8List.fromList(buffer));
          final packetLength = reader.readVarInt();
          if (buffer.length < packetLength + reader._offset) return;

          final packetId = reader.readVarInt();
          if (packetId == 0x00) {
            final jsonStr = reader.readString();
            final Map<String, dynamic> status = jsonDecode(jsonStr);
            
            server.isOnline = true;
            server.version = status['version']?['name'];
            server.playersOnline = status['players']?['online'];
            server.playersMax = status['players']?['max'];
            
            final motdData = status['description'];
            server.motdParts = _parseMotdToParts(motdData);
            server.motd = server.motdParts?.map((e) => e['text']).join("");
            server.iconBase64 = status['favicon'];
          }
          socket?.destroy();
          if (!completer.isCompleted) completer.complete();
        } catch (_) {}
      }, onError: (e) {
        socket?.destroy();
        if (!completer.isCompleted) completer.complete();
      }, onDone: () {
        if (!completer.isCompleted) completer.complete();
      });
      
      await completer.future.timeout(const Duration(seconds: 4));
    } catch (_) {
      server.isOnline = false;
      server.ping = null;
    } finally {
      socket?.destroy();
    }
  }

  static List<Map<String, dynamic>> _parseMotdToParts(dynamic data, {Map<String, dynamic>? parentStyle}) {
    List<Map<String, dynamic>> parts = [];
    if (data == null) return parts;
    if (data is String) {
      parts.add({'text': data, 'color': parentStyle?['color'], 'bold': parentStyle?['bold'] ?? false});
      return parts;
    }
    if (data is Map) {
      final String text = data['text'] ?? "";
      final Map<String, dynamic> currentStyle = {
        'color': data['color'] ?? parentStyle?['color'],
        'bold': data['bold'] ?? parentStyle?['bold'] ?? false,
      };
      if (text.isNotEmpty) parts.add({'text': text, ...currentStyle});
      if (data['extra'] != null && data['extra'] is List) {
        for (var extra in data['extra']) {
          parts.addAll(_parseMotdToParts(extra, parentStyle: currentStyle));
        }
      }
    } else if (data is List) {
      for (var e in data) {
        parts.addAll(_parseMotdToParts(e, parentStyle: parentStyle));
      }
    }
    return parts;
  }

  static void _sendPacket(Socket socket, Uint8List packetData) {
    final lengthBuilder = BytesBuilder();
    _writeVarIntToBuilder(lengthBuilder, packetData.length);
    socket.add(lengthBuilder.toBytes());
    socket.add(packetData);
  }

  static void _writeVarIntToBuilder(BytesBuilder builder, int value) {
    while ((value & 0xFFFFFF80) != 0) {
      builder.addByte(value & 0x7F | 0x80);
      value >>= 7;
    }
    builder.addByte(value & 0x7F);
  }

  static void _writeStringToBuilder(BytesBuilder builder, String value) {
    final bytes = utf8.encode(value);
    _writeVarIntToBuilder(builder, bytes.length);
    builder.add(bytes);
  }
}

class _ByteReader {
  final Uint8List data;
  int _offset = 0;
  _ByteReader(this.data);
  int readVarInt() {
    int numRead = 0, result = 0, byte;
    do {
      if (_offset >= data.length) return 0;
      byte = data[_offset++];
      result |= (byte & 0x7F) << (7 * numRead);
      numRead++;
    } while ((byte & 0x80) != 0);
    return result;
  }
  String readString() {
    final length = readVarInt();
    if (_offset + length > data.length) return "";
    final str = utf8.decode(data.sublist(_offset, _offset + length));
    _offset += length;
    return str;
  }
}