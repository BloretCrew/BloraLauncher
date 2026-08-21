import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:archive/archive_io.dart';
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
  static const int tagString = 8;
  static const int tagList = 9;
  static const int tagCompound = 10;

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
      final tag = reader.readTag();
      if (tag == null || tag is! Map) return [];
      
      final root = tag as Map<String, dynamic>;
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
      stderr.writeln("Failed to load servers.dat: $e");
      return [];
    }
  }

  static Future<void> saveToGame(String versionDir, String versionName, List<MinecraftServer> servers) async {
    final filePath = p.join(versionDir, "versions", versionName, "servers.dat");
    final file = File(filePath);
    final parentDir = file.parent;
    if (!await parentDir.exists()) await parentDir.create(recursive: true);

    final writer = _NbtWriter();
    final List<Map<String, dynamic>> nbtData = servers.map((s) => {
      'name': s.name,
      'ip': s.ip,
    }).toList();
    
    final bytes = writer.writeRoot({'servers': nbtData});
    final compressed = GZipEncoder().encode(bytes);

    final randomStr = Random().nextInt(1000000).toString();
    final tempFile = File("${filePath}_$randomStr.dat");
    final oldFile = File("${filePath}_old");

    try {
      await tempFile.writeAsBytes(compressed);
      
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

  static Future<void> pingServer(MinecraftServer server) async {
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

  dynamic readTag() {
    int type = data[offset++];
    if (type == MinecraftServerService.tagEnd) return null;
    readString();
    return _readValue(type);
  }

  dynamic _readValue(int type) {
    switch (type) {
      case MinecraftServerService.tagCompound:
        final map = <String, dynamic>{};
        while (true) {
          int innerType = data[offset++];
          if (innerType == MinecraftServerService.tagEnd) break;
          String name = readString();
          map[name] = _readValue(innerType);
        }
        return map;
      case MinecraftServerService.tagList:
        if (offset + 5 > data.length) return [];
        int innerType = data[offset++];
        int length = data.buffer.asByteData().getInt32(offset, Endian.big);
        offset += 4;
        final list = [];
        for (int i = 0; i < length; i++) {
          list.add(_readValue(innerType));
        }
        return list;
      case MinecraftServerService.tagString:
        return readString();
      case MinecraftServerService.tagByte:
        return data[offset++];
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

  Uint8List writeRoot(Map<String, dynamic> data) {
    bb.addByte(MinecraftServerService.tagCompound);
    _writeString(""); 
    _writeCompound(data);
    return bb.toBytes();
  }

  void _writeCompound(Map<String, dynamic> map) {
    map.forEach((key, value) {
      if (value is List) {
        bb.addByte(MinecraftServerService.tagList);
        _writeString(key);
        bb.addByte(MinecraftServerService.tagCompound);
        final lenData = ByteData(4)..setInt32(0, value.length, Endian.big);
        bb.add(lenData.buffer.asUint8List());
        for (var item in value) {
          _writeCompound(item as Map<String, dynamic>);
        }
      } else if (value is String) {
        bb.addByte(MinecraftServerService.tagString);
        _writeString(key);
        _writeString(value);
      }
    });
    bb.addByte(MinecraftServerService.tagEnd);
  }

  void _writeString(String s) {
    final bytes = utf8.encode(s);
    final lenData = ByteData(2)..setUint16(0, bytes.length, Endian.big);
    bb.add(lenData.buffer.asUint8List());
    bb.add(bytes);
  }
}
