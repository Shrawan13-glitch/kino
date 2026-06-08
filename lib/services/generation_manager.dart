import 'dart:async';
import 'dart:convert';
import 'llm_provider.dart';
import '../utils/streaming_think_tag_parser.dart';

/// Callback invoked for each tool execution.
/// Returns the tool result as a string.
typedef ToolExecutor = Future<String> Function(String name, Map<String, dynamic> arguments);

/// Events emitted by [GenerationManager.generate] for the UI layer.
sealed class GenerationEvent {}

class GenTextChunk extends GenerationEvent {
  final String text;
  GenTextChunk(this.text);
}

class GenThoughtChunk extends GenerationEvent {
  final String thought;
  GenThoughtChunk(this.thought);
}

class GenToolCallStart extends GenerationEvent {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  GenToolCallStart(this.id, this.name, this.arguments);
}

class GenToolCallResult extends GenerationEvent {
  final String id;
  final bool success;
  final String result;
  GenToolCallResult(this.id, this.success, this.result);
}

class GenUsage extends GenerationEvent {
  final int promptTokens;
  final int completionTokens;
  GenUsage(this.promptTokens, this.completionTokens);
}

class GenError extends GenerationEvent {
  final String message;
  GenError(this.message);
}

class GenDone extends GenerationEvent {
  final String finishReason;
  GenDone(this.finishReason);
}

class GenTurnEnd extends GenerationEvent {
  GenTurnEnd();
}

/// Core generation engine — mirrors Agora's GenerationManager.
///
/// Manages the full streaming + tool-calling loop with:
/// - Unlimited tool rounds (bounded only by liveness / cancellation)
/// - Deterministic tool call IDs via [buildToolCallId]
/// - Streaming-safe reasoning extraction (native + inline think tags)
/// - Cancellation support
class GenerationManager {
  CancellationToken? _cancelToken;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  CancellationToken? get cancelToken => _cancelToken;

  /// Start generation and stream [GenerationEvent]s.
  ///
  /// [provider] — the LLM provider to use
  /// [apiKey] / [model] — provider credentials
  /// [baseMessages] — the starting message list (system + user + history)
  /// [toolDefinitions] — tool definitions to expose to the model
  /// [executeTool] — callback that runs each tool and returns its result
  /// [reasoningConfig] — optional provider-specific reasoning config
  Stream<GenerationEvent> generate({
    required LlmProvider provider,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> baseMessages,
    required List<Map<String, dynamic>> toolDefinitions,
    required ToolExecutor executeTool,
    Map<String, dynamic>? reasoningConfig,
  }) {
    final controller = StreamController<GenerationEvent>();
    _cancelToken = CancellationToken();
    _isRunning = true;

    _runGeneration(
      controller: controller,
      provider: provider,
      apiKey: apiKey,
      model: model,
      baseMessages: baseMessages,
      toolDefinitions: toolDefinitions,
      executeTool: executeTool,
      cancelToken: _cancelToken!,
      reasoningConfig: reasoningConfig,
    ).whenComplete(() {
      _isRunning = false;
      controller.close();
    });

    return controller.stream;
  }

  void cancel() {
    _cancelToken?.cancel();
  }

  Future<void> _runGeneration({
    required StreamController<GenerationEvent> controller,
    required LlmProvider provider,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> baseMessages,
    required List<Map<String, dynamic>> toolDefinitions,
    required ToolExecutor executeTool,
    required CancellationToken cancelToken,
    Map<String, dynamic>? reasoningConfig,
  }) async {
    final toolMessages = <Map<String, dynamic>>[];

    try {
      while (!cancelToken.isCancelled) {

        final allMessages = [
          ...baseMessages,
          ...toolMessages,
        ];

        final thinkParser = StreamingThinkTagParser();
        bool hadToolCalls = false;

        await for (final event in provider.sendMessageStream(
          apiKey: apiKey,
          model: model,
          messages: allMessages,
          tools: toolDefinitions.isNotEmpty ? toolDefinitions : null,
          cancelToken: cancelToken,
        )) {
          if (cancelToken.isCancelled) break;

          switch (event) {
            case TextChunk(:final text):
              // Check for inline <think> tags
              final thought = thinkParser.process(text);
              if (thought != null) {
                controller.add(GenThoughtChunk(thought));
              }
              // Emit non-thought text (text outside think tags)
              if (!thinkParser.isInThink && !thinkParser.hasExited) {
                controller.add(GenTextChunk(text));
              } else if (thinkParser.hasExited) {
                controller.add(GenTextChunk(text));
              }

            case ThoughtChunk(:final thought):
              controller.add(GenThoughtChunk(thought));

            case ToolCallRequest():
              // SSE preview — actual execution emits GenToolCallStart in ToolCallsRequest
              break;

            case ToolCallsRequest(:final calls):
              hadToolCalls = true;

              // Build deterministic IDs if provider didn't supply them
              final resolvedCalls = calls.map((c) {
                final id = c.id.isNotEmpty
                    ? c.id
                    : buildToolCallId(c.name, c.arguments);
                return ToolCallInfo(id, c.name, c.arguments);
              }).toList();

              // Build assistant message for API context
              final assistantMsg = <String, dynamic>{
                'role': 'assistant',
                'content': '',
                'tool_calls': resolvedCalls.map((tc) {
                  return {
                    'id': tc.id,
                    'type': 'function',
                    'function': {
                      'name': tc.name,
                      'arguments': jsonEncode(tc.arguments),
                    },
                  };
                }).toList(),
              };
              toolMessages.add(assistantMsg);

              // Execute each tool
              for (final tc in resolvedCalls) {
                if (cancelToken.isCancelled) break;

                controller.add(GenToolCallStart(tc.id, tc.name, tc.arguments));

                try {
                  final result = await executeTool(tc.name, tc.arguments);
                  controller.add(GenToolCallResult(tc.id, true, result));

                  final toolMsg = _makeToolResultMessage(
                    toolCallId: tc.id,
                    content: result,
                  );
                  toolMessages.add(toolMsg);
                } catch (e) {
                  final errorMsg = 'Error executing tool "${tc.name}": $e';
                  controller.add(GenToolCallResult(tc.id, false, errorMsg));

                  final toolMsg = _makeToolResultMessage(
                    toolCallId: tc.id,
                    content: errorMsg,
                  );
                  toolMessages.add(toolMsg);
                }
              }

              if (!cancelToken.isCancelled) {
                controller.add(GenTurnEnd());
              }

            case UsageUpdate(:final promptTokens, :final completionTokens):
              controller.add(GenUsage(promptTokens, completionTokens));

            case StreamError(:final message, :final retryable):
              if (retryable) {
                controller.add(GenError(message));
              } else {
                controller.add(GenError(message));
                return;
              }

            case StreamDone():
              break;
          }
        }

        // Flush any remaining think tag content
        final remainingThought = thinkParser.flush();
        if (remainingThought != null && remainingThought.isNotEmpty) {
          controller.add(GenThoughtChunk(remainingThought));
        }

        if (cancelToken.isCancelled) return;

        // If no tool calls were made, generation is done
        if (!hadToolCalls) {
          controller.add(GenDone('stop'));
          return;
        }
      }
    } catch (e) {
      if (!cancelToken.isCancelled) {
        controller.add(GenError('Unexpected error: $e'));
      }
    }
  }

  Map<String, dynamic> _makeToolResultMessage({
    required String toolCallId,
    required String content,
  }) {
    return {
      'role': 'tool',
      'tool_call_id': toolCallId,
      'content': content,
    };
  }
}
