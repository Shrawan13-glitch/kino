import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ai_model.dart';

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
    required List<Map<String, String>> messages,
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

  static Stream<String> sendMessageStream({
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
  }) {
    final controller = StreamController<String>();

    _startStreaming(controller, apiKey, model, messages);

    return controller.stream;
  }

  static Future<void> _startStreaming(
    StreamController<String> controller,
    String apiKey,
    String model,
    List<Map<String, String>> messages,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/chat/completions'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      });
      request.body = jsonEncode({
        'model': model,
        'messages': messages,
        'stream': true,
      });

      final response = await client.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        final parsed = _tryDecode(body);
        final errorMsg =
            parsed?['error']?['message']?.toString() ?? 'Request failed';
        controller.addError(OpenRouterException(errorMsg));
        return;
      }

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
        if (content != null && content.isNotEmpty) {
          controller.add(content);
        }
      }
    } catch (e) {
      controller.addError(OpenRouterException('Connection error: $e'));
    } finally {
      client.close();
      await controller.close();
    }
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

class OpenRouterException implements Exception {
  final String message;
  const OpenRouterException(this.message);

  @override
  String toString() => message;
}
