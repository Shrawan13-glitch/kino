import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../services/openrouter_service.dart';
import '../services/search/search_service.dart';
import '../services/search/webfetch_service.dart';
import '../utils/content_parser.dart';
import 'settings_provider.dart';

class ChatProvider extends ChangeNotifier {
  final SettingsProvider _settingsProvider;
  final DatabaseHelper _db = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();
  late final SearchService _searchService;
  late final WebFetchService _webFetchService;

  ChatProvider(this._settingsProvider) {
    _searchService = SearchService();
    _webFetchService = WebFetchService();
  }

  List<Chat> _chats = [];
  Chat? _currentChat;
  List<Message> _messages = [];
  bool _isLoading = false;
  bool _isGenerating = false;
  bool _initialized = false;

  /// In-memory tool messages appended during the current generation loop.
  /// These include assistant tool_calls messages and tool result messages.
  final List<Map<String, dynamic>> _toolMessages = [];

  List<Chat> get chats => _chats;
  Chat? get currentChat => _currentChat;
  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isGenerating => _isGenerating;
  bool get initialized => _initialized;

  String get _effectiveModel =>
      _currentChat?.model ?? _settingsProvider.defaultModel;

  int get approximateContextTokens {
    var total = 0;
    for (final m in _messages) {
      total += m.content.length ~/ 4;
    }
    return total;
  }

  String? get contextInfo {
    final modelId = _effectiveModel;
    if (modelId.isEmpty) return null;
    final model = _settingsProvider.getModelById(modelId);
    if (model == null || model.contextLength <= 0) return null;
    final used = approximateContextTokens;
    return '${modelId.split('/').last} · ${_fmt(used)} / ${_fmt(model.contextLength)}';
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    _chats = await _db.getAllChats();
    await _searchService.init();
    _initialized = true;
    _isLoading = false;
    notifyListeners();
  }

  Future<Chat> createChat({String? model}) async {
    final now = DateTime.now();
    final chat = Chat(
      id: _uuid.v4(),
      title: 'New Chat',
      createdAt: now,
      updatedAt: now,
      model: model ?? _settingsProvider.defaultModel,
    );

    _currentChat = chat;
    _messages = [];
    notifyListeners();

    return chat;
  }

