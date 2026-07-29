import 'dart:convert';
import 'package:dio/dio.dart';

class BloretApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      responseType: ResponseType.json,
    ),
  );

  static const String _serverBaseUrl = 'http://123.129.241.101:20901/api/getserver';
  static const String _launcherInfoUrl = 'https://launcher.bloret.net/api/info';

  static Future<BloretServer?> fetchServerInfo(String name) async {
    for (int attempt = 1; attempt <= 5; attempt++) {
      try {
        final response = await _dio.get(
          _serverBaseUrl,
          queryParameters: {'name': name},
        );

        if (response.statusCode == 200 && response.data != null) {
          final data = response.data is String
              ? json.decode(response.data)
              : response.data;
          return BloretServer.fromJson(data);
        }
      } catch (_) {
        if (attempt == 5) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    return null;
  }

  static Future<BloretLauncherConfig?> fetchLauncherConfig() async {
    for (int attempt = 1; attempt <= 5; attempt++) {
      try {
        final response = await _dio.get(_launcherInfoUrl);

        if (response.statusCode == 200 && response.data != null) {
          final data = response.data is String
              ? json.decode(response.data)
              : response.data;
          return BloretLauncherConfig.fromJson(data);
        }
      } catch (_) {
        if (attempt == 5) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    return null;
  }
}

class BloretServer {
  final String title;
  final String text;
  final String url;
  final Map<String, String> otherIp;
  final bool onlineCheck;
  final List<String> type;
  final String tip;
  final Map<String, ServerLink> links;
  final String author;
  final int time;
  final String bestTime;
  final String background;
  final String authorAvatar;
  final String category;
  final String client;
  final String language;
  final String version;
  final String mode;
  final String build;
  final int updatedAt;
  final String privacy;
  final List<dynamic> activities;
  final List<String> gallery;
  final RealTimeStatus? realTimeStatus;

  BloretServer({
    required this.title,
    required this.text,
    required this.url,
    required this.otherIp,
    required this.onlineCheck,
    required this.type,
    required this.tip,
    required this.links,
    required this.author,
    required this.time,
    required this.bestTime,
    required this.background,
    required this.authorAvatar,
    required this.category,
    required this.client,
    required this.language,
    required this.version,
    required this.mode,
    required this.build,
    required this.updatedAt,
    required this.privacy,
    required this.activities,
    required this.gallery,
    this.realTimeStatus,
  });

  factory BloretServer.fromJson(Map<String, dynamic> json) {
    return BloretServer(
      title: json['title'] ?? '',
      text: json['text'] ?? '',
      url: json['url'] ?? '',
      otherIp: Map<String, String>.from(json['otherip'] ?? {}),
      onlineCheck: json['OnlineCheck'] ?? false,
      type: List<String>.from(json['type'] ?? []),
      tip: json['tip'] ?? '',
      links: (json['links'] as Map<String, dynamic>? ?? {}).map(
            (key, value) => MapEntry(key, ServerLink.fromJson(value)),
      ),
      author: json['author'] ?? '',
      time: json['time'] ?? 0,
      bestTime: json['BestTime'] ?? '',
      background: json['background'] ?? '',
      authorAvatar: json['authorAvatar'] ?? '',
      category: json['category'] ?? '',
      client: json['client'] ?? '',
      language: json['language'] ?? '',
      version: json['version'] ?? '',
      mode: json['mode'] ?? '',
      build: json['build'] ?? '',
      updatedAt: json['updatedAt'] ?? 0,
      privacy: json['privacy'] ?? '',
      activities: List<dynamic>.from(json['activities'] ?? []),
      gallery: List<String>.from(json['gallery'] ?? []),
      realTimeStatus: json['realTimeStatus'] != null
          ? RealTimeStatus.fromJson(json['realTimeStatus'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'text': text,
      'url': url,
      'otherip': otherIp,
      'OnlineCheck': onlineCheck,
      'type': type,
      'tip': tip,
      'links': links.map((key, value) => MapEntry(key, value.toJson())),
      'author': author,
      'time': time,
      'BestTime': bestTime,
      'background': background,
      'authorAvatar': authorAvatar,
      'category': category,
      'client': client,
      'language': language,
      'version': version,
      'mode': mode,
      'build': build,
      'updatedAt': updatedAt,
      'privacy': privacy,
      'activities': activities,
      'gallery': gallery,
      'realTimeStatus': realTimeStatus?.toJson(),
    };
  }
}

class ServerLink {
  final String link;
  final String icon;
  final String darkIcon;

  ServerLink({
    required this.link,
    required this.icon,
    required this.darkIcon,
  });

  factory ServerLink.fromJson(Map<String, dynamic> json) {
    return ServerLink(
      link: json['link'] ?? '',
      icon: json['icon'] ?? '',
      darkIcon: json['darkicon'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'link': link,
      'icon': icon,
      'darkicon': darkIcon,
    };
  }
}

class RealTimeStatus {
  final bool online;
  final String ip;
  final int port;
  final String version;
  final String protocolName;
  final int playersOnline;
  final int playersMax;
  final List<String> motdClean;

  RealTimeStatus({
    required this.online,
    required this.ip,
    required this.port,
    required this.version,
    required this.protocolName,
    required this.playersOnline,
    required this.playersMax,
    required this.motdClean,
  });

  factory RealTimeStatus.fromJson(Map<String, dynamic> json) {
    return RealTimeStatus(
      online: json['online'] ?? false,
      ip: json['ip'] ?? '',
      port: json['port'] ?? 0,
      version: json['version'] ?? '',
      protocolName: json['protocolName'] ?? '',
      playersOnline: json['playersOnline'] ?? 0,
      playersMax: json['playersMax'] ?? 0,
      motdClean: List<String>.from(json['motdClean'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'online': online,
      'ip': ip,
      'port': port,
      'version': version,
      'protocolName': protocolName,
      'playersOnline': playersOnline,
      'playersMax': playersMax,
      'motdClean': motdClean,
    };
  }
}

class BloretLauncherConfig {
  final String latestVersion;
  final String description;
  final String newVersionDescription;
  final BetaConfig beta;
  final Downloads downloads;
  final List<String> blTips;
  final Activity activity;

  BloretLauncherConfig({
    required this.latestVersion,
    required this.description,
    required this.newVersionDescription,
    required this.beta,
    required this.downloads,
    required this.blTips,
    required this.activity,
  });

  factory BloretLauncherConfig.fromJson(Map<String, dynamic> json) {
    return BloretLauncherConfig(
      latestVersion: json['latestVersion'] ?? '',
      description: json['description'] ?? '',
      newVersionDescription: json['newVersionDescription'] ?? '',
      beta: BetaConfig.fromJson(json['beta'] ?? {}),
      downloads: Downloads.fromJson(json['downloads'] ?? {}),
      blTips: List<String>.from(json['BLTips'] ?? []),
      activity: Activity.fromJson(json['activity'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latestVersion': latestVersion,
      'description': description,
      'newVersionDescription': newVersionDescription,
      'beta': beta.toJson(),
      'downloads': downloads.toJson(),
      'BLTips': blTips,
      'activity': activity.toJson(),
    };
  }
}

class BetaConfig {
  final bool enabled;

  BetaConfig({required this.enabled});

  factory BetaConfig.fromJson(Map<String, dynamic> json) {
    return BetaConfig(
      enabled: json['enabled'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
    };
  }
}

class Downloads {
  final StableDownloads stable;

  Downloads({required this.stable});

  factory Downloads.fromJson(Map<String, dynamic> json) {
    return Downloads(
      stable: StableDownloads.fromJson(json['stable'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stable': stable.toJson(),
    };
  }
}

class StableDownloads {
  final DownloadPlatform gitcode;
  final DownloadPlatform github;

  StableDownloads({required this.gitcode, required this.github});

  factory StableDownloads.fromJson(Map<String, dynamic> json) {
    return StableDownloads(
      gitcode: DownloadPlatform.fromJson(json['gitcode'] ?? {}),
      github: DownloadPlatform.fromJson(json['github'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gitcode': gitcode.toJson(),
      'github': github.toJson(),
    };
  }
}

class DownloadPlatform {
  final String exe;
  final String zip;

  DownloadPlatform({required this.exe, required this.zip});

  factory DownloadPlatform.fromJson(Map<String, dynamic> json) {
    return DownloadPlatform(
      exe: json['exe'] ?? '',
      zip: json['zip'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'exe': exe,
      'zip': zip,
    };
  }
}

class Activity {
  final bool show;
  final String status;
  final String title;
  final String description;
  final String icon;
  final String time;
  final String link;

  Activity({
    required this.show,
    required this.status,
    required this.title,
    required this.description,
    required this.icon,
    required this.time,
    required this.link,
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      show: json['show'] ?? false,
      status: json['status'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      icon: json['icon'] ?? '',
      time: json['time'] ?? '',
      link: json['link'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'show': show,
      'status': status,
      'title': title,
      'description': description,
      'icon': icon,
      'time': time,
      'link': link,
    };
  }
}