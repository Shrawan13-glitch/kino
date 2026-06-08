import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../services/openrouter_service.dart';
import '../utils/content_parser.dart';
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

    notifyListeners();

    await _generateResponse(chatId, model);
  }

  List<Map<String, String>> _buildApiMessages() {
    final list = <Map<String, String>>[
      {'role': 'system', 'content': _settingsProvider.systemPrompt},
    ];

    for (final m in _messages) {
      list.add({'role': m.role, 'content': m.content});
    }

    return list;
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

    try {
      final stream = OpenRouterService.sendMessageStream(
        apiKey: _settingsProvider.apiKey,
        model: model,
        messages: _buildApiMessages(),
      );

      int lastNotify = 0;
      await for (final chunk in stream) {
        aiMessage.content += chunk.content;
        if (chunk.reasoning != null) {
          aiMessage.reasoning = (aiMessage.reasoning ?? '') + chunk.reasoning!;
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotify > 50) {
          notifyListeners();
          lastNotify = now;
        }
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
      _isGenerating = false;
      notifyListeners();
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