  Future<void> selectChat(String id) async {
    if (_currentChat?.id == id) return;

    _isLoading = true;
    notifyListeners();

    _currentChat = _chats.firstWhere((c) => c.id == id);
    _messages = await _db.getMessages(id);
    await _migrateLegacyMessages();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> deleteChat(String id) async {
    await _db.deleteChat(id);
    _chats.removeWhere((c) => c.id == id);

    if (_currentChat?.id == id) {
      _currentChat = _chats.isNotEmpty ? _chats.first : null;
      if (_currentChat != null) {
        _messages = await _db.getMessages(_currentChat!.id);
      } else {
        _messages = [];
      }
    }
    notifyListeners();
  }

  Future<void> setChatModel(String modelId) async {
    if (_currentChat == null) return;

    _currentChat = _currentChat!.copyWith(model: modelId);
    await _db.updateChat(_currentChat!);
    notifyListeners();
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    if (!_settingsProvider.hasApiKey) {
      _showError('No API key configured. Add one in Settings > Providers.');
      return;
    }

    if (_currentChat == null) {
      await createChat();
    }

    final chatId = _currentChat!.id;
    final isDraft = _chats.every((c) => c.id != chatId);
    final now = DateTime.now();
    final model = _effectiveModel;

    if (model.isEmpty) {
      _showError('No model selected. Select one in Settings > Providers.');
      return;
    }

    if (isDraft) {
      _currentChat = _currentChat!.copyWith(
        title: _truncateTitle(content),
        updatedAt: now,
        model: model,
      );
      await _db.insertChat(_currentChat!);
      _chats.insert(0, _currentChat!);
    }

    final userMessage = Message(
      id: _uuid.v4(),
      chatId: chatId,
      role: 'user',
      content: content.trim(),
      createdAt: now,
    );

    await _db.insertMessage(userMessage);
    _messages.add(userMessage);

    if (!isDraft) {
      _currentChat = _currentChat!.copyWith(updatedAt: now);
      await _db.updateChat(_currentChat!);
      _chats.removeWhere((c) => c.id == chatId);
      _chats.insert(0, _currentChat!);
    }

    _toolMessages.clear();
    notifyListeners();

    await _generateResponse(chatId, model);
  }

  /// Builds the complete message list for the API, including persisted
  /// messages and in-memory tool messages from the current generation loop.
  List<Map<String, dynamic>> _buildApiMessages() {
    final list = <Map<String, dynamic>>[
      {'role': 'system', 'content': _settingsProvider.systemPrompt},
    ];

    for (final m in _messages) {
      list.add({'role': m.role, 'content': m.content});
    }

    list.addAll(_toolMessages);

    return list;
  }

  /// Builds tool definitions in OpenAI-compatible format.
  List<Map<String, dynamic>> _buildToolDefinitions() {
    return [
      OpenRouterService.makeToolDefinition(
        name: 'web_search',
        description:
            'Search the web for current information. Returns up to 10 results with titles, URLs, and summaries. Use this to find recent news, facts, or anything that needs up-to-date information.',
        parameters: {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'The search query',
            },
          },
          'required': ['query'],
        },
      ),
      OpenRouterService.makeToolDefinition(
        name: 'fetch_url',
        description:
            'Fetch and read the text content of a web page. Returns stripped text up to ~50KB. Use this to get detailed information from a specific URL.',
        parameters: {
          'type': 'object',
          'properties': {
            'url': {
              'type': 'string',
              'description': 'The URL of the web page to fetch',
            },
          },
          'required': ['url'],
        },
      ),
    ];
  }

  Future<void> _generateResponse(String chatId, String model) async {
    _isGenerating = true;
    notifyListeners();

    final aiMessage = Message(
      id: _uuid.v4(),
      chatId: chatId,
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
    );

    await _db.insertMessage(aiMessage);
    _messages.add(aiMessage);
    notifyListeners();

    int turn = 0;
    const int maxTurns = 5;

    try {
      while (turn < maxTurns) {
        turn++;

        final result = OpenRouterService.sendMessageStream(
          apiKey: _settingsProvider.apiKey,
          model: model,
          messages: _buildApiMessages(),
          tools: _buildToolDefinitions(),
        );

        final buffer = StringBuffer();
        final reasoningBuffer = StringBuffer();

        await for (final chunk in result.stream) {
          if (chunk.content.isNotEmpty) {
            buffer.write(chunk.content);
            aiMessage.content += chunk.content;
          }
          if (chunk.reasoning != null && chunk.reasoning!.isNotEmpty) {
            reasoningBuffer.write(chunk.reasoning);
            aiMessage.reasoning = (aiMessage.reasoning ?? '') + chunk.reasoning!;
          }
          notifyListeners();
        }

        final toolCalls = await result.toolCalls;
        if (toolCalls.isEmpty) break;

        // Record tool calls on the message for UI display
        final msgToolCalls = <ToolCall>[];
        for (final tc in toolCalls) {
          msgToolCalls.add(ToolCall(
            id: tc.id,
            name: tc.name,
            arguments: tc.arguments,
          ));
        }
        aiMessage.toolCalls = [
          ...?aiMessage.toolCalls,
          ...msgToolCalls,
        ];
        notifyListeners();

        // Record the assistant message with tool calls for the API context
        final assistantMsg = <String, dynamic>{
          'role': 'assistant',
          'content': buffer.toString(),
          'tool_calls': toolCalls.map((tc) {
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
        _toolMessages.add(assistantMsg);

        // Execute each tool call
        for (var i = 0; i < toolCalls.length; i++) {
          final tc = toolCalls[i];
          String resultContent;

          try {
            resultContent = await _executeTool(tc.name, tc.arguments);
            msgToolCalls[i].completed = true;
            msgToolCalls[i].result = resultContent;
          } catch (e) {
            resultContent = 'Error executing tool "${tc.name}": $e';
            msgToolCalls[i].error = true;
            msgToolCalls[i].result = resultContent;
          }
          notifyListeners();

          final toolMsg = OpenRouterService.makeToolResultMessage(
            toolCallId: tc.id,
            content: resultContent,
          );
          _toolMessages.add(toolMsg);
        }

        notifyListeners();
      }

      // Fallback: extract <think>/<thinking> tags from content for models
      // like DeepSeek R1 that don't use native reasoning_content
      if ((aiMessage.reasoning == null || aiMessage.reasoning!.isEmpty) &&
          _hasThinkTags(aiMessage.content)) {
        _extractThinkingFromContent(aiMessage);
      }

      notifyListeners();

      await _db.updateMessageContent(aiMessage.id, aiMessage.content,
          reasoning: aiMessage.reasoning);
    } on OpenRouterException catch (e) {
      _messages.remove(aiMessage);
      await _db.deleteMessage(aiMessage.id);
      await _insertErrorMessage(chatId, 'Error: ${e.message}');
    } catch (e) {
      _messages.remove(aiMessage);
      await _db.deleteMessage(aiMessage.id);
      await _insertErrorMessage(chatId, 'Connection error: $e');
    } finally {
      _toolMessages.clear();
      _isGenerating = false;
      notifyListeners();
    }
  }

  /// Executes a tool by name with the given arguments.
  Future<String> _executeTool(
      String name, Map<String, dynamic> arguments) async {
    switch (name) {
      case 'web_search':
        final query = arguments['query'] as String?;
        if (query == null || query.isEmpty) {
          return 'Error: query parameter is required for web_search';
        }
        final container = await _searchService.search(query);
        final results = container.getOrderedResults();
        final answers = container.answers;

        if (results.isEmpty && answers.isEmpty) {
          return 'No search results found for "$query".';
        }

        final sb = StringBuffer();
        sb.writeln('Search results for "$query":');
        sb.writeln();

        for (var i = 0; i < results.length; i++) {
          final r = results[i];
          sb.writeln('${i + 1}. ${r.title}');
          sb.writeln('   URL: ${r.url}');
          sb.writeln('   ${r.content}');
          if (r.publishedDate != null) {
            sb.writeln('   Published: ${r.publishedDate}');
          }
          sb.writeln();
        }

        for (final a in answers) {
          sb.writeln('Answer: ${a.answer}');
          if (a.url != null) sb.writeln('Source: ${a.url}');
          sb.writeln();
        }

        return sb.toString().trim();

      case 'fetch_url':
        final url = arguments['url'] as String?;
        if (url == null || url.isEmpty) {
          return 'Error: url parameter is required for fetch_url';
        }
        final content = await _webFetchService.fetchContent(url);
        if (content == null) {
          return 'Failed to fetch content from $url. The page might be unreachable or blocked.';
        }
        return 'Content from $url:\n\n$content';

      default:
        return 'Unknown tool: $name. Available tools: web_search, fetch_url.';
    }
  }

  /// Migrates legacy messages that have `<thinking>` tags embedded in content
  /// to use the separate [reasoning] field instead.
  Future<void> _migrateLegacyMessages() async {
    for (final msg in _messages) {
      if (!msg.isAssistant ||
          msg.reasoning != null ||
          !msg.content.contains('<thinking>')) {
        continue;
      }

      final sanitized = ContentParser.sanitize(msg.content);
      final result = ContentParser.parse(sanitized);
      final reasoningParts =
          result.segments.where((s) => s.isThinking).map((s) => s.content);
      final textParts =
          result.segments.where((s) => !s.isThinking).map((s) => s.content);

      final reasoning = reasoningParts.join('\n\n');
      if (reasoning.isEmpty) continue;

      final cleanedContent = textParts.join('');
      msg.reasoning = reasoning;
      msg.content = cleanedContent;
      await _db.updateMessageContent(msg.id, cleanedContent,
          reasoning: reasoning);
    }
  }

  /// Extracts `<think>`/`<thinking>` tags from message content into [Message.reasoning].
  void _extractThinkingFromContent(Message msg) {
    final sanitized = ContentParser.sanitize(msg.content);
    final result = ContentParser.parse(sanitized);
    final reasoningParts =
        result.segments.where((s) => s.isThinking).map((s) => s.content);
    if (reasoningParts.isEmpty) return;

    msg.reasoning = reasoningParts.join('\n\n');
    msg.content = result.segments
        .where((s) => !s.isThinking)
        .map((s) => s.content)
        .join('');
  }

  static bool _hasThinkTags(String content) {
    return RegExp(r'</?think(?:ing)?\b', caseSensitive: false)
        .hasMatch(content);
  }

  Future<void> _insertErrorMessage(String chatId, String content) async {
    final msg = Message(
      id: _uuid.v4(),
      chatId: chatId,
      role: 'assistant',
      content: content,
      createdAt: DateTime.now(),
    );
    await _db.insertMessage(msg);
    _messages.add(msg);
  }

  Future<void> deleteMessage(String id) async {
    await _db.deleteMessage(id);
    _messages.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  Future<void> clearAllChats() async {
    await _db.clearAll();
    _chats.clear();
    _currentChat = null;
    _messages = [];
    notifyListeners();
  }

  void _showError(String message) {
    if (_currentChat == null) {
      createChat();
    }
    _insertErrorMessage(_currentChat!.id, message);
    notifyListeners();
  }

  String _truncateTitle(String text) {
    if (text.length <= 40) return text;
    return '${text.substring(0, 40)}...';
  }
}
