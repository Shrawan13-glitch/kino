import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'llm_provider.dart';
import 'debug_service.dart';

/// OpenRouter implementation of [LlmProvider].
///
/// Features (mirrors Agora's provider design):
/// - Unified [StreamEvent] output
/// - SSE streaming with tool call accumulation
/// - Retry logic with exponential backoff (3 attempts)
/// - Configurable timeout (default 5 min)
/// - Cancellation via [CancellationToken]
/// - Token usage tracking
class OpenRouterProvider implements LlmProvider {
  static const String _baseUrl = 'https://openrouter.ai/api/v1';
  static const int _maxRetries = 3;

  @override
  Stream<StreamEvent> sendMessageStream({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? toolChoice,
    CancellationToken? cancelToken,
    Duration timeout = const Duration(minutes: 5),
  }) {
    final controller = StreamController<StreamEvent>();

    _startStreaming(
      controller: controller,
      apiKey: apiKey,
      model: model,
      messages: messages,
      tools: tools,
      toolChoice: toolChoice,
      cancelToken: cancelToken,
      timeout: timeout,
    );

    return controller.stream;
  }

  Future<void> _startStreaming({
    required StreamController<StreamEvent> controller,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? toolChoice,
    CancellationToken? cancelToken,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    DebugService.instance.info('OpenRouter._startStreaming: model="$model" messages=${messages.length} tools=${tools?.length}');
    try {
      for (int attempt = 1; attempt <= _maxRetries; attempt++) {
        if (cancelToken?.isCancelled == true) return;

        DebugService.instance.info('OpenRouter: attempt $attempt/$_maxRetries');
        final client = http.Client();
        try {
          final body = <String, dynamic>{
            'model': model,
            'messages': messages,
            'stream': true,
            'stream_options': {'include_usage': true},
          };

          if (tools != null && tools.isNotEmpty) {
            body['tools'] = tools;
            if (toolChoice != null) {
              body['tool_choice'] = toolChoice;
            }
          }

          final request = http.Request(
            'POST',
            Uri.parse('$_baseUrl/chat/completions'),
          );
          request.headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          });
          request.body = jsonEncode(body);

          DebugService.instance.info('OpenRouter: sending request to $_baseUrl/chat/completions');
          final response = await client
              .send(request)
              .timeout(timeout);

          DebugService.instance.info('OpenRouter: response status=${response.statusCode}');
          if (cancelToken?.isCancelled == true) return;

          if (response.statusCode == 401) {
            DebugService.instance.error('OpenRouter: 401 Authentication failed');
            controller.add(StreamError('Authentication failed. Check your API key.'));
            return;
          }

          if (response.statusCode == 429 || response.statusCode >= 500) {
            DebugService.instance.warn('OpenRouter: ${response.statusCode}, attempt $attempt/$_maxRetries');
            if (attempt < _maxRetries) {
              final delay = Duration(seconds: pow(2, attempt).toInt());
              controller.add(StreamError(
                'Server error (${response.statusCode}), retrying in ${delay.inSeconds}s...',
                retryable: true,
              ));
              await Future.delayed(delay);
              continue;
            }
            controller.add(StreamError(
              'Server error after $_maxRetries retries (${response.statusCode})',
            ));
            return;
          }

          if (response.statusCode != 200) {
            final responseBody = await response.stream.bytesToString();
            final parsed = _tryDecode(responseBody);
            final errorMsg =
                parsed?['error']?['message']?.toString() ?? 'Request failed (${response.statusCode})';
            DebugService.instance.error('OpenRouter: non-200 response: $errorMsg');
            controller.add(StreamError(errorMsg));
            return;
          }

          DebugService.instance.info('OpenRouter: connected, parsing SSE');
          // --- SSE parsing ---
          final toolCallAccumulators = <int, _ToolCallAccumulator2>{};

          await for (final line in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
            if (cancelToken?.isCancelled == true) return;

            if (!line.startsWith('data: ')) continue;
            final data = line.substring(6);
            if (data == '[DONE]') break;

            final json = _tryDecode(data);
            if (json == null) continue;

            // --- usage ---
            if (json['usage'] != null) {
              final usage = json['usage'] as Map<String, dynamic>;
              final prompt = (usage['prompt_tokens'] as num?)?.toInt() ?? 0;
              final completion = (usage['completion_tokens'] as num?)?.toInt() ?? 0;
              if (prompt > 0 || completion > 0) {
                controller.add(UsageUpdate(prompt, completion));
              }
            }

            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;

            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            if (delta == null) continue;

            // --- reasoning (emitted instantly as it arrives) ---
            String? reasoning = delta['reasoning_content'] as String?;
            if (reasoning == null || reasoning.isEmpty) {
              reasoning = delta['reasoning'] as String?;
            }
            if (reasoning != null && reasoning.isNotEmpty) {
              controller.add(ThoughtChunk(reasoning));
            }

            // --- text content ---
            final content = delta['content'] as String?;
            if (content != null && content.isNotEmpty) {
              controller.add(TextChunk(content));
            }

            // --- tool calls (emitted instantly as partial JSON parses) ---
            final toolCallsDelta = delta['tool_calls'] as List<dynamic>?;
            if (toolCallsDelta != null) {
              for (final tc in toolCallsDelta) {
                final tcMap = tc as Map<String, dynamic>;
                final index = tcMap['index'] as int;
                final id = tcMap['id'] as String?;
                final func = tcMap['function'] as Map<String, dynamic>?;

                if (!toolCallAccumulators.containsKey(index)) {
                  final name = func?['name'] as String? ?? '';
                  toolCallAccumulators[index] = _ToolCallAccumulator2(
                    id: id ?? '',
                    name: name,
                  );
                }

                final acc = toolCallAccumulators[index]!;
                if (id != null && id.isNotEmpty && acc.id.isEmpty) {
                  acc.id = id;
                }
                if (func != null) {
                  if (func['name'] is String && (func['name'] as String).isNotEmpty) {
                    acc.name = func['name'] as String;
                  }
                  if (func['arguments'] is String) {
                    acc.argumentsBuffer += func['arguments'] as String;
                    try {
                      final parsed =
                          jsonDecode(acc.argumentsBuffer) as Map<String, dynamic>;
                      if (acc.id.isNotEmpty) {
                        controller.add(ToolCallRequest(acc.id, acc.name, parsed));
                      }
                    } catch (_) {}
                  }
                }
              }
            }

            // --- finish reason ---
            final finishReason = choices[0]['finish_reason'] as String?;
            if (finishReason != null && finishReason.isNotEmpty) {
              controller.add(StreamDone(finishReason));
            }
          }

          // Finalize tool calls after SSE stream ends
          if (toolCallAccumulators.isNotEmpty) {
            final calls = <ToolCallInfo>[];
            for (final acc in toolCallAccumulators.values) {
              Map<String, dynamic> parsedArgs = {};
              if (acc.argumentsBuffer.isNotEmpty) {
                try {
                  parsedArgs =
                      jsonDecode(acc.argumentsBuffer) as Map<String, dynamic>;
                } catch (_) {
                  parsedArgs = {'raw': acc.argumentsBuffer};
                }
              }
              calls.add(ToolCallInfo(acc.id, acc.name, parsedArgs));
            }
            controller.add(ToolCallsRequest(calls));
          }

          return;
        } on TimeoutException {
          DebugService.instance.warn('OpenRouter: timeout on attempt $attempt');
          if (attempt < _maxRetries) {
            controller.add(StreamError('Request timed out, retrying...', retryable: true));
            await Future.delayed(Duration(seconds: pow(2, attempt).toInt()));
            continue;
          }
          controller.add(StreamError('Request timed out after $_maxRetries retries'));
          return;
        } catch (e, s) {
          DebugService.instance.error('OpenRouter: connection error', e, s);
          if (attempt < _maxRetries) {
            controller.add(StreamError('Connection error, retrying...', retryable: true));
            await Future.delayed(Duration(seconds: pow(2, attempt).toInt()));
            continue;
          }
          controller.add(StreamError('Connection error after $_maxRetries retries: $e'));
          return;
        } finally {
          client.close();
        }
      }
    } finally {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }

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

  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

class _ToolCallAccumulator2 {
  String id;
  String name;
  String argumentsBuffer = '';

  _ToolCallAccumulator2({required this.id, required this.name});
}
