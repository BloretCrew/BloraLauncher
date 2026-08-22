import 'dart:io';
import 'dart:typed_data';

import '../services/nbt_editor.dart';

class LitematicSize {
  final int x;
  final int y;
  final int z;

  const LitematicSize({
    required this.x,
    required this.y,
    required this.z,
  });

  factory LitematicSize.fromNbt(Map<String, dynamic> nbt) {
    return LitematicSize(
      x: (nbt['x'] as num?)?.toInt() ?? 0,
      y: (nbt['y'] as num?)?.toInt() ?? 0,
      z: (nbt['z'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toNbt() {
    return {
      'x': x,
      'y': y,
      'z': z,
    };
  }

  int get volume => x.abs() * y.abs() * z.abs();
}

class LitematicMetadata {
  final LitematicSize enclosingSize;
  final String author;
  final String description;
  final String name;
  final int regionCount;
  final int timeCreated;
  final int timeModified;
  final int totalBlocks;
  final int totalVolume;

  const LitematicMetadata({
    required this.enclosingSize,
    required this.author,
    required this.description,
    required this.name,
    required this.regionCount,
    required this.timeCreated,
    required this.timeModified,
    required this.totalBlocks,
    required this.totalVolume,
  });

  factory LitematicMetadata.fromNbt(Map<String, dynamic> nbt) {
    return LitematicMetadata(
      enclosingSize: LitematicSize.fromNbt(
        (nbt['EnclosingSize'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
      author: nbt['Author'] as String? ?? '',
      description: nbt['Description'] as String? ?? '',
      name: nbt['Name'] as String? ?? '',
      regionCount: (nbt['RegionCount'] as num?)?.toInt() ?? 0,
      timeCreated: (nbt['TimeCreated'] as num?)?.toInt() ?? 0,
      timeModified: (nbt['TimeModified'] as num?)?.toInt() ?? 0,
      totalBlocks: (nbt['TotalBlocks'] as num?)?.toInt() ?? 0,
      totalVolume: (nbt['TotalVolume'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toNbt() {
    return {
      'EnclosingSize': enclosingSize.toNbt(),
      'Author': author,
      'Description': description,
      'Name': name,
      'RegionCount': regionCount,
      'TimeCreated': timeCreated,
      'TimeModified': timeModified,
      'TotalBlocks': totalBlocks,
      'TotalVolume': totalVolume,
    };
  }
}

class LitematicRegion {
  final LitematicSize position;
  final LitematicSize size;

  final List<Map<String, dynamic>> blockStatePalette;

  final List<int> blockStates;

  final List<Map<String, dynamic>> entities;

  final List<Map<String, dynamic>> tileEntities;

  final List<Map<String, dynamic>> pendingBlockTicks;

  final List<Map<String, dynamic>> pendingFluidTicks;

  const LitematicRegion({
    required this.position,
    required this.size,
    required this.blockStatePalette,
    required this.blockStates,
    required this.entities,
    required this.tileEntities,
    required this.pendingBlockTicks,
    required this.pendingFluidTicks,
  });

  factory LitematicRegion.fromNbt(Map<String, dynamic> nbt) {
    final rawPalette = nbt['BlockStatePalette'];

    final palette = <Map<String, dynamic>>[];

    if (rawPalette is List) {
      for (final value in rawPalette) {
        if (value is Map) {
          palette.add(
            value.cast<String, dynamic>(),
          );
        }
      }
    }

    return LitematicRegion(
      position: LitematicSize.fromNbt(
        (nbt['Position'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
      size: LitematicSize.fromNbt(
        (nbt['Size'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
      blockStatePalette: palette,
      blockStates: _toIntList(nbt['BlockStates']),
      entities: _toCompoundList(nbt['Entities']),
      tileEntities: _toCompoundList(nbt['TileEntities']),
      pendingBlockTicks: _toCompoundList(
        nbt['PendingBlockTicks'],
      ),
      pendingFluidTicks: _toCompoundList(
        nbt['PendingFluidTicks'],
      ),
    );
  }

  Map<String, dynamic> toNbt() {
    return {
      'Position': position.toNbt(),
      'Size': size.toNbt(),
      'BlockStatePalette': blockStatePalette,
      'Entities': entities,
      'PendingBlockTicks': pendingBlockTicks,
      'PendingFluidTicks': pendingFluidTicks,
      'TileEntities': tileEntities,
      'BlockStates': blockStates,
    };
  }

  int get volume => size.volume;

  int get paletteSize => blockStatePalette.length;

  static List<int> _toIntList(dynamic value) {
    if (value is List) {
      return value
          .whereType<num>()
          .map((e) => e.toInt())
          .toList();
    }

    return const [];
  }

  static List<Map<String, dynamic>> _toCompoundList(
      dynamic value,
      ) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }
}

class Litematic {
  final int version;
  final int subVersion;
  final int minecraftDataVersion;

  final LitematicMetadata metadata;

  final Map<String, LitematicRegion> regions;

  const Litematic({
    required this.version,
    required this.subVersion,
    required this.minecraftDataVersion,
    required this.metadata,
    required this.regions,
  });

  factory Litematic.fromNbt(
      Map<String, dynamic> nbt,
      ) {
    final rawMetadata = nbt['Metadata'];

    final metadata = LitematicMetadata.fromNbt(
      rawMetadata is Map
          ? rawMetadata.cast<String, dynamic>()
          : const {},
    );

    final regions = <String, LitematicRegion>{};

    final rawRegions = nbt['Regions'];

    if (rawRegions is Map) {
      rawRegions.forEach((key, value) {
        if (value is Map) {
          regions[key.toString()] =
              LitematicRegion.fromNbt(
                value.cast<String, dynamic>(),
              );
        }
      });
    }

    return Litematic(
      version: (nbt['Version'] as num?)?.toInt() ?? 0,
      subVersion:
      (nbt['SubVersion'] as num?)?.toInt() ?? 0,
      minecraftDataVersion:
      (nbt['MinecraftDataVersion'] as num?)?.toInt() ?? 0,
      metadata: metadata,
      regions: regions,
    );
  }

  Map<String, dynamic> toNbt({
    String rootName = '',
  }) {
    return {
      'Metadata': metadata.toNbt(),

      'Regions': {
        for (final entry in regions.entries)
          entry.key: entry.value.toNbt(),
      },

      'MinecraftDataVersion': minecraftDataVersion,
      'SubVersion': subVersion,
      'Version': version,
    };
  }

  String get name => metadata.name;

  String get author => metadata.author;

  String get description => metadata.description;

  int get regionCount => regions.length;

  int get totalBlocks => metadata.totalBlocks;

  int get totalVolume => metadata.totalVolume;

  LitematicRegion? getRegion(String name) {
    return regions[name];
  }

  Uint8List toNbtBytes({
    String rootName = '',
  }) {
    final writer = NbtWriter();

    return writer.writeRoot(
      rootName,
      toNbt(rootName: rootName),
    );
  }

  static Litematic fromNbtBytes(Uint8List bytes) {
    final reader = NbtReader(bytes);

    final nbt = reader.readRoot();

    if (nbt == null) {
      throw const FormatException(
        'Invalid Litematic NBT root.',
      );
    }

    return Litematic.fromNbt(nbt);
  }

  static Future<Litematic> fromFile(
      String path, {
        bool compressed = true,
      }) async {
    final bytes = await File(path).readAsBytes();

    final nbtBytes = compressed
        ? gzip.decode(bytes)
        : bytes;

    return fromNbtBytes(
      Uint8List.fromList(nbtBytes),
    );
  }

  Future<void> save(
      String path, {
        bool compressed = true,
        String rootName = '',
      }) async {
    final nbtBytes = toNbtBytes(
      rootName: rootName,
    );

    final bytes = compressed
        ? gzip.encode(nbtBytes)
        : nbtBytes;

    await File(path).writeAsBytes(bytes);
  }
}