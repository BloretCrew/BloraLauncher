import 'dart:async';

enum AgentRole { system, user, assistant, tool }

class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  ToolCall({required this.id, required this.name, required this.arguments});
}

class ToolResult {
  final String toolCallId;
  final String name;
  final String content;

  ToolResult({required this.toolCallId, required this.name, required this.content});
}

class AgentMessage {
  final AgentRole role;
  final dynamic content;
  final List<ToolCall>? toolCalls;
  final ToolResult? toolResult;

  AgentMessage({
    required this.role,
    this.content,
    this.toolCalls,
    this.toolResult,
  });
}

class AgentTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final Future<String> Function(Map<String, dynamic> args) execute;

  AgentTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });
}

class LLMChunk {
  final String? text;
  final List<ToolCall> toolCalls;
  final String? reasoning;

  LLMChunk({this.text, this.toolCalls = const [], this.reasoning});
}

abstract class LLMProvider {
  Stream<LLMChunk> chat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    String? model,
  });
}
