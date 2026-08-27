enum MixinInjectionType {
  inject,
  redirect,
  modifyArg,
  modifyArgs,
  modifyVariable,
  modifyConstant,
  overwrite,
  unknown,
}

enum InjectionPointType {
  head,
  tail,
  return_,
  invoke,
  invokeString,
  invokeAssign,
  field,
  new_,
  constant,
  jump,
  constructorHead,
  loadLocal,
  storeLocal,
  unknown,
}

enum AtShift {
  none,
  before,
  after,
  by,
}

class MixinTarget {
  final String owner;
  final String name;
  final String descriptor;

  const MixinTarget({
    required this.owner,
    required this.name,
    required this.descriptor,
  });

  @override
  String toString() => '$owner.$name$descriptor';
}

class InjectionPoint {
  final InjectionPointType type;

  /// @At(target = ...)
  final MixinTarget? target;

  /// @At(ordinal = ...)
  final int ordinal;

  final AtShift shift;

  /// @At(by = ...)
  final int by;

  /// @At(args = ...)
  final List<String> args;

  /// @At(opcode = ...)
  final int? opcode;

  /// @At(slice = ...)
  final String? slice;

  const InjectionPoint({
    required this.type,
    this.target,
    this.ordinal = -1,
    this.shift = AtShift.none,
    this.by = 0,
    this.args = const [],
    this.opcode,
    this.slice,
  });
}

class MixinInjection {
  final MixinInjectionType type;

  /// Mixin handler method.
  final String handlerName;
  final String handlerDescriptor;

  /// @Inject(method = ...)
  final List<MixinTarget> targets;

  final List<InjectionPoint> points;

  /// Injector order.
  final int order;

  /// @Inject(require = ...)
  final int require;

  /// @Inject(expect = ...)
  final int? expect;

  /// @Inject(allow = ...)
  final int? allow;

  const MixinInjection({
    required this.type,
    required this.handlerName,
    required this.handlerDescriptor,
    required this.targets,
    required this.points,
    this.order = 1000,
    this.require = 0,
    this.expect,
    this.allow,
  });
}

class MixinClass {
  final String name;

  /// Internal names, e.g. net/minecraft/client/Minecraft.
  final List<String> targets;

  /// @Mixin(priority = ...)
  final int priority;

  final List<MixinInjection> injections;

  const MixinClass({
    required this.name,
    required this.targets,
    this.priority = 1000,
    this.injections = const [],
  });
}

class MixinConfig {
  final String path;
  final String packageName;

  /// Config-level priority.
  final int priority;

  final String? refmap;

  final List<String> mixins;
  final List<String> client;
  final List<String> server;

  const MixinConfig({
    required this.path,
    required this.packageName,
    this.priority = 1000,
    this.refmap,
    this.mixins = const [],
    this.client = const [],
    this.server = const [],
  });
}

class MixinExtraction {
  final String? sourceFile;
  final bool isMixin;
  final List<MixinInjectionInfo> injections;

  const MixinExtraction({
    this.sourceFile,
    required this.isMixin,
    this.injections = const [],
  });
}

class MixinInjectionInfo {
  final String annotation;

  final String? method;
  final String? at;
  final bool? cancellable;

  const MixinInjectionInfo({
    required this.annotation,
    this.method,
    this.at,
    this.cancellable,
  });
}