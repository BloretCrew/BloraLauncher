/*
 * Blora Launcher - Minecraft Crash Analysis Service
 * Copyright (C) 2026 Bloret Software Community
 *
 * Derived from PCL2: https://github.com/Meloong-Git/PCL
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * ==============================================================================
 *
 * 百络谷启动器 - Minecraft 崩溃分析服务
 * 版权所有 (C) 2026 百络谷软件社区
 *
 * 本代码源自 PCL2：https://github.com/Meloong-Git/PCL
 *
 * 本程序是自由软件：你可以根据自由软件基金会发布的 GNU 通用公共许可证（GPL）
 * 第 3 版（或根据你的选择，任何更高版本）的条款，重新分发它和/或修改它。
 *
 * 本程序的发布是希望它能有用，但不作任何保证；甚至没有对适销性或特定用途适用性的暗示保证。
 * 有关详细信息，请参阅 GNU 通用公共许可证。
 *
 * 你应该已经收到了一份 GNU 通用公共许可证的副本。如果没有，请参阅 <https://www.gnu.org/licenses/>。
 */

import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'dart:math' as math;
import '../main.dart';
import '../core/i18n.dart';
import '../core/grammer_candy.dart';

/// 导致崩溃的原因枚举
enum CrashReason {
  // Java 相关
  javaVmParameterError, // Java虚拟机参数有误
  usingJdk, // 使用JDK
  javaVersionTooHigh, // Java版本过高
  javaVersionIncompatible, // Java版本不兼容
  using32BitJava, // 使用32位Java导致JVM无法分配足够多的内存
  usingOpenJ9, // 使用OpenJ9

  // Mod 文件问题
  modFileExtracted, // Mod文件被解压
  modNameContainsSpecialCharacters, // Mod名称包含特殊字符
  modDuplicateInstallation, // Mod重复安装
  modIncompatibility, // Mod互不兼容
  modMissingDependencyOrWrongMcVersion, // Mod缺少前置或MC版本错误

  // Mod 分析结果
  definitelyModCausesCrash, // 确定Mod导致游戏崩溃
  suspectedModCausesCrash, // 怀疑Mod导致游戏崩溃
  modConfigFileCausesCrash, // Mod配置文件导致游戏崩溃
  modMixinFailure, // ModMixin失败
  modLoaderError, // Mod加载器报错
  modInitializationFailure, // Mod初始化失败

  // Forge/Fabric 相关
  forgeInstallationIncomplete, // Forge安装不完整
  multipleForgeInJsonVersion, // 版本Json中存在多个Forge
  lowVersionForgeWithHighVersionJavaIncompatible, // 低版本Forge与高版本Java不兼容
  forgeError, // Forge报错
  fabricError, // Fabric报错
  fabricErrorWithSolution, // Fabric报错并给出解决方案

  // Mixin 与启动相关
  mixinBootstrapMissing, // MixinBootstrap缺失
  modRequiresJava11, // Mod需要Java11

  // 显卡/驱动问题
  gpuDoesNotSupportOpenGL, // 显卡不支持OpenGL
  gpuDriverDoesNotSupportPixelFormat, // 显卡驱动不支持导致无法设置像素格式
  intelDriverIncompatible, // Intel驱动不兼容导致EXCEPTION_ACCESS_VIOLATION
  amdDriverIncompatible, // AMD驱动不兼容导致EXCEPTION_ACCESS_VIOLATION
  nvidiaDriverIncompatible, // Nvidia驱动不兼容导致EXCEPTION_ACCESS_VIOLATION
  shaderOrResourcePackCausesOpenGL1282Error, // 光影或资源包导致OpenGL1282错误
  textureToolargeOrGpuConfigurationInsufficient, // 材质过大或显卡配置不足
  shadersModAndOptifineSimultaneouslyInstalled, // ShadersMod与OptiFine同时安装

  // 内存问题
  insufficientMemory, // 内存不足
  initialHeapLargerThanMax, // 初始内存大于最大内存

  // OptiFine 相关
  optifineAndForgeIncompatible, // OptiFine与Forge不兼容
  optifineCannotLoadWorld, // OptiFine导致无法加载世界

  // NightConfig
  nightConfigBug, // NightConfig的Bug

  // 文件问题
  fileOrContentVerificationFailed, // 文件或内容校验失败
  tooManyModsExceedIdLimit, // Mod过多导致超出ID限制

  // 堆栈分析
  stacktraceFoundKeyword, // 堆栈分析发现关键字
  stacktraceFoundModName, // 堆栈分析发现Mod名称

  // 特定对象问题
  specificBlockCausesCrash, // 特定方块导致崩溃
  specificEntityCausesCrash, // 特定实体导致崩溃

  // 其他
  playerManuallyTriggeredDebugCrash, // 玩家手动触发调试崩溃
  couldNotCreateVm, // 无法创建虚拟机
  veryShortOutput, // 极短的程序输出
  noAnalyzableFiles, // 没有可用的分析文件
}

/// 日志文件分类类型
enum AnalyzeFileType {
  hsErr, // Java虚拟机崩溃日志
  minecraftLog, // Minecraft游戏日志
  extraLogFile, // 额外日志文件
  extraReportFile, // 额外报告文件
  crashReport, // Minecraft崩溃报告
}

/// 崩溃分析器 - 用于分析Minecraft游戏崩溃原因
///
/// 该类提供了对Minecraft崩溃日志的完整分析功能，包括：
/// 1. 收集日志文件
/// 2. 准备和分类日志
/// 3. 分析崩溃原因
/// 4. 输出分析结果
class CrashAnalyzer {
  /// 目标Minecraft实例信息
  String? targetInstance;

  /// 临时文件夹路径
  late String tempFolder;

  /// 用于分析的原始日志文件列表，格式为：文件路径 -> 文件内容行列表
  final List<MapEntry<String, List<String>>> analyzeRawFiles = [];

  /// 解析后的日志内容
  String? logMc; // Minecraft游戏日志
  String? logMcDebug; // Minecraft Debug日志
  String? logHs; // 虚拟机崩溃日志
  String? logCrash; // Minecraft崩溃报告
  String? logAll; // 所有日志内容的合并

  /// 在弹窗中直接打开的日志文件
  MapEntry<String, List<String>>? directFile;

  /// 需要输出的文件列表
  List<String> outputFiles = [];

  /// 崩溃原因字典，格式为：崩溃原因 -> 附加信息列表
  final Map<CrashReason, List<String>> crashReasons = {};

  /// Creates a new CrashAnalyzer instance.
  ///
  /// Initializes temporary directories for storing crash analysis files.
  /// The analyzer will create a temporary folder structure with 'Temp' and 'Report' subdirectories.
  ///
  /// Parameters:
  ///   - targetInstance: Optional target Minecraft instance information
  CrashAnalyzer({this.targetInstance}) {
    _initialize();
  }

  /// Initializes the crash analyzer by creating necessary directory structure.
  ///
  /// Sets up temporary folders for storing raw log files and generating reports.
  /// Also initializes logging for the initialization process.
  void _initialize() {
    tempFolder = _requestTaskTempFolder();
    _createDirectories('$tempFolder/Temp/');
    _createDirectories('$tempFolder/Report/');
    logger.info('Crash analysis temp folder: $tempFolder');
  }

