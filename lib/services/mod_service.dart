import 'dart:convert';
import 'package:dio/dio.dart';

class ModService {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: "https://api.modrinth.com/v2",
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );


  Future<Map<String, dynamic>?> searchMods(
    String keyword, {
    List<List<String>>? facets,
    int limit = 10,
  }) async {
    try {
      final res = await dio.get(
        "/search",
        queryParameters: {
          "query": keyword,
          "limit": limit,
          if (facets != null) "facets": jsonEncode(facets),
        },
      );

      return res.data;
    } catch (e) {
      print(e);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> searchModsStructured(
    String keyword, {
    String? gameVersion,
    String? loader,
    int limit = 8,
  }) async {
    List<List<String>> facets = [
      ["project_type:mod"]
    ];
    if (loader != null && loader.isNotEmpty) {
      facets.add(["categories:$loader"]);
    }
    if (gameVersion != null && gameVersion.isNotEmpty) {
      facets.add(["versions:$gameVersion"]);
    }

    final data = await searchMods(keyword, facets: facets, limit: limit);
    if (data == null || data['hits'] == null) return [];

    final List hits = data['hits'];
    return hits.map((hit) {
      String desc = (hit["description"] ?? "").toString().replaceAll("\n", " ").trim();
      if (desc.length > 120) {
        desc = "${desc.substring(0, 117)}...";
      }
      return {
        "slug": hit["slug"] ?? "",
        "title": hit["title"] ?? hit["slug"] ?? "Unknown",
        "description": desc,
        "downloads": hit["downloads"] ?? 0,
        "icon_url": hit["icon_url"],
        "author": hit["author"],
        "project_id": hit["project_id"] ?? hit["id"] ?? "",
        "categories": hit["display_categories"] ?? hit["categories"] ?? [],
      };
    }).toList();
  }

  Future<Map<String, dynamic>?> getProject(String slugOrId) async {
    try {
      final res = await dio.get("/project/$slugOrId");
      return res.data;
    } catch (e) {
      print(e);
      return null;
    }
  }

  Future<String?> getDownloadUrl(
    String slug, {
    String? loader,
    String? version,
  }) async {
    try {
      final res = await dio.get(
        "/project/$slug/version",
        queryParameters: {
          if (loader != null) "loaders": jsonEncode([loader]),
          if (version != null) "game_versions": jsonEncode([version]),
        },
      );

      final list = res.data;

      if (list is List && list.isNotEmpty) {
        final files = list[0]["files"] ?? [];

        for (final f in files) {
          if (f["filename"].toString().endsWith(".jar")) {
            return f["url"];
          }
        }

        if (files.isNotEmpty) {
          return files[0]["url"];
        }
      }
    } catch (e) {
      print(e);
    }

    return null;
  }



  Future<void> downloadFile(
      String url,
      String savePath,{
        ProgressCallback? onProgress,
      }) async {

    await dio.download(
      url,
      savePath,
      onReceiveProgress: onProgress,
    );

  }

}