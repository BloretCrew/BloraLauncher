import 'dart:convert';
import 'dart:io';
import 'package:ai_flutter_agent/ai_flutter_agent.dart';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/services/passport_service.dart';
import 'package:bloret_launcher/services/system_prompt.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:openai_dart/openai_dart.dart';
import 'package:path/path.dart' as p;

import 'memory.dart';

/// Adapter for [LLMClient] using our [Bloriko] OpenAI client.
class BlorikoLLMClient implements LLMClient {
  @override
  Future<List<ActionDescriptor>> requestActions({
    required String prompt,
    required List<Map<String, dynamic>> toolSchemas,
    List<Map<String, dynamic>>? messages,
  }) async {
    final List<ChatMessage> chatMessages = [
      ChatMessage.system('You are a UI automation agent. Analyze the UI tree and task, then call the appropriate tools. If the task is done, return plain text.'),
    ];

    if (messages != null) {
      for (var m in messages) {
        if (m['role'] == 'user') chatMessages.add(ChatMessage.user(m['content']));
        if (m['role'] == 'assistant') {
           chatMessages.add(ChatMessage.assistant(content: m['content']));
        }
      }
    }

    chatMessages.add(ChatMessage.user(prompt));

    final response = await Bloriko.client.chat.completions.create(
      ChatCompletionCreateRequest(
        model: ConfigService.get("ai_model") ?? 'default',
        messages: chatMessages,
        tools: toolSchemas.map((s) => Tool.fromJson(s)).toList(),
        toolChoice: ToolChoice.auto(),
      ),
    );

    final choice = response.choices.first;
    if (choice.message.toolCalls == null || choice.message.toolCalls!.isEmpty) {
      return [];
    }

    return choice.message.toolCalls!.map((tc) {
      return ActionDescriptor(
        actionName: tc.function.name,
        args: jsonDecode(tc.function.arguments),
      );
    }).toList();
  }
}

class Bloriko extends ChangeNotifier {
  static Bloriko? _instance;
  static Bloriko get instance => _instance ??= Bloriko._();

  static String key = "";
  static OpenAIClient client = OpenAIClient(
    config: OpenAIConfig(
      authProvider: ApiKeyProvider(key),
      baseUrl: 'https://passport.bloret.net/v1',
    ),
  );

  final List<Map<String, dynamic>> messages = [];
  String conversationTitle = "";
  String? currentSessionFile;
  int requestBatch = 0;
  bool _busy = false;
  bool get busy => _busy;

  String _currentEmotion = "neutral";
  String get emotion => _currentEmotion;

  bool _isCancelled = false;

  AgentCore? _uiAgent;

  Bloriko._() {
    _initUiAgent();
  }

  void _initUiAgent() {
    final treeWalker = SemanticTreeWalker();
    final registry = ActionRegistry();

    BuiltInActions.registerDefaults(
      registry, 
      performAction: (nodeId, action, {actionArgs}) async {
        RendererBinding.instance.pipelineOwner.semanticsOwner?.performAction(nodeId, action, actionArgs);
      }
    );
    
    _uiAgent = AgentCore(
      config: const AgentConfig(debugMode: true, maxSteps: 5),
      treeWalker: treeWalker,
      planner: Planner(
        llmClient: BlorikoLLMClient(),
        actionRegistry: registry,
      ),
      executor: Executor(
        actionRegistry: registry,
        auditLog: AuditLog(),
      ),
      verifier: Verifier(treeWalker: treeWalker),
    );
  }

  static Bloriko getInstance([String key = ""]) {
    if (key.isNotEmpty) {
      Bloriko.key = key;
      Bloriko.client = OpenAIClient(
        config: OpenAIConfig(
          authProvider: ApiKeyProvider(key),
          baseUrl: 'https://passport.bloret.net/v1',
        ),
      );
    } else {
      Bloriko.key = "${PassportService.appId};${PassportService.appSecret};${ConfigService.get("Bloret_PassPort_Token")}";
      Bloriko.client = OpenAIClient(
        config: OpenAIConfig(
          authProvider: ApiKeyProvider(Bloriko.key),
          baseUrl: 'https://passport.bloret.net/v1',
        ),
      );
    }
    return instance;
  }

  void clearSession() {
    messages.clear();
    conversationTitle = "";
    currentSessionFile = null;
    _currentEmotion = "neutral";
    notifyListeners();
  }

  void cancelAgent() {
    _isCancelled = true;
    _uiAgent?.stop();
    _busy = false;
    notifyListeners();
  }