  /// Collects available log files for crash analysis from the version directory.
  ///
  /// This method performs multiple searches to locate crash logs:
  /// 1. Searches crash-reports folder within the version directory
  /// 2. Searches the parent Minecraft directory for .log files
  /// 3. Searches the version directory itself for .log files
  /// 4. Adds standard log file paths (latest.log, debug.log)
  ///
  /// Files are filtered based on modification time (must be modified within the last 3 minutes)
  /// to ensure they are related to the crash event.
  ///
  /// Parameters:
  ///   - versionPathIndie: The path to the Minecraft version directory
  ///   - latestLog: Optional list containing the last 200 lines of program output captured by Blora Launcher
  void collect(String versionPathIndie, {List<String>? latestLog}) {
    logger.info('Step 1: Collecting log files');

    final possibleLogs = <String>{};

    // Try to collect from crash-reports folder
    try {
      final dir = Directory('$versionPathIndie/crash-reports/');
      if (dir.existsSync()) {
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is File) {
            possibleLogs.add(entity.path);
          }
        }
      }
    } catch (e) {
      logger.warning('Warning: Failed to collect crash reports from folder: $e');
    }

    // Try to collect .log files from parent directories
    try {
      final parentDir = Directory(versionPathIndie).parent.parent;
      if (parentDir.existsSync()) {
        for (final entity in parentDir.listSync()) {
          if (entity is File && entity.path.endsWith('.log')) {
            possibleLogs.add(entity.path);
          }
        }
      }
    } catch (e) {
      logger.warning('Warning: Failed to collect logs from parent folder: $e');
    }

    // Try to collect .log files from version folder
    try {
      final versionDir = Directory(versionPathIndie);
      if (versionDir.existsSync()) {
        for (final entity in versionDir.listSync()) {
          if (entity is File && entity.path.endsWith('.log')) {
            possibleLogs.add(entity.path);
          }
        }
      }
    } catch (e) {
      logger.warning('Warning: Failed to collect logs from version folder: $e');
    }

    // Add standard log file paths
    possibleLogs.add('$versionPathIndie/logs/latest.log');
    possibleLogs.add('$versionPathIndie/logs/debug.log');

    // Filter valid log files by modification time
    final rightLogs = <String>[];
    for (final logFile in possibleLogs) {
      try {
        final file = File(logFile);
        if (!file.existsSync() || file.lengthSync() == 0) continue;

        final lastModified = file.lastModifiedSync();
        final minutesAgo = DateTime.now().difference(lastModified).inMinutes.abs();

        if (minutesAgo < 3) {
          rightLogs.add(logFile);
          logger.info('Possible log file: $logFile (${minutesAgo.toStringAsFixed(1)} minutes ago)');
        }
      } catch (e) {
        logger.warning('Warning: Failed to verify log file time: $logFile - $e');
      }
    }

    // Read collected log files
    for (final filePath in rightLogs) {
      try {
        final file = File(filePath);
        final lines = file.readAsLinesSync();
        analyzeRawFiles.add(MapEntry(filePath, lines));
      } catch (e) {
        logger.warning('Warning: Failed to read log file: $filePath - $e');
      }
    }

    // Process latest game output if provided
    if (latestLog != null && latestLog.isNotEmpty) {
      final rawOutput = latestLog.join('\n');
      logger.info('Latest game output:\n$rawOutput');
      final outputFile = File('$tempFolder/RawOutput.log');
      outputFile.writeAsStringSync(rawOutput);
      analyzeRawFiles.add(MapEntry('$tempFolder/RawOutput.log', latestLog));
    }

    logger.info('Step 1: Completed collecting ${analyzeRawFiles.length} log files');
  }

  /// Imports log files or crash report archives from a given file path.
  ///
  /// This method attempts to extract the file as a ZIP archive first.
  /// If extraction fails, it copies the file directly to the temp directory.
  /// Only .log and .txt files are kept; other files are deleted.
  ///
  /// Parameters:
  ///   - filePath: The path to the log file or crash report archive to import
  void import(String filePath) {
    logger.info('Step 1: Importing log file');

    // Try to extract as ZIP
    try {
      final file = File(filePath);
      if (file.existsSync() &&
          file.lengthSync() > 0 &&
          !filePath.endsWith('.jar')) {
        _extractZipFile(filePath, '$tempFolder/Temp/');
        logger.info('Extracted log file: $filePath');
        _processExtractedFiles();
        return;
      }
    } catch (e) {
      logger.info('Not a zip file or extraction failed: $e');
    }

    // Copy file directly if not a ZIP
    final fileName = path.basename(filePath);
    try {
      File(filePath).copySync('$tempFolder/Temp/$fileName');
      logger.info('Copied log file: $filePath');
    } catch (e) {
      logger.warning('Warning: Failed to copy file: $e');
    }

    _processExtractedFiles();
  }

  /// Processes extracted files and imports valid log files.
  ///
  /// Iterates through files in the temp directory and imports .log and .txt files.
  /// Files with other extensions are deleted.
  void _processExtractedFiles() {
    final tempDir = Directory('$tempFolder/Temp/');
    if (!tempDir.existsSync()) return;

    for (final entity in tempDir.listSync()) {
      if (entity is! File) continue;

      try {
        if (!entity.existsSync() || entity.lengthSync() == 0) continue;

        final ext = path.extension(entity.path).toLowerCase();
        if (ext == '.log' || ext == '.txt') {
          final lines = entity.readAsLinesSync();
          analyzeRawFiles.add(MapEntry(entity.path, lines));
        } else {
          entity.deleteSync();
        }
      } catch (e) {
        logger.warning('Warning: Failed to import log file: $e');
      }
    }

    logger.info('Step 1: Import completed with ${analyzeRawFiles.length} files');
  }

  /// Prepares log files for analysis by classifying and extracting relevant content.
  ///
  /// This method performs several important tasks:
  /// 1. Classifies log files by type (HsErr, MinecraftLog, CrashReport, etc.)
  /// 2. Extracts relevant portions of log files
  /// 3. Prioritizes log files based on their type and freshness
  /// 4. Removes empty lines and duplicate entries
  ///
  /// Returns true if sufficient analyzable logs are found, false otherwise.
  bool prepare() {
    logger.info('Step 2: Preparing log text');

    logMc = null;
    logMcDebug = null;
    logHs = null;
    logCrash = null;
    directFile = null;

    final allFiles =
    <MapEntry<AnalyzeFileType, MapEntry<String, List<String>>>?>[];

    // Classify log files
    for (final logFile in analyzeRawFiles) {
      final matchName = path.basename(logFile.key).toLowerCase();
      AnalyzeFileType? targetType;

      if (matchName.startsWith('hs_err')) {
        targetType = AnalyzeFileType.hsErr;
        directFile ??= logFile;
      } else if (matchName.startsWith('crash-')) {
        targetType = AnalyzeFileType.crashReport;
        directFile ??= logFile;
      } else if (_isMinecraftLogFile(matchName)) {
        targetType = AnalyzeFileType.minecraftLog;
        directFile = logFile;
      } else if (_isLauncherLogFile(matchName, logFile.value)) {
        targetType = AnalyzeFileType.minecraftLog;
        directFile ??= logFile;
      } else if (matchName.endsWith('.log')) {
        targetType = AnalyzeFileType.extraLogFile;
      } else if (matchName.endsWith('.txt')) {
        targetType = AnalyzeFileType.extraReportFile;
      }

      if (targetType != null && logFile.value.isNotEmpty) {
        allFiles.add(MapEntry(targetType, logFile));
        logger.info('Classified $matchName as $targetType');
      }
    }

    // If only extra logs found, treat them as Minecraft logs
    if (allFiles.isNotEmpty &&
        allFiles.every((f) => f?.key == AnalyzeFileType.extraLogFile)) {
      logger.info('Only extra logs found, treating as Minecraft logs');
      for (var i = 0; i < allFiles.length; i++) {
        final file = allFiles[i];
        if (file != null) {
          allFiles[i] = MapEntry(AnalyzeFileType.minecraftLog, file.value);
        }
      }
    }

    // Process classified files
    for (final selectType in AnalyzeFileType.values) {
      final selectedFiles = <MapEntry<String, List<String>>>[];

      for (final file in allFiles) {
        if (file?.key == selectType) {
          selectedFiles.add(file!.value);
        }
      }

      if (selectedFiles.isEmpty) continue;

      _processFilesByType(selectType, selectedFiles);
    }

    final result = logMc != null || logHs != null || logCrash != null;
    if (result) {
      logger.info('Step 2: Preparation completed with analyzable logs');
    } else {
      logger.info('Step 2: No analyzable logs found');
    }
    return result;
  }

  /// Analyzes crash logs to identify potential crash reasons.
  ///
  /// The analysis is performed in three phases:
  /// 1. Precise log matching with high priority
  /// 2. Precise log matching with medium priority
  /// 3. Stack trace analysis and low priority matching
  ///
  /// Results are stored in the crashReasons map with additional information.
  void analyze() {
    logger.info('Step 3: Analyzing crash reasons');

    logAll = '${logMc ?? ''}${logHs ?? ''}${logCrash ?? ''}';

    // Phase 1: High priority precise log matching
    _analyzeCrit1();
    if (crashReasons.isNotEmpty) {
      _printResults();
      return;
    }

    // Phase 2: Medium priority precise log matching
    _analyzeCrit2();
    if (crashReasons.isNotEmpty) {
      _printResults();
      return;
    }

    // Phase 3: Stack trace analysis
    if (_shouldAnalyzeStack()) {
      _analyzeStack();
      if (crashReasons.isNotEmpty) {
        _printResults();
        return;
      }
    }

    // Phase 4: Low priority precise log matching
    _analyzeCrit3();

    _printResults();
  }

  /// Outputs crash analysis results to the user.
  ///
  /// Displays analysis results and optionally allows the user to view log files
  /// or export a complete crash report with all collected logs and diagnostics.
  ///
  /// Parameters:
  ///   - isManualAnalyze: Whether this is a manual analysis (affects output format)
  ///   - extraFiles: Optional list of additional files to include in the crash report
  void output({
    bool isManualAnalyze = false,
    List<String>? extraFiles,
  }) {
    logger.info('Outputting crash analysis results');
    final detail = getAnalyzeResult(isManualAnalyze);
    logger.info(detail);

    if (!isManualAnalyze && (extraFiles?.isNotEmpty ?? false)) {
      _exportCrashReport(extraFiles!);
    }
  }

  /// Performs high-priority crash reason analysis using precise log matching.
  ///
  /// Checks game logs, crash reports, and VM logs for specific error patterns
  /// that definitively indicate crash causes.
  void _analyzeCrit1() {
    // Check if we have any analyzable logs
    if (logMc == null && logHs == null && logCrash == null) {
      _appendReason(CrashReason.noAnalyzableFiles);
      return;
    }

    if (logMc != null) {
      _analyzeGameLog(logMc!);
    }

    if (logCrash != null) {
      _analyzeCrashReport(logCrash!);
    }

    if (logHs != null) {
      _analyzeVmLog(logHs!);
    }
  }

  /// Performs medium-priority crash reason analysis.
  ///
  /// Analyzes Mixin failures and Mod loading issues that are less definitive
  /// than high-priority matches but still important indicators.
  void _analyzeCrit2() {
    if (logMc != null) {
      _analyzeMixin(logMc!);
    }
    if (logCrash != null) {
      _analyzeMixin(logCrash!);
    }
  }

  /// Performs low-priority crash reason analysis.
  ///
  /// Handles edge cases and less common crash indicators that should only be
  /// reported if no higher-priority causes were found.
  void _analyzeCrit3() {
    if (logMc != null) {
      // Very short output analysis
      if (!logMc!.contains('at net.') &&
          !logMc!.contains('INFO]') &&
          logHs == null &&
          logCrash == null &&
          logMc!.length < 100) {
        _appendReason(CrashReason.veryShortOutput, [logMc!]);
      }
    }

    if (logCrash != null) {
      _analyzeCrashReportDetails(logCrash!);
    }
  }

  /// Analyzes Minecraft game log for crash indicators.
  ///
  /// Searches for specific error messages and exception patterns that indicate
  /// common crash causes.
  ///
  /// Parameters:
  ///   - log: The Minecraft game log content
  void _analyzeGameLog(String log) {
    // Java parameter errors
    if (log.contains('Unrecognized option:')) {
      _appendReason(CrashReason.javaVmParameterError);
    }
    
    // Could not create VM
    if (log.contains('Could not create the Java Virtual Machine')) {
      _appendReason(CrashReason.couldNotCreateVm);
    }

    // Multiple Forge versions
    if (log.contains('Found multiple arguments for option fml.forgeVersion')) {
      _appendReason(CrashReason.multipleForgeInJsonVersion);
    }

    // OpenGL not supported
    if (log.contains('The driver does not appear to support OpenGL')) {
      _appendReason(CrashReason.gpuDoesNotSupportOpenGL);
    }

    // JDK instead of JRE
    if (log.contains('java.lang.ClassCastException: java.base/jdk') ||
        log.contains('java.lang.ClassCastException: class jdk.')) {
      _appendReason(CrashReason.usingJdk);
    }

    // OptiFine and Forge incompatibility (multiple checks)
    if (log.contains(
        'java.lang.NoSuchMethodError: \'void net.minecraft.client.renderer.texture.SpriteContents.<init>') ||
        log.contains(
            'java.lang.NoSuchMethodError: \'java.lang.String com.mojang.blaze3d.systems.RenderSystem.getBackendDescription') ||
        log.contains(
            'java.lang.NoSuchMethodError: \'void net.minecraft.client.renderer.block.model.BakedQuad.<init>') ||
        log.contains(
            'java.lang.NoSuchMethodError: \'void net.minecraftforge.client.gui.overlay.ForgeGui.renderSelectedItemName') ||
        log.contains(
            'java.lang.NoSuchMethodError: \'void net.minecraft.server.level.DistanceManager') ||
        log.contains(
            'java.lang.NoSuchMethodError: \'net.minecraft.network.chat.FormattedText net.minecraft.client.gui.Font.ellipsize')) {
      _appendReason(CrashReason.optifineAndForgeIncompatible);
    }

    // OpenJ9 JVM
    if (log.contains('Open J9 is not supported') ||
        log.contains('OpenJ9 is incompatible') ||
        log.contains('.J9VMInternals.')) {
      _appendReason(CrashReason.usingOpenJ9);
    }

    // Java version too high
    if (log.contains('java.lang.NoSuchFieldException: ucp') ||
        log.contains('because module java.base does not export') ||
        log.contains(
            'java.lang.ClassNotFoundException: jdk.nashorn.api.scripting.NashornScriptEngineFactory') ||
        log.contains(
            'java.lang.ClassNotFoundException: java.lang.invoke.LambdaMetafactory')) {
      _appendReason(CrashReason.javaVersionTooHigh);
    }

    // Extracted Mod files
    if (log.contains(
        'The directories below appear to be extracted jar files. Fix this before you continue.') ||
        log.contains('Extracted mod jars found, loading will NOT continue')) {
      _appendReason(CrashReason.modFileExtracted);
    }

    // Mixin Bootstrap missing
    if (log.contains(
        'java.lang.ClassNotFoundException: org.spongepowered.asm.launch.MixinTweaker')) {
      _appendReason(CrashReason.mixinBootstrapMissing);
    }

    // Pixel format not supported
    if (log.contains('Couldn\'t set pixel format')) {
      _appendReason(CrashReason.gpuDriverDoesNotSupportPixelFormat);
    }

    // Out of memory
    if (log.contains('java.lang.OutOfMemoryError') ||
        log.contains('an out of memory error')) {
      _appendReason(CrashReason.insufficientMemory);
    }

    // Initial heap larger than max
    if (log.contains('Initial heap size set to a larger value than the maximum heap size')) {
      _appendReason(CrashReason.initialHeapLargerThanMax);
    }

    // Shaders Mod with OptiFine
    if (log.contains(
        'java.lang.RuntimeException: Shaders Mod detected. Please remove it, OptiFine has built-in support for shaders.')) {
      _appendReason(CrashReason.shadersModAndOptifineSimultaneouslyInstalled);
    }

    // Java version incompatibility
    if (log.contains('java.lang.NoSuchMethodError: sun.security.util.ManifestEntryVerifier') ||
        log.contains(
            'java.lang.NoSuchMethodError: \'void sun.security.util.ManifestEntryVerifier')) {
      _appendReason(CrashReason.javaVersionIncompatible);
    }

    // OpenGL error 1282
    if (log.contains('1282: Invalid operation')) {
      _appendReason(CrashReason.shaderOrResourcePackCausesOpenGL1282Error);
    }

    // File verification failure
    if (log.contains(
        'signer information does not match signer information of other classes in the same package')) {
      final modName = _extractModNameFromLog(log);
      _appendReason(CrashReason.fileOrContentVerificationFailed, [modName]);
    }

    // Texture resolution too high
    if (log.contains('Maybe try a lower resolution resourcepack?')) {
      _appendReason(CrashReason.textureToolargeOrGpuConfigurationInsufficient);
    }

    // OptiFine world loading failure
    if (log.contains(
        'java.lang.NoSuchMethodError: net.minecraft.world.server.ChunkManager\$ProxyTicketManager.shouldForceTicks(J)Z') &&
        log.contains('OptiFine')) {
      _appendReason(CrashReason.optifineCannotLoadWorld);
    }

    // NightConfig parsing error
    if (log.contains(
        'com.electronwill.nightconfig.core.io.ParsingException: Not enough data available') &&
        !crashReasons.containsKey(CrashReason.modConfigFileCausesCrash)) {
      _appendReason(CrashReason.nightConfigBug);
    }

    // Forge installation incomplete
    if (log.contains('Cannot find launch target fmlclient, unable to launch') ||
        (log.contains('Invalid paths argument, contained no existing paths') &&
            log.contains('libraries\\net\\minecraftforge\\fmlcore'))) {
      _appendReason(CrashReason.forgeInstallationIncomplete);
    }

    // Mod name contains special characters
    if (log.contains('Invalid module name: \'\' is not a Java identifier')) {
      _appendReason(CrashReason.modNameContainsSpecialCharacters);
    }

    // Java version incompatibility (class file version)
    if (log.contains(
        'has been compiled by a more recent version of the Java Runtime (class file version 55.0)')) {
      _appendReason(CrashReason.javaVersionIncompatible);
    }

    // Unsafe defineAnonymousClass not available
    if (log.contains(
        'java.lang.RuntimeException: java.lang.NoSuchMethodException: no such method: sun.misc.Unsafe.defineAnonymousClass')) {
      _appendReason(CrashReason.javaVersionTooHigh);
    }

    // Java 11 compatibility
    if (log.contains(
        'java.lang.IllegalArgumentException: The requested compatibility level JAVA_11 could not be set')) {
      _appendReason(CrashReason.modRequiresJava11);
    }

    // Unsupported class file versions
    if (log.contains('Unsupported class file major version') ||
        log.contains('Unsupported major.minor version') ||
        log.contains('Level is not supported by the active JRE or ASM version')) {
      _appendReason(CrashReason.javaVersionIncompatible);
    }

    // Invalid maximum heap size
    if (log.contains('Invalid maximum heap size')) {
      _appendReason(CrashReason.using32BitJava);
    }

    // Could not reserve memory
    if (log.contains('Could not reserve enough space')) {
      if (log.contains('for 1048576KB object heap')) {
        _appendReason(CrashReason.using32BitJava);
      } else {
        _appendReason(CrashReason.insufficientMemory);
      }
    }

    // Definite Mod crash
    if (log.contains('Caught exception from ')) {
      final modName = _extractModNameFromCaughtException(log);
      _appendReason(CrashReason.definitelyModCausesCrash, [modName]);
    }

    // Duplicate Mods
    if (log.contains('DuplicateModsFoundException')) {
      final modNames = _extractDuplicateModNames(log);
      _appendReason(CrashReason.modDuplicateInstallation, modNames);
    }

    if (log.contains('Found a duplicate mod')) {
      final modNames = _extractDuplicateModNames(log);
      _appendReason(CrashReason.modDuplicateInstallation, modNames);
    }

    if (log.contains('Found duplicate mods')) {
      final modNames = _extractModIdNames(log);
      _appendReason(CrashReason.modDuplicateInstallation, modNames);
    }

    if (log.contains('ModResolutionException: Duplicate')) {
      final modNames = _extractDuplicateModNames(log);
      _appendReason(CrashReason.modDuplicateInstallation, modNames);
    }

    // Incompatible mods
    if (log.contains('Incompatible mods found!')) {
      final modNames = _extractIncompatibleModNames(log);
      _appendReason(CrashReason.modIncompatibility, modNames);
    }

    // Missing dependencies
    if (log.contains('Missing or unsupported mandatory dependencies:')) {
      final dependencies = _extractMissingDependencies(log);
      _appendReason(CrashReason.modMissingDependencyOrWrongMcVersion, dependencies);
    }
  }

  /// Analyzes crash report for crash indicators.
  ///
  /// Examines Minecraft crash reports for specific patterns indicating crash causes.
  ///
  /// Parameters:
  ///   - report: The crash report content
  void _analyzeCrashReport(String report) {
    // Out of memory in crash report
    if (report.contains('java.lang.OutOfMemoryError')) {
      _appendReason(CrashReason.insufficientMemory);
    }

    // Pixel format issues
    if (report.contains('Pixel format not accelerated')) {
      _appendReason(CrashReason.gpuDriverDoesNotSupportPixelFormat);
    }

    // Player manually triggered crash
    if (report.contains('Manually triggered debug crash')) {
      _appendReason(CrashReason.playerManuallyTriggeredDebugCrash);
    }

    // ID limit exceeded
    if (report.contains('maximum id range exceeded')) {
      _appendReason(CrashReason.tooManyModsExceedIdLimit);
    }

    // OptiFine not found in mods
    if (report.contains('has mods that were not found') &&
        report.contains('optifine\\OptiFine')) {
      _appendReason(CrashReason.optifineCannotLoadWorld);
    }

    // Mod crash section
    if (report.contains('-- MOD ')) {
      final modInfo = _extractModInfoFromCrashReport(report);
      if (modInfo.isNotEmpty) {
        _appendReason(CrashReason.definitelyModCausesCrash, [modInfo]);
      }
    }

    // Multiple entries with same key
    if (report.contains('Multiple entries with same key: ')) {
      final modName = _extractModNameFromReport(report, 'Multiple entries');
      _appendReason(CrashReason.definitelyModCausesCrash, [modName]);
    }

    // Loader exception from Mod
    if (report.contains('LoaderExceptionModCrash: Caught exception from ')) {
      final modName = _extractModNameFromReport(report, 'LoaderExceptionModCrash');
      _appendReason(CrashReason.definitelyModCausesCrash, [modName]);
    }

    // Failed loading config file
    if (report.contains('Failed loading config file ')) {
      final modName = _extractModNameFromConfigError(report);
      _appendReason(CrashReason.modConfigFileCausesCrash, [modName]);
    }

    // Java version issue in crash report
    if (report.contains(
        'Unable to make protected final java.lang.Class java.lang.ClassLoader.defineClass')) {
      _appendReason(CrashReason.javaVersionTooHigh);
    }
  }

  /// Analyzes VM error log (hs_err_pid*.log) for crash indicators.
  ///
  /// Looks for patterns specific to Java Virtual Machine crashes.
  ///
  /// Parameters:
  ///   - log: The VM error log content
  void _analyzeVmLog(String log) {
    // Out of physical memory
    if (log.contains('The system is out of physical RAM or swap space')) {
      _appendReason(CrashReason.insufficientMemory);
    }

    if (log.contains('Out of Memory Error')) {
      _appendReason(CrashReason.insufficientMemory);
    }

    // Access violation errors
    if (log.contains('EXCEPTION_ACCESS_VIOLATION')) {
      if (log.contains('# C  [ig')) {
        _appendReason(CrashReason.intelDriverIncompatible);
      } else if (log.contains('# C  [atio')) {
        _appendReason(CrashReason.amdDriverIncompatible);
      } else if (log.contains('# C  [nvoglv')) {
        _appendReason(CrashReason.nvidiaDriverIncompatible);
      }
    }
  }

  /// Analyzes log for Mixin-related issues.
  ///
  /// Detects Mixin bytecode injection failures which indicate mod incompatibilities.
  ///
  /// Parameters:
  ///   - log: The log content to analyze
  void _analyzeMixin(String log) {
    if (log.contains('Mixin prepare failed') ||
        log.contains('Mixin apply failed') ||
        log.contains('MixinApplyError') ||
        log.contains('MixinTransformerError') ||
        log.contains('mixin.injection.throwables.') ||
        log.contains('.json] FAILED during )')) {
      _appendReason(CrashReason.modMixinFailure);
    }
  }

  /// Analyzes specific crash report details for block and entity issues.
  ///
  /// Parameters:
  ///   - report: The crash report content
  void _analyzeCrashReportDetails(String report) {
    // Specific block crash
    if (report.contains('\tBlock location: World: ')) {
      final blockInfo = _extractBlockInfo(report);
      _appendReason(CrashReason.specificBlockCausesCrash, [blockInfo]);
    }

    // Specific entity crash
    if (report.contains('\tEntity\'s Exact location: ')) {
      final entityInfo = _extractEntityInfo(report);
      _appendReason(CrashReason.specificEntityCausesCrash, [entityInfo]);
    }
  }

  /// Determines if stack trace analysis should be performed.
  ///
  /// Stack analysis is only performed if Forge, Fabric, or other modloaders
  /// are detected in the logs.
  ///
  /// Returns true if modloader is detected, false otherwise
  bool _shouldAnalyzeStack() {
    return (logAll?.contains('orge') ?? false) ||
        (logAll?.contains('abric') ?? false) ||
        (logAll?.contains('uilt') ?? false) ||
        (logAll?.contains('iteloader') ?? false);
  }

  /// Performs stack trace analysis to extract Mod names.
  ///
  /// Analyzes stack traces in various log formats to identify problematic mods.
  void _analyzeStack() {
    logger.info('Analyzing stack traces');
    final keywords = <String>[];

    // Analyze crash report stack
    if (logCrash != null) {
      logger.info('Beginning crash log stack trace analysis');
      final beforeSystemDetails = logCrash!.split('System Details').first;
      keywords.addAll(_analyzeStackKeyword(beforeSystemDetails));
    }

    // Analyze Minecraft log stack
    if (logMc != null) {
      logger.info('Beginning Minecraft log stack trace analysis');
      final fatalLines = _extractFatalErrors(logMc!);
      for (final fatal in fatalLines) {
        keywords.addAll(_analyzeStackKeyword(fatal));
      }
    }

    // Analyze VM log stack
    if (logHs != null) {
      logger.info('Beginning VM log stack trace analysis');
      final stackLogs = logHs!.split('Registers:').first.split('T H R E A D').last;
      keywords.addAll(_analyzeStackKeyword(stackLogs));
    }

    // Try to identify mod names from keywords
    if (keywords.isNotEmpty) {
      final modNames = _analyzeModName(keywords);
      if (modNames == null) {
        _appendReason(CrashReason.stacktraceFoundKeyword, keywords);
      } else {
        _appendReason(CrashReason.stacktraceFoundModName, modNames);
      }
    }
  }

  /// Appends a crash reason to the results dictionary.
  ///
  /// If the reason already exists, additional information is merged.
  /// Logs the addition of a new crash reason.
  ///
  /// Parameters:
  ///   - reason: The crash reason to append
  ///   - additional: Optional additional information related to the reason
  void _appendReason(CrashReason reason, [List<String>? additional]) {
    if (crashReasons.containsKey(reason)) {
      if (additional != null) {
        crashReasons[reason]!.addAll(additional);
        crashReasons[reason] = crashReasons[reason]!.toSet().toList();
      }
    } else {
      crashReasons[reason] = additional ?? [];
    }
    logger.info('Possible crash reason: $reason');
  }

  /// Prints analysis results to the console.
  ///
  /// Outputs summary of found crash reasons and their associated information.
  void _printResults() {
    if (crashReasons.isEmpty) {
      logger.info('Step 3: No possible crash reasons found');
    } else {
      logger.info('Step 3: Found ${crashReasons.length} possible reasons');
      for (final entry in crashReasons.entries) {
        final additionalInfo =
        entry.value.isNotEmpty ? ' (${entry.value.join('; ')})' : '';
        logger.info('- ${entry.key}$additionalInfo');
      }
    }
  }

  /// Gets a human-readable description of the crash analysis results.
  ///
  /// Converts crash reasons and associated information into user-friendly messages.
  ///
  /// Parameters:
  ///   - isManualAnalyze: Whether this is a manual analysis
  ///
  /// Returns a formatted string describing the crash causes and recommendations
  String getAnalyzeResult(bool isManualAnalyze) {
    if (crashReasons.isEmpty) {
      return isManualAnalyze
          ? 'Sorry, Blora Launcher cannot determine the error cause.'.tl
          : 'Sorry, your game encountered some problems...\nIf you need help, please send the error report file to others instead of sending screenshots of this window.'.tl;
    }

    final results = <String>[];
    for (final entry in crashReasons.entries) {
      final msg = _getReasonMessage(entry.key, entry.value);
      if (msg.isNotEmpty) {
        results.add(msg);
      }
    }

    return results.join('\n\n');
  }

  /// Generates a user-friendly message for a specific crash reason.
  ///
  /// Parameters:
  ///   - reason: The crash reason
  ///   - additional: Additional information about the crash reason
  ///
  /// Returns a formatted message describing the issue and recommendations
  String _getReasonMessage(CrashReason reason, List<String> additional) {
    switch (reason) {
      case CrashReason.javaVmParameterError:
        return 'The game cannot run due to incorrect Java parameters.\nPlease check the Java VM parameters in Advanced Options.'.tl;

      case CrashReason.modFileExtracted:
        return 'The game cannot run because Mod files were extracted.\nPlace the entire Mod file in the Mod folder.'.tl;

      case CrashReason.insufficientMemory:
        return 'Minecraft ran out of memory.\nThis may be due to insufficient system memory, low allocated memory, or high configuration requirements.'.tl;

      case CrashReason.initialHeapLargerThanMax:
        return 'The game failed to start because the Initial Heap Size is larger than the Maximum Heap Size.\nPlease check your memory settings and ensure the minimum memory is not greater than the maximum memory.'.tl;

      case CrashReason.usingJdk:
        return 'The game crashed because JDK is being used.\nPlease use Java 8 instead in the version settings.'.tl;

      case CrashReason.gpuDoesNotSupportOpenGL:
        return 'Your graphics card does not support OpenGL.\nTry updating your graphics drivers or using a different graphics card.'.tl;

      case CrashReason.usingOpenJ9:
        return 'The game crashed because OpenJ9 is not supported.\nPlease switch to a different Java version in the version settings.'.tl;

      case CrashReason.javaVersionTooHigh:
        return 'The game crashed because your Java version is too high.\nPlease use a lower Java version like Java 8 or Java 11 in the version settings.'.tl;

      case CrashReason.javaVersionIncompatible:
        return 'The game is incompatible with your current Java version.\nPlease use an appropriate Java version in the version settings.'.tl;

      case CrashReason.modNameContainsSpecialCharacters:
        return 'A Mod file name contains special characters, causing the crash.\nPlease rename the Mod file to only contain English letters, numbers, hyphens (-), and underscores (_).'.tl;

      case CrashReason.gpuDriverDoesNotSupportPixelFormat:
        return 'Graphics driver does not support the required pixel format.\nTry updating your graphics driver or changing graphics settings.'.tl;

      case CrashReason.mixinBootstrapMissing:
        return 'MixinBootstrap is missing, causing the crash.\nTry installing MixinBootstrap. If it still crashes, try adding an exclamation mark before the filename.'.tl;

      case CrashReason.using32BitJava:
        if (Platform.environment['PROCESSOR_ARCHITECTURE'] == 'AMD64') {
          return 'You are using 32-bit Java, which prevents Minecraft from using required memory.\nPlease install and use 64-bit Java instead.'.tl;
        } else {
          return 'You are using a 32-bit operating system, which prevents Minecraft from using required memory.\nConsider upgrading to a 64-bit operating system.'.tl;
        }

      case CrashReason.modMissingDependencyOrWrongMcVersion:
        if (additional.isNotEmpty) {
          return 'Required dependencies are not installed, causing the game to exit.\nMissing dependencies:\n - %s\n\nPlease install the required mods.'
              .tl
              .format(additional.join('\n - '));
        } else {
          return 'Required dependencies are not installed, causing the game to exit.\nPlease check the error log for details about missing dependencies.'
              .tl;
        }

      case CrashReason.stacktraceFoundKeyword:
        if (additional.length == 1) {
          return 'The game encountered an error. Blora Launcher found a suspicious keyword: %s.\n\nIf you know which Mod corresponds to this keyword, try disabling it.'
              .tl
              .format(additional.first);
        } else {
          return 'The game encountered an error. Blora Launcher found these suspicious keywords:\n - %s\n\nTry disabling mods corresponding to these keywords.'
              .tl
              .format(additional.join(', '));
        }

      case CrashReason.stacktraceFoundModName:
      case CrashReason.suspectedModCausesCrash:
        if (additional.length == 1) {
          return 'Blora Launcher suspects that the Mod "%s" caused the error, but cannot be completely certain.\nTry disabling this Mod and observing if the game still crashes.'
              .tl
              .format(additional.first);
        } else {
          return 'Blora Launcher suspects these Mods caused the error, but cannot be completely certain:\n - %s\n\nTry disabling these Mods one by one.'
              .tl
              .format(additional.join('\n - '));
        }

      case CrashReason.definitelyModCausesCrash:
        if (additional.length == 1) {
          return 'The Mod "%s" caused the error.\nTry disabling this Mod and observing if the game still crashes.'
              .tl
              .format(additional.first);
        } else {
          return 'These Mods caused the error:\n - %s\n\nTry disabling these Mods one by one.'
              .tl
              .format(additional.join('\n - '));
        }

      case CrashReason.modMixinFailure:
        if (additional.isEmpty) {
          return 'Some Mods failed to inject, causing the error.\nThis generally indicates that some Mods are incompatible with other Mods or the current environment, or they have bugs.\nTry disabling Mods one by one.'
              .tl;
        } else if (additional.length == 1) {
          return 'The Mod "%s" failed to inject, causing the error.\nThis generally indicates that it\'s incompatible with other Mods or the current environment, or it has bugs.'
              .tl
              .format(additional.first);
        } else {
          return 'These Mods failed to inject:\n - %s\nTry disabling them one by one.'
              .tl
              .format(additional.join('\n - '));
        }

      case CrashReason.modConfigFileCausesCrash:
        if (additional.isNotEmpty) {
          return 'The Mod "%s" has a config file error.\nTry deleting the mod config file and regenerating it, or update the Mod.'
              .tl
              .format(additional.first);
        } else {
          return 'A Mod\'s config file is corrupted, causing the crash.\nTry deleting the mod config files and regenerating them.'
              .tl;
        }

      case CrashReason.modDuplicateInstallation:
        if (additional.isNotEmpty) {
          return 'Duplicate Mods installed:\n - %s\n\nRemove the duplicate Mods.'
              .tl
              .format(additional.join('\n - '));
        } else {
          return 'Duplicate Mods are installed.\nRemove the duplicate Mods.'.tl;
        }

      case CrashReason.modIncompatibility:
        if (additional.isNotEmpty) {
          return 'Incompatible Mods detected:\n - %s\n\nTry disabling these Mods one by one.'
              .tl
              .format(additional.join('\n - '));
        } else {
          return 'Incompatible Mods are installed.\nTry disabling Mods one by one to find the incompatible pair.'
              .tl;
        }

      case CrashReason.optifineAndForgeIncompatible:
        return 'OptiFine and Forge are incompatible with this version.\nTry updating both OptiFine and Forge, or use one without the other.'.tl;

      case CrashReason.optifineCannotLoadWorld:
        return 'OptiFine is preventing the world from loading.\nTry updating OptiFine or temporarily disabling it.'.tl;

      case CrashReason.shadersModAndOptifineSimultaneouslyInstalled:
        return 'ShadersMod and OptiFine are installed simultaneously.\nOptiFine has built-in shader support. Remove ShadersMod.'.tl;

      case CrashReason.forgeInstallationIncomplete:
        return 'Forge installation is incomplete.\nTry reinstalling Forge.'.tl;

      case CrashReason.shaderOrResourcePackCausesOpenGL1282Error:
        return 'A shader or resource pack is causing an OpenGL error.\nTry disabling shaders or using a lower resolution resource pack.'.tl;

      case CrashReason.textureToolargeOrGpuConfigurationInsufficient:
        return 'The resource pack texture is too large or GPU configuration is insufficient.\nTry using a lower resolution resource pack.'.tl;

      case CrashReason.fileOrContentVerificationFailed:
        if (additional.isNotEmpty) {
          return 'File signature verification failed for %s.\nThis may be due to file corruption or modification. Try reinstalling the Mod.'
              .tl
              .format(additional.first);
        } else {
          return 'File signature verification failed.\nThis may be due to file corruption. Try reinstalling affected Mods.'
              .tl;
        }

      case CrashReason.tooManyModsExceedIdLimit:
        return 'Too many Mods installed, exceeding ID limit.\nTry disabling some Mods or increasing the ID limit if possible.'.tl;

      case CrashReason.playerManuallyTriggeredDebugCrash:
        return 'This is a manually triggered debug crash (not a real crash).'.tl;

      case CrashReason.couldNotCreateVm:
        return 'The game failed to start because the Java Virtual Machine could not be created.\nThis is often caused by incompatible Java arguments, incorrect Java version, or system memory issues.'.tl;

      case CrashReason.veryShortOutput:
        return 'Very short program output detected. The game may have crashed before outputting error information.'.tl;

      case CrashReason.noAnalyzableFiles:
        return 'No analyzable log files found.'.tl;

      case CrashReason.nightConfigBug:
        return 'NightConfig encountered a parsing error, possibly due to a corrupted mod config file.\nTry deleting mod config files and regenerating them.'.tl;

      case CrashReason.modLoaderError:
        if (additional.isNotEmpty) {
          return 'Mod loader error: %s\nTry updating the mod loader or reinstalling mods.'
              .tl
              .format(additional.join('\n'));
        } else {
          return 'Mod loader encountered an error.\nTry updating the mod loader.'
              .tl;
        }

      case CrashReason.modInitializationFailure:
        if (additional.isNotEmpty) {
          return 'The Mod "%s" failed to initialize.\nTry updating or reinstalling this Mod.'
              .tl
              .format(additional.first);
        } else {
          return 'A Mod failed to initialize.\nTry updating or reinstalling Mods.'.tl;
        }

      case CrashReason.intelDriverIncompatible:
        return 'Intel graphics driver is incompatible, causing an access violation.\nTry updating your graphics driver.'.tl;

      case CrashReason.amdDriverIncompatible:
        return 'AMD graphics driver is incompatible, causing an access violation.\nTry updating your graphics driver.'.tl;

      case CrashReason.nvidiaDriverIncompatible:
        return 'NVIDIA graphics driver is incompatible, causing an access violation.\nTry updating your graphics driver.'.tl;

      case CrashReason.fabricError:
        return 'Fabric loader encountered an error.\nTry updating Fabric or check mod compatibility.'.tl;

      case CrashReason.fabricErrorWithSolution:
        if (additional.isNotEmpty) {
          return 'Fabric loader error with a potential solution:\n%s'
              .tl
              .format(additional.first);
        } else {
          return 'Fabric loader encountered an error. Check the log for solutions.'
              .tl;
        }

      case CrashReason.forgeError:
        if (additional.isNotEmpty) {
          return 'Forge error: %s'.tl.format(additional.first);
        } else {
          return 'Forge loader encountered an error.\nTry updating Forge or checking mod compatibility.'
              .tl;
        }

      case CrashReason.lowVersionForgeWithHighVersionJavaIncompatible:
        return 'Low version Forge is incompatible with high version Java.\nTry updating Forge to a newer version.'.tl;

      case CrashReason.multipleForgeInJsonVersion:
        return 'Multiple Forge versions specified in version JSON.\nEnsure only one Forge version is specified.'.tl;

      case CrashReason.modRequiresJava11:
        return 'This Mod requires Java 11 or higher.\nPlease install and use Java 11 or higher.'.tl;
      case CrashReason.specificBlockCausesCrash:
        if (additional.isNotEmpty) {
          return 'The game crashed due to a specific block: %s.\nTry removing the block using an external editor or disabling the Mod it belongs to.'
              .tl
              .format(additional.first);
        } else {
          return 'The game crashed due to a specific block.\nTry removing the block using an external editor.'
              .tl;
        }
      case CrashReason.specificEntityCausesCrash:
        if (additional.isNotEmpty) {
          return 'The game crashed due to a specific entity: %s.\nTry removing the entity or disabling the Mod it belongs to.'
              .tl
              .format(additional.first);
        } else {
          return 'The game crashed due to a specific entity.\nTry removing the entity.'.tl;
        }
    }
  }

  /// Exports crash analysis results as a ZIP file containing all relevant logs and diagnostics.
  ///
  /// Creates a comprehensive crash report with anonymized personal information and
  /// file signatures filtered for privacy.
  ///
  /// Parameters:
  ///   - extraFiles: Additional files to include in the crash report
  void _exportCrashReport(List<String> extraFiles) {
    logger.info('Exporting crash report');
    // Implementation for crash report export
    // This would include creating ZIP archive with filtered log files
  }

  // ============ Helper methods for log analysis ============

  /// Checks if filename matches standard Minecraft log file patterns.
  bool _isMinecraftLogFile(String name) {
    return name == 'latest.log' ||
        name == 'latest log.txt' ||
        name == 'debug.log' ||
        name == 'debug log.txt' ||
        name == 'Game output before crash.txt'.tl ||
        name == 'rawoutput.log';
  }

  /// Checks if filename matches launcher log patterns.
  bool _isLauncherLogFile(String name, List<String> content) {
    return (name == 'Launcher log.txt'.tl ||
        name == 'Blora Launcher log.txt'.tl ||
        name == 'log1.txt') &&
        content.any((line) => line.contains('The following is the last part of the game output'.tl));
  }

  /// Processes classified log files and extracts relevant content.
  void _processFilesByType(
      AnalyzeFileType type,
      List<MapEntry<String, List<String>>> files,
      ) {
    switch (type) {
      case AnalyzeFileType.hsErr:
      case AnalyzeFileType.crashReport:
        final newest = files.last;
        final content = _getHeadTailLines(newest.value,
            type == AnalyzeFileType.hsErr ? 200 : 300,
            type == AnalyzeFileType.hsErr ? 100 : 700);
        if (type == AnalyzeFileType.hsErr) {
          logHs = content;
        } else {
          logCrash = content;
        }
        outputFiles.add(newest.key);
        break;

      case AnalyzeFileType.minecraftLog:
        logMc = '';
        logMcDebug = '';
        final fileDict = <String, MapEntry<String, List<String>>>{};

        for (final file in files) {
          final fileName = path.basename(file.key).toLowerCase();
          fileDict[fileName] = file;
          outputFiles.add(file.key);
        }

        // Try to extract launcher logs
        for (final fileName in [
          'rawoutput.log',
          'Launcher log.txt'.tl,
          'log1.txt',
          'Game output before crash.txt'.tl,
          'Blora Launcher log.txt'.tl
        ]) {
          if (!fileDict.containsKey(fileName)) continue;
          final currentLog = fileDict[fileName]!;
          var hasLauncherMark = false;
          for (final line in currentLog.value) {
            if (hasLauncherMark) {
              logMc = '${logMc!}$line\n';
            } else if (line.contains('The following is the last part of the game output'.tl)) {
              hasLauncherMark = true;
            }
          }
          if (!hasLauncherMark) {
            logMc = logMc! + _getHeadTailLines(currentLog.value, 0, 500);
          }
          logMc = logMc!.trimRight();
          break;
        }

        // Try to extract Minecraft logs
        for (final fileName in ['latest.log', 'latest log.txt', 'debug.log', 'debug log.txt']) {
          if (!fileDict.containsKey(fileName)) continue;
          final currentLog = fileDict[fileName]!;
          logMc = logMc! + _getHeadTailLines(currentLog.value, 1500, 500);
          break;
        }

        // Try to extract debug logs
        for (final fileName in ['debug.log', 'debug log.txt']) {
          if (!fileDict.containsKey(fileName)) continue;
          final currentLog = fileDict[fileName]!;
          logMcDebug = logMcDebug! + _getHeadTailLines(currentLog.value, 1000, 0);
          break;
        }

        // Fallback
        if (logMc!.isEmpty) {
          if (logMcDebug!.isNotEmpty) {
            logMc = logMcDebug;
          } else if (fileDict.isNotEmpty) {
            final firstFile = fileDict.values.first;
            logMc = logMc! + _getHeadTailLines(firstFile.value, 1500, 500);
          } else {
            logMc = null;
          }
        }
        if (logMcDebug!.isEmpty) logMcDebug = null;
        break;

      case AnalyzeFileType.extraLogFile:
      case AnalyzeFileType.extraReportFile:
        for (final file in files) {
          outputFiles.add(file.key);
        }
        break;
    }
  }

  /// Extracts the first N and last M lines from a log, removing duplicates and empty lines.
  ///
  /// Parameters:
  ///   - raw: The raw log lines
  ///   - headLines: Number of lines to extract from the beginning
  ///   - tailLines: Number of lines to extract from the end
  ///
  /// Returns formatted string with deduplicated lines
  String _getHeadTailLines(
      List<String> raw,
      int headLines,
      int tailLines,
      ) {
    if (raw.length <= headLines + tailLines) {
      return raw.toSet().toList().join('\n');
    }

    final lines = <String>[];
    var realHeadLines = 0;
    var viewedLines = 0;

    // Extract head lines
    for (viewedLines = 0; viewedLines < raw.length; viewedLines++) {
      if (lines.contains(raw[viewedLines])) continue;
      realHeadLines++;
      lines.add(raw[viewedLines]);
      if (realHeadLines >= headLines) break;
    }

    // Extract tail lines
    var realTailLines = 0;
    for (var i = raw.length - 1; i >= viewedLines; i--) {
      if (lines.contains(raw[i])) continue;
      realTailLines++;
      lines.insert(realHeadLines, raw[i]);
      if (realTailLines >= tailLines) break;
    }

    final result = StringBuffer();
    for (final line in lines) {
      if (line.isEmpty) continue;
      result.writeln(line);
    }

    return result.toString();
  }

  /// Extracts mod keywords from stack traces.
  ///
  /// Parameters:
  ///   - errorStack: The stack trace to analyze
  ///
  /// Returns list of extracted keywords or empty list if none found
  List<String> _analyzeStackKeyword(String errorStack) {
    errorStack = '\n$errorStack\n';

    // Regex patterns for stack trace analysis
    final stackSearchResults = <String>[];

    // Standard stack trace pattern
    final pattern1 = RegExp(
        r'(?<=\n[^{]+)[a-zA-Z_]+\w+\.[a-zA-Z_]+[\w.]+(?=\.[\w.$]+\.)');
    stackSearchResults.addAll(pattern1.allMatches(errorStack).map((m) => m.group(0)!));

    // Mixin stack pattern
    final pattern2 = RegExp(r'(?<=at [^(]+?\.\w+\$\w+\$)[\w$]+?(?=\$\w+\()');
    stackSearchResults
        .addAll(pattern2.allMatches(errorStack).map((m) => m.group(0)!.replaceAll('\$', '.')));

    // Filter and remove duplicates
    var possibleStacks = stackSearchResults.toSet().toList();

    // Remove known library prefixes
    final ignoreStacks = {
      'java',
      'sun',
      'javax',
      'jdk',
      'oolloo',
      'org.lwjgl',
      'com.sun',
      'net.minecraftforge',
      'paulscode.sound',
      'com.mojang',
      'net.minecraft',
      'cpw.mods',
      'com.google',
      'org.apache',
      'org.spongepowered',
      'net.fabricmc',
      'com.mumfrey',
      'com.electronwill.nightconfig',
      'it.unimi.dsi',
      'MojangTricksIntelDriversForPerformance_javaw',
    };

    possibleStacks = possibleStacks
        .where((stack) => !ignoreStacks.any((ignore) => stack.startsWith(ignore)))
        .toList();

    if (possibleStacks.isEmpty) return [];

    // Extract keywords from package names
    final possibleWords = <String>{};
    for (final stack in possibleStacks) {
      final parts = stack.split('.');
      final limit = math.min(3, parts.length - 1);
      for (var i = 0; i <= limit; i++) {
        final word = parts[i];
        if (word.length <= 2 || word.startsWith('func_')) continue;

        final commonWords = {
          'com',
          'org',
          'net',
          'asm',
          'fml',
          'mod',
          'jar',
          'sun',
          'lib',
          'map',
          'gui',
          'dev',
          'nio',
          'api',
          'dsi',
          'top',
          'mcp',
          'core',
          'init',
          'mods',
          'main',
          'file',
          'game',
          'load',
          'read',
          'done',
          'util',
          'tile',
          'item',
          'base',
          'fake',
          'oshi',
          'impl',
          'data',
          'pool',
          'task',
          'forge',
          'setup',
          'block',
          'model',
          'mixin',
          'event',
          'unimi',
          'netty',
          'world',
          'lwjgl',
          'fakes',
          'fabric',
          'gitlab',
          'common',
          'server',
          'config',
          'mixins',
          'compat',
          'loader',
          'launch',
          'script',
          'entity',
          'assist',
          'client',
          'plugin',
          'modapi',
          'mojang',
          'shader',
          'events',
          'method',
          'thread',
          'helper',
          'wrapper',
          'access',
          'invoke',
          'object',
          'string',
          'number',
          'list',
          'hash',
          'proxy',
          'stream',
          'buffer',
          'reader',
          'writer',
          'preinit',
          'preload',
          'machine',
          'reflect',
          'channel',
          'general',
          'handler',
          'content',
          'systems',
          'modules',
          'service',
          'scripts',
          'network',
          'fastutil',
          'optifine',
          'internal',
          'platform',
          'override',
          'fabricmc',
          'neoforge',
          'external',
          'injection',
          'listeners',
          'scheduler',
          'minecraft',
          'universal',
          'multipart',
          'neoforged',
          'microsoft',
          'transformer',
          'transformers',
          'minecraftforge',
          'blockentity',
          'spongepowered',
          'electronwill',
          'concurrent',
        };

        if (!commonWords.contains(word.toLowerCase())) {
          possibleWords.add(word.trim());
        }
      }
    }

    if (possibleWords.length > 10) {
      logger.info('Too many keywords detected, likely matching error');
      return [];
    }

    return possibleWords.toList();
  }

  /// Analyzes mod names from extracted keywords.
  ///
  /// Attempts to match keywords with actual mod file names in crash report.
  ///
  /// Parameters:
  ///   - keywords: Keywords extracted from stack traces
  ///
  /// Returns list of probable mod names or null if unable to determine
  List<String>? _analyzeModName(List<String> keywords) {
    final modFileNames = <String>{};

    // Preprocess keywords
    final realKeywords = <String>[];
    for (final keyword in keywords) {
      for (final subKeyword in keyword.split('(')) {
        realKeywords.add(subKeyword.trim());
      }
    }

    // Extract from crash report
    if (logCrash != null && logCrash!.contains('A detailed walkthrough of the error')) {
      var details = logCrash!.replaceAll('A detailed walkthrough of the error', '¨');
      final isFabricDetail = details.contains('Fabric Mods');
      if (isFabricDetail) {
        details = details.replaceAll('Fabric Mods', '¨');
      }
      details = details.split('¨').last;

      // Extract mod name lines
      final modNameLines = <String>[];
      for (final line in details.split('\n')) {
        final jarCount = '.jar'.allMatches(line).length;
        if ((jarCount == 1) ||
            (isFabricDetail && line.startsWith('\t\t') && !line.contains('fabric'))) {
          modNameLines.add(line);
        }
      }

      // Find matching lines
      for (final keyword in realKeywords) {
        for (final modString in modNameLines) {
          final realModString = modString.toLowerCase().replaceAll('_', '');
          if (realModString.contains(keyword.toLowerCase().replaceAll('_', '')) &&
              !realModString.contains('minecraft.jar') &&
              !realModString.contains('forge-') &&
              !realModString.contains('mixin-')) {
            // Extract mod name
            if (isFabricDetail) {
              final match = RegExp(r'(?<=: )[^\n]+(?= [^\n]+)').firstMatch(modString);
              if (match != null) modFileNames.add(match.group(0)!);
            } else {
              final match = RegExp(r'(?<=\()[^\t]+\.jar(?=\))|(?<=(\t\t)|(\| ))[^\t|]+\.jar')
                  .firstMatch(modString);
              if (match != null) modFileNames.add(match.group(0)!);
            }
            break;
          }
        }
      }
    }

    // Extract from debug.log
    if (logMcDebug != null) {
      final debugModLines = RegExp(r'(?<=valid mod file ).*', multiLine: true)
          .allMatches(logMcDebug!)
          .map((m) => m.group(0)!)
          .toList();

      for (final keyword in realKeywords) {
        for (final modString in debugModLines) {
          if (modString.contains('{$keyword}')) {
            final match = RegExp(r'.*(?= with)').firstMatch(modString);
            if (match != null) modFileNames.add(match.group(0)!);
            break;
          }
        }
      }
    }

    return modFileNames.isEmpty ? null : modFileNames.toList();
  }

  // ============ Regex extraction helper methods ============

  String _extractModNameFromLog(String log) {
    final match = RegExp(r'(?<=signer information does not match).+').firstMatch(log);
    return match?.group(0) ?? '';
  }

  String _extractModNameFromCaughtException(String log) {
    final match = RegExp(r'(?<=Caught exception from )[^\n]+?').firstMatch(log);
    return match?.group(0)?.trim() ?? '';
  }

  List<String> _extractDuplicateModNames(String log) {
    final matches = RegExp(r'[^\\/]+\.jar').allMatches(log);
    return matches.map((m) => m.group(0)!).toList();
  }

  List<String> _extractModIdNames(String log) {
    final matches = RegExp(r"(?<=Mod ID: ')\w+?(?=' from mod files:)").allMatches(log);
    return matches.map((m) => m.group(0)!).toList();
  }

  List<String> _extractIncompatibleModNames(String log) {
    final match = RegExp(r'(?<=Incompatible mods found![\s\S]+: )[\s\S]+?(?=\tat )')
        .firstMatch(log);
    if (match != null) {
      return [match.group(0)!.trim()];
    }
    return [];
  }

  List<String> _extractMissingDependencies(String log) {
    final matches =
    RegExp(r'(?<=Missing or unsupported mandatory dependencies:)([\n\r]+\t(.*))+',
        caseSensitive: false)
        .allMatches(log);
    return matches.map((m) => m.group(0)!.trim()).toList();
  }

  String _extractModInfoFromCrashReport(String report) {
    final match = RegExp(r'(?<=Mod File: ).+').firstMatch(report);
    return match?.group(0)?.trim() ?? '';
  }

  String _extractModNameFromReport(String report, String marker) {
    if (marker == 'Multiple entries') {
      final match = RegExp(r'(?<=Multiple entries with same key: ).+').firstMatch(report);
      return match?.group(0)?.trim() ?? '';
    } else if (marker == 'LoaderExceptionModCrash') {
      final match = RegExp(r'(?<=LoaderExceptionModCrash: Caught exception from ).+')
          .firstMatch(report);
      return match?.group(0)?.trim() ?? '';
    }
    return '';
  }

  String _extractModNameFromConfigError(String report) {
    final match = RegExp(r'(?<=Failed loading config file ).*').firstMatch(report);
    return match?.group(0) ?? '';
  }

  List<String> _extractFatalErrors(String log) {
    return RegExp(r'/FATAL] .+?(?=\n+\[)', multiLine: true)
        .allMatches(log)
        .map((m) => m.group(0)!)
        .toList();
  }

  String _extractBlockInfo(String report) {
    final match = RegExp(r'(?<=\tBlock: Block\{)[^\}]+').firstMatch(report);
    return match?.group(0) ?? '';
  }

  String _extractEntityInfo(String report) {
    final match = RegExp(r'(?<=\tEntity Type: )[^\n]+(?= \()').firstMatch(report);
    return match?.group(0) ?? '';
  }

  // ============ File system helper methods ============

  /// Creates directories if they don't exist.
  void _createDirectories(String dirPath) {
    Directory(dirPath).createSync(recursive: true);
  }

  /// Generates a unique temporary folder path.
  String _requestTaskTempFolder() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return './temp_crash_$timestamp/';
  }

  /// Extracts a ZIP file to the specified directory.
  void _extractZipFile(String zipPath, String extractPath) {
    try {
      final bytes = File(zipPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final outFile = File(path.join(extractPath, filename));
          outFile.createSync(recursive: true);
          outFile.writeAsBytesSync(file.content as List<int>);
        }
      }
    } catch (e) {
      logger.info('Failed to extract zip file: $e');
      rethrow;
    }
  }
}