import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'dart:ui';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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
  bool isOnline = false;

  MinecraftServer({required this.name, required this.ip});

  Map<String, String> toMap() => {'name': name, 'ip': ip};
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
      
      final reader = _NbtReader(data);
      final root = reader.readRoot();
      if (root == null) return [];
      
      final serversList = root['servers'] as List<dynamic>?;
      if (serversList == null) return [];

      return serversList.map((s) {
        final map = s as Map<String, dynamic>;
        return MinecraftServer(
          name: map['name'] ?? "Unknown Server",
          ip: map['ip'] ?? "127.0.0.1",
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
      final reader = _NbtReader(Uint8List.fromList(decoded));
      
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
    final writer = _NbtWriter();
    final bytes = writer.writeRoot("", {'Data': data});
    final compressed = GZipEncoder().encode(bytes);
    await _safeSave(filePath, Uint8List.fromList(compressed));
  }

  static Future<void> saveToGame(String versionDir, String versionName, List<MinecraftServer> servers) async {
    final filePath = p.join(versionDir, "versions", versionName, "servers.dat");
    final List<Map<String, dynamic>> nbtData = servers.map((s) => {
      'name': s.name,
      'ip': s.ip,
    }).toList();
    
    final writer = _NbtWriter();
    final bytes = writer.writeRoot("", {'servers': nbtData});
    final compressed = GZipEncoder().encode(bytes);
    await _safeSave(filePath, Uint8List.fromList(compressed));
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

class _NbtReader {
  final Uint8List data;
  int offset = 0;
  _NbtReader(this.data);

  Map<String, dynamic>? readRoot() {
    if (offset >= data.length) return null;
    int type = data[offset++];
    if (type != MinecraftServerService.tagCompound) return null;
    readString();
    return _readValue(type) as Map<String, dynamic>;
  }

  dynamic _readValue(int type) {
    final bd = ByteData.sublistView(data, offset);
    switch (type) {
      case MinecraftServerService.tagByte:
        return data[offset++];
      case MinecraftServerService.tagShort:
        int val = bd.getInt16(0, Endian.big);
        offset += 2;
        return val;
      case MinecraftServerService.tagInt:
        int val = bd.getInt32(0, Endian.big);
        offset += 4;
        return val;
      case MinecraftServerService.tagLong:
        int val = bd.getInt64(0, Endian.big);
        offset += 8;
        return val;
      case MinecraftServerService.tagFloat:
        double val = bd.getFloat32(0, Endian.big);
        offset += 4;
        return val;
      case MinecraftServerService.tagDouble:
        double val = bd.getFloat64(0, Endian.big);
        offset += 8;
        return val;
      case MinecraftServerService.tagByteArray:
        int len = bd.getInt32(0, Endian.big);
        offset += 4;
        final arr = data.sublist(offset, offset + len);
        offset += len;
        return arr;
      case MinecraftServerService.tagString:
        return readString();
      case MinecraftServerService.tagList:
        int innerType = data[offset++];
        int length = ByteData.sublistView(data, offset).getInt32(0, Endian.big);
        offset += 4;
        final list = [];
        for (int i = 0; i < length; i++) {
          list.add(_readValue(innerType));
        }
        return list;
      case MinecraftServerService.tagCompound:
        final map = <String, dynamic>{};
        while (true) {
          if (offset >= data.length) break;
          int innerType = data[offset++];
          if (innerType == MinecraftServerService.tagEnd) break;
          String name = readString();
          map[name] = _readValue(innerType);
        }
        return map;
      case MinecraftServerService.tagIntArray:
        int len = bd.getInt32(0, Endian.big);
        offset += 4;
        final list = <int>[];
        for (int i = 0; i < len; i++) {
          list.add(ByteData.sublistView(data, offset).getInt32(0, Endian.big));
          offset += 4;
        }
        return list;
      case MinecraftServerService.tagLongArray:
        int len = bd.getInt32(0, Endian.big);
        offset += 4;
        final list = <int>[];
        for (int i = 0; i < len; i++) {
          list.add(ByteData.sublistView(data, offset).getInt64(0, Endian.big));
          offset += 8;
        }
        return list;
      default:
        return null;
    }
  }

  String readString() {
    if (offset + 2 > data.length) return "";
    int len = data.buffer.asByteData().getUint16(offset, Endian.big);
    offset += 2;
    if (offset + len > data.length) return "";
    String s = utf8.decode(data.sublist(offset, offset + len));
    offset += len;
    return s;
  }
}

class _NbtWriter {
  final BytesBuilder bb = BytesBuilder();

  Uint8List writeRoot(String name, Map<String, dynamic> data) {
    bb.addByte(MinecraftServerService.tagCompound);
    _writeString(name); 
    _writeCompound(data);
    return bb.toBytes();
  }

  void _writeCompound(Map<String, dynamic> map) {
    map.forEach((key, value) {
      int type = _guessType(value);
      bb.addByte(type);
      _writeString(key);
      _writeValue(type, value);
    });
    bb.addByte(MinecraftServerService.tagEnd);
  }

  int _guessType(dynamic v) {
    if (v is bool) return MinecraftServerService.tagByte;
    if (v is int) {
      if (v >= -128 && v <= 127) return MinecraftServerService.tagByte;
      if (v >= -32768 && v <= 32767) return MinecraftServerService.tagShort;
      if (v >= -2147483648 && v <= 2147483647) return MinecraftServerService.tagInt;
      return MinecraftServerService.tagLong;
    }
    if (v is double) return MinecraftServerService.tagDouble;
    if (v is String) return MinecraftServerService.tagString;
    if (v is List) return MinecraftServerService.tagList;
    if (v is Map) return MinecraftServerService.tagCompound;
    if (v is Uint8List) return MinecraftServerService.tagByteArray;
    return MinecraftServerService.tagEnd;
  }

  void _writeValue(int type, dynamic v) {
    final bd = ByteData(8);
    switch (type) {
      case MinecraftServerService.tagByte:
        if (v is bool) {
          bb.addByte(v ? 1 : 0);
        } else {
          bb.addByte(v as int);
        }
        break;
      case MinecraftServerService.tagShort:
        bd.setInt16(0, v as int, Endian.big);
        bb.add(bd.buffer.asUint8List(0, 2));
        break;
      case MinecraftServerService.tagInt:
        bd.setInt32(0, v as int, Endian.big);
        bb.add(bd.buffer.asUint8List(0, 4));
        break;
      case MinecraftServerService.tagLong:
        bd.setInt64(0, v as int, Endian.big);
        bb.add(bd.buffer.asUint8List(0, 8));
        break;
      case MinecraftServerService.tagFloat:
        bd.setFloat32(0, v as double, Endian.big);
        bb.add(bd.buffer.asUint8List(0, 4));
        break;
      case MinecraftServerService.tagDouble:
        bd.setFloat64(0, v as double, Endian.big);
        bb.add(bd.buffer.asUint8List(0, 8));
        break;
      case MinecraftServerService.tagString:
        _writeString(v as String);
        break;
      case MinecraftServerService.tagList:
        final list = v as List;
        int innerType = list.isEmpty ? MinecraftServerService.tagEnd : _guessType(list.first);
        bb.addByte(innerType);
        bd.setInt32(0, list.length, Endian.big);
        bb.add(bd.buffer.asUint8List(0, 4));
        for (var item in list) {
          _writeValue(innerType, item);
        }
        break;
      case MinecraftServerService.tagCompound:
        _writeCompound(v as Map<String, dynamic>);
        break;
      case MinecraftServerService.tagByteArray:
        final arr = v as Uint8List;
        bd.setInt32(0, arr.length, Endian.big);
        bb.add(bd.buffer.asUint8List(0, 4));
        bb.add(arr);
        break;
    }
  }

  void _writeString(String s) {
    final bytes = utf8.encode(s);
    final bd = ByteData(2)..setUint16(0, bytes.length, Endian.big);
    bb.add(bd.buffer.asUint8List());
    bb.add(bytes);
  }
}
