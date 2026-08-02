import 'package:bloret_launcher/core/llm_interface.dart';
import 'package:genai/genai.dart';

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
    final request = AIRequestModel(
      modelApiProvider: provider,
      model: modelName,
      apiKey: apiKey,
      systemPrompt: messages.firstWhere((m) => m.role == AgentRole.system, orElse: () => AgentMessage(role: AgentRole.system, content: "")).content,
      userPrompt: messages.lastWhere((m) => m.role == AgentRole.user, orElse: () => AgentMessage(role: AgentRole.user, content: "")).content,
      stream: true,
    );

    final stream = await streamGenAIRequest(request);

    await for (final chunk in stream) {
      yield LLMChunk(
        text: chunk.toString(),
        toolCalls: [],
      );
    }
  }
}