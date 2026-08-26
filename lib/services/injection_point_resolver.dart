import '../models/mixin_model.dart';
import '../models/bytecode_model.dart';

abstract interface class InjectionPointResolver {
  InjectionPointType get type;

  List<BytecodeInstruction> resolve(
      BytecodeMethod method,
      InjectionPoint point,
      );
}

class HeadInjectionResolver implements InjectionPointResolver {
  @override
  InjectionPointType get type => InjectionPointType.head;

  @override
  List<BytecodeInstruction> resolve(
      BytecodeMethod method,
      InjectionPoint point,
      ) {
    if (method.instructions.isEmpty) {
      return const [];
    }

    return [method.instructions.first];
  }
}

class ReturnInjectionResolver implements InjectionPointResolver {
  @override
  InjectionPointType get type => InjectionPointType.return_;

  @override
  List<BytecodeInstruction> resolve(
      BytecodeMethod method,
      InjectionPoint point,
      ) {
    return method.instructions
        .where((instruction) =>
    instruction.type == BytecodeInstructionType.return_)
        .toList();
  }
}

class TailInjectionResolver implements InjectionPointResolver {
  @override
  InjectionPointType get type => InjectionPointType.tail;

  @override
  List<BytecodeInstruction> resolve(
      BytecodeMethod method,
      InjectionPoint point,
      ) {
    for (var i = method.instructions.length - 1; i >= 0; i--) {
      final instruction = method.instructions[i];

      if (instruction.type == BytecodeInstructionType.return_) {
        return [instruction];
      }
    }

    return const [];
  }
}

class InvokeInjectionResolver implements InjectionPointResolver {
  @override
  InjectionPointType get type => InjectionPointType.invoke;

  @override
  List<BytecodeInstruction> resolve(
      BytecodeMethod method,
      InjectionPoint point,
      ) {
    final target = point.target;

    if (target == null) {
      return const [];
    }

    final matches = <BytecodeInstruction>[];

    for (final instruction in method.instructions) {
      final isInvoke = switch (instruction.type) {
        BytecodeInstructionType.invokeVirtual ||
        BytecodeInstructionType.invokeSpecial ||
        BytecodeInstructionType.invokeStatic ||
        BytecodeInstructionType.invokeInterface ||
        BytecodeInstructionType.invokeDynamic =>
        true,
        _ => false,
      };

      if (!isInvoke) {
        continue;
      }

      if (instruction.owner != target.owner) {
        continue;
      }

      if (instruction.name != target.name) {
        continue;
      }

      if (instruction.descriptor != target.descriptor) {
        continue;
      }

      matches.add(instruction);
    }

    if (point.ordinal >= 0) {
      if (point.ordinal >= matches.length) {
        return const [];
      }

      return [matches[point.ordinal]];
    }

    return matches;
  }
}

class InjectionPointRegistry {
  final Map<InjectionPointType, InjectionPointResolver> _resolvers = {};

  void register(InjectionPointResolver resolver) {
    _resolvers[resolver.type] = resolver;
  }

  InjectionPointResolver? get(InjectionPointType type) {
    return _resolvers[type];
  }

  List<BytecodeInstruction> resolve(
      BytecodeMethod method,
      InjectionPoint point,
      ) {
    final resolver = _resolvers[point.type];

    if (resolver == null) {
      return const [];
    }

    return resolver.resolve(method, point);
  }
}