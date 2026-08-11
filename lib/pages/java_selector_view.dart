import 'package:bloret_launcher/widgets/button.dart';
import 'package:bloret_launcher/widgets/windows_widgets.dart';
import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../services/zulu_api.dart';

class JavaSelectorView extends StatefulWidget {
  final VoidCallback onBack;

  const JavaSelectorView({
    super.key,
    required this.onBack,
  });

  @override
  State<JavaSelectorView> createState() => _JavaSelectorViewState();
}

enum JavaType {
  zulu,
  graal
}

enum JavaVersion {
  any,
  java8,
  java11,
  java13,
  java15,
  java17,
  java18,
  java19,
  java20,
  java21,
  java22,
  java23,
  java24,
  java25,
}

extension JavaVersionExtension on JavaVersion {
  String get label => switch (this) {
    JavaVersion.any => 'Any',
    JavaVersion.java8 => 'Java 8',
    JavaVersion.java11 => 'Java 11',
    JavaVersion.java13 => 'Java 13',
    JavaVersion.java15 => 'Java 15',
    JavaVersion.java17 => 'Java 17',
    JavaVersion.java18 => 'Java 18',
    JavaVersion.java19 => 'Java 19',
    JavaVersion.java20 => 'Java 20',
    JavaVersion.java21 => 'Java 21',
    JavaVersion.java22 => 'Java 22',
    JavaVersion.java23 => 'Java 23',
    JavaVersion.java24 => 'Java 24',
    JavaVersion.java25 => 'Java 25',
  };
}

extension OperatingSystemExtension on OperatingSystem {
  String get label => switch (this) {
    OperatingSystem.any => 'Any',
    OperatingSystem.windows => 'Windows',
    OperatingSystem.linux => 'Linux',
    OperatingSystem.macos => 'macOS',
    OperatingSystem.solaris => 'Solaris',
    OperatingSystem.aix => 'AIX',
    OperatingSystem.alpineLinux => 'Alpine Linux',
  };
}

extension ArchitectureExtension on Architecture {
  String get label => switch (this) {
    Architecture.any => 'Any',
    Architecture.x86_64 => 'x86 64-bit',
    Architecture.x86_32 => 'x86 32-bit',
    Architecture.arm64 => 'ARM 64-bit',
    Architecture.arm32 => 'ARM 32-bit',
    Architecture.ppc64le => 'PowerPC 64-bit LE',
    Architecture.ppc64 => 'PowerPC 64-bit',
    Architecture.s390x => 's390x',
    Architecture.riscv64 => 'RISC-V 64-bit',
  };
}

extension JavaPackageExtension on JavaPackage {
  String get label => switch (this) {
    JavaPackage.any => 'Any',
    JavaPackage.jdk => 'JDK',
    JavaPackage.jre => 'JRE',
  };
}

enum OperatingSystem {
  any,
  windows,
  linux,
  macos,
  solaris,
  aix,
  alpineLinux,
}

enum Architecture {
  any,
  x86_64,
  x86_32,
  arm64,
  arm32,
  ppc64le,
  ppc64,
  s390x,
  riscv64,
}

enum JavaPackage {
  any,
  jdk,
  jre,
}

T nextEnum<T extends Enum>(T current, List<T> values) {
  final index = values.indexOf(current);
  return values[(index + 1) % values.length];
}

class _JavaSelectorViewState extends State<JavaSelectorView> {
  bool loading = true;
  JavaType javaType = .zulu;
  JavaVersion javaVersion = JavaVersion.any;
  OperatingSystem operatingSystem = OperatingSystem.any;
  Architecture architecture = Architecture.any;
  JavaPackage javaPackage = JavaPackage.any;
  List<ZuluPackage> packages = [];

  @override
  void initState() {
    super.initState();
    _fetchPackages();
  }

