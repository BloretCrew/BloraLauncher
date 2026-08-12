import 'dart:convert';
import 'package:http/http.dart' as http;

class AzulApi {
  static const _baseUrl = 'https://api.azul.com/metadata/v1/zulu/packages';
  final http.Client _client;
  AzulApi({http.Client? client}) : _client = client ?? http.Client();

  Future<List<ZuluPackage>> getPackages({int page = 1, int pageSize = 1000}) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'availability_types': 'ca',
      'release_status': 'both',
      'page_size': '$pageSize',
      'include_fields': 'java_package_features,release_status,support_term,os,arch,hw_bitness,abi,java_package_type,javafx_bundled,sha256_hash,cpu_gen,size,archive_type,certifications,lib_c_type,crac_supported',
      'page': '$page',
      'azul_com': 'true',
    });
    final response = await _client.get(uri);
    if (response.statusCode == 404) return const [];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AzulApiException('Azul API request failed', statusCode: response.statusCode, body: response.body);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw const AzulApiException('Unexpected response format: expected a List');
    return decoded.whereType<Map<String, dynamic>>().map(ZuluPackage.fromJson).toList();
  }

  Stream<List<ZuluPackage>> getAllPackages({int pageSize = 1000}) async* {
    for (var page = 1;; page++) {
      final packages = await getPackages(page: page, pageSize: pageSize);
      if (packages.isEmpty) break;
      yield packages;
    }
  }

  void dispose() => _client.close();
}

class AzulApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;
  const AzulApiException(this.message, {this.statusCode, this.body});
  @override
  String toString() => statusCode == null ? 'AzulApiException: $message' : 'AzulApiException($statusCode): $message';
}

class ZuluPackage {
  final String abi;
  final String arch;
  final String archiveType;
  final String availabilityType;
  final List<String> certifications;
  final List<dynamic> cpuGen;
  final bool cracSupported;
  final List<int> distroVersion;
  final String downloadUrl;
  final int hwBitness;
  final List<String> javaPackageFeatures;
  final String javaPackageType;
  final List<int> javaVersion;
  final bool javafxBundled;
  final bool latest;
  final String libCType;
  final String name;
  final int openjdkBuildNumber;
  final String os;
  final String packageUuid;
  final String product;
  final String releaseStatus;
  final String sha256Hash;
  final int size;
  final String supportTerm;

  const ZuluPackage({
    required this.abi,
    required this.arch,
    required this.archiveType,
    required this.availabilityType,
    required this.certifications,
    required this.cpuGen,
    required this.cracSupported,
    required this.distroVersion,
    required this.downloadUrl,
    required this.hwBitness,
    required this.javaPackageFeatures,
    required this.javaPackageType,
    required this.javaVersion,
    required this.javafxBundled,
    required this.latest,
    required this.libCType,
    required this.name,
    required this.openjdkBuildNumber,
    required this.os,
    required this.packageUuid,
    required this.product,
    required this.releaseStatus,
    required this.sha256Hash,
    required this.size,
    required this.supportTerm,
  });

  factory ZuluPackage.fromJson(Map<String, dynamic> json) {
    return ZuluPackage(
      abi: json['abi'] ?? '',
      arch: json['arch'] ?? '',
      archiveType: json['archive_type'] ?? '',
      availabilityType: json['availability_type'] ?? '',
      certifications: List<String>.from(json['certifications'] ?? []),
      cpuGen: List<dynamic>.from(json['cpu_gen'] ?? []),
      cracSupported: json['crac_supported'] ?? false,
      distroVersion: List<int>.from(json['distro_version'] ?? []),
      downloadUrl: json['download_url'] ?? '',
      hwBitness: json['hw_bitness'] ?? 0,
      javaPackageFeatures: List<String>.from(json['java_package_features'] ?? []),
      javaPackageType: json['java_package_type'] ?? '',
      javaVersion: List<int>.from(json['java_version'] ?? []),
      javafxBundled: json['javafx_bundled'] ?? false,
      latest: json['latest'] ?? false,
      libCType: json['lib_c_type'] ?? '',
      name: json['name'] ?? '',
      openjdkBuildNumber: json['openjdk_build_number'] ?? 0,
      os: json['os'] ?? '',
      packageUuid: json['package_uuid'] ?? '',
      product: json['product'] ?? '',
      releaseStatus: json['release_status'] ?? '',
      sha256Hash: json['sha256_hash'] ?? '',
      size: json['size'] ?? 0,
      supportTerm: json['support_term'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'abi': abi,
    'arch': arch,
    'archive_type': archiveType,
    'availability_type': availabilityType,
    'certifications': certifications,
    'cpu_gen': cpuGen,
    'crac_supported': cracSupported,
    'distro_version': distroVersion,
    'download_url': downloadUrl,
    'hw_bitness': hwBitness,
    'java_package_features': javaPackageFeatures,
    'java_package_type': javaPackageType,
    'java_version': javaVersion,
    'javafx_bundled': javafxBundled,
    'latest': latest,
    'lib_c_type': libCType,
    'name': name,
    'openjdk_build_number': openjdkBuildNumber,
    'os': os,
    'package_uuid': packageUuid,
    'product': product,
    'release_status': releaseStatus,
    'sha256_hash': sha256Hash,
    'size': size,
    'support_term': supportTerm,
  };
}