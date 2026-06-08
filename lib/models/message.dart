import 'dart:convert';

class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  String? result;
  bool completed;
  bool error;

  ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.result,
    this.completed = false,
    this.error = false,
  });
}

class Message {
  final String id;
  final String chatId;
  final String role;
  String content;
  String? reasoning;
  final DateTime createdAt;
  Map<String, dynamic>? metadata;

  /// In-memory tool calls attached to this assistant message.
  /// Not persisted to the database.
  List<ToolCall>? toolCalls;

  Message({
    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    this.reasoning,
    required this.createdAt,
    this.metadata,
    this.toolCalls,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'role': role,
      'content': content,
      'reasoning': reasoning,
      'created_at': createdAt.toIso8601String(),
      'metadata': metadata != null ? jsonEncode(metadata) : null,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      role: map['role'] as String,
      content: map['content'] as String,
      reasoning: map['reasoning'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      metadata: map['metadata'] != null
          ? jsonDecode(map['metadata'] as String) as Map<String, dynamic>
          : null,
    );
  }
}
