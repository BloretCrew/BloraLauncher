import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:ai_flutter_agent/ai_flutter_agent.dart';
import 'package:bloret_launcher/core/logger.dart';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/services/mod_service.dart';
import 'package:bloret_launcher/services/passport_service.dart';
import 'package:bloret_launcher/services/system_prompt.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:http/io_client.dart';
import 'package:openai_dart/openai_dart.dart' as oa;
import 'package:openai_dart/openai_dart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:genai/genai.dart';
import '../core/llm_interface.dart' as llm;
import 'llm/genai_adapter.dart';
import 'memory.dart';
import 'shizuku_service.dart';

/// Adapter for [LLMClient] using our [Bloriko] OpenAI client.
class BlorikoLLMClient implements LLMClient {
  @override
  Future<List<ActionDescriptor>> requestActions({
    required String prompt,
    required List<Map<String, dynamic>> toolSchemas,
    List<Map<String, dynamic>>? messages,
  }) async {
    final l = await AppLogger.getInstance();
    l.log("LLM requestActions Start", level: LogLevel.info, source: LogSource.network);
    Bloriko.instance._updateConnectionStatus(BlorikoConnectionStatus.connecting);

    final List<ChatMessage> chatMessages = [
      ChatMessage.system('You are a UI automation agent. Analyze the UI tree and task, then call the appropriate tools. If the task is done, return plain text.'),
    ];

    if (messages != null) {
      for (var m in messages) {
        if (m['role'] == 'user') {
          chatMessages.add(ChatMessage.user(m['content']));
        } else if (m['role'] == 'assistant') {
          chatMessages.add(ChatMessage.raw({
            'role': 'assistant',
            'content': m['content'],
            if (m['tool_calls'] != null) 'tool_calls': m['tool_calls'],
            if (m['reasoning_content'] != null) 'reasoning_content': m['reasoning_content'],
          }));
        } else if (m['role'] == 'tool') {
          chatMessages.add(ChatMessage.tool(
            toolCallId: m['tool_call_id'] ?? '',
            content: m['content']?.toString() ?? '',
          ));
        }
      }
    }

    chatMessages.add(ChatMessage.user(prompt));
    Bloriko.instance._updateConnectionStatus(BlorikoConnectionStatus.handshake);

    final provider = ConfigService.get("ai_provider") ?? "bloret_passport";

    if (provider == 'google_ai_studio') {
      l.log("Calling GenAIAdapter (Google AI Studio) - Tool calling disabled", level: LogLevel.info, source: LogSource.network);
      final adapter = GenAIAdapter(
        provider: ModelAPIProvider.gemini,
        apiKey: ConfigService.get("google_ai_key") ?? "",
        modelName: ConfigService.get("ai_model") ?? 'gemini-1.5-pro',
      );

      final stream = adapter.chat(
        messages: Bloriko.instance._convertToAgentMessages(chatMessages),
        tools: [],
      );

      await for (final _ in stream) {}
      Bloriko.instance._updateConnectionStatus(BlorikoConnectionStatus.finished);

      return [];
    }

    l.log("Calling OpenAI chat.completions.create", level: LogLevel.info, source: LogSource.network, detail: "Model: ${ConfigService.get("ai_model") ?? 'default'}");
    final startTime = DateTime.now();

    try {
      final response = await Bloriko.client.chat.completions.create(
        ChatCompletionCreateRequest(
          model: ConfigService.get("ai_model") ?? 'default',
          messages: chatMessages,
          tools: toolSchemas.map((s) => Tool.fromJson(s)).toList(),
          toolChoice: ToolChoice.auto(),
        ),
      );

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      l.log("LLM requestActions Response Received", level: LogLevel.info, source: LogSource.network, detail: "Duration: ${duration}ms");
      Bloriko.instance._updateConnectionStatus(BlorikoConnectionStatus.finished);

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
    } catch (e) {
      l.log("LLM requestActions Error", level: LogLevel.error, source: LogSource.network, detail: e.toString());
      Bloriko.instance._updateConnectionStatus(BlorikoConnectionStatus.error);
      rethrow;
    }
  }
}

enum BlorikoConnectionStatus { idle, connecting, handshake, streaming, finished, error }

class Bloriko extends ChangeNotifier {
  static Bloriko? _instance;
  static Bloriko get instance => _instance ??= Bloriko._();

  BlorikoConnectionStatus _connectionStatus = BlorikoConnectionStatus.idle;
  BlorikoConnectionStatus get connectionStatus => _connectionStatus;

  void _updateConnectionStatus(BlorikoConnectionStatus status) {
    _connectionStatus = status;
    notifyListeners();
  }

  static final ValueNotifier<String> typeNotifier = ValueNotifier(ConfigService.get("bloriko_type") ?? "default");
  static final ValueNotifier<String> modeNotifier = ValueNotifier(ConfigService.get("bloriko_mode") ?? "auto");

  static String get type => typeNotifier.value;
  static set type(String value) {
    if (typeNotifier.value == value) return;
    typeNotifier.value = value;
    ConfigService.set("bloriko_type", value);
    instance.notifyListeners();
  }

  static String get mode => modeNotifier.value;
  static set mode(String value) {
    if (modeNotifier.value == value) return;
    modeNotifier.value = value;
    ConfigService.set("bloriko_mode", value);
    instance.notifyListeners();
  }

  static Future<void> setType(String newType) async {
    type = newType;
  }

  static Future<void> setMode(String newMode) async {
    mode = newMode;
  }

  static String key = "";
  String? _currentRequestId;

  static OpenAIClient get client {
    final provider = ConfigService.get("ai_provider") ?? "bloret_passport";
    String baseUrl = 'https://passport.bloret.net/v1';
    String apiKey = key;

    if (provider == 'google_ai_studio') {
      baseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai/';
      apiKey = ConfigService.get("google_ai_key") ?? "";
    } else if (provider == 'custom_api') {
      baseUrl = ConfigService.get("custom_ai_base_url") ?? "https://api.openai.com/v1";
      apiKey = ConfigService.get("custom_ai_key") ?? "";
    } else if (provider == 'opencode_zen') {
      baseUrl = 'https://passport.bloret.net/v1';
      apiKey = key;
    }

    final httpClient = HttpClient()
      ..idleTimeout = const Duration(minutes: 2)
      ..connectionTimeout = const Duration(seconds: 25);

    return OpenAIClient(
      config: OpenAIConfig(
        authProvider: ApiKeyProvider(apiKey),
        baseUrl: baseUrl,
      ),
      httpClient: IOClient(
        httpClient
      ),
    );
  }

  final List<Map<String, dynamic>> messages = [];
  String conversationTitle = "";
  String? currentSessionFile;
  int requestBatch = 0;
  bool _busy = false;
  bool get busy => _busy;

  String? currentTool;
  String? initialPrompt;

  String _currentEmotion = "neutral";
  String get emotion => _currentEmotion;

