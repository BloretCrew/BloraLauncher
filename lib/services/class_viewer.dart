import 'dart:typed_data' show Uint8List;

class ClassViewer {
  final Uint8List data;
  int offset = 0;

  ClassViewer(this.data);

  int readU1() {
    return data[offset++];
  }

  int readU2() {
    final value = (data[offset] << 8) | data[offset + 1];
    offset += 2;
    return value;
  }

  int readU4() {
    final value = (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

    offset += 4;
    return value;
  }

  String readUtf8(int length) {
    final bytes = data.sublist(offset, offset + length);
    offset += length;

    return String.fromCharCodes(bytes);
  }

  String parse() {
    final magic = readU4();

    if (magic != 0xCAFEBABE) {
      throw const FormatException('Not a Java class file');
    }

    final minor = readU2();
    final major = readU2();

    final constantPoolCount = readU2();

    final constants = List<Object?>.filled(
      constantPoolCount,
      null,
    );

    var i = 1;

    while (i < constantPoolCount) {
      final tag = readU1();

      switch (tag) {
        case 1: // CONSTANT_Utf8
          final length = readU2();
          constants[i] = readUtf8(length);
          break;

        case 3: // Integer
        case 4: // Float
          readU4();
          break;

        case 5: // Long
        case 6: // Double
          readU4();
          readU4();
          i++;
          break;

        case 7: // Class
          constants[i] = ClassRef(readU2());
          break;

        case 8: // String
          constants[i] = StringRef(readU2());
          break;

        case 9: // Fieldref
        case 10: // Methodref
        case 11: // InterfaceMethodref
          constants[i] = MemberRef(
            readU2(),
            readU2(),
          );
          break;

        case 12: // NameAndType
          constants[i] = NameAndType(
            readU2(),
            readU2(),
          );
          break;

        case 15: // MethodHandle
          readU1();
          readU2();
          break;

        case 16: // MethodType
          readU2();
          break;

        case 17: // Dynamic
        case 18: // InvokeDynamic
          readU2();
          readU2();
          break;

        case 19: // Module
        case 20: // Package
          readU2();
          break;

        default:
          throw FormatException(
            'Unknown Constant Pool tag: $tag (index=$i)',
          );
      }

      i++;
    }

    final _ = readU2();
    final thisClass = readU2();
    final superClass = readU2();

    final result = StringBuffer();

    result.writeln('Class Version: $major.$minor');
    result.writeln('Constant Pool: $constantPoolCount');
    result.writeln();

    result.writeln('=== Class ===');

    final classRef = constants[thisClass];

    if (classRef is ClassRef) {
      result.writeln(
        'this = ${_resolveUtf8(constants, classRef.nameIndex)}',
      );
    }

    final superRef = constants[superClass];

    if (superRef is ClassRef) {
      result.writeln(
        'super = ${_resolveUtf8(constants, superRef.nameIndex)}',
      );
    }

    result.writeln();
    result.writeln('=== Constants ===');

    for (var index = 1; index < constants.length; index++) {
      final value = constants[index];

      if (value == null) continue;

      result.writeln(
        '#$index ${_formatConstant(constants, value)}',
      );
    }

    return result.toString();
  }

  String _resolveUtf8(
      List<Object?> constants,
      int index,
      ) {
    final value = constants[index];

    if (value is String) {
      return value;
    }

    return '#$index';
  }

  String _formatConstant(
      List<Object?> constants,
      Object value,
      ) {
    if (value is String) {
      return 'Utf8 "$value"';
    }

    if (value is ClassRef) {
      return 'Class #${value.nameIndex} '
          '(${_resolveUtf8(constants, value.nameIndex)})';
    }

    if (value is StringRef) {
      return 'String #${value.stringIndex}';
    }

    if (value is MemberRef) {
      return 'MemberRef '
          '#${value.classIndex}.'
          '#${value.nameAndTypeIndex}';
    }

    if (value is NameAndType) {
      return 'NameAndType '
          '#${value.nameIndex}:'
          '#${value.descriptorIndex}';
    }

    return value.toString();
  }
}

class ClassRef {
  final int nameIndex;

  ClassRef(this.nameIndex);
}

class StringRef {
  final int stringIndex;

  StringRef(this.stringIndex);
}

class MemberRef {
  final int classIndex;
  final int nameAndTypeIndex;

  MemberRef(
      this.classIndex,
      this.nameAndTypeIndex,
      );
}

class NameAndType {
  final int nameIndex;
  final int descriptorIndex;

  NameAndType(
      this.nameIndex,
      this.descriptorIndex,
      );
}