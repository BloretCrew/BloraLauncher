import 'dart:convert';
import 'dart:typed_data';

import 'minecraft_server_service.dart';

class NbtReader {
  final Uint8List data;
  int offset = 0;
  NbtReader(this.data);

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

class NbtWriter {
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
    if (v is int) {
      if (v >= -128 && v <= 127) return MinecraftServerService.tagByte;
      if (v >= -32768 && v <= 32767) return MinecraftServerService.tagShort;
      if (v >= -2147483648 && v <= 2147483647) {
        return MinecraftServerService.tagInt;
      }
      return MinecraftServerService.tagLong;
    }

    return switch (v) {
      bool() => MinecraftServerService.tagByte,
      double() => MinecraftServerService.tagDouble,
      String() => MinecraftServerService.tagString,
      Uint8List() => MinecraftServerService.tagByteArray,
      List<int>() => MinecraftServerService.tagLongArray,
      List() => MinecraftServerService.tagList,
      Map() => MinecraftServerService.tagCompound,
      _ => MinecraftServerService.tagEnd,
    };
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