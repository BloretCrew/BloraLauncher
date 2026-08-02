import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class DownloadTask extends ChangeNotifier {
  final String id;
  double progress = 0.0;
  String status = "准备中...";
  bool isDownloading = false;

  DownloadTask(this.id);

  void update(double p, String s) {
    progress = p;
    status = s;
    notifyListeners();
  }
}

class DownloadService extends ChangeNotifier {
  static final DownloadService instance = DownloadService._();
  DownloadService._();

  final Map<String, DownloadTask> _tasks = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final Dio _dio = Dio();

  List<DownloadTask> getTasks() => _tasks.values.toList();

  DownloadTask getTask(String id) {
    return _tasks.putIfAbsent(id, () {
      final task = DownloadTask(id);
      task.addListener(notifyListeners);
      return task;
    });
  }

  void cancelTask(String id) {
    _cancelTokens[id]?.cancel("User cancelled");
    _cancelTokens.remove(id);
    final task = _tasks[id];
    if (task != null) {
      task.update(0.0, "已取消");
      task.isDownloading = false;
    }
  }

  Future<void> downloadFile(
    String id, 
    String url, 
    String fileName, 
    Future<bool> Function(String path, Function(String) updateStatus) onComplete
  ) async {
    final task = getTask(id);
    if (task.isDownloading) return;
    
    final cancelToken = CancelToken();
    _cancelTokens[id] = cancelToken;
    
    task.isDownloading = true;
    task.update(0.0, "正在下载...");

    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = p.join(tempDir.path, fileName);

      await _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (count, total) {
          if (total != -1) {
            task.update(count / total, "下载中: ${(count / total * 100).toInt()}%");
          }
        },
      );
      
      final success = await onComplete(savePath, (newStatus) {
        task.update(1.0, newStatus);
      });
      
      task.update(1.0, success ? "安装完成" : "安装失败");
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        task.update(0.0, "已取消");
      } else {
        task.update(0.0, "下载失败: $e");
      }
    } finally {
      _cancelTokens.remove(id);
      task.isDownloading = false;
    }
  }
}
