import 'dart:convert';
import 'package:bloret_launcher/core/llm_interface.dart';
import 'package:genai/genai.dart' show ModelAPIProvider;
import 'package:openai_dart/openai_dart.dart' as oa;

class GenAIAdapter implements LLMProvider {
  final ModelAPIProvider provider;
  final String apiKey;
  final String modelName;

  GenAIAdapter({
    required this.provider,
    required this.apiKey,
    required this.modelName,
  });

  @override
  Stream<LLMChunk> chat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    String? model,
  }) async* {
    final client = oa.OpenAIClient(
      config: oa.OpenAIConfig(
        authProvider: oa.ApiKeyProvider(apiKey),
        baseUrl: provider == ModelAPIProvider.gemini 
            ? 'https://generativelanguage.googleapis.com/v1beta/openai/'
            : 'https://api.openai.com/v1',
      ),
    );

    final stream = client.chat.completions.createStream(
      oa.ChatCompletionCreateRequest(
        model: model ?? modelName,
        messages: messages.map((m) {
          switch (m.role) {
            case AgentRole.system:
              return oa.ChatMessage.system(m.content.toString());
            case AgentRole.user:
              return oa.ChatMessage.user(m.content);
            case AgentRole.assistant:
              return oa.ChatMessage.assistant(
                content: m.content?.toString(),
                toolCalls: m.toolCalls?.map((tc) => oa.ToolCall(
                  id: tc.id,
                  type: 'function',
                  function: oa.FunctionCall(name: tc.name, arguments: jsonEncode(tc.arguments)),
                )).toList(),
              );
            case AgentRole.tool:
              return oa.ChatMessage.tool(
                toolCallId: m.toolResult?.toolCallId ?? '',
                content: m.toolResult?.content ?? '',
              );
          }
        }).toList(),
      ),
    );

    await for (final event in stream) {
      final choice = event.choices?.firstOrNull;
      if (choice == null) continue;
      
      final text = choice.delta.content;
      final reasoning = choice.delta.reasoningContent;

      if ((text != null && text.isNotEmpty) || (reasoning != null && reasoning.isNotEmpty)) {
        yield LLMChunk(
          text: text,
          reasoning: reasoning,
          toolCalls: [],
        );
      }
    }
  }
}
