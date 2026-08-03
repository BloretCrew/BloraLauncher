import 'dart:convert';
import 'package:bloret_launcher/core/llm_interface.dart';
import 'package:genai/genai.dart' show ModelAPIProvider;
import 'package:openai_dart/openai_dart.dart' as oa;

class GenAIProvider implements LLMProvider {
  final ModelAPIProvider provider;
  final String apiKey;
  final String modelName;

  GenAIProvider({
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
        model: modelName,
        messages: messages.map((m) {
          switch (m.role) {
            case AgentRole.system:
              return oa.ChatMessage.system(m.content.toString());
            case AgentRole.user:
              return oa.ChatMessage.user(m.content);
            case AgentRole.assistant:
              return oa.ChatMessage.assistant(content: m.content?.toString());
            case AgentRole.tool:
              return oa.ChatMessage.tool(
                toolCallId: m.toolResult?.toolCallId ?? '', 
                content: m.toolResult?.content ?? ''
              );
          }
        }).toList(),
      ),
    );

    await for (final event in stream) {
      final text = event.choices?.firstOrNull?.delta.content;
      if (text != null && text.isNotEmpty) {
        yield LLMChunk(
          text: text,
          toolCalls: [],
        );
      }
    }
  }
}
