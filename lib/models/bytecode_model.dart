enum BytecodeInstructionType {
  invokeVirtual,
  invokeSpecial,
  invokeStatic,
  invokeInterface,
  invokeDynamic,

  getField,
  putField,
  getStatic,
  putStatic,

  newObject,

  return_,
  jump,
  constant,

  other,
}

class BytecodeInstruction {
  final int index;
  final BytecodeInstructionType type;

  /// INVOKE / FIELD / NEW 的 owner。
  final String? owner;

  /// 方法名或字段名。
  final String? name;

  /// 方法 descriptor / 字段 descriptor。
  final String? descriptor;

  /// 原始 opcode。
  final int? opcode;

  const BytecodeInstruction({
    required this.index,
    required this.type,
    this.owner,
    this.name,
    this.descriptor,
    this.opcode,
  });
}

class BytecodeMethod {
  final String name;
  final String descriptor;
  final List<BytecodeInstruction> instructions;

  const BytecodeMethod({
    required this.name,
    required this.descriptor,
    this.instructions = const [],
  });
}

class BytecodeClass {
  final String name;
  final List<BytecodeMethod> methods;

  const BytecodeClass({
    required this.name,
    this.methods = const [],
  });

  BytecodeMethod? findMethod(String name, String descriptor) {
    for (final method in methods) {
      if (method.name == name && method.descriptor == descriptor) {
        return method;
      }
    }

    return null;
  }
}