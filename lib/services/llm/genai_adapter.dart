import 'package:bloret_launcher/core/llm_interface.dart';
import 'package:genai/genai.dart';

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
    final systemPrompt = messages.firstWhere(
      (m) => m.role == AgentRole.system,
      orElse: () => AgentMessage(role: AgentRole.system, content: ""),
    ).content as String;

    final userPrompt = messages.lastWhere(
      (m) => m.role == AgentRole.user,
      orElse: () => AgentMessage(role: AgentRole.user, content: ""),
    ).content as String;

    final request = AIRequestModel(
      modelApiProvider: provider,
      model: model ?? modelName,
      apiKey: apiKey,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
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