  Future<void> _fetchPackages() async {
    final packages = await AzulApi().getAllPackages();
    if (mounted) {
      setState(() {
        this.packages = packages;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredPackages = packages.where((package) {
      final versionMatch = javaVersion == JavaVersion.any ||
          package.javaVersion.first == int.parse(javaVersion.name.substring(4));

      final osMatch = operatingSystem == OperatingSystem.any ||
          package.os == operatingSystem.name;

      final archMatch = architecture == Architecture.any ||
          package.arch == architecture.name;

      final packageMatch = javaPackage == JavaPackage.any ||
          package.javaPackageType == javaPackage.name;

      return versionMatch && osMatch && archMatch && packageMatch;
    }).toList();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 8),
              Text(
                "Java Installation".tl,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.sync),
                  onPressed: () {
                    setState(() {
                      javaType = nextEnum(javaType, JavaType.values);
                    });
                  }
              )
            ],
          ),
          const SizedBox(height: 8,),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: switch (javaType) {
                        JavaType.zulu => Colors.grey[200],
                        JavaType.graal => Color(0xFF32393F),
                      },
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: switch (javaType) {
                          JavaType.zulu => CustomPaint(
                            key: const ValueKey(JavaType.zulu),
                            size: const Size(120, 120),
                            painter: AzulIcon(color: const Color(0xFF142241)),
                          ),
                          JavaType.graal => CustomPaint(
                            key: const ValueKey(JavaType.graal),
                            size: const Size(120, 120),
                            painter: GraalIcon(color: Colors.white, color2: const Color(0xFFE69539)),
                          ),
                        },
                      ),
                    )
                ),
                const SizedBox(width: 24,),
                Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      switch (javaType) {
                        JavaType.zulu => "Zulu Java Downloads".tl,
                        JavaType.graal => "GraalVM Downloads".tl,
                      },
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6,),
                    Text(
                      switch (javaType) {
                        JavaType.zulu => "© Azul 2026. All rights reserved.",
                        JavaType.graal => "Copyright © 2018, 2026, Oracle and/or its affiliates. All rights reserved. ",
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12,),
          Row(
            children: [
              const SizedBox(width: 12),
              Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  Text("Java Version".tl),
                  Win11Dropdown(
                    width: 160,
                    initialValue: javaVersion.name,
                    items: JavaVersion.values.map((e) => Win11DropdownItem(label: e.label, value: e.name)).toList(),
                    onChanged: (value) {
                      setState(() {
                        javaVersion = JavaVersion.values.firstWhere((e) => e.name == value);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  Text("Operating System".tl),
                  Win11Dropdown(
                    width: 160,
                    initialValue: operatingSystem.name,
                    items: OperatingSystem.values.map((e) => Win11DropdownItem(label: e.label, value: e.name)).toList(),
                    onChanged: (value) {
                      setState(() {
                        operatingSystem = OperatingSystem.values.firstWhere((e) => e.name == value);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  Text("Architecture".tl),
                  Win11Dropdown(
                    width: 160,
                    initialValue: architecture.name,
                    items: Architecture.values.map((e) => Win11DropdownItem(label: e.label, value: e.name)).toList(),
                    onChanged: (value) {
                      setState(() {
                        architecture = Architecture.values.firstWhere((e) => e.name == value);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  Text("Java Package".tl),
                  Win11Dropdown(
                    width: 160,
                    initialValue: javaPackage.name,
                    items: JavaPackage.values.map((e) => Win11DropdownItem(label: e.label, value: e.name)).toList(),
                    onChanged: (value) {
                      setState(() {
                        javaPackage = JavaPackage.values.firstWhere((e) => e.name == value);
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12,),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
              itemCount: filteredPackages.length,
              itemBuilder: (context, index) {
                final package = filteredPackages[index];
                return SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Container(
                      height: 72,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.blue.withValues(alpha: 0.1),
                            ),
                            child: const Icon(Icons.inventory_2_outlined),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Java ${package.javaVersion.join('.')}',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  package.os,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              package.javaPackageType.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 90,
                            child: Text(
                              package.arch,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 12),
                          BloretButton(
                            text: "Download".tl,
                            onPressed: () {

                            },
                          )
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

class AzulIcon extends CustomPainter {
  final Color color;

  AzulIcon({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.scale(0.135);
    canvas.translate(size.width * 3.2, size.height * 0.8);
    canvas.drawPath(buildPath(), paint);
    canvas.translate(size.width * 2.6, size.height * 0.5);
    canvas.drawPath(buildPath4(), paint);
    canvas.translate(-size.width * 1.58, -size.height * 0.8);
    canvas.drawPath(buildPath5(), paint);
    canvas.translate(size.width * 1.4, size.height * 2.58);
    canvas.drawPath(buildPath6(), paint);
    canvas.translate(-size.width * 4.8, size.height);
    canvas.drawPath(buildPath2(), paint);
    canvas.translate(size.width * 4.2, 0);
    canvas.drawPath(buildPath3(), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class GraalIcon extends CustomPainter {
  final Color color;
  final Color color2;

  GraalIcon({required this.color, required this.color2});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.scale(1.6);
    canvas.translate(0, size.height * 0.25);
    canvas.drawPath(buildPath7().path, paint);
    final paint2 = Paint()
      ..color = color2
      ..style = PaintingStyle.fill;
    canvas.drawPath(buildPath8().path, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Path 1
Path buildPath() {
  final Path path = Path();
  path.moveTo(0.0, 0.0);
  path.cubicTo(30.84472738, 29.61362808, 44.04333918, 69.69565318, 45.37574387, 111.80989075);
  path.cubicTo(45.55650624, 121.16777924, 45.56261182, 130.52628453, 45.56642032, 139.88563061);
  path.cubicTo(45.5709607, 143.94927947, 45.58899738, 148.01286547, 45.60621643, 152.07647705);
  path.cubicTo(45.65492225, 164.1063256, 45.68633577, 176.13620979, 45.70751953, 188.1661377);
  path.cubicTo(45.72407599, 197.56337259, 45.74691329, 206.96048602, 45.79054028, 216.35763955);
  path.cubicTo(45.81219783, 221.17307198, 45.82038626, 225.98827277, 45.81814754, 230.80375051);
  path.cubicTo(45.8198209, 233.79790681, 45.83390638, 236.79191261, 45.85136032, 239.78601456);
  path.cubicTo(45.85956997, 241.82014668, 45.85305424, 243.85432182, 45.84599304, 245.88845825);
  path.cubicTo(45.83077182, 256.99183042, 45.83077182, 256.99183042, 50.57070065, 266.74404526);
  path.cubicTo(54.59276535, 270.38699074, 58.94385336, 272.13195747, 64.33862305, 272.21411133);
  path.cubicTo(65.90870117, 272.0671582, 65.90870117, 272.0671582, 67.51049805, 271.91723633);
  path.cubicTo(69.06510742, 271.78575195, 69.06510742, 271.78575195, 70.65112305, 271.65161133);
  path.cubicTo(73.63872325, 271.25067797, 76.53493197, 270.73636849, 79.48608398, 270.13696289);
  path.cubicTo(80.82941803, 269.86508148, 80.82941803, 269.86508148, 82.19989014, 269.58770752);
  path.cubicTo(82.87989075, 269.44895203, 83.55989136, 269.31019653, 84.26049805, 269.16723633);
  path.cubicTo(84.39354397, 277.04544792, 84.52404924, 284.92369764, 84.65164948, 292.80199909);
  path.cubicTo(84.71102627, 296.46356016, 84.77115344, 300.12510509, 84.83325195, 303.78662109);
  path.cubicTo(85.15137464, 322.58251016, 85.33723128, 341.36803691, 85.26049805, 360.16723633);
  path.cubicTo(70.2461584, 364.85921747, 55.70914571, 366.52968187, 40.03369141, 366.48291016);
  path.cubicTo(37.82689234, 366.47974192, 35.621431, 366.5033751, 33.41479492, 366.52856445);
  path.cubicTo(7.03695241, 366.64583503, -17.59333907, 358.88910752, -36.73950195, 340.16723633);
  path.cubicTo(-46.71430851, 329.65325104, -53.05195356, 316.73408311, -57.73950195, 303.16723633);
  path.cubicTo(-58.26157227, 303.95485352, -58.78364258, 304.7424707, -59.3215332, 305.55395508);
  path.cubicTo(-79.93540086, 336.05959111, -108.19818566, 354.58249338, -144.23950195, 362.41723633);
  path.cubicTo(-144.92488037, 362.56829834, -145.61025879, 362.71936035, -146.31640625, 362.875);
  path.cubicTo(-160.04587688, 365.64968955, -173.94312936, 366.50438526, -187.91674805, 366.42797852);
  path.cubicTo(-190.23944162, 366.41723661, -192.56136231, 366.42797363, -194.8840332, 366.44067383);
  path.cubicTo(-209.29386214, 366.4553556, -223.62464239, 365.30265114, -237.67700195, 361.97973633);
  path.cubicTo(-239.04912842, 361.65827637, -239.04912842, 361.65827637, -240.44897461, 361.33032227);
  path.cubicTo(-260.65983781, 356.39198452, -279.24909079, 348.2988395, -294.73950195, 334.16723633);
  path.cubicTo(-295.51680664, 333.47114258, -296.29411133, 332.77504883, -297.0949707, 332.05786133);
  path.cubicTo(-314.34486805, 315.7877344, -325.30308361, 291.1501085, -326.00486755, 267.4715271);
  path.cubicTo(-326.053343, 264.68643398, -326.0637798, 261.90266017, -326.05517578, 259.1171875);
  path.cubicTo(-326.05203186, 256.99987414, -326.07550602, 254.88398601, -326.10083008, 252.7668457);
  path.cubicTo(-326.21891837, 227.7163224, -318.19010545, 204.26050705, -301.73950195, 185.16723633);
  path.cubicTo(-301.22129883, 184.5046582, -300.7030957, 183.84208008, -300.16918945, 183.15942383);
  path.cubicTo(-271.67517406, 147.7924801, -217.77544976, 136.98751381, -175.42700195, 131.85473633);
  path.cubicTo(-174.75515869, 131.77324341, -174.08331543, 131.69175049, -173.39111328, 131.60778809);
  path.cubicTo(-157.21140642, 129.68106411, -141.17290083, 129.01746277, -124.89575195, 129.06958008);
  path.cubicTo(-123.14742066, 129.07145118, -121.39908884, 129.0728718, -119.65075684, 129.0738678);
  path.cubicTo(-115.10697922, 129.07763856, -110.56323491, 129.08742057, -106.01947021, 129.09857178);
  path.cubicTo(-101.35974579, 129.10890467, -96.70001585, 129.11339055, -92.0402832, 129.1184082);
  path.cubicTo(-82.94000836, 129.12904922, -73.83975796, 129.14605798, -64.73950195, 129.16723633);
  path.cubicTo(-64.87204155, 124.6669604, -65.01573386, 120.16710574, -65.16137695, 115.66723633);
  path.cubicTo(-65.21720947, 113.76458008, -65.21720947, 113.76458008, -65.27416992, 111.82348633);
  path.cubicTo(-65.85480581, 94.33609963, -69.59994894, 79.07347571, -80.73950195, 65.16723633);
  path.cubicTo(-81.48780273, 64.22944336, -81.48780273, 64.22944336, -82.2512207, 63.27270508);
  path.cubicTo(-94.55009531, 49.54877195, -114.99874801, 44.17607254, -132.73950195, 43.16723633);
  path.cubicTo(-154.8588994, 42.34615633, -177.122465, 46.08014203, -194.42700195, 60.72973633);
  path.cubicTo(-205.48806402, 71.30095136, -209.80181852, 83.47881917, -212.73950195, 98.16723633);
  path.cubicTo(-246.72950195, 98.16723633, -280.71950195, 98.16723633, -315.73950195, 98.16723633);
  path.cubicTo(-314.5622518, 82.86298437, -314.5622518, 82.86298437, -312.98950195, 75.29223633);
  path.cubicTo(-312.81249756, 74.43637939, -312.63549316, 73.58052246, -312.453125, 72.69873047);
  path.cubicTo(-305.24014849, 39.11242621, -286.6734731, 10.14232303, -258.73950195, -9.83276367);
  path.cubicTo(-258.19632324, -10.22415527, -257.65314453, -10.61554688, -257.09350586, -11.01879883);
  path.cubicTo(-229.67075603, -30.4691445, -195.89119598, -39.80938543, -162.73950195, -42.83276367);
  path.cubicTo(-160.9315918, -42.99905273, -160.9315918, -42.99905273, -159.0871582, -43.16870117);
  path.cubicTo(-103.93871645, -47.38024368, -41.93128287, -39.27836119, 0.0, 0.0);
  path.close();
  path.moveTo(-206.95043945, 215.85083008);
  path.cubicTo(-215.50853801, 226.93151226, -216.87193282, 238.63977878, -215.73950195, 252.16723633);
  path.cubicTo(-214.92297433, 255.89993401, -213.6903669, 258.89344109, -211.73950195, 262.16723633);
  path.cubicTo(-211.32700195, 262.86977539, -210.91450195, 263.57231445, -210.48950195, 264.29614258);
  path.cubicTo(-203.43139617, 274.86324982, -192.03756733, 279.64643943, -180.02075195, 282.22583008);
  path.cubicTo(-151.85531346, 287.65736213, -120.79780791, 282.54245126, -96.5168457, 267.12036133);
  path.cubicTo(-93.84078883, 265.22098671, -91.28027005, 263.24297199, -88.73950195, 261.16723633);
  path.cubicTo(-88.03696289, 260.62711914, -87.33442383, 260.08700195, -86.6105957, 259.53051758);
  path.cubicTo(-75.28022016, 250.37309077, -67.5324333, 237.4272442, -64.73950195, 223.16723633);
  path.cubicTo(-64.58658469, 220.57717959, -64.52326621, 217.9804689, -64.54418945, 215.38598633);
  path.cubicTo(-64.54701935, 214.68703247, -64.54984924, 213.98807861, -64.55276489, 213.26794434);
  path.cubicTo(-64.56382925, 211.06752317, -64.5889059, 208.86753139, -64.61450195, 206.66723633);
  path.cubicTo(-64.6245496, 205.16203393, -64.6336723, 203.65682507, -64.6418457, 202.15161133);
  path.cubicTo(-64.66372302, 198.49001694, -64.69815499, 194.82866865, -64.73950195, 191.16723633);
  path.cubicTo(-72.63500308, 191.1201089, -80.53046896, 191.08497167, -88.42607689, 191.06361198);
  path.cubicTo(-92.09554518, 191.05334098, -95.76491472, 191.03950368, -99.43432617, 191.01635742);
  path.cubicTo(-157.50773657, 189.45206092, -157.50773657, 189.45206092, -206.95043945, 215.85083008);
  path.close();
  return path;
}

// Path 2
Path buildPath2() {
  final Path path = Path();
  path.moveTo(0.0, 0.0);
  path.cubicTo(37.62, 0.0, 75.24, 0.0, 114.0, 0.0);
  path.cubicTo(114.02578125, 17.38171875, 114.0515625, 34.7634375, 114.078125, 52.671875);
  path.cubicTo(114.10329901, 63.70053202, 114.12947416, 74.7291717, 114.16015625, 85.7578125);
  path.cubicTo(114.17624564, 91.55501223, 114.19208874, 97.35221254, 114.20751953, 103.14941406);
  path.cubicTo(114.20946347, 103.87587922, 114.21140741, 104.60234438, 114.21341026, 105.35082364);
  path.cubicTo(114.24433013, 117.03969912, 114.2613772, 128.72855501, 114.27319422, 140.41746363);
  path.cubicTo(114.2856577, 152.43642748, 114.3132752, 164.45528953, 114.35461307, 176.47418904);
  path.cubicTo(114.37737316, 183.21536062, 114.39291507, 189.95637867, 114.39188385, 196.69759369);
  path.cubicTo(114.39113291, 203.05716116, 114.40925683, 209.41640939, 114.44116783, 215.77589417);
  path.cubicTo(114.44960845, 218.09601126, 114.45145705, 220.41616442, 114.44580269, 222.73628998);
  path.cubicTo(114.3968252, 245.94443642, 116.41470239, 270.0732445, 133.0, 288.0);
  path.cubicTo(133.6084375, 288.66128906, 134.216875, 289.32257813, 134.84375, 290.00390625);
  path.cubicTo(147.94199486, 302.88221789, 165.95172629, 306.52817591, 183.69335938, 306.41992188);
  path.cubicTo(202.99397773, 305.9047103, 219.77782545, 298.48490104, 233.3359375, 284.609375);
  path.cubicTo(242.62736708, 274.01777951, 248.86894024, 260.70226152, 252.0, 247.0);
  path.cubicTo(252.24915696, 245.93281675, 252.24915696, 245.93281675, 252.5033474, 244.84407425);
  path.cubicTo(254.67194312, 234.01643637, 254.30871547, 223.05679276, 254.31884766, 212.06542969);
  path.cubicTo(254.32815689, 209.74841465, 254.33832703, 207.43140295, 254.34928894, 205.11439514);
  path.cubicTo(254.37649068, 198.85291578, 254.39170916, 192.5914588, 254.40471697, 186.32993603);
  path.cubicTo(254.42039063, 179.77561578, 254.4471673, 173.22134094, 254.4727478, 166.66705322);
  path.cubicTo(254.51448426, 155.67534892, 254.54877524, 144.68363851, 254.578125, 133.69189453);
  path.cubicTo(254.60835962, 122.37579557, 254.64275464, 111.05972165, 254.68261719, 99.74365234);
  path.cubicTo(254.6850987, 99.0377551, 254.6875802, 98.33185786, 254.69013691, 97.60456979);
  path.cubicTo(254.71176199, 91.46323722, 254.73369996, 85.32190577, 254.75566864, 79.18057442);
  path.cubicTo(254.84967824, 52.7870779, 254.92315695, 26.39356501, 255.0, 0.0);
  path.cubicTo(292.62, 0.0, 330.24, 0.0, 369.0, 0.0);
  path.cubicTo(369.02187378, 13.34179688, 369.02187378, 13.34179688, 369.04418945, 26.953125);
  path.cubicTo(369.09294957, 55.41386596, 369.15635942, 83.87455743, 369.22898628, 112.3352471);
  path.cubicTo(369.24025441, 116.75621263, 369.25139287, 121.17717847, 369.26245117, 125.59814453);
  path.cubicTo(369.2657567, 126.91834384, 369.2657567, 126.91834384, 369.269129, 128.26521385);
  path.cubicTo(369.30449915, 142.51525771, 369.32936488, 156.76530151, 369.35034702, 171.01537299);
  path.cubicTo(369.37211132, 185.63780722, 369.40516773, 200.26018449, 369.44870156, 214.88257027);
  path.cubicTo(369.47520742, 223.90499927, 369.49291064, 232.92735731, 369.49934604, 241.94982332);
  path.cubicTo(369.50460318, 248.13728706, 369.52083111, 254.32466151, 369.54566566, 260.51207739);
  path.cubicTo(369.55966951, 264.08163169, 369.56885566, 267.65102619, 369.56500816, 271.22060966);
  path.cubicTo(369.56096049, 275.09340045, 369.58002473, 278.9658841, 369.60127258, 282.83862305);
  path.cubicTo(369.59642501, 283.96315006, 369.59157743, 285.08767708, 369.58658296, 286.24628067);
  path.cubicTo(369.65499203, 293.79522771, 370.70162705, 299.30618633, 374.75, 305.8125);
  path.cubicTo(378.87766727, 309.82550985, 382.93799923, 311.16258043, 388.5625, 311.375);
  path.cubicTo(395.49241048, 311.0261541, 395.49241048, 311.0261541, 408.0, 308.0);
  path.cubicTo(408.0, 337.7, 408.0, 367.4, 408.0, 398.0);
  path.cubicTo(390.24217399, 402.93272945, 376.40000544, 405.41781358, 358.5, 405.375);
  path.cubicTo(357.60948944, 405.37412384, 356.71897888, 405.37324768, 355.80148315, 405.37234497);
  path.cubicTo(332.59292462, 405.29686616, 309.54059336, 402.30080109, 291.0, 387.0);
  path.cubicTo(290.17242187, 386.33355469, 289.34484375, 385.66710937, 288.4921875, 384.98046875);
  path.cubicTo(274.90110254, 373.44674986, 266.97967193, 358.50829673, 261.0, 342.0);
  path.cubicTo(260.46375, 342.7528125, 259.9275, 343.505625, 259.375, 344.28125);
  path.cubicTo(235.09410928, 377.52338829, 200.1255705, 397.84768406, 159.70288086, 404.54638672);
  path.cubicTo(155.82514629, 405.02142007, 152.00951825, 405.17831554, 148.109375, 405.203125);
  path.cubicTo(147.37131119, 405.21013931, 146.63324738, 405.21715363, 145.87281799, 405.22438049);
  path.cubicTo(143.49848283, 405.24181947, 141.12439689, 405.24823434, 138.75, 405.25);
  path.cubicTo(137.94009613, 405.25067474, 137.13019226, 405.25134949, 136.29574585, 405.25204468);
  path.cubicTo(124.3081717, 405.23615175, 112.69018603, 404.90988261, 101.0, 402.0);
  path.cubicTo(100.2790918, 401.82307617, 99.55818359, 401.64615234, 98.81542969, 401.46386719);
  path.cubicTo(79.97989321, 396.68691773, 62.92900418, 388.56614021, 48.0, 376.0);
  path.cubicTo(47.20078125, 375.33484375, 46.4015625, 374.6696875, 45.578125, 373.984375);
  path.cubicTo(16.33313717, 348.73559669, 3.32080387, 311.47991917, 0.18704081, 273.87444663);
  path.cubicTo(-0.46027313, 263.92651382, -0.256834, 253.92938567, -0.22705078, 243.96606445);
  path.cubicTo(-0.22648549, 241.29334104, -0.22671789, 238.62062858, -0.22793579, 235.94790649);
  path.cubicTo(-0.22897593, 230.23292964, -0.22279153, 224.51799905, -0.21146011, 218.80303383);
  path.cubicTo(-0.19508835, 210.54053192, -0.18998528, 202.27805199, -0.18748413, 194.01553562);
  path.cubicTo(-0.18312517, 180.60466411, -0.16986533, 167.19381718, -0.15087891, 153.78295898);
  path.cubicTo(-0.13247323, 140.7686373, -0.11833978, 127.75432233, -0.10986328, 114.73999023);
  path.cubicTo(-0.10933783, 113.93550618, -0.10881239, 113.13102212, -0.10827102, 112.30215976);
  path.cubicTo(-0.10566062, 108.26561855, -0.10313328, 104.22907729, -0.10064721, 100.192536);
  path.cubicTo(-0.07997082, 66.79500222, -0.04313167, 33.3975142, 0.0, 0.0);
  path.close();
  return path;
}

// Path 3
Path buildPath3() {
  final Path path = Path();
  path.moveTo(0.0, 0.0);
  path.cubicTo(37.29, 0.0, 74.58, 0.0, 113.0, 0.0);
  path.cubicTo(113.01458252, 8.85376465, 113.02916504, 17.7075293, 113.04418945, 26.82958984);
  path.cubicTo(113.09296464, 55.17007164, 113.15637868, 83.51050381, 113.22898628, 111.85093417);
  path.cubicTo(113.24025422, 116.25430088, 113.25139271, 120.65766791, 113.26245117, 125.06103516);
  path.cubicTo(113.26465486, 125.93765279, 113.26685854, 126.81427043, 113.269129, 127.71745224);
  path.cubicTo(113.30448505, 141.90471294, 113.32935874, 156.09197359, 113.35034702, 170.27926199);
  path.cubicTo(113.37212255, 184.84068529, 113.40518964, 199.4020515, 113.44870156, 213.96342623);
  path.cubicTo(113.47518807, 222.94592714, 113.49290553, 231.92835693, 113.49934604, 240.91089495);
  path.cubicTo(113.50460911, 247.0736107, 113.5208569, 253.23623704, 113.54566566, 259.39890485);
  path.cubicTo(113.55964923, 262.95250485, 113.56886328, 266.5059449, 113.56500816, 270.05957413);
  path.cubicTo(113.56094891, 273.91852814, 113.58005906, 277.77717582, 113.60127258, 281.63607788);
  path.cubicTo(113.59642501, 282.75088827, 113.59157743, 283.86569865, 113.58658296, 285.01429117);
  path.cubicTo(113.65815479, 292.91602265, 114.29167642, 300.55969707, 119.3125, 306.9375);
  path.cubicTo(126.09569124, 312.14320491, 130.56675267, 312.53262615, 139.0, 312.0);
  path.cubicTo(143.29, 311.01, 147.58, 310.02, 152.0, 309.0);
  path.cubicTo(152.0, 338.7, 152.0, 368.4, 152.0, 399.0);
  path.cubicTo(136.61359959, 403.73427705, 136.61359959, 403.73427705, 130.4140625, 404.7265625);
  path.cubicTo(129.66379791, 404.84818756, 128.91353333, 404.96981262, 128.14053345, 405.09512329);
  path.cubicTo(120.06037255, 406.29631716, 112.01478481, 406.45380525, 103.85839844, 406.39111328);
  path.cubicTo(101.36858785, 406.3749584, 98.88038868, 406.39111688, 96.390625, 406.41015625);
  path.cubicTo(70.34709974, 406.44626919, 46.21221028, 399.10744082, 27.0, 381.0);
  path.cubicTo(5.93549285, 358.80377756, -0.19322487, 327.57514336, -0.12025452, 297.99069214);
  path.cubicTo(-0.12110894, 296.71216311, -0.12196337, 295.43363407, -0.12284368, 294.11636174);
  path.cubicTo(-0.12506546, 290.59305426, -0.12109932, 287.06977754, -0.11606562, 283.54647398);
  path.cubicTo(-0.11172781, 279.73747991, -0.1132099, 275.92848743, -0.1139679, 272.11949158);
  path.cubicTo(-0.11449102, 265.52857938, -0.11136629, 258.93767712, -0.10573006, 252.34676743);
  path.cubicTo(-0.09758644, 242.81753989, -0.09499691, 233.28831714, -0.09374207, 223.7590865);
  path.cubicTo(-0.09155604, 208.29674505, -0.08490814, 192.83440889, -0.07543945, 177.37207031);
  path.cubicTo(-0.06625371, 162.35612006, -0.05917856, 147.34017125, -0.05493164, 132.32421875);
  path.cubicTo(-0.05466892, 131.39789036, -0.05440619, 130.47156197, -0.05413551, 129.51716302);
  path.cubicTo(-0.05283043, 124.86982322, -0.05156673, 120.2224834, -0.05032361, 115.57514358);
  path.cubicTo(-0.03996499, 77.05009102, -0.02153422, 38.52504825, 0.0, 0.0);
  path.close();
  return path;
}

// Path 4
Path buildPath4() {
  final Path path = Path();
  path.moveTo(0.0, 0.0);
  path.cubicTo(0.721875, 0.144375, 1.44375, 0.28875, 2.1875, 0.4375);
  path.cubicTo(0.80785739, 3.37829548, -0.78753924, 5.91808368, -2.71875, 8.52734375);
  path.cubicTo(-3.29222168, 9.3044873, -3.86569336, 10.08163086, -4.45654297, 10.88232422);
  path.cubicTo(-5.06900879, 11.70490723, -5.68147461, 12.52749023, -6.3125, 13.375);
  path.cubicTo(-6.94687988, 14.23109863, -7.58125977, 15.08719727, -8.23486328, 15.96923828);
  path.cubicTo(-12.45476754, 21.65024834, -16.72910704, 27.28398278, -21.0625, 32.87890625);
  path.cubicTo(-24.62866793, 37.48385567, -28.15719657, 42.11753493, -31.6875, 46.75);
  path.cubicTo(-32.37432861, 47.65121582, -33.06115723, 48.55243164, -33.76879883, 49.48095703);
  path.cubicTo(-38.48868943, 55.68143336, -43.17467643, 61.90636072, -47.84033203, 68.14770508);
  path.cubicTo(-51.43948611, 72.95684372, -55.09199417, 77.72136585, -58.8125, 82.4375);
  path.cubicTo(-54.98801148, 78.71089601, -51.45894271, 74.81629335, -48.0, 70.75);
  path.cubicTo(-47.46938965, 70.12843018, -46.9387793, 69.50686035, -46.39208984, 68.86645508);
  path.cubicTo(-42.87042174, 64.72466948, -39.43778739, 60.52306713, -36.06640625, 56.2578125);
  path.cubicTo(-33.04159051, 52.47286109, -29.95857561, 48.73713747, -26.875, 45.0);
  path.cubicTo(-26.26156738, 44.25645264, -25.64813477, 43.51290527, -25.01611328, 42.74682617);
  path.cubicTo(-23.81822252, 41.2949005, -22.62030667, 39.84299553, -21.42236328, 38.39111328);
  path.cubicTo(-19.37931111, 35.91181339, -17.344788, 33.4256283, -15.3125, 30.9375);
  path.cubicTo(-11.44207804, 26.20456828, -7.56776462, 21.47486481, -3.6875, 16.75);
  path.cubicTo(-3.11322266, 16.04875, -2.53894531, 15.3475, -1.94726562, 14.625);
  path.cubicTo(-0.81705758, 13.25010774, 0.31791073, 11.87911384, 1.45776367, 10.51220703);
  path.cubicTo(2.66118066, 9.06878606, 3.85326161, 7.61586946, 5.03637695, 6.15576172);
  path.cubicTo(5.6418335, 5.42760254, 6.24729004, 4.69944336, 6.87109375, 3.94921875);
  path.cubicTo(7.41306396, 3.28752686, 7.95503418, 2.62583496, 8.51342773, 1.9440918);
  path.cubicTo(10.1875, 0.4375, 10.1875, 0.4375, 14.125, -0.0625);
  path.cubicTo(15.135625, 0.1025, 16.14625, 0.2675, 17.1875, 0.4375);
  path.cubicTo(16.64875244, 1.15256714, 16.64875244, 1.15256714, 16.09912109, 1.88208008);
  path.cubicTo(12.86952878, 6.17726069, 9.67144471, 10.49382237, 6.49560547, 14.82885742);
  path.cubicTo(0.09419643, 23.56185017, -6.41337622, 32.20747193, -12.98974609, 40.80932617);
  path.cubicTo(-17.43132168, 46.61948305, -21.83917018, 52.45284409, -26.21289062, 58.31420898);
  path.cubicTo(-29.12869434, 62.2143444, -32.07389833, 66.0903476, -35.0390625, 69.953125);
  path.cubicTo(-35.76738281, 70.90316406, -36.49570312, 71.85320312, -37.24609375, 72.83203125);
  path.cubicTo(-38.68073687, 74.70141471, -40.11813375, 76.56868882, -41.55859375, 78.43359375);
  path.cubicTo(-42.21214844, 79.28566406, -42.86570312, 80.13773437, -43.5390625, 81.015625);
  path.cubicTo(-44.12252441, 81.77262695, -44.70598633, 82.52962891, -45.30712891, 83.30957031);
  path.cubicTo(-46.70954683, 85.2919697, -47.79680103, 87.23650714, -48.8125, 89.4375);
  path.cubicTo(-43.141506, 82.78659159, -37.51428832, 76.11793681, -32.08203125, 69.26953125);
  path.cubicTo(-27.34684425, 63.36073508, -22.50153434, 57.54098468, -17.68115234, 51.70166016);
  path.cubicTo(-14.61834776, 47.99060062, -11.55902569, 44.27667465, -8.5, 40.5625);
  path.cubicTo(-7.61513916, 39.48826782, -7.61513916, 39.48826782, -6.71240234, 38.39233398);
  path.cubicTo(-2.87905433, 33.73709108, 0.94343903, 29.07315202, 4.7578125, 24.40234375);
  path.cubicTo(6.74791606, 21.97390549, 8.74339121, 19.55018253, 10.7421875, 17.12890625);
  path.cubicTo(11.68674805, 15.98421875, 11.68674805, 15.98421875, 12.65039062, 14.81640625);
  path.cubicTo(13.90092956, 13.30145306, 15.15220186, 11.78710486, 16.40429688, 10.2734375);
  path.cubicTo(17.26764648, 9.22736328, 17.26764648, 9.22736328, 18.1484375, 8.16015625);
  path.cubicTo(18.66196777, 7.53890869, 19.17549805, 6.91766113, 19.70458984, 6.27758789);
  path.cubicTo(21.24851805, 4.42203704, 21.24851805, 4.42203704, 22.64697266, 2.22045898);
  path.cubicTo(23.15534668, 1.63208252, 23.6637207, 1.04370605, 24.1875, 0.4375);
  path.cubicTo(27.875, 0.1875, 27.875, 0.1875, 31.1875, 0.4375);
  path.cubicTo(27.72451161, 6.04207331, 23.83559241, 11.20803997, 19.6875, 16.3125);
  path.cubicTo(15.04527116, 22.03268866, 10.59719559, 27.86510232, 6.25, 33.8125);
  path.cubicTo(0.25534072, 42.01105401, -5.86707799, 50.09926789, -12.05712891, 58.15087891);
  path.cubicTo(-15.33942351, 62.42653554, -18.60746795, 66.71305675, -21.875, 71.0);
  path.cubicTo(-22.54515137, 71.87922119, -23.21530273, 72.75844238, -23.90576172, 73.66430664);
  path.cubicTo(-29.91585755, 81.55795625, -35.87598458, 89.48841591, -41.8125, 97.4375);
  path.cubicTo(-37.65535557, 93.44292546, -34.0096391, 89.15814197, -30.375, 84.6875);
  path.cubicTo(-29.13289351, 83.16920456, -27.89070357, 81.65097738, -26.6484375, 80.1328125);
  path.cubicTo(-26.01518555, 79.35711914, -25.38193359, 78.58142578, -24.72949219, 77.78222656);
  path.cubicTo(-21.66424804, 74.03304104, -18.5812552, 70.29852719, -15.5, 66.5625);
  path.cubicTo(-11.0619994, 61.17553494, -6.63492906, 55.77987587, -2.21875, 50.375);
  path.cubicTo(1.52295642, 45.80720255, 5.28012543, 41.25215751, 9.03515625, 36.6953125);
  path.cubicTo(12.25944724, 32.78159428, 15.47906584, 28.86424032, 18.6875, 24.9375);
  path.cubicTo(22.66050607, 20.07826573, 26.64024414, 15.22460145, 30.625, 10.375);
  path.cubicTo(31.24117187, 9.62347656, 31.85734375, 8.87195313, 32.4921875, 8.09765625);
  path.cubicTo(33.07097656, 7.39382812, 33.64976562, 6.69, 34.24609375, 5.96484375);
  path.cubicTo(34.76486084, 5.33312256, 35.28362793, 4.70140137, 35.81811523, 4.05053711);
  path.cubicTo(37.1875, 2.4375, 37.1875, 2.4375, 39.1875, 0.4375);
  path.cubicTo(42.3125, 0.3125, 42.3125, 0.3125, 45.1875, 0.4375);
  path.cubicTo(41.30105427, 6.43620147, 37.18866925, 12.15022191, 32.75, 17.75);
  path.cubicTo(27.69138321, 24.19247604, 22.71280412, 30.68629583, 17.8125, 37.25);
  path.cubicTo(12.5165984, 44.34149879, 7.18323229, 51.40248202, 1.8125, 58.4375);
  path.cubicTo(-2.92648658, 64.64544922, -7.64786749, 70.86387979, -12.31640625, 77.125);
  path.cubicTo(-14.4688465, 79.99616976, -16.6539753, 82.84171842, -18.83984375, 85.6875);
  path.cubicTo(-19.56429687, 86.63238281, -20.28875, 87.57726562, -21.03515625, 88.55078125);
  path.cubicTo(-22.4893909, 90.4461594, -23.94633827, 92.3394599, -25.40625, 94.23046875);
  path.cubicTo(-26.07527344, 95.10316406, -26.74429688, 95.97585938, -27.43359375, 96.875);
  path.cubicTo(-28.0361499, 97.65746094, -28.63870605, 98.43992187, -29.25952148, 99.24609375);
  path.cubicTo(-30.68134493, 101.25242723, -31.7868505, 103.20779957, -32.8125, 105.4375);
  path.cubicTo(-32.46171387, 105.01154541, -32.11092773, 104.58559082, -31.74951172, 104.14672852);
  path.cubicTo(-30.6815621, 102.84993255, -29.61360931, 101.55313919, -28.5456543, 100.25634766);
  path.cubicTo(-27.29188806, 98.73390545, -26.0381451, 97.21144407, -24.78442383, 95.68896484);
  path.cubicTo(-21.55082796, 91.7622542, -18.31690033, 87.8358181, -15.08203125, 83.91015625);
  path.cubicTo(-9.44961838, 77.07428196, -3.82303252, 70.23397264, 1.78125, 63.375);
  path.cubicTo(5.52295642, 58.80720255, 9.28012543, 54.25215751, 13.03515625, 49.6953125);
  path.cubicTo(16.96496407, 44.9252218, 20.88365843, 40.14628559, 24.79296875, 35.359375);
  path.cubicTo(26.6658161, 33.07407351, 28.54376928, 30.79336432, 30.42578125, 28.515625);
  path.cubicTo(31.00779297, 27.81042725, 31.58980469, 27.10522949, 32.18945312, 26.37866211);
  path.cubicTo(33.39308017, 24.92200721, 34.59879995, 23.46707893, 35.80664062, 22.01391602);
  path.cubicTo(38.79795424, 18.40129848, 41.72495943, 14.76156316, 44.54296875, 11.01171875);
  path.cubicTo(45.07365967, 10.31530273, 45.60435059, 9.61888672, 46.15112305, 8.90136719);
  path.cubicTo(47.15154686, 7.58188242, 48.13700915, 6.25087532, 49.10473633, 4.90722656);
  path.cubicTo(50.46875, 3.12109375, 50.46875, 3.12109375, 53.1875, 0.4375);
  path.cubicTo(56.53125, 0.03515625, 56.53125, 0.03515625, 59.1875, 0.4375);
  path.cubicTo(55.28636777, 6.46316776, 51.14909422, 12.1920916, 46.6875, 17.8125);
  path.cubicTo(41.65674185, 24.21142496, 36.74501123, 30.68171305, 31.9375, 37.25);
  path.cubicTo(26.92649633, 44.09229025, 21.83220953, 50.85072902, 16.63964844, 57.55664062);
  path.cubicTo(7.65029894, 69.1998734, -1.21844609, 80.92824073, -9.91357422, 92.79272461);
  path.cubicTo(-14.77837755, 99.42121354, -19.75899898, 105.95178555, -24.8125, 112.4375);
  path.cubicTo(-21.1593015, 108.87645426, -17.77643077, 105.16233045, -14.5, 101.25);
  path.cubicTo(-14.01635986, 100.67540039, -13.53271973, 100.10080078, -13.03442383, 99.50878906);
  path.cubicTo(-9.66027188, 95.48599852, -6.36350842, 91.40731617, -3.1015625, 87.29296875);
  path.cubicTo(1.72518555, 81.27188885, 6.66646189, 75.34335415, 11.57763672, 69.39111328);
  path.cubicTo(13.62068889, 66.91181339, 15.655212, 64.4256283, 17.6875, 61.9375);
  path.cubicTo(22.1214688, 56.51085162, 26.57863538, 51.10343719, 31.03515625, 45.6953125);
  path.cubicTo(34.25944724, 41.78159428, 37.47906584, 37.86424032, 40.6875, 33.9375);
  path.cubicTo(43.29602343, 30.74497879, 45.910428, 27.55742672, 48.53125, 24.375);
  path.cubicTo(49.12881104, 23.64917725, 49.72637207, 22.92335449, 50.34204102, 22.17553711);
  path.cubicTo(51.56454402, 20.69297526, 52.78896781, 19.21199501, 54.01538086, 17.73266602);
  path.cubicTo(56.69778421, 14.49223512, 59.35793546, 11.24666622, 61.91015625, 7.90234375);
  path.cubicTo(62.68230469, 6.90332031, 63.45445312, 5.90429688, 64.25, 4.875);
  path.cubicTo(65.22646484, 3.57369141, 65.22646484, 3.57369141, 66.22265625, 2.24609375);
  path.cubicTo(68.1875, 0.4375, 68.1875, 0.4375, 70.93359375, 0.16015625);
  path.cubicTo(71.67738281, 0.25167969, 72.42117188, 0.34320313, 73.1875, 0.4375);
  path.cubicTo(70.46670078, 5.47033986, 67.46190327, 9.79535154, 63.8125, 14.1875);
  path.cubicTo(59.05209267, 20.0225986, 54.50576298, 25.98269168, 50.0625, 32.0625);
  path.cubicTo(45.42917049, 38.39763891, 40.74367935, 44.67355956, 35.9375, 50.87890625);
  path.cubicTo(27.11331211, 62.27347311, 18.40746679, 73.76259335, 9.78808594, 85.31274414);
  path.cubicTo(6.87208498, 89.21346534, 3.92645885, 93.0898823, 0.9609375, 96.953125);
  path.cubicTo(0.23261719, 97.90316406, -0.49570312, 98.85320312, -1.24609375, 99.83203125);
  path.cubicTo(-2.68073687, 101.70141471, -4.11813375, 103.56868882, -5.55859375, 105.43359375);
  path.cubicTo(-6.21214844, 106.28566406, -6.86570312, 107.13773437, -7.5390625, 108.015625);
  path.cubicTo(-8.12252441, 108.77262695, -8.70598633, 109.52962891, -9.30712891, 110.30957031);
  path.cubicTo(-10.70954683, 112.2919697, -11.79680103, 114.23650714, -12.8125, 116.4375);
  path.cubicTo(-6.06353301, 108.50273321, 0.61488978, 100.51955235, 7.1875, 92.4375);
  path.cubicTo(14.21906692, 83.82416283, 21.28595085, 75.2401606, 28.35693359, 66.65917969);
  path.cubicTo(31.30117588, 63.0858795, 34.2442964, 59.51165572, 37.1875, 55.9375);
  path.cubicTo(38.35416096, 54.52082863, 39.52082763, 53.10416197, 40.6875, 51.6875);
  path.cubicTo(41.265, 50.98625, 41.8425, 50.285, 42.4375, 49.5625);
  path.cubicTo(44.1875, 47.4375, 45.9375, 45.3125, 47.6875, 43.1875);
  path.cubicTo(48.2652417, 42.48592773, 48.8429834, 41.78435547, 49.43823242, 41.06152344);
  path.cubicTo(50.60234354, 39.64801797, 51.7665684, 38.23460616, 52.9309082, 36.82128906);
  path.cubicTo(55.88762504, 33.23202429, 58.84221204, 29.64104178, 61.79296875, 26.046875);
  path.cubicTo(68.85470852, 17.45001605, 75.97144392, 8.90532091, 83.1875, 0.4375);
  path.cubicTo(85.1675, 0.9325, 85.1675, 0.9325, 87.1875, 1.4375);
  path.cubicTo(80.31294358, 10.86988403, 73.39330218, 20.25465832, 66.1875, 29.4375);
  path.cubicTo(60.70593058, 36.42461427, 55.39916427, 43.5236971, 50.15185547, 50.68798828);
  path.cubicTo(45.73403864, 56.71454088, 41.21465401, 62.64826856, 36.63964844, 68.55664062);
  path.cubicTo(27.67001338, 80.17433876, 18.82591106, 91.878977, 10.15673828, 103.72241211);
  path.cubicTo(4.99236082, 110.75473996, -0.36523651, 117.62286221, -5.8125, 124.4375);
  path.cubicTo(-1.98801148, 120.71089601, 1.54105729, 116.81629335, 5.0, 112.75);
  path.cubicTo(5.53061035, 112.12843018, 6.0612207, 111.50686035, 6.60791016, 110.86645508);
  path.cubicTo(10.12957826, 106.72466948, 13.56221261, 102.52306713, 16.93359375, 98.2578125);
  path.cubicTo(19.95840949, 94.47286109, 23.04142439, 90.73713747, 26.125, 87.0);
  path.cubicTo(26.73843262, 86.25645264, 27.35186523, 85.51290527, 27.98388672, 84.74682617);
  path.cubicTo(29.18177748, 83.2949005, 30.37969333, 81.84299553, 31.57763672, 80.39111328);
  path.cubicTo(33.62068889, 77.91181339, 35.655212, 75.4256283, 37.6875, 72.9375);
  path.cubicTo(42.1214688, 67.51085162, 46.57863538, 62.10343719, 51.03515625, 56.6953125);
  path.cubicTo(54.25944724, 52.78159428, 57.47906584, 48.86424032, 60.6875, 44.9375);
  path.cubicTo(68.11528191, 35.84842122, 75.59152681, 26.7989928, 83.05859375, 17.7421875);
  path.cubicTo(83.68741455, 16.97922363, 84.31623535, 16.21625977, 84.96411133, 15.43017578);
  path.cubicTo(86.16546021, 13.97256241, 87.36710399, 12.51519201, 88.5690918, 11.05810547);
  path.cubicTo(91.46916071, 7.53906471, 94.350569, 4.00788145, 97.1875, 0.4375);
  path.cubicTo(99.1675, 0.9325, 99.1675, 0.9325, 101.1875, 1.4375);
  path.cubicTo(93.30779955, 12.21798979, 85.33414442, 22.9188675, 77.22265625, 33.52612305);
  path.cubicTo(72.67777948, 39.47215473, 68.16942005, 45.44389151, 63.6875, 51.4375);
  path.cubicTo(58.53926809, 58.32215796, 53.34715759, 65.17126616, 48.125, 72.0);
  path.cubicTo(43.03392106, 78.65846277, 38.01209018, 85.36074577, 33.0625, 92.125);
  path.cubicTo(27.86826588, 99.22161867, 22.53765669, 106.19702885, 17.11621094, 113.12133789);
  path.cubicTo(12.38633029, 119.16364535, 7.75665014, 125.27277362, 3.1875, 131.4375);
  path.cubicTo(7.01199349, 127.71089117, 10.54101899, 123.81627024, 14.0, 119.75);
  path.cubicTo(14.79047729, 118.82417114, 14.79047729, 118.82417114, 15.59692383, 117.87963867);
  path.cubicTo(19.24077784, 113.59461774, 22.79474209, 109.24713576, 26.28515625, 104.8359375);
  path.cubicTo(32.74459088, 96.69200964, 39.42360488, 88.7188099, 46.03369141, 80.69702148);
  path.cubicTo(49.25851988, 76.78277392, 52.47859114, 72.86482129, 55.6875, 68.9375);
  path.cubicTo(60.1214688, 63.51085162, 64.57863538, 58.10343719, 69.03515625, 52.6953125);
  path.cubicTo(72.25944724, 48.78159428, 75.47906584, 44.86424032, 78.6875, 40.9375);
  path.cubicTo(83.11553353, 35.51811568, 87.56625679, 30.11754079, 92.01757812, 24.71728516);
  path.cubicTo(95.41797283, 20.59074523, 98.80838656, 16.45648034, 102.1875, 12.3125);
  path.cubicTo(105.46322286, 8.30203556, 108.79615294, 4.35059276, 112.1875, 0.4375);
  path.cubicTo(114.1675, 0.9325, 114.1675, 0.9325, 116.1875, 1.4375);
  path.cubicTo(115.5790625, 2.20449219, 114.970625, 2.97148437, 114.34375, 3.76171875);
  path.cubicTo(103.25712452, 17.78246771, 92.46027934, 32.02775576, 81.76147461, 46.34594727);
  path.cubicTo(77.64890876, 51.84246354, 73.48197208, 57.29658423, 69.3125, 62.75);
  path.cubicTo(64.15925903, 69.49200412, 59.07321521, 76.27645685, 54.0625, 83.125);
  path.cubicTo(48.98168992, 90.06781558, 43.76156906, 96.88352527, 38.45019531, 103.65112305);
  path.cubicTo(33.51800619, 109.95759563, 28.77172684, 116.39055071, 24.04638672, 122.8527832);
  path.cubicTo(19.90375136, 128.50480148, 15.65697845, 134.0380369, 11.1875, 139.4375);
  path.cubicTo(15.01198852, 135.71089601, 18.54105729, 131.81629335, 22.0, 127.75);
  path.cubicTo(22.53061035, 127.12843018, 23.0612207, 126.50686035, 23.60791016, 125.86645508);
  path.cubicTo(27.12957826, 121.72466948, 30.56221261, 117.52306713, 33.93359375, 113.2578125);
  path.cubicTo(36.95840949, 109.47286109, 40.04142439, 105.73713747, 43.125, 102.0);
  path.cubicTo(43.73843262, 101.25645264, 44.35186523, 100.51290527, 44.98388672, 99.74682617);
  path.cubicTo(46.18177748, 98.2949005, 47.37969333, 96.84299553, 48.57763672, 95.39111328);
  path.cubicTo(50.62068889, 92.91181339, 52.655212, 90.4256283, 54.6875, 87.9375);
  path.cubicTo(61.44615671, 79.66720288, 68.24762038, 71.43201918, 75.04003906, 63.18945312);
  path.cubicTo(83.37748395, 53.07474034, 83.37748395, 53.07474034, 91.6875, 42.9375);
  path.cubicTo(95.4061509, 38.38713606, 99.13879293, 33.84844741, 102.875, 29.3125);
  path.cubicTo(103.46313477, 28.59819824, 104.05126953, 27.88389648, 104.65722656, 27.14794922);
  path.cubicTo(107.81045574, 23.31927144, 110.96728781, 19.49362874, 114.12890625, 15.671875);
  path.cubicTo(114.76675049, 14.8998877, 115.40459473, 14.12790039, 116.06176758, 13.33251953);
  path.cubicTo(117.28830522, 11.84815835, 118.51596147, 10.3647206, 119.74487305, 8.88232422);
  path.cubicTo(120.29828369, 8.21217285, 120.85169434, 7.54202148, 121.421875, 6.8515625);
  path.cubicTo(122.15229004, 5.96911865, 122.15229004, 5.96911865, 122.89746094, 5.06884766);
  path.cubicTo(124.07205631, 3.58348689, 125.1370831, 2.01312535, 126.1875, 0.4375);
  path.cubicTo(129.3125, 0.25, 129.3125, 0.25, 132.1875, 0.4375);
  path.cubicTo(124.54481214, 10.6947916, 116.73095866, 20.80409863, 108.72241211, 30.77734375);
  path.cubicTo(105.33282499, 34.99983182, 101.96721303, 39.23991834, 98.625, 43.5);
  path.cubicTo(98.17374756, 44.07500244, 97.72249512, 44.65000488, 97.25756836, 45.24243164);
  path.cubicTo(95.00585634, 48.1136367, 92.75767465, 50.98757211, 90.51171875, 53.86328125);
  path.cubicTo(85.06925961, 60.8223618, 79.54211077, 67.70402826, 73.95361328, 74.54638672);
  path.cubicTo(69.7934375, 79.65491958, 65.77563392, 84.8543633, 61.78125, 90.09375);
  path.cubicTo(58.82538799, 93.93637061, 55.75637436, 97.68497212, 52.6875, 101.4375);
  path.cubicTo(48.76137237, 106.23926754, 44.88567104, 111.06740957, 41.125, 116.0);
  path.cubicTo(37.06407221, 121.32257526, 32.91114171, 126.56225401, 28.71850586, 131.78149414);
  path.cubicTo(25.34807615, 135.97957853, 22.00656085, 140.19870661, 18.6875, 144.4375);
  path.cubicTo(14.88321461, 149.2944574, 11.04752133, 154.12472392, 7.1875, 158.9375);
  path.cubicTo(3.30986504, 163.7734692, -0.54807846, 168.6237833, -4.375, 173.5);
  path.cubicTo(-4.82633301, 174.07508301, -5.27766602, 174.65016602, -5.74267578, 175.24267578);
  path.cubicTo(-7.99426335, 178.11383313, -10.24239571, 180.9876622, -12.48828125, 183.86328125);
  path.cubicTo(-17.93074039, 190.8223618, -23.45788923, 197.70402826, -29.04638672, 204.54638672);
  path.cubicTo(-33.2065625, 209.65491958, -37.22436608, 214.8543633, -41.21875, 220.09375);
  path.cubicTo(-44.17461201, 223.93637061, -47.24362564, 227.68497212, -50.3125, 231.4375);
  path.cubicTo(-54.23862763, 236.23926754, -58.11432896, 241.06740957, -61.875, 246.0);
  path.cubicTo(-65.93592779, 251.32257526, -70.08885829, 256.56225401, -74.28149414, 261.78149414);
  path.cubicTo(-77.65192493, 265.97957988, -80.99334045, 270.19878279, -84.3125, 274.4375);
  path.cubicTo(-88.24612133, 279.45739333, -92.20529245, 284.45604878, -96.1875, 289.4375);
  path.cubicTo(-96.91936523, 290.35402344, -96.91936523, 290.35402344, -97.66601562, 291.2890625);
  path.cubicTo(-98.13458984, 291.87429688, -98.60316406, 292.45953125, -99.0859375, 293.0625);
  path.cubicTo(-99.49247559, 293.57039063, -99.89901367, 294.07828125, -100.31787109, 294.6015625);
  path.cubicTo(-100.81109863, 295.20742188, -101.30432617, 295.81328125, -101.8125, 296.4375);
  path.cubicTo(-102.50136795, 297.45131744, -103.1902359, 298.46513489, -103.89997864, 299.50967407);
  path.cubicTo(-106.20943647, 302.25600872, -106.7352561, 302.42249491, -110.52680969, 303.1590271);
  path.cubicTo(-111.98698977, 303.17631033, -113.44779395, 303.16070404, -114.9074707, 303.11865234);
  path.cubicTo(-115.70799362, 303.1195285, -116.50851654, 303.12040466, -117.33329773, 303.12130737);
  path.cubicTo(-119.96929819, 303.11713973, -122.6027276, 303.07053106, -125.23828125, 303.0234375);
  path.cubicTo(-127.0695812, 303.01224232, -128.90089915, 303.00370366, -130.73222351, 302.99771118);
  path.cubicTo(-135.54462585, 302.97483797, -140.35593596, 302.91592813, -145.16790771, 302.8494873);
  path.cubicTo(-150.08118922, 302.78803199, -154.99464779, 302.76068925, -159.90820312, 302.73046875);
  path.cubicTo(-169.54344778, 302.66618313, -179.17788295, 302.56382214, -188.8125, 302.4375);
  path.cubicTo(-189.04574245, 294.18743422, -189.22264033, 285.93877852, -189.33062172, 277.6862154);
  path.cubicTo(-189.38248927, 273.85268312, -189.45264429, 270.02142969, -189.56689453, 266.18920898);
  path.cubicTo(-189.67676152, 262.48016222, -189.73558404, 258.77328465, -189.76127243, 255.0627346);
  path.cubicTo(-189.77953967, 253.65805121, -189.8152089, 252.25346675, -189.86980057, 250.84972572);
  path.cubicTo(-190.32021893, 238.77087219, -186.60065155, 232.9531806, -178.8125, 224.4375);
  path.cubicTo(-177.79973589, 223.16865286, -176.79787026, 221.89086644, -175.81640625, 220.59765625);
  path.cubicTo(-175.01074219, 219.57542969, -174.20507812, 218.55320312, -173.375, 217.5);
  path.cubicTo(-172.44919976, 216.3242337, -171.52341909, 215.14845199, -170.59765625, 213.97265625);
  path.cubicTo(-170.13762207, 213.38887207, -169.67758789, 212.80508789, -169.20361328, 212.20361328);
  path.cubicTo(-167.36222891, 209.86585011, -165.52376001, 207.52580399, -163.68554688, 205.18554688);
  path.cubicTo(-162.31024115, 203.43462423, -160.93441723, 201.68410958, -159.55859375, 199.93359375);
  path.cubicTo(-157.73646622, 197.61469876, -155.91631206, 195.29427485, -154.09765625, 192.97265625);
  path.cubicTo(-149.90249658, 187.62054902, -145.6942142, 182.28107675, -141.43164062, 176.98242188);
  path.cubicTo(-136.66013582, 171.05078649, -131.97710272, 165.06415005, -127.375, 159.0);
  path.cubicTo(-122.60251572, 152.71288217, -117.69421826, 146.55908029, -112.68774414, 140.45727539);
  path.cubicTo(-108.79333875, 135.69237651, -105.02895701, 130.84212837, -101.3125, 125.9375);
  path.cubicTo(-96.49279249, 119.57714379, -91.53573168, 113.35088906, -86.47875977, 107.17797852);
  path.cubicTo(-83.16662406, 103.12724809, -79.92209928, 99.036221, -76.75, 94.875);
  path.cubicTo(-73.22965438, 90.25880486, -69.64216187, 85.70803089, -66.0, 81.1875);
  path.cubicTo(-61.70577995, 75.85460081, -57.51324039, 70.45469909, -53.375, 65.0);
  path.cubicTo(-48.60262595, 58.71280136, -43.69421485, 52.55907614, -38.68774414, 46.45727539);
  path.cubicTo(-34.23139837, 41.0048289, -29.95602921, 35.42821127, -25.70507812, 29.81494141);
  path.cubicTo(-21.33332473, 24.06409854, -16.81465602, 18.44514544, -12.21289062, 12.87695312);
  path.cubicTo(-9.70361764, 9.82791335, -7.33269821, 6.77178221, -5.11328125, 3.50390625);
  path.cubicTo(-2.8125, 0.4375, -2.8125, 0.4375, 0.0, 0.0);
  path.close();
  path.moveTo(-60.8125, 84.4375);
  path.cubicTo(-61.4725, 85.7575, -62.1325, 87.0775, -62.8125, 88.4375);
  path.cubicTo(-61.8225, 87.7775, -60.8325, 87.1175, -59.8125, 86.4375);
  path.cubicTo(-60.1425, 85.7775, -60.4725, 85.1175, -60.8125, 84.4375);
  path.close();
  path.moveTo(-64.8125, 89.4375);
  path.cubicTo(-64.8125, 92.4375, -64.8125, 92.4375, -64.8125, 92.4375);
  path.close();
  path.moveTo(-51.8125, 91.4375);
  path.cubicTo(-52.4725, 92.7575, -53.1325, 94.0775, -53.8125, 95.4375);
  path.cubicTo(-52.8225, 94.7775, -51.8325, 94.1175, -50.8125, 93.4375);
  path.cubicTo(-51.1425, 92.7775, -51.4725, 92.1175, -51.8125, 91.4375);
  path.close();
  path.moveTo(-56.8125, 97.4375);
  path.cubicTo(-55.8125, 99.4375, -55.8125, 99.4375, -55.8125, 99.4375);
  path.close();
  path.moveTo(-44.8125, 100.4375);
  path.cubicTo(-45.4725, 101.7575, -46.1325, 103.0775, -46.8125, 104.4375);
  path.cubicTo(-45.8225, 103.7775, -44.8325, 103.1175, -43.8125, 102.4375);
  path.cubicTo(-44.1425, 101.7775, -44.4725, 101.1175, -44.8125, 100.4375);
  path.close();
  path.moveTo(-49.8125, 106.4375);
  path.cubicTo(-48.8125, 108.4375, -48.8125, 108.4375, -48.8125, 108.4375);
  path.close();
  path.moveTo(-35.8125, 107.4375);
  path.cubicTo(-36.4725, 108.7575, -37.1325, 110.0775, -37.8125, 111.4375);
  path.cubicTo(-36.8225, 110.7775, -35.8325, 110.1175, -34.8125, 109.4375);
  path.cubicTo(-35.1425, 108.7775, -35.4725, 108.1175, -35.8125, 107.4375);
  path.close();
  path.moveTo(-40.8125, 113.4375);
  path.cubicTo(-39.8125, 115.4375, -39.8125, 115.4375, -39.8125, 115.4375);
  path.close();
  path.moveTo(-27.8125, 115.4375);
  path.cubicTo(-27.8125, 118.4375, -27.8125, 118.4375, -27.8125, 118.4375);
  path.close();
  path.moveTo(-15.8125, 118.4375);
  path.cubicTo(-16.4725, 119.7575, -17.1325, 121.0775, -17.8125, 122.4375);
  path.cubicTo(-16.8225, 121.7775, -15.8325, 121.1175, -14.8125, 120.4375);
  path.cubicTo(-15.1425, 119.7775, -15.4725, 119.1175, -15.8125, 118.4375);
  path.close();
  path.moveTo(-31.8125, 120.4375);
  path.cubicTo(-31.8125, 123.4375, -31.8125, 123.4375, -31.8125, 123.4375);
  path.close();
  path.moveTo(-19.8125, 123.4375);
  path.cubicTo(-19.8125, 126.4375, -19.8125, 126.4375, -19.8125, 126.4375);
  path.close();
  path.moveTo(-7.8125, 126.4375);
  path.cubicTo(-8.4725, 127.7575, -9.1325, 129.0775, -9.8125, 130.4375);
  path.cubicTo(-8.8225, 129.7775, -7.8325, 129.1175, -6.8125, 128.4375);
  path.cubicTo(-7.1425, 127.7775, -7.4725, 127.1175, -7.8125, 126.4375);
  path.close();
  path.moveTo(-11.8125, 131.4375);
  path.cubicTo(-11.8125, 134.4375, -11.8125, 134.4375, -11.8125, 134.4375);
  path.close();
  path.moveTo(1.1875, 133.4375);
  path.cubicTo(0.5275, 134.7575, -0.1325, 136.0775, -0.8125, 137.4375);
  path.cubicTo(0.1775, 136.7775, 1.1675, 136.1175, 2.1875, 135.4375);
  path.cubicTo(1.8575, 134.7775, 1.5275, 134.1175, 1.1875, 133.4375);
  path.close();
  path.moveTo(-2.8125, 138.4375);
  path.cubicTo(-2.8125, 141.4375, -2.8125, 141.4375, -2.8125, 141.4375);
  path.close();
  path.moveTo(9.1875, 141.4375);
  path.cubicTo(8.5275, 142.7575, 7.8675, 144.0775, 7.1875, 145.4375);
  path.cubicTo(8.1775, 144.7775, 9.1675, 144.1175, 10.1875, 143.4375);
  path.cubicTo(9.8575, 142.7775, 9.5275, 142.1175, 9.1875, 141.4375);
  path.close();
  path.moveTo(5.1875, 146.4375);
  path.cubicTo(5.1875, 149.4375, 5.1875, 149.4375, 5.1875, 149.4375);
  path.close();
  return path;
}

// Path 5
Path buildPath5() {
  final Path path = Path();
  path.moveTo(0.0, 0.0);
  path.cubicTo(105.93, 0.0, 211.86, 0.0, 321.0, 0.0);
  path.cubicTo(321.0, 29.7, 321.0, 59.4, 321.0, 90.0);
  path.cubicTo(215.07, 90.0, 109.14, 90.0, 0.0, 90.0);
  path.cubicTo(0.0, 89.34, 0.0, 88.68, 0.0, 88.0);
  path.cubicTo(16.08366365, 87.2098958, 32.16679315, 86.81445317, 48.265625, 86.5);
  path.cubicTo(49.30924698, 86.47946564, 50.35286896, 86.45893127, 51.42811584, 86.43777466);
  path.cubicTo(61.27879468, 86.24457325, 71.12959125, 86.05777403, 80.98046875, 85.875);
  path.cubicTo(86.4169249, 85.7738816, 91.85328294, 85.66841943, 97.28960419, 85.56030273);
  path.cubicTo(99.34526085, 85.52032825, 101.40095144, 85.48205978, 103.45667267, 85.44555664);
  path.cubicTo(106.31007716, 85.39485217, 109.16332527, 85.33866089, 112.01660156, 85.28125);
  path.cubicTo(112.85701996, 85.26771484, 113.69743835, 85.25417969, 114.56332397, 85.24023438);
  path.cubicTo(118.49392694, 85.15562546, 122.16176107, 84.95517901, 126.0, 84.0);
  path.cubicTo(124.76068222, 83.97716446, 123.52136444, 83.95432892, 122.24449158, 83.93080139);
  path.cubicTo(110.46396503, 83.71335789, 98.68349889, 83.49286144, 86.90308285, 83.26950932);
  path.cubicTo(80.84923356, 83.15482522, 74.79536908, 83.04115164, 68.74145508, 82.92993164);
  path.cubicTo(62.87989542, 82.82220589, 57.01839518, 82.7116376, 51.15692329, 82.59924126);
  path.cubicTo(48.94029125, 82.55720855, 46.72364076, 82.51613558, 44.50697136, 82.4761219);
  path.cubicTo(29.65849917, 82.20724874, 14.83367147, 81.71921685, 0.0, 81.0);
  path.cubicTo(0.0, 79.68, 0.0, 78.36, 0.0, 77.0);
  path.cubicTo(11.46069329, 75.96528922, 22.90488857, 75.7422481, 34.40437889, 75.55444336);
  path.cubicTo(37.79849264, 75.49888655, 41.1924921, 75.43850743, 44.58650208, 75.37695312);
  path.cubicTo(53.00767122, 75.22516292, 61.42897024, 75.08119736, 69.85028076, 74.9375);
  path.cubicTo(76.99177613, 74.81539258, 84.13319983, 74.69003288, 91.27456093, 74.56030273);
  path.cubicTo(94.60179223, 74.50117599, 97.92907891, 74.44678549, 101.25639343, 74.39257812);
  path.cubicTo(103.31310448, 74.35570783, 105.36981147, 74.31861028, 107.42651367, 74.28125);
  path.cubicTo(108.33744781, 74.26771484, 109.24838196, 74.25417969, 110.18692017, 74.24023438);
  path.cubicTo(116.49299699, 74.11876221, 122.72638418, 73.64404286, 129.0, 73.0);
  path.cubicTo(127.87058487, 72.97716446, 126.74116974, 72.95432892, 125.57752991, 72.93080139);
  path.cubicTo(114.77140591, 72.71209452, 103.96531942, 72.49160672, 93.15926456, 72.26950932);
  path.cubicTo(87.60790227, 72.15546552, 82.05652984, 72.04198364, 76.50512695, 71.92993164);
  path.cubicTo(50.99883998, 71.41467808, 25.49744572, 70.854946, 0.0, 70.0);
  path.cubicTo(0.0, 68.68, 0.0, 67.36, 0.0, 66.0);
  path.cubicTo(12.42873607, 65.09130987, 24.83184785, 64.7322068, 37.2890625, 64.5);
  path.cubicTo(39.32425633, 64.4593362, 41.359443, 64.41831267, 43.3946228, 64.37695312);
  path.cubicTo(48.72581765, 64.26930113, 54.05707656, 64.1653125, 59.3883667, 64.0625);
  path.cubicTo(67.86545516, 63.89880582, 76.34246038, 63.73110548, 84.81940842, 63.56030273);
  path.cubicTo(87.72199126, 63.50257688, 90.62461377, 63.44742574, 93.5272522, 63.39257812);
  path.cubicTo(109.36099757, 63.07781355, 125.16683037, 62.52777232, 141.0, 62.0);
  path.cubicTo(71.205, 60.515, 71.205, 60.515, 0.0, 59.0);
  path.cubicTo(0.0, 57.68, 0.0, 56.36, 0.0, 55.0);
  path.cubicTo(3.16321355, 53.94559548, 5.50252983, 53.83241237, 8.82756042, 53.76585388);
  path.cubicTo(10.64740967, 53.72600325, 10.64740967, 53.72600325, 12.50402355, 53.68534756);
  path.cubicTo(13.85578959, 53.66051089, 15.20755719, 53.63575959, 16.55932617, 53.61108398);
  path.cubicTo(18.00147222, 53.58132643, 19.44360982, 53.55115685, 20.88573933, 53.52060795);
  path.cubicTo(24.75159363, 53.43985746, 28.61753847, 53.36475496, 32.48352814, 53.29080963);
  path.cubicTo(36.10973344, 53.22059827, 39.73582635, 53.14531027, 43.36193848, 53.07043457);
  path.cubicTo(53.97035615, 52.85434742, 64.57893883, 52.64642383, 75.1875, 52.4375);
  path.cubicTo(98.885625, 51.963125, 122.58375, 51.48875, 147.0, 51.0);
  path.cubicTo(74.235, 49.515, 74.235, 49.515, 0.0, 48.0);
  path.cubicTo(0.0, 46.68, 0.0, 45.36, 0.0, 44.0);
  path.cubicTo(4.0986668, 43.23873782, 8.02225326, 42.84946612, 12.18832397, 42.76585388);
  path.cubicTo(13.40821014, 42.73923676, 14.62809631, 42.71261963, 15.88494873, 42.68519592);
  path.cubicTo(17.22326509, 42.66041042, 18.56158302, 42.63570924, 19.89990234, 42.61108398);
  path.cubicTo(21.31949634, 42.58175612, 22.73908241, 42.55204229, 24.15866089, 42.52197266);
  path.cubicTo(28.0010865, 42.4416716, 31.8436003, 42.36675546, 35.68615294, 42.29281878);
  path.cubicTo(39.7060854, 42.21454864, 43.72591491, 42.13130832, 47.74575806, 42.04859924);
  path.cubicTo(55.35284022, 41.89283541, 62.96000423, 41.74152997, 70.56720793, 41.59183317);
  path.cubicTo(79.22988884, 41.42114871, 87.89246651, 41.24548349, 96.55503917, 41.06940353);
  path.cubicTo(114.36991704, 40.7074005, 132.18491472, 40.35164047, 150.0, 40.0);
  path.cubicTo(149.26946883, 39.9854606, 148.53893766, 39.97092119, 147.78626919, 39.9559412);
  path.cubicTo(130.00008873, 39.60165649, 112.21400966, 39.24263443, 94.42803097, 38.87835789);
  path.cubicTo(85.82682156, 38.70230954, 77.22558534, 38.52785696, 68.62426758, 38.35717773);
  path.cubicTo(61.12622176, 38.20838709, 53.62824395, 38.05658531, 46.13033205, 37.90118736);
  path.cubicTo(42.16130387, 37.81903195, 38.19225815, 37.73837117, 34.22312737, 37.66131783);
  path.cubicTo(30.48438874, 37.58868948, 26.74575429, 37.5120237, 23.00716019, 37.43231201);
  path.cubicTo(20.98680035, 37.39027207, 18.96635376, 37.35246746, 16.94590759, 37.31480408);
  path.cubicTo(11.21599092, 37.18905536, 5.64538899, 37.02113106, 0.0, 36.0);
  path.cubicTo(0.0, 34.68, 0.0, 33.36, 0.0, 32.0);
  path.cubicTo(67.815, 30.515, 67.815, 30.515, 137.0, 29.0);
  path.cubicTo(120.49690271, 28.20358044, 120.49690271, 28.20358044, 103.99145508, 27.71875);
  path.cubicTo(102.62790138, 27.69167969, 102.62790138, 27.69167969, 101.23680115, 27.6640625);
  path.cubicTo(99.31651487, 27.6262793, 97.3962037, 27.58974107, 95.47587013, 27.55444336);
  path.cubicTo(92.41498012, 27.49807461, 89.35418231, 27.43792675, 86.29338074, 27.37695312);
  path.cubicTo(78.70374038, 27.22645421, 71.11399213, 27.08175829, 63.52423096, 26.9375);
  path.cubicTo(57.06792615, 26.81461648, 50.61168146, 26.68914787, 44.15549278, 26.56030273);
  path.cubicTo(41.17872047, 26.50189709, 38.20189662, 26.44714502, 35.22505188, 26.39257812);
  path.cubicTo(23.46609938, 26.16517988, 11.740415, 25.69878438, 0.0, 25.0);
  path.cubicTo(0.0, 23.68, 0.0, 22.36, 0.0, 21.0);
  path.cubicTo(25.15646708, 19.99278969, 50.32269432, 19.50807968, 75.4932251, 19.00421143);
  path.cubicTo(81.09251921, 18.89167574, 86.6917649, 18.77677967, 92.29101562, 18.66210938);
  path.cubicTo(103.19396545, 18.43915593, 114.09696463, 18.21872726, 125.0, 18.0);
  path.cubicTo(122.28217543, 17.09405848, 120.6139272, 16.85793059, 117.81211853, 16.81054688);
  path.cubicTo(116.95893539, 16.79378906, 116.10575226, 16.77703125, 115.22671509, 16.75976562);
  path.cubicTo(114.29330292, 16.74623047, 113.35989075, 16.73269531, 112.39819336, 16.71875);
  path.cubicTo(110.91934914, 16.69167969, 110.91934914, 16.69167969, 109.41062927, 16.6640625);
  path.cubicTo(107.26465925, 16.62541738, 105.11864877, 16.58897188, 102.97260857, 16.55444336);
  path.cubicTo(99.56063584, 16.49952992, 96.14880443, 16.43896069, 92.73695374, 16.37695312);
  path.cubicTo(86.70228334, 16.26822077, 80.66753826, 16.16454636, 74.63275146, 16.0625);
  path.cubicTo(65.02771206, 15.90004422, 55.42275646, 15.73343683, 45.81790352, 15.56030273);
  path.cubicTo(42.48492229, 15.50145795, 39.15189059, 15.44686066, 35.8188324, 15.39257812);
  path.cubicTo(23.85769096, 15.18639948, 11.93799815, 14.77983683, 0.0, 14.0);
  path.cubicTo(0.0, 12.68, 0.0, 11.36, 0.0, 10.0);
  path.cubicTo(12.33328423, 9.68555228, 24.66661931, 9.37314084, 37.0, 9.0625);
  path.cubicTo(38.36363678, 9.02815228, 38.36363678, 9.02815228, 39.75482178, 8.99311066);
  path.cubicTo(69.16849306, 8.25287367, 98.58232649, 7.56325869, 128.0, 7.0);
  path.cubicTo(124.10622787, 5.70207596, 120.36949759, 5.78410502, 116.30712891, 5.71875);
  path.cubicTo(114.97183136, 5.69167969, 114.97183136, 5.69167969, 113.60955811, 5.6640625);
  path.cubicTo(110.64862652, 5.60505814, 107.6876139, 5.55261699, 104.7265625, 5.5);
  path.cubicTo(102.64797052, 5.45945437, 100.5693878, 5.41843084, 98.49081421, 5.37695312);
  path.cubicTo(92.9880879, 5.26815151, 87.48527623, 5.16459673, 81.98242188, 5.0625);
  path.cubicTo(72.23035415, 4.88096064, 62.47843775, 4.6915674, 52.7265625, 4.5);
  path.cubicTo(51.16387508, 4.469561, 51.16387508, 4.469561, 49.56961823, 4.43850708);
  path.cubicTo(33.03962292, 4.1142004, 16.5199811, 3.66911477, 0.0, 3.0);
  path.cubicTo(0.0, 2.01, 0.0, 1.02, 0.0, 0.0);
  path.close();
  return path;
}

// Path 6
Path buildPath6() {
  final Path path = Path();
  path.moveTo(0.0, 0.0);
  path.cubicTo(51.81, 0.0, 103.62, 0.0, 157.0, 0.0);
  path.cubicTo(157.0, 29.37, 157.0, 58.74, 157.0, 89.0);
  path.cubicTo(83.08, 89.0, 9.16, 89.0, -67.0, 89.0);
  path.cubicTo(-66.34, 87.68, -65.68, 86.36, -65.0, 85.0);
  path.cubicTo(-60.40204002, 83.70517712, -55.63457496, 83.8318405, -50.88330078, 83.79467773);
  path.cubicTo(-50.09238541, 83.78477814, -49.30147003, 83.77487854, -48.48658752, 83.76467896);
  path.cubicTo(-45.88952561, 83.73325812, -43.29244545, 83.70838386, -40.6953125, 83.68359375);
  path.cubicTo(-38.88784325, 83.66300743, -37.08037863, 83.64201052, -35.2729187, 83.62062073);
  path.cubicTo(-30.52848068, 83.56557335, -25.78400047, 83.51608801, -21.03948975, 83.46777344);
  path.cubicTo(-16.19295521, 83.41743143, -11.34648154, 83.36181181, -6.5, 83.30664062);
  path.cubicTo(2.99994794, 83.19927123, 12.49994885, 83.09777961, 22.0, 83.0);
  path.cubicTo(-9.7483927, 81.40469488, -9.7483927, 81.40469488, -41.5, 79.875);
  path.cubicTo(-43.3411481, 79.78780835, -45.18229392, 79.70056846, -47.0234375, 79.61328125);
  path.cubicTo(-51.3489328, 79.40831042, -55.67445638, 79.20394846, -60.0, 79.0);
  path.cubicTo(-59.34, 77.68, -58.68, 76.36, -58.0, 75.0);
  path.cubicTo(-56.79755394, 74.96574669, -56.79755394, 74.96574669, -55.57081604, 74.93080139);
  path.cubicTo(-47.93835548, 74.71292198, -40.30597269, 74.49254567, -32.67366123, 74.26950932);
  path.cubicTo(-28.75179733, 74.15498631, -24.82991215, 74.04135898, -20.90795898, 73.92993164);
  path.cubicTo(-17.10827443, 73.82194256, -13.30867124, 73.71140109, -9.50910759, 73.59924126);
  path.cubicTo(-8.07460993, 73.5573159, -6.64008708, 73.51624173, -5.2055378, 73.4761219);
  path.cubicTo(5.21158373, 73.1839696, 15.60030022, 72.66110968, 26.0, 72.0);
  path.cubicTo(25.30303513, 71.97716446, 24.60607025, 71.95432892, 23.88798523, 71.93080139);
  path.cubicTo(17.22742655, 71.71223652, 10.56693131, 71.49183355, 3.906497, 71.26950932);
  path.cubicTo(0.4846521, 71.15534972, -2.93721125, 71.04183161, -6.35913086, 70.92993164);
  path.cubicTo(-21.58181337, 70.43167154, -36.7949254, 69.89626104, -52.0, 69.0);
  path.cubicTo(-51.30072021, 67.04492188, -51.30072021, 67.04492188, -50.0, 65.0);
  path.cubicTo(-47.85601807, 64.40820312, -47.85601807, 64.40820312, -45.18847656, 64.28125);
  path.cubicTo(-44.19690552, 64.22582031, -43.20533447, 64.17039062, -42.18371582, 64.11328125);
  path.cubicTo(-40.60777649, 64.05720703, -40.60777649, 64.05720703, -39.0, 64.0);
  path.cubicTo(-37.47288391, 63.92845703, -37.47288391, 63.92845703, -35.91491699, 63.85546875);
  path.cubicTo(-32.60518205, 63.71218464, -29.29560902, 63.60269744, -25.984375, 63.5);
  path.cubicTo(-24.77033997, 63.45939453, -23.55630493, 63.41878906, -22.30548096, 63.37695312);
  path.cubicTo(-18.45374526, 63.24832488, -14.60189561, 63.12374015, -10.75, 63.0);
  path.cubicTo(11.14186025, 62.33017201, 11.14186025, 62.33017201, 33.0, 61.0);
  path.cubicTo(32.2985939, 60.97716446, 31.59718781, 60.95432892, 30.87452698, 60.93080139);
  path.cubicTo(24.1839016, 60.7125785, 17.4933513, 60.4921877, 10.80287266, 60.26950932);
  path.cubicTo(7.36528166, 60.15516897, 3.92766929, 60.04159567, 0.48999023, 59.92993164);
  path.cubicTo(-28.70681573, 58.98050373, -28.70681573, 58.98050373, -43.0, 58.0);
  path.cubicTo(-42.1875, 56.0625, -42.1875, 56.0625, -41.0, 54.0);
  path.cubicTo(-37.96364151, 52.9878805, -35.740325, 52.81699097, -32.55737305, 52.71875);
  path.cubicTo(-31.44158371, 52.68201172, -30.32579437, 52.64527344, -29.17619324, 52.60742188);
  path.cubicTo(-27.96691666, 52.57197266, -26.75764008, 52.53652344, -25.51171875, 52.5);
  path.cubicTo(-24.26179642, 52.45939453, -23.01187408, 52.41878906, -21.72407532, 52.37695312);
  path.cubicTo(-18.39061556, 52.26903261, -15.05708739, 52.16468352, -11.72344971, 52.0625);
  path.cubicTo(-7.0717657, 51.91970165, -2.42020556, 51.77321309, 2.23124695, 51.62304688);
  path.cubicTo(4.70333598, 51.54340815, 7.17551212, 51.4664107, 9.64778137, 51.39257812);
  path.cubicTo(17.78370417, 51.13276986, 25.88489271, 50.63470812, 34.0, 50.0);
  path.cubicTo(33.34204437, 49.97716446, 32.68408875, 49.95432892, 32.00619507, 49.93080139);
  path.cubicTo(25.09418953, 49.69040356, 18.18231702, 49.44641598, 11.27050781, 49.20043945);
  path.cubicTo(8.69859948, 49.10936849, 6.12665968, 49.01918144, 3.5546875, 48.92993164);
  path.cubicTo(-0.16415094, 48.8007251, -3.8828607, 48.66823097, -7.6015625, 48.53515625);
  path.cubicTo(-9.2977623, 48.47727684, -9.2977623, 48.47727684, -11.02822876, 48.41822815);
  path.cubicTo(-19.0344995, 48.12736089, -27.01239461, 47.61625819, -35.0, 47.0);
  path.cubicTo(-33.125, 43.125, -33.125, 43.125, -32.0, 42.0);
  path.cubicTo(-29.73216075, 41.81636372, -27.4587962, 41.70077584, -25.18530273, 41.61108398);
  path.cubicTo(-24.47314606, 41.58167725, -23.76098938, 41.55227051, -23.0272522, 41.52197266);
  path.cubicTo(-20.66285782, 41.42547617, -18.29825573, 41.3357729, -15.93359375, 41.24609375);
  path.cubicTo(-14.29832822, 41.18067863, -12.6630795, 41.11484201, -11.02784729, 41.04859924);
  path.cubicTo(-6.71582692, 40.87506093, -2.40360098, 40.70727247, 1.90869141, 40.54064941);
  path.cubicTo(6.30580154, 40.36974058, 10.70269495, 40.19343768, 15.09960938, 40.01757812);
  path.cubicTo(23.73286913, 39.67308273, 32.36635329, 39.33465668, 41.0, 39.0);
  path.cubicTo(40.35235184, 38.97716446, 39.70470367, 38.95432892, 39.03742981, 38.93080139);
  path.cubicTo(32.23910956, 38.69056741, 25.44093209, 38.44655455, 18.64282227, 38.20043945);
  path.cubicTo(16.1125829, 38.10931923, 13.58230972, 38.01913226, 11.05200195, 37.92993164);
  path.cubicTo(7.39525005, 37.80085284, 3.73863667, 37.66831292, 0.08203125, 37.53515625);
  path.cubicTo(-1.03205612, 37.49656998, -2.14614349, 37.4579837, -3.29399109, 37.41822815);
  path.cubicTo(-10.88117993, 37.13749626, -18.43435007, 36.63454276, -26.0, 36.0);
  path.cubicTo(-24.125, 32.125, -24.125, 32.125, -23.0, 31.0);
  path.cubicTo(-20.47247652, 30.77929909, -17.96654414, 30.6196014, -15.43359375, 30.5);
  path.cubicTo(-14.64847916, 30.45939453, -13.86336456, 30.41878906, -13.05445862, 30.37695312);
  path.cubicTo(-10.51567395, 30.24690092, -7.9766112, 30.12349434, -5.4375, 30.0);
  path.cubicTo(-3.81443231, 29.91707308, -2.19138513, 29.83374375, -0.56835938, 29.75);
  path.cubicTo(12.61864451, 29.0836216, 25.80666169, 28.54972243, 39.0, 28.0);
  path.cubicTo(10.785, 26.515, 10.785, 26.515, -18.0, 25.0);
  path.cubicTo(-16.0, 21.0, -16.0, 21.0, -14.0, 19.0);
  path.cubicTo(-11.78536987, 18.68356323, -11.78536987, 18.68356323, -8.99951172, 18.58935547);
  path.cubicTo(-7.95858368, 18.54946503, -6.91765564, 18.50957458, -5.84518433, 18.46847534);
  path.cubicTo(-4.71807037, 18.43505035, -3.59095642, 18.40162537, -2.4296875, 18.3671875);
  path.cubicTo(-1.27832306, 18.32562531, -0.12695862, 18.28406311, 1.05929565, 18.24124146);
  path.cubicTo(4.74761449, 18.11017333, 8.43622468, 17.99244639, 12.125, 17.875);
  path.cubicTo(14.62112422, 17.78863675, 17.11721868, 17.70140841, 19.61328125, 17.61328125);
  path.cubicTo(25.74187698, 17.39880353, 31.87076436, 17.19528609, 38.0, 17.0);
  path.cubicTo(31.64693389, 16.32024444, 25.31042151, 15.78977872, 18.9296875, 15.46484375);
  path.cubicTo(18.12258331, 15.42186661, 17.31547913, 15.37888947, 16.48391724, 15.33460999);
  path.cubicTo(13.94772103, 15.20005622, 11.41137082, 15.06871659, 8.875, 14.9375);
  path.cubicTo(7.13800952, 14.84591736, 5.40103024, 14.75412225, 3.6640625, 14.66210938);
  path.cubicTo(-0.55716661, 14.4389556, -4.7785369, 14.21868083, -9.0, 14.0);
  path.cubicTo(-7.125, 9.125, -7.125, 9.125, -6.0, 8.0);
  path.cubicTo(-2.90074403, 7.76798951, 0.18113659, 7.59595228, 3.28515625, 7.46484375);
  path.cubicTo(4.21597519, 7.42186661, 5.14679413, 7.37888947, 6.1058197, 7.33460999);
  path.cubicTo(9.09119735, 7.1977981, 12.07682229, 7.06758289, 15.0625, 6.9375);
  path.cubicTo(17.08139985, 6.84613609, 19.10028041, 6.75434489, 21.11914062, 6.66210938);
  path.cubicTo(26.07919885, 6.43563201, 31.03953612, 6.21806563, 36.0, 6.0);
  path.cubicTo(23.46, 5.34, 10.92, 4.68, -2.0, 4.0);
  path.cubicTo(-1.34, 2.68, -0.68, 1.36, 0.0, 0.0);
  path.close();
  return path;
}

class PathEx {
  final Path path = Path();
  double _x = 0;
  double _y = 0;

  Offset getCurrentPoint() => Offset(_x, _y);

  void moveTo(double x, double y) {
    path.moveTo(x, y);
    _x = x;
    _y = y;
  }

  void lineTo(double x, double y) {
    path.lineTo(x, y);
    _x = x;
    _y = y;
  }

  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) {
    path.cubicTo(x1, y1, x2, y2, x3, y3);
    _x = x3;
    _y = y3;
  }

  void quadraticBezierTo(double x1, double y1, double x2, double y2) {
    path.quadraticBezierTo(x1, y1, x2, y2);
    _x = x2;
    _y = y2;
  }

  void close() {
    path.close();
  }
}

PathEx buildPath7() {
  final PathEx path = PathEx();
  path.moveTo(5.14416, 15.9989);
  path.cubicTo(1.91223, 15.9989, 0.0, 13.614, 0.0, 8.4966);
  path.cubicTo(0.0, 3.24706, 2.47782, 0.535382, 5.70975, 0.535382);
  path.cubicTo(6.47018, 0.547533, 7.21801, 0.737841, 7.89684, 1.09195);
  path.cubicTo(8.57567, 1.44606, 9.16776, 1.95472, 9.62847, 2.57957);
  path.lineTo(8.61849, 3.60167);
  path.cubicTo(7.83755, 2.9018, 6.85047, 2.49506, 5.81748, 2.44746);
  path.cubicTo(3.75039, 2.44746, 2.41048, 4.33869, 2.41048, 8.07246);
  path.cubicTo(2.41048, 12.3903, 3.64266, 14.059, 5.53469, 14.059);
  path.cubicTo(6.23375, 14.0794, 6.91836, 13.8511, 7.47385, 13.4124);
  path.lineTo(path.getCurrentPoint().dx, 9.16409);
  path.lineTo(5.58855, path.getCurrentPoint().dy);
  path.lineTo(path.getCurrentPoint().dx, 7.38411);
  path.lineTo(9.79007, path.getCurrentPoint().dy);
  path.lineTo(path.getCurrentPoint().dx, 14.2328);
  path.cubicTo(8.50925, 15.3998, 6.852, 16.0298, 5.14416, 15.9989);
  path.close();
  path.moveTo(17.7756, 6.78615);
  path.cubicTo(17.4801, 6.69458, 17.1749, 6.64087, 16.8667, 6.62623);
  path.cubicTo(16.2405, 6.62623, 15.6614, 7.1199, 14.6043, 8.47574);
  path.lineTo(path.getCurrentPoint().dx, 15.7764);
  path.lineTo(12.3891, path.getCurrentPoint().dy);
  path.lineTo(path.getCurrentPoint().dx, 4.69329);
  path.lineTo(14.2205, path.getCurrentPoint().dy);
  path.lineTo(14.409, 6.58452);
  path.cubicTo(15.5739, 5.02704, 16.3078, 4.49861, 17.1023, 4.49861);
  path.cubicTo(17.4335, 4.50307, 17.759, 4.58887, 18.0517, 4.74892);
  path.lineTo(17.7756, 6.78615);
  path.close();
  path.moveTo(25.5929, 15.7764);
  path.lineTo(25.4178, 14.5735);
  path.cubicTo(24.5233, 15.4525, 23.3398, 15.9493, 22.1051, 15.9641);
  path.cubicTo(19.9909, 15.9641, 18.8731, 14.8517, 18.8731, 12.8909);
  path.cubicTo(18.8731, 10.6242, 20.5766, 9.10846, 24.3405, 9.10846);
  path.lineTo(25.1148, path.getCurrentPoint().dy);
  path.lineTo(path.getCurrentPoint().dx, 8.14199);
  path.cubicTo(25.1148, 6.80701, 24.4415, 6.16038, 22.8929, 6.16038);
  path.cubicTo(21.8168, 6.19028, 20.7535, 6.40894, 19.7485, 6.80701);
  path.lineTo(19.4253, 5.41641);
  path.cubicTo(20.6957, 4.82522, 22.0718, 4.51497, 23.4652, 4.50556);
  path.cubicTo(26.1585, 4.50556, 27.3031, 5.84054, 27.3031, 7.86387);
  path.lineTo(path.getCurrentPoint().dx, 15.7903);
  path.lineTo(25.5929, 15.7764);
  path.close();
  path.moveTo(25.1148, 10.6103);
  path.lineTo(24.1924, path.getCurrentPoint().dy);
  path.cubicTo(21.7482, 10.6103, 21.0749, 11.4516, 21.0749, 12.6128);
  path.cubicTo(21.0518, 12.8436, 21.0788, 13.0768, 21.1538, 13.2955);
  path.cubicTo(21.2287, 13.5142, 21.3499, 13.713, 21.5085, 13.8774);
  path.cubicTo(21.667, 14.0417, 21.859, 14.1677, 22.0705, 14.246);
  path.cubicTo(22.282, 14.3243, 22.5077, 14.3531, 22.7313, 14.3302);
  path.cubicTo(23.6266, 14.2556, 24.469, 13.8624, 25.1148, 13.2177);
  path.lineTo(path.getCurrentPoint().dx, 10.6103);
  path.close();
  path.moveTo(36.0563, 15.7764);
  path.lineTo(35.8879, 14.5735);
  path.cubicTo(34.9902, 15.4518, 33.805, 15.9483, 32.5685, 15.9641);
  path.cubicTo(30.4542, 15.9641, 29.3365, 14.8517, 29.3365, 12.8909);
  path.cubicTo(29.3365, 10.6242, 31.04, 9.10846, 34.8106, 9.10846);
  path.lineTo(35.5849, path.getCurrentPoint().dy);
  path.lineTo(path.getCurrentPoint().dx, 8.14199);
  path.cubicTo(35.5849, 6.80701, 34.9116, 6.16038, 33.363, 6.16038);
  path.cubicTo(32.2869, 6.19028, 31.2236, 6.40894, 30.2186, 6.80701);
  path.lineTo(29.8954, 5.41641);
  path.cubicTo(31.1661, 4.8262, 32.542, 4.51599, 33.9353, 4.50556);
  path.cubicTo(36.6286, 4.50556, 37.7665, 5.84054, 37.7665, 7.86387);
  path.lineTo(path.getCurrentPoint().dx, 15.7903);
  path.lineTo(36.0563, 15.7764);
  path.close();
  path.moveTo(35.5849, 10.6103);
  path.lineTo(34.6625, path.getCurrentPoint().dy);
  path.cubicTo(32.1847, 10.6103, 31.5383, 11.4586, 31.5383, 12.6128);
  path.cubicTo(31.5165, 12.8433, 31.5443, 13.076, 31.6197, 13.2941);
  path.cubicTo(31.6951, 13.5122, 31.8163, 13.7104, 31.9746, 13.8745);
  path.cubicTo(32.1329, 14.0386, 32.3243, 14.1646, 32.5352, 14.2434);
  path.cubicTo(32.7462, 14.3221, 32.9713, 14.3518, 33.1947, 14.3302);
  path.cubicTo(34.0927, 14.2589, 34.9384, 13.8653, 35.5849, 13.2177);
  path.lineTo(path.getCurrentPoint().dx, 10.6103);
  path.close();
  path.moveTo(42.3181, 15.9294);
  path.cubicTo(40.9715, 15.9294, 40.3588, 15.5261, 40.3588, 13.7253);
  path.lineTo(path.getCurrentPoint().dx, 0.0);
  path.lineTo(42.6211, path.getCurrentPoint().dy);
  path.lineTo(path.getCurrentPoint().dx, 12.8422);
  path.cubicTo(42.6211, 14.1355, 42.776, 14.3371, 43.3954, 14.3371);
  path.cubicTo(43.5907, 14.3371, 43.8264, 14.3371, 43.9812, 14.3371);
  path.lineTo(44.089, 15.7277);
  path.cubicTo(43.5255, 15.8856, 42.9419, 15.9536, 42.3585, 15.9294);
  path.lineTo(42.3181, path.getCurrentPoint().dy);
  path.close();
  return path;
}

// Path 2
PathEx buildPath8() {
  final PathEx path = PathEx();
  path.moveTo(51.8365, 15.7754);
  path.lineTo(49.0758, path.getCurrentPoint().dy);
  path.cubicTo(47.3668, 10.8686, 45.9701, 5.8517, 44.8945, 0.756836);
  path.lineTo(47.4397, path.getCurrentPoint().dy);
  path.cubicTo(48.1938, 4.76178, 49.4192, 9.01007, 50.6514, 13.2723);
  path.cubicTo(51.8577, 9.16488, 52.8201, 4.9853, 53.5332, 0.756836);
  path.lineTo(55.8427, path.getCurrentPoint().dy);
  path.cubicTo(54.894, 5.86454, 53.5544, 10.8865, 51.8365, 15.7754);
  path.close();
  path.moveTo(69.6121, 15.7754);
  path.cubicTo(69.5246, 11.4089, 69.2216, 6.89635, 68.9388, 3.80226);
  path.lineTo(65.2759, 15.7754);
  path.lineTo(63.357, path.getCurrentPoint().dy);
  path.lineTo(59.6537, 3.80226);
  path.cubicTo(59.3776, 7.11885, 59.1824, 11.4089, 59.115, 15.7754);
  path.lineTo(56.8998, path.getCurrentPoint().dy);
  path.cubicTo(57.0278, 10.9082, 57.3711, 5.65176, 57.9502, 0.756836);
  path.lineTo(61.0138, path.getCurrentPoint().dy);
  path.lineTo(64.5016, 11.7913);
  path.lineTo(67.9961, 0.756836);
  path.lineTo(70.8981, path.getCurrentPoint().dy);
  path.cubicTo(71.457, 5.62395, 71.8879, 10.9013, 72.0159, 15.7754);
  path.lineTo(69.6121, path.getCurrentPoint().dy);
  path.close();
  path.moveTo(73.7059, 14.2457);
  path.lineTo(73.1807, path.getCurrentPoint().dy);
  path.lineTo(path.getCurrentPoint().dx, 13.9398);
  path.lineTo(74.6149, path.getCurrentPoint().dy);
  path.lineTo(path.getCurrentPoint().dx, 14.2318);
  path.lineTo(74.0897, path.getCurrentPoint().dy);
  path.lineTo(path.getCurrentPoint().dx, 15.7615);
  path.lineTo(73.7059, path.getCurrentPoint().dy);
  path.lineTo(path.getCurrentPoint().dx, 14.2457);
  path.close();
  path.moveTo(74.9919, 13.9398);
  path.lineTo(75.6114, path.getCurrentPoint().dy);
  path.lineTo(75.9884, 15.2747);
  path.lineTo(76.3924, 13.9398);
  path.lineTo(76.9984, path.getCurrentPoint().dy);
  path.lineTo(path.getCurrentPoint().dx, 15.7754);
  path.lineTo(76.6146, path.getCurrentPoint().dy);
  path.lineTo(path.getCurrentPoint().dx, 14.2318);
  path.lineTo(76.1366, 15.8032);
  path.lineTo(75.8201, path.getCurrentPoint().dy);
  path.lineTo(75.3488, 14.2318);
  path.lineTo(path.getCurrentPoint().dx, 15.8032);
  path.lineTo(74.9919, path.getCurrentPoint().dy);
  path.lineTo(path.getCurrentPoint().dx, 13.9398);
  path.close();
  return path;
}