  // ============================================================
  // 工具定义
  // ============================================================
  static final List<Tool> tools = [
    Tool.function(
      name: 'read_file',
      description: '读取文件内容。',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'}
        },
        'required': ['path']
      },
    ),
    Tool.function(
      name: 'write_file',
      description: '写入或创建文件。',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'content': {'type': 'string'}
        },
        'required': ['path', 'content']
      },
    ),
    Tool.function(
      name: 'get_directory_tree',
      description: '显示目录树。',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'max_depth': {'type': 'integer'}
        }
      },
    ),
    Tool.function(
      name: 'set_emotion',
      description: '更新情感状态。',
      parameters: {
        'type': 'object',
        'properties': {
          'emotion': {
            'type': 'string',
            'enum': ["neutral", "happy", "shy", "angry", "sad", "excited", "curious"]
          }
        },
        'required': ['emotion']
      },
    ),
    Tool.function(
      name: 'set_emutation',
      description: '更新情感状态（别名）。',
      parameters: {
        'type': 'object',
        'properties': {
          'emotion': {
            'type': 'string',
            'enum': ["neutral", "happy", "shy", "angry", "sad", "excited", "curious"]
          }
        },
        'required': ['emotion']
      },
    ),
    Tool.function(
      name: 'memory',
      description: '管理记忆。',
      parameters: {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'enum': ["add", "replace", "remove"]},
          'target': {'type': 'string', 'enum': ["memory", "user"]},
          'content': {'type': 'string'}
        },
        'required': ['action', 'target']
      },
    ),
    Tool.function(
      name: 'execute_command',
      description: '执行 shell 命令。返回 stdout 和 stderr。',
      parameters: {
        'type': 'object',
        'properties': {
          'command': {'type': 'string', 'description': '要执行的命令'}
        },
        'required': ['command']
      },
    ),
    Tool.function(
      name: 'interact_with_ui',
      description: '与 Flutter 应用 UI 交互。',
      parameters: {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'description': '执行的动作，例如 tap、input、scroll'
          },
          'nodeId': {
            'type': 'string',
            'description': '目标语义节点ID'
          },
          'value': {
            'type': 'string',
            'description': '输入内容或动作参数'
          }
        },
        'required': ['action', 'nodeId']
      },
    ),
    Tool.function(
      name: 'get_ui_semantics',
      description: '获取当前 Flutter 应用的语义树，用于理解当前界面有哪些可交互元素。',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
  ];

  Future<void> chatWithTools(
    String userPrompt, {
    required Function(String text) onTextChunk,
    required Function(String toolName, Map<String, dynamic> args) onToolStart,
    required Function(String toolName, String result) onToolEnd,
    required Function(String error) onError,
    String workingDir = "",
    bool enableUiInteraction = false,
  }) async {
    if (_busy) return;
    _busy = true;
    _isCancelled = false;
    notifyListeners();

    try {
      final List<ChatMessage> chatMsgs = [
        ChatMessage.system(buildSystemPrompt(
          MemoryStore.instance,
          workingDir,
          currentEmotion: _currentEmotion,
          uiEnabled: enableUiInteraction,
        )),
      ];

      for (var msg in messages) {
        if (msg['role'] == 'user') {
          chatMsgs.add(ChatMessage.user(msg['content'] ?? ''));
        } else if (msg['role'] == 'assistant') {
          chatMsgs.add(ChatMessage.assistant(content: msg['content'] ?? ''));
        }
      }

      if (messages.isEmpty || messages.last['content'] != userPrompt) {
         chatMsgs.add(ChatMessage.user(userPrompt));
      }

      int iterations = 0;
      const maxIterations = 15;

      while (iterations < maxIterations && !_isCancelled) {
        iterations++;
        final accumulator = ChatStreamAccumulator();

        final List<Tool> availableTools = List.from(tools);
        if (!enableUiInteraction) {
           availableTools.removeWhere((t) => t.function.name == 'interact_with_ui');
        }

        final stream = client.chat.completions.createStream(
          ChatCompletionCreateRequest(
            model: ConfigService.get("ai_model") ?? 'default',
            messages: chatMsgs,
            tools: availableTools,
            toolChoice: ToolChoice.auto(),
          ),
        );

        await for (final chunk in stream) {
          if (_isCancelled) break;
          accumulator.add(chunk);
          final text = chunk.textDelta;
          if (text != null && text.isNotEmpty) {
            onTextChunk(accumulator.content.replaceAll("[DONE]", ""));
          }
        }

        if (_isCancelled) break;

        final accumulatedContent = accumulator.content.replaceAll("[DONE]", "");
        final toolCalls = accumulator.toolCalls;
        
        if (toolCalls.isNotEmpty) {
          chatMsgs.add(ChatMessage.assistant(
            content: accumulatedContent.isNotEmpty ? accumulatedContent : null,
            toolCalls: toolCalls,
          ));

          for (final tc in toolCalls) {
            if (_isCancelled) break;
            final name = tc.function.name;
            final Map<String, dynamic> args = jsonDecode(tc.function.arguments);
            onToolStart(name, args);
            final result = await _executeTool(name, tc.function.arguments, workingDir);
            onToolEnd(name, result);
            chatMsgs.add(ChatMessage.tool(toolCallId: tc.id, content: result));
          }
          continue; 
        } else {
          final xmlTool = _parseXmlToolCall(accumulatedContent);
          if (xmlTool != null) {
            final name = xmlTool['name'];
            final args = xmlTool['args'] as Map<String, dynamic>;
            onToolStart(name, args);
            final result = await _executeTool(name, jsonEncode(args), workingDir);
            onToolEnd(name, result);
            chatMsgs.add(ChatMessage.assistant(content: accumulatedContent));
            chatMsgs.add(ChatMessage.user("工具执行结果: $result"));
            continue; 
          }
        }

        if (accumulatedContent.isNotEmpty) {
           chatMsgs.add(ChatMessage.assistant(content: accumulatedContent));
        }
        break;
      }
    } catch (e) {
      onError("Agent Loop Error: $e");
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Map<String, dynamic>? _parseXmlToolCall(String content) {
    try {
      if (!content.contains("<tool_call>")) return null;
      final functionMatch = RegExp(r'<function=(.*?)>').firstMatch(content);
      if (functionMatch == null) return null;
      final name = functionMatch.group(1);
      final Map<String, dynamic> args = {};
      final paramMatches = RegExp(r'<parameter=(.*?)>(.*?)</parameter>', dotAll: true).allMatches(content);
      for (final m in paramMatches) {
        args[m.group(1)!] = m.group(2);
      }
      return {"name": name, "args": args};
    } catch (_) { return null; }
  }

  Future<String> _executeTool(String name, String argsJson, String workingDir) async {
    try {
      final Map<String, dynamic> args = jsonDecode(argsJson);
      switch (name) {
        case 'read_file':
          final file = File(p.join(workingDir, args['path']));
          return await file.exists() ? await file.readAsString() : "错误：文件不存在";
        case 'write_file':
          final file = File(p.join(workingDir, args['path']));
          await file.parent.create(recursive: true);
          await file.writeAsString(args['content']);
          return "成功：文件已写入";
        case 'get_directory_tree':
          return _generateDirTree(workingDir, args['path'] ?? "", args['max_depth'] ?? 3);
        case 'set_emotion':
        case 'set_emutation':
          _currentEmotion = args['emotion'] ?? "neutral";
          notifyListeners();
          return "情感已更新为: $_currentEmotion";
        case 'memory':
          final result = await MemoryStore.instance.add(args['target'], args['content'] ?? "");
          return jsonEncode(result);
        case 'execute_command':
          final command = args['command'] as String;
          try {
            final result = await Process.run('cmd', ['/c', command], workingDirectory: workingDir);
            String output = "";
            if (result.stdout.toString().isNotEmpty) output += result.stdout.toString();
            if (result.stderr.toString().isNotEmpty) {
              if (output.isNotEmpty) output += "\n--- ERR ---\n";
              output += result.stderr.toString();
            }
            return output.isEmpty ? "命令已执行（无输出）" : output;
          } catch (e) { return "命令执行失败: $e"; }
        case 'interact_with_ui':
          if (_uiAgent == null) return "错误：UI 交互 Agent 未初始化";
          final task = args['task'] as String;
          try {
            await _uiAgent!.run(task);
            return "UI 交互任务已尝试执行: $task";
          } catch (e) { return "UI 交互出错: $e"; }
        default:
          return "错误：未实现的工具 $name";
      }
    } catch (e) { return "执行工具出错: $e"; }
  }

  String _generateDirTree(String root, String subPath, int maxDepth) {
    final dir = Directory(p.join(root, subPath));
    if (!dir.existsSync()) return "目录不存在";
    StringBuffer sb = StringBuffer()..writeln("${p.basename(dir.path)}/");
    _walkDir(dir, sb, "", 1, maxDepth);
    return sb.toString();
  }

  void _walkDir(Directory dir, StringBuffer sb, String indent, int depth, int maxDepth) {
    if (depth > maxDepth) return;
    try {
      final entities = dir.listSync();
      for (int i = 0; i < entities.length; i++) {
        final e = entities[i];
        final isLast = i == entities.length - 1;
        sb.write("$indent${isLast ? "└── " : "├── "}${p.basename(e.path)}");
        if (e is Directory) {
          sb.writeln("/");
          _walkDir(e, sb, indent + (isLast ? "    " : "│   "), depth + 1, maxDepth);
        } else {
          sb.writeln("");
        }
      }
    } catch (_) {}
  }
}