  bool _isCancelled = false;

  Completer<String>? _questionCompleter;
  Completer<String>? _questionDetailCompleter;
  Completer<String>? _securityCompleter;

  FlutterAgentBridge? _uiAgent;
  ActionRegistry? _actionRegistry;

  // ignore: unused_field
  AgentWorker? _worker;

  Bloriko._() {
    _initUiAgent();
    _initWorker();
    _loadWhitelist();
  }

  Future<void> _initWorker() async {
    final workspace = await _getWorkspaceDir();

    final subActionRegistry = ActionRegistry();
    BuiltInActions.registerDefaults(
      subActionRegistry,
      performAction: (nodeId, action, {actionArgs}) async {
        // ignore: deprecated_member_use
        RendererBinding.instance.pipelineOwner.semanticsOwner?.performAction(nodeId, action, actionArgs);
      },
    );

    _worker = await AgentWorker.create(
      workingDir: workspace.path,
      actionRegistry: subActionRegistry,
    );
  }

  Future<Directory> _getWorkspaceDir() async {
    final appDir = await getSupportData();
    final workspaceDir = Directory(p.join(appDir.path, 'blora_agent', 'workspace'));
    if (!await workspaceDir.exists()) {
      await workspaceDir.create(recursive: true);
    }
    return workspaceDir;
  }


  void _initUiAgent() {
    final treeWalker = SemanticTreeWalker();
    _actionRegistry = ActionRegistry();

    BuiltInActions.registerDefaults(
      _actionRegistry!,
      performAction: (nodeId, action, {actionArgs}) async {
        // ignore: deprecated_member_use
        RendererBinding.instance.pipelineOwner.semanticsOwner?.performAction(nodeId, action, actionArgs);
      }
    );

    _uiAgent = FlutterAgentBridge(
      core: AgentCore(
        config: const AgentConfig(debugMode: true, maxSteps: 1),
        treeWalker: treeWalker,
        planner: Planner(
          llmClient: BlorikoLLMClient(),
          actionRegistry: _actionRegistry!,
        ),
        executor: Executor(
          actionRegistry: _actionRegistry!,
          auditLog: AuditLog(),
        ),
        verifier: Verifier(treeWalker: treeWalker),
      ),
      walker: treeWalker,
    );
  }

  Set<String> _whitelist = {};
  Future<void> _loadWhitelist() async {
    try {
      final appDir = await getSupportData();
      final file = File(p.join(appDir.path, 'blora_agent', 'security', 'command_whitelist.json'));
      if (await file.exists()) {
        final List data = jsonDecode(await file.readAsString());
        _whitelist = data.cast<String>().toSet();
      }
    } catch (_) {}
  }

