import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/thread_entry.dart';
import '../services/openrouter_provider.dart';
import '../services/generation_manager.dart';
import '../services/openrouter_service.dart';
import '../services/search/search_service.dart';
import '../services/search/webfetch_service.dart';
import '../utils/content_parser.dart';
import 'settings_provider.dart';

class ChatProvider extends ChangeNotifier {
  final SettingsProvider _settingsProvider;
  final DatabaseHelper _db = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();
  final OpenRouterProvider _provider = OpenRouterProvider();
  final GenerationManager _genManager = GenerationManager();
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

  Timer? _batchTimer;
  StringBuffer _contentBuffer = StringBuffer();
  StringBuffer _reasoningBuffer = StringBuffer();

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

    cancelGeneration();

    _isLoading = true;
    notifyListeners();

    _currentChat = _chats.firstWhere((c) => c.id == id);
    _messages = await _db.getMessages(id);
    await _migrateLegacyMessages();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> deleteChat(String id) async {
    cancelGeneration();
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

  void cancelGeneration() {
    _genManager.cancel();
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    // Cancel any ongoing generation before sending a new message
    if (_isGenerating) {
      cancelGeneration();
    }

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

    notifyListeners();
    await _generateResponse(chatId, model);
  }

  Future<void> _generateResponse(String chatId, String model) async {
    _isGenerating = true;
    _contentBuffer = StringBuffer();
    _reasoningBuffer = StringBuffer();
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

    final toolDefinitions = _buildToolDefinitions();

    try {
      final stream = _genManager.generate(
        provider: _provider,
        apiKey: _settingsProvider.apiKey,
        model: model,
        baseMessages: _buildApiMessages(),
        toolDefinitions: toolDefinitions,
        executeTool: (name, args) => _executeTool(name, args),
      );

      stream.listen(
        (event) {
          _queueGenerationEvent(event, aiMessage);
        },
        onDone: () async {
          _batchTimer?.cancel();
          _batchTimer = null;
          notifyListeners();
          // Fallback: extract <think>/<thinking> tags from content for models
          // that don't use native reasoning_content
          if ((aiMessage.reasoning == null || aiMessage.reasoning!.isEmpty) &&
              _hasThinkTags(aiMessage.content)) {
            _extractThinkingFromContent(aiMessage);
          }

          // Persist final message
          final meta = <String, dynamic>{
            ...?aiMessage.metadata,
          };
          if (aiMessage.toolCalls != null && aiMessage.toolCalls!.isNotEmpty) {
            meta['tool_calls'] =
                aiMessage.toolCalls!.map((tc) => tc.toJson()).toList();
          }
          if (aiMessage.entries.isNotEmpty) {
            meta['entries'] = ThreadEntry.listToJson(aiMessage.entries);
          }
          await _db.updateMessageContent(
            aiMessage.id,
            aiMessage.content,
            reasoning: aiMessage.reasoning,
            metadata: meta.isNotEmpty ? jsonEncode(meta) : null,
          );

          _isGenerating = false;
          notifyListeners();
        },
        onError: (e) async {
          _messages.remove(aiMessage);
          await _db.deleteMessage(aiMessage.id);
          await _insertErrorMessage(chatId, 'Error: $e');
          _isGenerating = false;
          notifyListeners();
        },
      );
    } catch (e) {
      _messages.remove(aiMessage);
      await _db.deleteMessage(aiMessage.id);
      await _insertErrorMessage(chatId, 'Connection error: $e');
      _isGenerating = false;
      notifyListeners();
    }
  }

  void _queueGenerationEvent(GenerationEvent event, Message aiMessage) {
    if (event is GenTextChunk || event is GenThoughtChunk) {
      _applyGenerationEvent(event, aiMessage);
      _batchTimer ??= Timer(const Duration(milliseconds: 50), () {
        _batchTimer = null;
        notifyListeners();
      });
      return;
    }

    _batchTimer?.cancel();
    _batchTimer = null;
    notifyListeners();
    _handleGenerationEvent(event, aiMessage);
  }

  void _handleGenerationEvent(GenerationEvent event, Message aiMessage) {
    _applyGenerationEvent(event, aiMessage);
    notifyListeners();
  }

  void _applyGenerationEvent(GenerationEvent event, Message aiMessage) {
    switch (event) {
      case GenTextChunk(:final text):
        _contentBuffer.write(text);
        aiMessage.content = _contentBuffer.toString();
        _appendOrExtendEntry(aiMessage, TextEntry(text, isStreaming: true));

      case GenThoughtChunk(:final thought):
        _reasoningBuffer.write(thought);
        aiMessage.reasoning = _reasoningBuffer.toString();
        _appendOrExtendEntry(aiMessage, ThinkingEntry(thought, isStreaming: true));

      case GenToolCallStart(:final id, :final name, :final arguments):
        aiMessage.toolCalls ??= [];
        final existing = aiMessage.toolCalls?.indexWhere((t) => t.id == id);
        if (existing == null || existing < 0) {
          aiMessage.toolCalls!.add(ToolCall(
            id: id,
            name: name,
            arguments: arguments,
          ));
        } else {
          aiMessage.toolCalls![existing].arguments = arguments;
        }
        _finalizeStreamingEntries(aiMessage);
        aiMessage.entries.add(ToolCallEntry(
          toolCallId: id,
          toolName: name,
          toolArguments: arguments,
          isExecuting: true,
        ));

      case GenToolCallResult(:final id, :final success, :final result):
        final idx = aiMessage.toolCalls?.indexWhere((t) => t.id == id);
        if (idx != null && idx >= 0 && idx < (aiMessage.toolCalls?.length ?? 0)) {
          final tc = aiMessage.toolCalls![idx];
          tc.completed = success;
          tc.error = !success;
          tc.result = result;
        }
        for (final entry in aiMessage.entries) {
          if (entry is ToolCallEntry && entry.toolCallId == id) {
            entry.completed = success;
            entry.error = !success;
            entry.result = result;
            entry.isExecuting = false;
            break;
          }
        }

      case GenUsage():
        break;

      case GenError(:final message):
        aiMessage.content = '${aiMessage.content}\n\nError: $message';
        aiMessage.entries.add(TextEntry('\n\nError: $message'));

      case GenDone():
        for (var i = 0; i < aiMessage.entries.length; i++) {
          final entry = aiMessage.entries[i];
          if (entry is ThinkingEntry && entry.isStreaming) {
            aiMessage.entries[i] = ThinkingEntry(entry.content);
          } else if (entry is TextEntry && entry.isStreaming) {
            aiMessage.entries[i] = TextEntry(entry.content);
          }
        }

      case GenTurnEnd():
        break;
    }
  }

  void _appendOrExtendEntry(Message msg, ThreadEntry newEntry) {
    if (msg.entries.isEmpty) {
      msg.entries.add(newEntry);
      return;
    }

    final last = msg.entries.last;
    if (newEntry is ThinkingEntry && last is ThinkingEntry && last.isStreaming) {
      last.content += newEntry.content;
      return;
    }
    if (newEntry is TextEntry && last is TextEntry && last.isStreaming) {
      last.content += newEntry.content;
      return;
    }

    _finalizeStreamingEntries(msg);
    msg.entries.add(newEntry);
  }

  void _finalizeStreamingEntries(Message msg) {
    for (var i = 0; i < msg.entries.length; i++) {
      final entry = msg.entries[i];
      if (entry is ThinkingEntry && entry.isStreaming) {
        msg.entries[i] = ThinkingEntry(entry.content);
      } else if (entry is TextEntry && entry.isStreaming) {
        msg.entries[i] = TextEntry(entry.content);
      }
    }
  }

  List<Map<String, dynamic>> _buildApiMessages() {
    final list = <Map<String, dynamic>>[
      {'role': 'system', 'content': _settingsProvider.systemPrompt},
    ];

    for (final m in _messages) {
      final msg = <String, dynamic>{'role': m.role, 'content': m.content};
      if (m.toolCalls != null && m.toolCalls!.isNotEmpty && m.role == 'assistant') {
        msg['tool_calls'] = m.toolCalls!.map((tc) => {
          'id': tc.id,
          'type': 'function',
          'function': {
            'name': tc.name,
            'arguments': jsonEncode(tc.arguments),
          },
        }).toList();
      }
      list.add(msg);
    }

    return list;
  }

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
      msg.entries = Message.buildLegacyEntries(
        reasoning: reasoning,
        content: cleanedContent,
        toolCalls: msg.toolCalls,
      );
      final meta = <String, dynamic>{...?msg.metadata};
      if (msg.entries.isNotEmpty) {
        meta['entries'] = ThreadEntry.listToJson(msg.entries);
      }
      await _db.updateMessageContent(msg.id, cleanedContent,
          reasoning: reasoning,
          metadata: meta.isNotEmpty ? jsonEncode(meta) : null);
    }
  }

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

    msg.entries = Message.buildLegacyEntries(
      reasoning: msg.reasoning,
      content: msg.content,
      toolCalls: msg.toolCalls,
    );
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

  Future<void> retryFromMessage(String messageId) async {
    if (_currentChat == null) return;
    cancelGeneration();

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    if (!_messages[idx].isAssistant) return;

    _messages.removeAt(idx);
    await _db.deleteMessage(messageId);
    notifyListeners();

    await _generateResponse(_currentChat!.id, _effectiveModel);
  }

  Future<void> clearAllChats() async {
    cancelGeneration();
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
