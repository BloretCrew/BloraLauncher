import 'dart:io';
import 'package:git_clone/git_clone.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class GitService {
  static final GitService instance = GitService._();
  GitService._();

  Future<bool> cloneRepo(String url, String destinationPath) async {
    try {
      final destination = Directory(destinationPath);
      if (await destination.exists()) {
        await destination.delete(recursive: true);
      }
      await destination.create(recursive: true);

      await gitClone(
        repo: url,
        directory: destinationPath,
        options: {'depth': 1},
      );
      
      return true;
    } catch (e) {
      debugPrint("Git clone Failed: $e");
      return false;
    }
  }

  Future<bool> cloneAsArchive(String url, String destinationPath) async {
    try {
      await gitCloneArchive(
        url: url,
        destination: destinationPath,
      );
      return true;
    } catch (e) {
      debugPrint("Archive Download Failed: $e");
      return false;
    }
  }

  Future<String?> getCurrentBranch(String repoPath) async {
    try {
      final headFile = File(p.join(repoPath, '.git', 'HEAD'));
      if (await headFile.exists()) {
        final content = await headFile.readAsString();
        return content.trim().split('/').last;
      }
      return null;
    } catch (e) {
      debugPrint("获取分支失败: $e");
      return null;
    }
  }
}
