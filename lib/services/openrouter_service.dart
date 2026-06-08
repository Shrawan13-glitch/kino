import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ai_model.dart';

class StreamChunk {
  final String content;
  final String? reasoning;
  const StreamChunk({this.content = '', this.reasoning});
}

class ToolCallData {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  ToolCallData({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

class ToolStreamResult {
  final Stream<StreamChunk> stream;
  final Future<List<ToolCallData>> toolCalls;
  final Future<String?> finishReason;

  ToolStreamResult({
    required this.stream,
    required this.toolCalls,
    required this.finishReason,
  });
}

class OpenRouterService {
  static const String baseUrl = 'https://openrouter.ai/api/v1';

  static Future<List<AiModel>> fetchModels(String apiKey) async {
    final response = await http.get(
      Uri.parse('$baseUrl/models'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (data['data'] as List)
          .map((m) => AiModel.fromJson(m as Map<String, dynamic>))
          .toList();

      models.sort((a, b) {
        final providerCmp = a.provider.compareTo(b.provider);
        return providerCmp != 0 ? providerCmp : a.name.compareTo(b.name);
      });

      return models;
    }

    final body = _tryDecode(response.body);
    final errorMsg =
        body?['error']?['message']?.toString() ?? 'Failed to load models';
    throw OpenRouterException(errorMsg);
  }

  static Future<String> sendMessage({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choice = (data['choices'] as List).first as Map<String, dynamic>;
      final message = choice['message'] as Map<String, dynamic>;
      return message['content'] as String? ?? '';
    }

    final body = _tryDecode(response.body);
    final errorMsg =
        body?['error']?['message']?.toString() ?? 'Request failed';
    throw OpenRouterException(errorMsg);
  }

  /// Sends messages with optional tool definitions and streams the response.
  /// Returns a [ToolStreamResult] with:
  /// - [stream]: text/reasoning deltas in real-time
  /// - [toolCalls]: resolves after stream ends with any tool calls made
  /// - [finishReason]: resolves after stream ends with the stop reason
  static ToolStreamResult sendMessageStream({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? toolChoice,
  }) {
    final toolCallsCompleter = Completer<List<ToolCallData>>();
    final finishReasonCompleter = Completer<String?>();

    final controller = StreamController<StreamChunk>();

    _startStreaming(
      controller,
      apiKey,
      model,
      messages,
      tools: tools,
      toolChoice: toolChoice,
      toolCallsCompleter: toolCallsCompleter,
      finishReasonCompleter: finishReasonCompleter,
    );

    return ToolStreamResult(
      stream: controller.stream,
      toolCalls: toolCallsCompleter.future,
      finishReason: finishReasonCompleter.future,
    );
  }

  static Future<void> _startStreaming(
    StreamController<StreamChunk> controller,
    String apiKey,
    String model,
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? toolChoice,
    Completer<List<ToolCallData>>? toolCallsCompleter,
    Completer<String?>? finishReasonCompleter,
  }) async {
    final client = http.Client();
    try {
      final body = <String, dynamic>{
        'model': model,
        'messages': messages,
        'stream': true,
        'reasoning': {'effort': 'medium', 'exclude': false},
      };

      if (tools != null && tools.isNotEmpty) {
        body['tools'] = tools;
        if (toolChoice != null) {
          body['tool_choice'] = toolChoice;
        }
      }

      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/chat/completions'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      });
      request.body = jsonEncode(body);

      final response = await client.send(request);

      if (response.statusCode != 200) {
        final responseBody = await response.stream.bytesToString();
        final parsed = _tryDecode(responseBody);
        final errorMsg =
            parsed?['error']?['message']?.toString() ?? 'Request failed';
        controller.addError(OpenRouterException(errorMsg));
        if (toolCallsCompleter?.isCompleted == false) {
          toolCallsCompleter?.complete([]);
        }
        if (finishReasonCompleter?.isCompleted == false) {
          finishReasonCompleter?.complete(null);
        }
        return;
      }

      // Accumulate tool calls from streaming deltas
      // Map from index to ToolCallAccumulator
      final toolCallAccumulators = <int, _ToolCallAccumulator>{};

      await for (final chunk in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!chunk.startsWith('data: ')) continue;

        final data = chunk.substring(6);
        if (data == '[DONE]') break;

        final json = _tryDecode(data);
        if (json == null) continue;

        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;

        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;

        final content = delta['content'] as String?;

        String? reasoning = delta['reasoning_content'] as String?;
        if (reasoning == null || reasoning.isEmpty) {
          reasoning = delta['reasoning'] as String?;
        }

        if (content != null && content.isNotEmpty) {
          controller.add(StreamChunk(content: content));
        }
        if (reasoning != null && reasoning.isNotEmpty) {
          controller.add(StreamChunk(reasoning: reasoning));
        }

        // Detect tool calls in delta
        final toolCallsDelta = delta['tool_calls'] as List<dynamic>?;
        if (toolCallsDelta != null) {
          for (final tc in toolCallsDelta) {
            final tcMap = tc as Map<String, dynamic>;
            final index = tcMap['index'] as int;
            final id = tcMap['id'] as String?;
            final func = tcMap['function'] as Map<String, dynamic>?;

            if (!toolCallAccumulators.containsKey(index)) {
              toolCallAccumulators[index] = _ToolCallAccumulator(
                id: id ?? '',
                name: func?['name'] as String? ?? '',
              );
            }

            final accumulator = toolCallAccumulators[index]!;
            if (id != null && id.isNotEmpty && accumulator.id.isEmpty) {
              accumulator.id = id;
            }
            if (func != null) {
              if (func['name'] is String &&
                  (func['name'] as String).isNotEmpty) {
                accumulator.name = func['name'] as String;
              }
              if (func['arguments'] is String) {
                accumulator.argumentsBuffer += func['arguments'] as String;
              }
            }
          }
        }

        // Check finish reason
        final finishReason = choices[0]['finish_reason'] as String?;
        if (finishReason != null && finishReason.isNotEmpty) {
          if (finishReasonCompleter?.isCompleted == false) {
            finishReasonCompleter?.complete(finishReason);
          }
        }
      }

      // Finalize tool calls - parse JSON arguments
      final completedCalls = <ToolCallData>[];
      for (final acc in toolCallAccumulators.values) {
        Map<String, dynamic> parsedArgs = {};
        if (acc.argumentsBuffer.isNotEmpty) {
          try {
            parsedArgs =
                jsonDecode(acc.argumentsBuffer) as Map<String, dynamic>;
          } catch (_) {
            // If JSON parsing fails, pass raw string
            parsedArgs = {'raw': acc.argumentsBuffer};
          }
        }
        completedCalls.add(ToolCallData(
          id: acc.id,
          name: acc.name,
          arguments: parsedArgs,
        ));
      }

      if (toolCallsCompleter?.isCompleted == false) {
        toolCallsCompleter?.complete(completedCalls);
      }
      if (finishReasonCompleter?.isCompleted == false) {
        finishReasonCompleter?.complete(null);
      }
    } catch (e) {
      controller.addError(OpenRouterException('Connection error: $e'));
      if (toolCallsCompleter?.isCompleted == false) {
        toolCallsCompleter?.complete([]);
      }
      if (finishReasonCompleter?.isCompleted == false) {
        finishReasonCompleter?.complete(null);
      }
    } finally {
      client.close();
      await controller.close();
    }
  }

  /// Builds a tool result message for sending back to the API.
  static Map<String, dynamic> makeToolResultMessage({
    required String toolCallId,
    required String content,
  }) {
    return {
      'role': 'tool',
      'tool_call_id': toolCallId,
      'content': content,
    };
  }

  /// Builds a tool definition in OpenAI-compatible format.
  static Map<String, dynamic> makeToolDefinition({
    required String name,
    required String description,
    required Map<String, dynamic> parameters,
  }) {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parameters,
      },
    };
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

/// Internal class to accumulate tool call arguments during streaming.
class _ToolCallAccumulator {
  String id;
  String name;
  String argumentsBuffer = '';

  _ToolCallAccumulator({
    required this.id,
    required this.name,
  });
}

class OpenRouterException implements Exception {
  final String message;
  const OpenRouterException(this.message);

  @override
  String toString() => message;
}
