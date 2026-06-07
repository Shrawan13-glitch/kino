import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../utils/mock_responses.dart';

class ChatProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

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

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    _chats = await _db.getAllChats();
    _initialized = true;
    _isLoading = false;
    notifyListeners();
  }

  Future<Chat> createChat() async {
    final now = DateTime.now();
    final chat = Chat(
      id: _uuid.v4(),
      title: 'New Chat',
      createdAt: now,
      updatedAt: now,
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

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    if (_currentChat == null) {
      await createChat();
    }

    final chatId = _currentChat!.id;
    final isDraft = _chats.every((c) => c.id != chatId);
    final now = DateTime.now();

    if (isDraft) {
      _currentChat = _currentChat!.copyWith(
        title: _truncateTitle(content),
        updatedAt: now,
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

    await _generateMockResponse(chatId);
  }

  Future<void> _generateMockResponse(String chatId) async {
    _isGenerating = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 1200));

    final lastUserMsg = _messages.lastWhere(
      (m) => m.isUser,
      orElse: () => _messages.first,
    );

    final responseContent = MockResponses.getResponse(lastUserMsg.content);

    final aiMessage = Message(
      id: _uuid.v4(),
      chatId: chatId,
      role: 'assistant',
      content: responseContent,
      createdAt: DateTime.now(),
    );

    await _db.insertMessage(aiMessage);
    _messages.add(aiMessage);
    _isGenerating = false;
    notifyListeners();
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

  String _truncateTitle(String text) {
    if (text.length <= 40) return text;
    return '${text.substring(0, 40)}...';
  }
}
