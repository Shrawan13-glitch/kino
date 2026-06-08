import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/tool_call.dart';
import '../services/openrouter_service.dart';
import '../services/tool_service.dart';
import 'settings_provider.dart';

class ChatProvider extends ChangeNotifier {
  final SettingsProvider _settingsProvider;
  final DatabaseHelper _db = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  ChatProvider(this._settingsProvider);

  List<Chat> _chats = [];
  Chat? _currentChat;
  List<Message> _messages = [];
  bool _isLoading = false;
  bool _isGenerating = false;
  bool _initialized = false;

  List<Chat> get chats => _chats;
  Chat? get currentChat => _currentChat;
  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isGenerating => _isGenerating;
  bool get initialized => _initialized;

  String get _effectiveModel =>
      _currentChat?.model ?? _settingsProvider.defaultModel;

  static final RegExp _toolTagRe =
      RegExp(r'<tool\s+name="([^"]+)"\s+args="([^"]*)"\s*/>');
  static final RegExp _toolMarkerRe = RegExp(r'\x00tool:(\d+)\x00');

  static String _toolMarker(int idx) => '\x00tool:$idx\x00';

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

    notifyListeners();

    await _generateResponse(chatId, model);
  }

  String _contentForApi(String content) =>
      content.replaceAll(_toolMarkerRe, '');

  List<Map<String, String>> _buildApiMessages(
      Message aiMessage, List<ToolCall> toolResults) {
    final list = <Map<String, String>>[
      {'role': 'system', 'content': _settingsProvider.systemPrompt},
    ];

    for (final m in _messages) {
      if (m.id == aiMessage.id) continue;
      list.add({'role': m.role, 'content': _contentForApi(m.content)});
    }

    if (toolResults.isNotEmpty) {
      final buf = StringBuffer('Tool results:\n\n');
      final grouped = <String, List<ToolCall>>{};
      for (final t in toolResults) {
        grouped.putIfAbsent(t.name, () => []).add(t);
      }
      for (final entry in grouped.entries) {
        buf.writeln('--- ${entry.key} ---');
        for (final t in entry.value) {
          buf.writeln('Args: ${t.args}');
          if (t.result != null) buf.writeln(t.result);
          if (t.error != null) buf.writeln('Error: ${t.error}');
          buf.writeln();
        }
      }
      buf.write('Continue your response incorporating these results.');
      list.add({'role': 'system', 'content': buf.toString().trim()});
    }

    return list;
  }

  List<ToolCall> _parseToolCalls(String content) {
    return _toolTagRe.allMatches(content).map((m) => ToolCall(
          name: m.group(1)!,
          args: m.group(2)!,
        )).toList();
  }

  String _replaceWithMarkers(String content, List<ToolCall> calls) {
    int idx = 0;
    return content.replaceAllMapped(_toolTagRe, (m) {
      final replacement = _toolMarker(idx);
      idx++;
      return replacement;
    });
  }

  Future<String> _executeTool(String name, String args) async {
    switch (name) {
      case 'websearch':
        final result = await ToolService.webSearch(args);
        return result.formatted;
      default:
        throw Exception('Unknown tool: $name');
    }
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

    final allToolCalls = <ToolCall>[];
    int rounds = 0;
    const maxRounds = 5;

    try {
      while (rounds < maxRounds) {
        final apiMessages = _buildApiMessages(aiMessage,
            rounds > 0 ? allToolCalls : []);

        final stream = OpenRouterService.sendMessageStream(
          apiKey: _settingsProvider.apiKey,
          model: model,
          messages: apiMessages,
        );

        await for (final chunk in stream) {
          aiMessage.content += chunk;
          notifyListeners();
        }

        final toolCalls = _parseToolCalls(aiMessage.content);
        if (toolCalls.isEmpty) break;

        rounds++;

        aiMessage.content =
            _replaceWithMarkers(aiMessage.content.trim(), toolCalls);
        await _db.updateMessageContent(aiMessage.id, aiMessage.content);

        for (final tool in toolCalls) {
          tool.isRunning = true;
          notifyListeners();
          try {
            final result = await _executeTool(tool.name, tool.args);
            tool.result = result;
          } catch (e) {
            tool.error = e.toString();
          }
          tool.isRunning = false;
        }

        allToolCalls.addAll(toolCalls);
        aiMessage.metadata = {
          'tool_calls': allToolCalls.map((t) => t.toJson()).toList(),
        };
        notifyListeners();
      }

      await _db.updateMessageContent(aiMessage.id, aiMessage.content);
    } on OpenRouterException catch (e) {
      _messages.remove(aiMessage);
      await _db.deleteMessage(aiMessage.id);
      await _insertErrorMessage(chatId, 'Error: ${e.message}');
    } catch (e) {
      _messages.remove(aiMessage);
      await _db.deleteMessage(aiMessage.id);
      await _insertErrorMessage(chatId, 'Connection error: $e');
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
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
