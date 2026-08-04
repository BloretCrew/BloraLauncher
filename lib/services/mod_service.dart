import 'package:dio/dio.dart';

class ModService {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: "https://api.modrinth.com/v2",
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );


  Future<Map<String,dynamic>?> searchMods(
      String keyword,{
        List<List<String>>? facets,
        int limit = 10,
      }) async {

    try {

      final res = await dio.get(
        "/search",
        queryParameters: {
          "query": keyword,
          "limit": limit,
          "facets": ?facets,
        },
      );

      return res.data;

    }catch(e){
      print(e);
      return null;
    }
  }


  Future<String?> getDownloadUrl(
      String slug,{
        String? loader,
        String? version,
      }) async {

    try{

      final res = await dio.get(
        "/project/$slug/version",
        queryParameters: {
          if(loader != null)
            "loaders":[loader],

          if(version != null)
            "game_versions":[version],
        },
      );


      final list = res.data;

      if(list is List && list.isNotEmpty){

        final files =
            list[0]["files"] ?? [];


        for(final f in files){

          if(
          f["filename"]
              .toString()
              .endsWith(".jar")
          ){
            return f["url"];
          }

        }

        if(files.isNotEmpty){
          return files[0]["url"];
        }
      }

    }catch(e){
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