  Future<void> _saveWhitelist() async {
    try {
      final appDir = await getSupportData();
      final file = File(p.join(appDir.path, 'blora_agent', 'security', 'command_whitelist.json'));
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_whitelist.toList()));
    } catch (_) {}
  }

  void handleSecurityAction(String action, {String? command}) {
    if (_securityCompleter != null && !_securityCompleter!.isCompleted) {
      for (int i = messages.length - 1; i >= 0; i--) {
        if (messages[i]['role'] == 'security' && messages[i]['status'] == 'waiting') {
          messages[i]['status'] = 'handled';
          messages[i]['result'] = action;
          break;
        }
      }

      if (action == 'always' && command != null) {
        _whitelist.add(command);
        _saveWhitelist();
        _securityCompleter!.complete("allow");
      } else {
        _securityCompleter!.complete(action);
      }
      notifyListeners();
    }
  }

  static Bloriko getInstance([String key = ""]) {
    type = ConfigService.get("bloriko_type") ?? "default";
    mode = ConfigService.get("bloriko_mode") ?? "auto";

    if (key.isNotEmpty) {
      Bloriko.key = key;
    } else {
      final String customKey = ConfigService.get("Custom_AI_Key") ?? "";
      if (customKey.isNotEmpty) {
        Bloriko.key = customKey;
      } else {
        Bloriko.key = "${PassportService.appId};${PassportService.appSecret};${ConfigService.get("Bloret_PassPort_Token")}";
      }
    }
    return instance;
  }

  static Future<void> setCustomKey(String newKey) async {
    await ConfigService.set("Custom_AI_Key", newKey);
    getInstance(newKey);
  }

  void clearSession() {
    messages.clear();
    conversationTitle = "";
    currentSessionFile = null;
    _currentEmotion = "neutral";
    currentTool = null;
    notifyListeners();
  }

  void startNewSession(String prompt) {
    clearSession();
    initialPrompt = prompt;
    notifyListeners();
  }

  void cancelAgent() {
    _isCancelled = true;
    _uiAgent?.core.stop();
    if (_questionCompleter != null && !_questionCompleter!.isCompleted) {
      _questionCompleter!.completeError("cancelled");
    }
    if (_questionDetailCompleter != null && !_questionDetailCompleter!.isCompleted) {
      _questionDetailCompleter!.completeError("cancelled");
    }
    if (_securityCompleter != null && !_securityCompleter!.isCompleted) {
      _securityCompleter!.completeError("cancelled");
    }
    _busy = false;
    _updateConnectionStatus(BlorikoConnectionStatus.idle);
    notifyListeners();
  }

  void answerQuestion(String answer) {
    if (_questionCompleter != null && !_questionCompleter!.isCompleted) {
      _questionCompleter!.complete(answer);
    }
  }

  void answerDetailQuestion(String answer) {
    if (_questionDetailCompleter != null && !_questionDetailCompleter!.isCompleted) {
      _questionDetailCompleter!.complete(answer);
    }
  }

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
      name: 'memory',
      description: '管理你的记忆。支持添加、替换、删除记忆条目。',
      parameters: {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'description': '操作类型：add（添加）、replace（替换）、remove（删除）、list（查看）',
            'enum': ["add", "replace", "remove", "list"]
          },
          'target': {
            'type': 'string',
            'description': '目标：memory（记忆）或 user（用户画像）',
            'enum': ["memory", "user"]
          },
          'content': {
            'type': 'string',
            'description': '新内容（add 和 replace 时使用）'
          },
          'old_text': {
            'type': 'string',
            'description': '要匹配的旧文本（replace 和 remove 时使用，支持子字符串匹配）'
          }
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
      name: 'perform_ui_actions',
      description: '合批执行一组具体的 UI 动作。适用于已知节点 ID 的情况，响应极其迅速。一次思考，瞬间执行多个操作。',
      parameters: {
        'type': 'object',
        'properties': {
          'actions': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'action': {'type': 'string', 'enum': ['tap', 'setText', 'scrollUp', 'scrollDown']},
                'id': {'type': 'string', 'description': '目标节点 ID'},
                'text': {'type': 'string', 'description': '输入文字（仅 setText 需要）'}
              },
              'required': ['action', 'id']
            }
          }
        },
        'required': ['actions']
      },
    ),
    Tool.function(
      name: 'set_user_identity',
      description: '静默记录用户身份（哥哥、姐姐、妹妹）。仅在完全确定时调用。',
      parameters: {
        'type': 'object',
        'properties': {
          'identity': {'type': 'string', 'enum': ['brother', 'sister', 'little_sister']}
        },
        'required': ['identity']
      },
    ),
    // Tool.function(
    //   name: 'delegate_task',
    //   description: '将复杂任务委派给全能型子 Agent 处理。子 Agent 会利用所有工具完成任务，执行完后直接返回最终结果，期间保持静默。',
    //   parameters: {
    //     'type': 'object',
    //     'properties': {
    //       'task': {'type': 'string', 'description': '需要完成的任务描述'}
    //     },
    //     'required': ['task']
    //   },
    // ),
    Tool.function(
      name: 'delegate_ui_task',
      description: '将复杂 UI 任务委派给子 Agent 处理。子 Agent 会执行所有必要动作，执行完后直接返回最终结果，期间保持静默，不进行对话。',
      parameters: {
        'type': 'object',
        'properties': {
          'task': {'type': 'string', 'description': '需要完成的 UI 操作目标'}
        },
        'required': ['task']
      },
    ),
    Tool.function(
      name: 'interact_with_ui',
      description:
      '执行单个具体的 Flutter UI 交互任务（如“点击设置”）。请不要一次性要求执行复杂的连串操作，以免产生多次误点击。',
      parameters: {
        'type':'object',
        'properties': {
          'task': {
            'type':'string',
            'description':'需要完成的 UI 操作目标。'
          }
        },
        'required':['task']
      },
    ),
    Tool.function(
      name: 'get_semantics_tree',
      description: '获取当前 Flutter 应用的语义树，用于理解当前界面有哪些可交互元素及其 ID。',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    Tool.function(
      name: 'recall_history',
      description: '回忆之前的对话。返回历史对话的列表和简要开头，帮助你记起之前聊过什么。',
      parameters: {
        'type': 'object',
        'properties': {
          'count': {
            'type': 'integer',
            'description': '要回忆的对话条数，默认为 5。'
          }
        },
      },
    ),
    Tool.function(
      name: 'web_search',
      description: '使用 Tavily 搜索引擎在互联网上搜索信息。请严格遵守当地法律法规和 Prompt 规范。支持翻页查看更多结果。',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索查询关键词'
          },
          'count': {
            'type': 'integer',
            'description': '返回结果条数，默认为 5',
            'default': 5
          },
          'page': {
            'type': 'integer',
            'description': '起始页码（从 1 开始）',
            'default': 1
          }
        },
        'required': ['query']
      },
    ),
    Tool.function(
      name: 'ask_question',
      description: '向用户提问并提供多个选项供其选择。适用于需要用户确认或提供偏好的场景。',
      parameters: {
        'type': 'object',
        'properties': {
          'question': {
            'type': 'string',
            'description': '要问用户的问题内容'
          },
          'options': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '可供选择的选项列表'
          }
        },
        'required': ['question', 'options']
      },
    ),
    Tool.function(
      name: 'ask_question_details',
      description: '向用户提问并提供输入框供其输入。适用于需要用户确定极为个性化的场景。',
      parameters: {
        'type': 'object',
        'properties': {
          'question': {
            'type': 'string',
            'description': '要问用户的问题内容'
          },
          'description': {
            'type': 'string',
            'description': '输入框中的描述'
          }
        },
        'required': ['question', 'description']
      },
    ),
    Tool.function(
      name: 'fetch_page',
      description: '读取指定网页内容，用于获取网页正文信息。',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': '需要读取的网址'
          }
        },
        'required': [
          'url'
        ]
      },
    ),
    Tool.function(
      name: 'shizuku_init',
      description: '【仅 Android】初始化 Shizuku 服务并请求权限。如果用户想要执行高权限命令，必须先调用此工具。',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    Tool.function(
      name: 'shizuku_check_permission',
      description: '【仅 Android】检查当前是否已获得 Shizuku 权限。',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    Tool.function(
      name: 'shizuku_run_shell',
      description: '【仅 Android】使用 Shizuku 以更高权限（通常是 Shell/ADB权限）执行命令。仅在普通 execute_command 无法完成任务（如修改系统设置、安装应用、管理其他进程）且用户明确要求提权时使用。',
      parameters: {
        'type': 'object',
        'properties': {
          'command': {'type': 'string', 'description': '要执行的高权限命令'}
        },
        'required': ['command']
      },
    ),
    Tool.function(
      name: 'modrinth_search',
      description: '在 Modrinth 上搜索 Minecraft 模组。支持按版本和加载器过滤。',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '搜索关键词'},
          'game_version': {'type': 'string', 'description': '游戏版本，如 1.20.1'},
          'loader': {'type': 'string', 'description': '加载器类型，如 fabric, forge, quilt'},
          'limit': {'type': 'integer', 'description': '返回结果数量，默认 8'},
        },
        'required': ['query']
      },
    ),
    Tool.function(
      name: 'modrinth_get_project',
      description: '获取 Modrinth 项目的详细信息。',
      parameters: {
        'type': 'object',
        'properties': {
          'slug_or_id': {'type': 'string', 'description': '项目的 slug 或 ID'}
        },
        'required': ['slug_or_id']
      },
    ),
  ];

  Future<void> chatWithTools(
    dynamic userContent, {
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
    final String currentRequestId = DateTime.now().toIso8601String();
    _currentRequestId = currentRequestId;
    notifyListeners();

    final l = await AppLogger.getInstance();
    l.log("LLM Request Start", level: LogLevel.info, source: LogSource.network);

    try {
      final List<ChatMessage> chatMsgs = [
        ChatMessage.system(buildSystemPrompt(
          MemoryStore.instance,
          workingDir,
          currentEmotion: _currentEmotion,
          uiEnabled: enableUiInteraction,
        )),
      ];
      l.log("System Prompt Built", level: LogLevel.debug, source: LogSource.network, detail: "Length: ${chatMsgs.first.toString().length}");

      final historicalMsgs = messages.length > 10 ? messages.sublist(messages.length - 10) : messages;

      for (var msg in historicalMsgs) {
        final role = msg['role'];
        final content = msg['content'];
        if (role == 'user') {
          if (content is String) {
            chatMsgs.add(ChatMessage.user(content));
          } else if (content is List) {
            chatMsgs.add(ChatMessage.user(content.map((p) {
              if (p['type'] == 'text' || p['type'] == 'input_text') {
                return ContentPart.text(p['text'] ?? '');
              } else if (p['type'] == 'image_url' || p['type'] == 'input_image') {
                return ContentPart.imageUrl(p['image_url'] ?? '');
              } else if (p['type'] == 'input_file') {
                final data = p['file_data'] as String? ?? '';
                final filename = p['filename'] as String? ?? 'file.txt';
                final mediaType = filename.toLowerCase().endsWith('.pdf') ? 'application/pdf' : 'text/plain';
                return ContentPart.fileData(data: data, mediaType: mediaType, filename: filename);
              }
              return ContentPart.text('');
            }).toList()));
          }
        } else if (role == 'assistant') {
          chatMsgs.add(ChatMessage.raw({
            'role': 'assistant',
            'content': msg['content'],
            if (msg['tool_calls'] != null) 'tool_calls': msg['tool_calls'],
            if (msg['reasoning_content'] != null) 'reasoning_content': msg['reasoning_content'],
          }));
        } else if (role == 'tool') {
          chatMsgs.add(ChatMessage.tool(
            toolCallId: msg['tool_call_id'] ?? '',
            content: msg['content']?.toString() ?? '',
          ));
        }
      }
      l.log("History Prepared", level: LogLevel.debug, source: LogSource.network, detail: "Messages: ${chatMsgs.length}");

      if (userContent is String) {
        chatMsgs.add(ChatMessage.user(userContent));
      } else if (userContent is List) {
        chatMsgs.add(ChatMessage.user(userContent.map((p) {
          if (p['type'] == 'text' || p['type'] == 'input_text') {
            return ContentPart.text(p['text'] ?? '');
          } else if (p['type'] == 'image_url' || p['type'] == 'input_image') {
            return ContentPart.imageUrl(p['image_url'] ?? '');
          } else if (p['type'] == 'input_file') {
            final data = p['file_data'] as String? ?? '';
            final filename = p['filename'] as String? ?? 'file.txt';
            final mediaType = filename.toLowerCase().endsWith('.pdf') ? 'application/pdf' : 'text/plain';
            return ContentPart.fileData(data: data, mediaType: mediaType, filename: filename);
          }
          return ContentPart.text('');
        }).toList()));
      }

      int iterations = 0;
      int searchCount = 0;
      const maxIterations = 15;

      while (iterations < maxIterations && !_isCancelled && _currentRequestId == currentRequestId) {
        iterations++;
        l.log("Iteration $iterations Start", level: LogLevel.debug, source: LogSource.network);
        final accumulator = ChatStreamAccumulator();

        final List<Tool> availableTools = List.from(tools);
        if (!enableUiInteraction) {
           availableTools.removeWhere((t) => t.function.name == 'interact_with_ui');
           availableTools.removeWhere((t) => t.function.name == 'get_semantics_tree');
           availableTools.removeWhere((t) => t.function.name == 'perform_ui_actions');
        }

        if (Bloriko.mode == "plan") {
          availableTools.removeWhere((t) => t.function.name == 'interact_with_ui');
          availableTools.removeWhere((t) => t.function.name == 'get_semantics_tree');
          availableTools.removeWhere((t) => t.function.name == 'perform_ui_actions');
          availableTools.removeWhere((t) => t.function.name == 'shizuku_init');
          availableTools.removeWhere((t) => t.function.name == 'shizuku_check_permission');
          availableTools.removeWhere((t) => t.function.name == 'shizuku_run_shell');
          availableTools.removeWhere((t) => t.function.name == 'execute_command');
        }

        if (!Platform.isAndroid) {
          availableTools.removeWhere((t) => t.function.name == 'shizuku_init');
          availableTools.removeWhere((t) => t.function.name == 'shizuku_check_permission');
          availableTools.removeWhere((t) => t.function.name == 'shizuku_run_shell');
        }

        if (searchCount >= 6) {
          availableTools.removeWhere((t) => t.function.name == 'web_search');
          chatMsgs.add(ChatMessage.system("你已经尝试搜索了 6 次。如果仍未找到，请如实告知用户搜不到。"));
        }

        final provider = ConfigService.get("ai_provider") ?? "bloret_passport";
        String genAiContent = "";
        String genAiReasoning = "";

        l.log("Stream API Call Initiated", level: LogLevel.info, source: LogSource.network, detail: "Iteration: $iterations, Provider: $provider");
        final apiStartTime = DateTime.now();
        _updateConnectionStatus(BlorikoConnectionStatus.connecting);

        try {
          if (_isCancelled || _currentRequestId != currentRequestId) break;
          
          final Stream stream;
          if (provider == 'google_ai_studio') {
            final adapter = GenAIAdapter(
              provider: ModelAPIProvider.gemini,
              apiKey: ConfigService.get("google_ai_key") ?? "",
              modelName: ConfigService.get("ai_model") ?? 'gemini-1.5-pro',
            );
            stream = adapter.chat(
              messages: _convertToAgentMessages(chatMsgs),
              tools: _convertToAgentTools(availableTools, workingDir),
            );
          } else {
            stream = client.chat.completions.createStream(
              ChatCompletionCreateRequest(
                model: ConfigService.get("ai_model") ?? 'default',
                messages: chatMsgs,
                tools: availableTools,
                toolChoice: ToolChoice.auto(),
                reasoningEffort: ReasoningEffort.low,
              ),
            );
          }

          l.log("Stream Connection Established", level: LogLevel.debug, source: LogSource.network);
          _updateConnectionStatus(BlorikoConnectionStatus.handshake);

          bool firstChunk = true;
          await for (final chunk in stream) {
            if (_isCancelled || _currentRequestId != currentRequestId) break;
            if (firstChunk) {
              final duration = DateTime.now().difference(apiStartTime).inMilliseconds;
              l.log("First Stream Chunk Received (TTFB)", level: LogLevel.info, source: LogSource.network, detail: "Wait time: ${duration}ms");
              firstChunk = false;
              _updateConnectionStatus(BlorikoConnectionStatus.streaming);
            }

            if (chunk is ChatStreamEvent) {
              accumulator.add(chunk);
              final text = chunk.textDelta;
              if (text != null && text.isNotEmpty) {
                final fullContent = accumulator.content.replaceAll("[DONE]", "");
                _internalUpdateLastAssistantMessage(fullContent);
                onTextChunk(fullContent);
              }
            } else if (chunk is llm.LLMChunk) {
              if (chunk.text != null) {
                genAiContent += chunk.text!;
                _internalUpdateLastAssistantMessage(genAiContent);
                onTextChunk(genAiContent);
              }
            }
          }
          if (_isCancelled || _currentRequestId != currentRequestId) {
            l.log("Stream Interrupted by Cancellation", level: LogLevel.info, source: LogSource.network);
            _updateConnectionStatus(BlorikoConnectionStatus.idle);
            break;
          }
          l.log("Stream Consumed Completely", level: LogLevel.info, source: LogSource.network, detail: "Total duration: ${DateTime.now().difference(apiStartTime).inMilliseconds}ms");
          _updateConnectionStatus(BlorikoConnectionStatus.finished);
        } catch (e) {
          if (_isCancelled || _currentRequestId != currentRequestId) return;
          final l = await AppLogger.getInstance();
          l.log("网络连接异常或模型响应出错", level: LogLevel.error, source: LogSource.network, detail: e.toString());
          _internalAddMessage({'role': 'error', 'title': "网络异常", 'content': "网络连接异常或模型响应出错: $e"});
          onError("网络连接异常或模型响应出错: $e");
          _updateConnectionStatus(BlorikoConnectionStatus.error);
          return;
        }

        if (_isCancelled || _currentRequestId != currentRequestId) break;

        final accumulatedContent = (provider == 'google_ai_studio') 
            ? genAiContent.trim()
            : accumulator.content.replaceAll("[DONE]", "").trim();
            
        final List<oa.ToolCall> toolCalls = (provider == 'google_ai_studio')
            ? []
            : accumulator.toolCalls;

        if (accumulatedContent.isEmpty && toolCalls.isEmpty) {
          _internalAddMessage({'role': 'error', 'title': "空回复", 'content': "AI 返回内容为空，请检查 API 状态。"});
          onError("AI 返回内容持续为空，请检查 API 状态。");
          break;
        }

        if (toolCalls.isNotEmpty) {
          chatMsgs.add(ChatMessage.raw({
            'role': 'assistant',
            'content': accumulatedContent.isNotEmpty ? accumulatedContent : null,
            'tool_calls': toolCalls.map((t) => t.toJson()).toList(),
          }));

          for (final tc in toolCalls) {
            if (_isCancelled || _currentRequestId != currentRequestId) break;
            final name = tc.function.name;
            if (name == 'web_search') searchCount++;
            final Map<String, dynamic> args = jsonDecode(tc.function.arguments);

            _internalAddSystemMessage(name, args);
            onToolStart(name, args);

            currentTool = _getToolFriendlyName(name);
            notifyListeners();

            final result = await _executeTool(name, tc.function.arguments, workingDir);

            currentTool = null;
            _internalUpdateSystemMessage(name, result);
            onToolEnd(name, result);

            if (messages.isNotEmpty && messages.last['role'] == 'assistant') {
              messages.last['tool_calls'] = toolCalls.map((t) => t.toJson()).toList();

              final finalReasoning = (provider == 'google_ai_studio') 
                  ? genAiReasoning 
                  : accumulator.reasoning;
                  
              if (finalReasoning.isNotEmpty) {
                messages.last['reasoning_content'] = finalReasoning;
              }
            }

            chatMsgs.add(ChatMessage.raw({
              'role': 'tool',
              'tool_call_id': tc.id,
              'name': tc.function.name,
              'content': result,
            }));

            _internalAddMessage({
              'role': 'tool',
              'tool_call_id': tc.id,
              'content': result,
            });
          }
          continue;
        } else {
          // Google AI Studio 模式下跳过 XML 工具解析，仅限其他供应商
          final xmlTool = (provider == 'google_ai_studio') ? null : _parseXmlToolCall(accumulatedContent);
          if (xmlTool != null) {
            final name = xmlTool['name'];
            final args = xmlTool['args'] as Map<String, dynamic>;

            _internalAddSystemMessage(name, args);
            onToolStart(name, args);

            currentTool = _getToolFriendlyName(name);
            notifyListeners();

            final result = await _executeTool(name, jsonEncode(args), workingDir);

            currentTool = null;
            _internalUpdateSystemMessage(name, result);
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
      final l = await AppLogger.getInstance();
      l.log("Agent Loop 核心异常", level: LogLevel.error, source: LogSource.system, detail: e.toString());
      _internalAddMessage({'role': 'error', 'title': "Agent Loop Error", 'content': "Agent Loop Error: $e"});
      onError("Agent Loop Error: $e");
    } finally {
      if (_currentRequestId == currentRequestId) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  void _internalAddMessage(Map<String, dynamic> msg) {
    messages.add(msg);
    notifyListeners();
  }

  void _internalUpdateLastAssistantMessage(String content) {
    if (messages.isNotEmpty && messages.last['role'] == 'assistant') {
      messages.last['content'] = content;
      messages.last['emotion'] = _currentEmotion;
    } else {
      messages.add({
        'role': 'assistant',
        'content': content,
        'emotion': _currentEmotion,
      });
    }
    notifyListeners();
  }

  void _internalAddSystemMessage(String toolName, Map<String, dynamic> args) {
    final friendlyName = _getToolFriendlyName(toolName);

    if (messages.isNotEmpty &&
        messages.last['role'] == 'system' &&
        messages.last['tool'] == toolName) {

      final last = messages.last;
      final newCount = (last['count'] ?? 1) + 1;
      last['count'] = newCount;
      last['status'] = 'running';
      last['content'] = "正在执行工具: $friendlyName x$newCount";
      last['isExpanded'] = toolName == 'ask_question' || toolName == 'ask_question_details';
      last['_detailIdx'] = newCount - 1;

      List calls = last['calls'] ?? [];
      calls.add({'args': jsonEncode(args), 'status': 'running'});
      last['calls'] = calls;

      last['args'] = jsonEncode(args);
      last['result'] = null;

      notifyListeners();
      return;
    }

    messages.add({
      'role': 'system',
      'content': "正在执行工具: $friendlyName",
      'tool': toolName,
      'args': jsonEncode(args),
      'isExpanded': toolName == 'ask_question' || toolName == 'ask_question_details',
      'status': 'running',
      'count': 1,
      'calls': [{'args': jsonEncode(args), 'status': 'running'}],
    });
    notifyListeners();
  }

  void _internalUpdateSystemMessage(String toolName, String result) {
    final friendlyName = _getToolFriendlyName(toolName);
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i]['role'] == 'system' &&
          messages[i]['tool'] == toolName &&
          messages[i]['status'] == 'running') {

        final msg = messages[i];
        final count = msg['count'] ?? 1;
        msg['content'] = "执行工具完毕: $friendlyName${count > 1 ? " x$count" : ""}";
        msg['result'] = result;
        msg['status'] = 'done';
        if (toolName == 'ask_question') {
           msg['isExpanded'] = false;
        }

        List calls = msg['calls'] ?? [];
        if (calls.isNotEmpty) {
          for (int j = calls.length - 1; j >= 0; j--) {
            if (calls[j]['status'] == 'running') {
              calls[j]['result'] = result;
              calls[j]['status'] = 'done';
              break;
            }
          }
        }
        break;
      }
    }
    notifyListeners();
  }

  String _getToolFriendlyName(String name) {
    switch (name) {
      case 'read_file': return "读取文件";
      case 'write_file': return "写入文件";
      case 'get_directory_tree': return "查看目录树";
      case 'set_emotion':
      case 'set_emutation': return "切换心情";
      case 'memory': return "管理记忆";
      case 'list_files': return "列出文件";
      case 'execute_command': return "执行命令";
      case 'interact_with_ui': return "辅助点击";
      case 'perform_ui_actions': return "批量操作";
      case 'get_semantics_tree': return "查看语义树";
      case 'recall_history': return "回忆对话";
      case 'web_search': return "网页搜索";
      case 'ask_question': return "向你提问";
      case 'ask_question_details': return "详细提问";
      case 'fetch_page': return "抓取网页";
      case 'set_user_identity': return "记录身份";
      case 'delegate_task': return "委派子任务";
      case 'shizuku_init': return "初始化 Shizuku";
      case 'shizuku_check_permission': return "检查 Shizuku 权限";
      case 'shizuku_run_shell': return "Shizuku 权限命令";
      case 'modrinth_search': return "搜索 Modrinth";
      case 'modrinth_get_project': return "获取项目详情";
      default: return "未知工具";
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
    final l = await AppLogger.getInstance();
    l.log("Tool Execution Start: $name", level: LogLevel.info, source: LogSource.tool);
    final startTime = DateTime.now();

    try {
      final Map<String, dynamic> args = jsonDecode(argsJson);
      String resultText = "";
      switch (name) {
        case 'read_file':
          final file = File(p.join(workingDir, args['path']));
          resultText = await file.exists() ? await file.readAsString() : "错误：文件不存在";
          break;
        case 'write_file':
          final file = File(p.join(workingDir, args['path']));
          await file.parent.create(recursive: true);
          await file.writeAsString(args['content']);
          resultText = "成功：文件已写入";
          break;
        case 'get_directory_tree':
          resultText = _generateDirTree(workingDir, args['path'] ?? "", args['max_depth'] ?? 3);
          break;
        case 'set_emotion':
        case 'set_emutation':
          _currentEmotion = args['emotion'] ?? "neutral";
          notifyListeners();
          resultText = "情感已更新为: $_currentEmotion";
          break;
        case 'memory':
          final action = args['action'] as String;
          final target = args['target'] as String;
          final content = args['content'] ?? "";
          final oldText = args['old_text'] ?? "";

          dynamic result;
          if (action == 'add') {
            result = await MemoryStore.instance.add(target, content);
          } else if (action == 'replace') {
            result = await MemoryStore.instance.replace(target, oldText, content);
          } else if (action == 'remove') {
            result = await MemoryStore.instance.remove(target, oldText);
          } else if (action == 'list') {
            resultText = MemoryStore.instance.getAllEntries(target);
            break;
          } else {
            resultText = "错误：未知的记忆操作 $action";
            break;
          }
          resultText = jsonEncode(result);
          break;
        case 'execute_command':
          final command = args['command'] as String;

          final commands = splitShellCommands(command);

          for (final cmd in commands) {
            final main = getMainCommand(cmd);

            if (!_whitelist.contains(main)) {
              _securityCompleter = Completer<String>();

              _internalAddMessage({
                'role': 'security',
                'command': cmd,
                'status': 'waiting'
              });

              notifyListeners();

              final decision = await _securityCompleter!.future;
              _securityCompleter = null;

              if (decision == 'deny') {
                resultText = "拒绝执行：用户未授权此命令。";
                break;
              }
            }
          }

          if (resultText.isNotEmpty) break;

          try {
            final result = await Process.run('cmd', ['/c', command], workingDirectory: workingDir);
            String output = "";
            if (result.stdout.toString().isNotEmpty) output += result.stdout.toString();
            if (result.stderr.toString().isNotEmpty) {
              if (output.isNotEmpty) output += "\n--- ERR ---\n";
              output += result.stderr.toString();
            }
            resultText = output.isEmpty ? "命令已执行（无输出）" : output;
          } catch (e) {
            final l = await AppLogger.getInstance();
            l.log("执行命令失败", level: LogLevel.error, source: LogSource.tool, detail: "Command: $command\nError: $e");
            resultText = "命令执行失败: $e";
          }
          break;
        case 'get_semantics_tree':
          if (_uiAgent == null) {
            resultText = "错误：UI Agent 未初始化";
            break;
          }

          try {
            final tree = _uiAgent!.getSemanticsTree();
            if (tree == null) {
              resultText = "错误：无法获取语义树，请确保 Semantics 已启用";
              break;
            }
            debugPrint(tree.toString());
            final simplifiedTree = simplifySemanticsTree(tree);
            if (simplifiedTree == null) {
              resultText = "错误：无法简化语义树";
              break;
            }
            debugPrint(simplifiedTree.toString());
            resultText = jsonEncode(simplifiedTree);
          } catch (e) {
            final l = await AppLogger.getInstance();
            l.log("获取语义树失败", level: LogLevel.error, source: LogSource.ui, detail: e.toString());
            resultText = "获取语义树失败: $e";
          }
          break;
        case 'perform_ui_actions':
          if (_actionRegistry == null) {
            resultText = "错误：ActionRegistry 未就绪";
            break;
          }
          final List actionsList = args['actions'] ?? [];
          final List<Map<String, dynamic>> results = [];
          for (var item in actionsList) {
            final String actName = item['action'];
            final String nodeId = item['id'].toString();
            final String? text = item['text'];
            try {
              await _actionRegistry!.execute(actName, {'id': nodeId, 'text': ?text});
              results.add({"action": actName, "id": nodeId, "success": true});
              await Future.delayed(const Duration(milliseconds: 150));
            } catch (e) {
              results.add({"action": actName, "id": nodeId, "success": false, "error": e.toString()});
              break;
            }
          }
          await Future.delayed(const Duration(milliseconds: 800));
          resultText = jsonEncode(results);
          break;

        case 'interact_with_ui':
          if (_uiAgent == null) {
            resultText = jsonEncode({
              "success": false,
              "error": "UI Agent 未初始化",
            });
            break;
          }

          final task = args['task'] as String?;

          if (task == null || task.isEmpty) {
            resultText = jsonEncode({
              "success": false,
              "error": "缺少 task",
            });
            break;
          }

          try {
            await _uiAgent!.run(task);

            await Future.delayed(const Duration(milliseconds: 1500));

            final state = _uiAgent!.core.state;

            resultText = jsonEncode({
              "success": state.status.name == "completed",
              "task": task,
              "status": state.status.name,
              "steps": state.stepCount,
              if (state.lastError != null)
                "error": state.lastError,
            });
          } catch (e) {
            final l = await AppLogger.getInstance();
            l.log("UI 交互出错", level: LogLevel.error, source: LogSource.ui, detail: "Task: $task\nError: $e");
            resultText = jsonEncode({
              "success": false,
              "task": task,
              "error": e.toString(),
            });
          }
          break;
        case 'recall_history':
          resultText = await _executeRecallHistory(args['count'] ?? 5);
          break;
        case 'web_search':
          resultText = await _executeWebSearch(args['query'], count: args['count'] ?? 5,);
          break;
        case 'ask_question':
          _questionCompleter = Completer<String>();
          final DateTime startTime = DateTime.now();
          notifyListeners();
          final answer = await _questionCompleter!.future;
          _questionCompleter = null;

          final double duration = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
          resultText = "$answer (用户选择时长: ${duration.toStringAsFixed(1)}s)";
          break;
        case 'set_user_identity':
          final identity = args['identity'] as String;
          await ConfigService.set("user_identity", identity);
          resultText = "成功：身份已记录为 $identity";
          break;
        case 'ask_question_details':
          _questionDetailCompleter = Completer<String>();
          final DateTime startTime = DateTime.now();
          notifyListeners();
          final answer = await _questionDetailCompleter!.future;
          _questionDetailCompleter = null;

          final double duration = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
          resultText = "$answer (用户输入时长: ${duration.toStringAsFixed(1)}s)";
          break;
        case 'fetch_page':
          final url = args['url'] as String?;
          if (url == null || url.isEmpty) {
            resultText = "错误：缺少 url";
            break;
          }
          resultText = await _executeFetchPage(url);
          break;
        case 'shizuku_init':
          if (!Platform.isAndroid) {
            resultText = "错误：Shizuku 仅支持 Android 平台";
            break;
          }
          final status = await ShizukuService.init();
          final statusMap = {0: "成功(已获权)", 1: "失败", 2: "不支持", 3: "正在授权/运行", -1: "未知"};
          resultText = "Shizuku 初始化状态: ${statusMap[status] ?? status}";
          break;
        case 'shizuku_check_permission':
          if (!Platform.isAndroid) {
            resultText = "错误：Shizuku 仅支持 Android 平台";
            break;
          }
          final hasPerm = await ShizukuService.checkPermission();
          resultText = "Shizuku 权限状态: ${hasPerm ? "已获得" : "未获得"}";
          break;
        case 'shizuku_run_shell':
          if (!Platform.isAndroid) {
            resultText = "错误：Shizuku 仅支持 Android 平台";
            break;
          }
          final shCommand = args['command'] as String;
          
          final shCommands = splitShellCommands(shCommand);
          for (final cmd in shCommands) {
            final main = getMainCommand(cmd);
            if (!_whitelist.contains(main)) {
              _securityCompleter = Completer<String>();
              _internalAddMessage({
                'role': 'security',
                'command': "[Shizuku] $cmd",
                'status': 'waiting'
              });
              notifyListeners();
              final decision = await _securityCompleter!.future;
              _securityCompleter = null;
              if (decision == 'deny') {
                resultText = "拒绝执行：用户未授权此 Shizuku 命令。";
                break;
              }
            }
          }
          if (resultText.isEmpty) {
            resultText = await ShizukuService.runShell(shCommand);
          }
          break;
        case 'modrinth_search':
          final modService = ModService();
          final results = await modService.searchModsStructured(
            args['query'],
            gameVersion: args['game_version'],
            loader: args['loader'],
            limit: args['limit'] ?? 8,
          );
          resultText = jsonEncode(results);
          break;
        case 'modrinth_get_project':
          final modService = ModService();
          final project = await modService.getProject(args['slug_or_id']);
          resultText = jsonEncode(project);
          break;
        default:
          resultText = "错误：未实现的工具 $name";
      }
      
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      l.log("Tool Execution Finished: $name", level: LogLevel.info, source: LogSource.tool, detail: "Duration: ${duration}ms");
      return resultText;
    } catch (e) {
      final l = await AppLogger.getInstance();
      l.log("执行工具出错: $name", level: LogLevel.error, source: LogSource.tool, detail: e.toString());
      return "执行工具出错: $e";
    }
  }

  List<String> splitShellCommands(String command) {
    final result = <String>[];

    final separator = RegExp(r'\s*(?:&&|\|\||[|&;])\s*');

    for (final part in command.split(separator)) {
      final value = part.trim();
      if (value.isNotEmpty) {
        result.add(value);
      }
    }

    return result;
  }

  String getMainCommand(String command) {
    command = command.trim();

    if (command.isEmpty) {
      return "";
    }

    if (command.startsWith('"')) {
      final end = command.indexOf('"', 1);
      if (end > 0) {
        return command.substring(1, end);
      }
    }

    return command.split(RegExp(r'\s+')).first;
  }

  Future<String> _executeFetchPage(String url) async {
    try {
      final dio = Dio();

      final response = await dio.get(
        url,
        options: Options(
          headers: {
            "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
            "Accept":
            "text/html,application/xhtml+xml",
          },
          responseType: ResponseType.plain,
        ),
      ).timeout(
        const Duration(seconds: 15),
      );


      final content = extractPageText(
        response.data.toString(),
      );


      return jsonEncode({
        "url": url,
        "content": content,
      });


    } catch (e) {

      final l = await AppLogger.getInstance();

      l.log(
        "网页读取失败",
        level: LogLevel.error,
        source: LogSource.network,
        detail: "URL: $url\nError: $e",
      );

      return jsonEncode({
        "success": false,
        "error": e.toString(),
      });
    }
  }

  String extractPageText(String html) {

    final document =
    html_parser.parse(html);


    for (final element in document.querySelectorAll(
      "script,style,noscript,svg,iframe",
    )) {
      element.remove();
    }


    var text =
        document.body?.text ?? "";


    text = text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();


    const maxLength = 12000;

    if (text.length > maxLength) {
      text =
          "${text.substring(0, maxLength)}\n...[内容已截断]";
    }


    return text;
  }

  Future<String> _executeWebSearch(
      String query, {
        int count = 5,
      }) async {
    try {
      final dio = Dio();

      final response = await dio.post(
        "https://api.tavily.com/search",
        options: Options(
          headers: {
            "Content-Type": "application/json",
          },
        ),
        data: {
          "api_key": "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",
          "query": query,
          "max_results": count,
          "search_depth": "basic",
          "include_answer": true,
        },
      );


      return jsonEncode(response.data);


    } on DioException catch(e) {

      if (e.response?.statusCode == 429) {
        return jsonEncode({
          "success": false,
          "error": "搜索服务额度已用完",
          "reason": "rate_limit",
          "suggestion": "请稍后再试，或使用已有知识回答",
        });
      }


      if (e.response?.statusCode == 401) {
        return jsonEncode({
          "success": false,
          "error": "搜索 API Key 无效",
          "reason": "invalid_key",
        });
      }


      return jsonEncode({
        "success": false,
        "error": "搜索失败",
        "detail": e.message,
      });


    } catch(e) {

      return jsonEncode({
        "success": false,
        "error": e.toString(),
      });
    }
  }

  List<llm.AgentMessage> _convertToAgentMessages(List<ChatMessage> messages) {
    return messages.map((m) {
      llm.AgentRole role;
      if (m is SystemMessage) {
        role = llm.AgentRole.system;
      } else if (m is UserMessage) {
        role = llm.AgentRole.user;
      } else if (m is AssistantMessage) {
        role = llm.AgentRole.assistant;
      } else if (m is ToolMessage) {
        role = llm.AgentRole.tool;
      } else {
        final rawRole = (m as dynamic).toJson()['role'];
        role = switch (rawRole) {
          'system' => llm.AgentRole.system,
          'user' => llm.AgentRole.user,
          'assistant' => llm.AgentRole.assistant,
          'tool' => llm.AgentRole.tool,
          _ => llm.AgentRole.assistant,
        };
      }

      dynamic content;
      if (m is SystemMessage) {
        content = m.content;
      }
      if (m is UserMessage) {
         final text = m.text;
         if (text != null) {
           content = text;
         } else {
           content = m.parts?.map((p) => p.toString()).join("\n");
         }
      }
      if (m is AssistantMessage) {
        content = m.content;
      }
      if (m is ToolMessage) {
        content = m.content;
      }
      if (m is MapMessage) {
        content = m.json['content'];
      }

      return llm.AgentMessage(
        role: role,
        content: content?.toString() ?? "",
        toolCalls: m is AssistantMessage ? m.toolCalls?.map((tc) => llm.ToolCall(
          id: tc.id,
          name: tc.function.name,
          arguments: jsonDecode(tc.function.arguments),
        )).toList() : null,
      );
    }).toList();
  }

  List<llm.AgentTool> _convertToAgentTools(List<Tool> tools, String workingDir) {
    return tools.map((t) => llm.AgentTool(
      name: t.function.name,
      description: t.function.description ?? "",
      parameters: t.function.parameters ?? {},
      execute: (args) => _executeTool(t.function.name, jsonEncode(args), workingDir),
    )).toList();
  }

  Future<List<SearchResult>> searchBing(
      String query, {
        int count = 5,
        int page = 1,
      }) async {

    final dio = Dio();
    final first = (page - 1) * 10 + 1;

    final response = await dio.get(
      "https://www.bing.com/search",
      queryParameters: {
        "q": query,
        "first": first,
        "setlang": "zh-CN",
        "cc": "CN",
        "mkt": "zh-CN",
      },
      options: Options(
        headers: {
          "User-Agent":
          "Mozilla/5.0",
          "Accept-Language":
          "zh-CN,zh;q=0.9",
        },
      ),
    ).timeout(const Duration(seconds: 15));


    return parseBingHtml(response.data)
        .take(count)
        .toList();
  }

  Future<String> _executeRecallHistory(int count) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final historyDir = Directory(p.join(appDir.path, 'blora_agent', 'history'));
      
      if (!await historyDir.exists()) return "暂无历史对话记录。";

      final List<FileSystemEntity> files = historyDir.listSync();
      final List<Map<String, dynamic>> results = [];

      for (var file in files) {
        if (file is File && file.path.endsWith('.json')) {
          try {
            final content = await file.readAsString();
            final data = jsonDecode(content);
            final List messages = data['messages'] ?? [];
            String summary = "无消息内容";
            if (messages.isNotEmpty) {
              final firstUserMsg = messages.firstWhere((m) => m['role'] == 'user', orElse: () => null);
              if (firstUserMsg != null) {
                summary = firstUserMsg['content'] ?? summary;
              }
            }
            results.add({
              'title': data['title'] ?? '未命名会话',
              'first_message': summary,
              'time': p.basenameWithoutExtension(file.path).split('_').last,
            });
          } catch (_) {}
        }
      }

      results.sort((a, b) => b['time'].compareTo(a['time']));
      final limited = results.take(count).toList();

      if (limited.isEmpty) return "未找到有效的历史对话记录。";
      
      return "为你找回了最近的 ${limited.length} 条对话记忆：\n${limited.map((r) => "- 【${r['title']}】 开头说：\"${r['first_message']}\"").join("\n")}";
    } catch (e) {
      final l = await AppLogger.getInstance();
      l.log("回忆失败", level: LogLevel.error, source: LogSource.system, detail: e.toString());
      return "回忆失败: $e";
    }
  }

  Map<String, dynamic>? simplifySemanticsTree(dynamic node) {
    final children = (node.children ?? [])
        .map(simplifySemanticsTree)
        .whereType<Map<String, dynamic>>()
        .toList();

    final label = node.label?.toString() ?? "";
    final role = node.role?.toString() ?? "";
    final actions = (node.actions ?? [])
        .map((e) => e.toString())
        .toList();

    final result = <String, dynamic>{
      "id": node.id.toString(),
    };

    if (role.isNotEmpty && role != "generic") {
      result["role"] = role;
    }

    if (label.isNotEmpty) {
      result["label"] = label;
    }

    if (actions.isNotEmpty) {
      result["actions"] = actions;
    }

    if (children.isNotEmpty) {
      result["children"] = children;
    }

    if (result.length == 1) {
      return null;
    }

    return result;
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

class FlutterAgentBridge {
  final AgentCore core;
  final SemanticTreeWalker walker;

  FlutterAgentBridge({
    required this.core,
    required this.walker,
  });

  dynamic getSemanticsTree() {
    return walker.capture();
  }

  Future<void> run(String task) {
    return core.run(task);
  }
}

class SearchResult {
  final String title;
  final String url;
  final String snippet;

  SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  Map<String, dynamic> toJson() =>
      {
        "title": title,
        "url": url,
        "snippet": snippet,
      };
}

List<SearchResult> parseBingHtml(String body) {
  final document = html_parser.parse(body);

  final results = <SearchResult>[];

  final items = document.querySelectorAll("li.b_algo");

  for (final item in items) {
    final titleNode = item.querySelector("h2 a");
    final snippetNode = item.querySelector(".b_caption p");

    if (titleNode == null) continue;

    final title = titleNode.text.trim();
    final url = titleNode.attributes["href"] ?? "";
    final snippet = snippetNode?.text.trim() ?? "";

    if (title.isEmpty || url.isEmpty) continue;

    results.add(
      SearchResult(
        title: title,
        url: url,
        snippet: snippet,
      ),
    );
  }

  return results;
}

class AgentWorker {
  final AgentCore core;

  AgentWorker._(this.core);

  static Future<AgentWorker> create({
    required String workingDir,
    required ActionRegistry actionRegistry,
  }) async {
    final treeWalker = SemanticTreeWalker();

    final planner = Planner(
      llmClient: BlorikoLLMClient(),
      actionRegistry: actionRegistry,
    );
    final executor = Executor(
      actionRegistry: actionRegistry,
      auditLog: AuditLog(),
    );
    final verifier = Verifier(treeWalker: treeWalker);
    return AgentWorker._(
      AgentCore(
        config: const AgentConfig(debugMode: true, maxSteps: 10),
        treeWalker: treeWalker,
        planner: planner,
        executor: executor,
        verifier: verifier,
      ),
    );
  }

  Future<String> runTask(String task, dynamic compressedTree) async {
    try {
      final contextualTask = "当前 UI 结构: ${jsonEncode(compressedTree)}\n\n任务: $task";
      await core.run(contextualTask);
      return "任务执行完毕。";
    } catch (e) {
      return "任务执行出错: $e";
    }
  }
}
