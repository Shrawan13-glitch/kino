import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../services/debug_service.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('kino.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, fileName);
    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE chats(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT 'New Chat',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        model TEXT,
        system_prompt TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE messages(
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        role TEXT NOT NULL CHECK(role IN ('user', 'assistant', 'system')),
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        reasoning TEXT,
        metadata TEXT,
        FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_messages_chat_id ON messages(chat_id)');
    await db.execute('CREATE INDEX idx_chats_updated ON chats(updated_at)');
    await db.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings(
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE messages ADD COLUMN reasoning TEXT');
    }
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE messages ADD COLUMN reasoning TEXT');
      } catch (_) {
        // Column already exists from the v3 migration above
      }
    }
  }

  Future<List<Chat>> getAllChats() async {
    final db = await database;
    final maps = await db.query('chats', orderBy: 'updated_at DESC');
    return maps.map((map) => Chat.fromMap(map)).toList();
  }

  Future<Chat?> getChat(String id) async {
    final db = await database;
    final maps = await db.query('chats', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Chat.fromMap(maps.first);
  }

  Future<void> insertChat(Chat chat) async {
    try {
      final db = await database;
      await db.insert('chats', chat.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      DebugService.instance.info('DB: chat inserted id=${chat.id}');
    } catch (e, s) {
      DebugService.instance.error('DB: insertChat failed', e, s);
      rethrow;
    }
  }

  Future<void> updateChat(Chat chat) async {
    try {
      final db = await database;
      await db.update('chats', chat.toMap(),
          where: 'id = ?', whereArgs: [chat.id]);
    } catch (e, s) {
      DebugService.instance.error('DB: updateChat failed', e, s);
      rethrow;
    }
  }

  Future<void> deleteChat(String id) async {
    final db = await database;
    await db.delete('messages', where: 'chat_id = ?', whereArgs: [id]);
    await db.delete('chats', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Message>> getMessages(String chatId) async {
    try {
      final db = await database;
      final maps = await db.query('messages',
          where: 'chat_id = ?',
          whereArgs: [chatId],
          orderBy: 'created_at ASC');
      return maps.map((map) => Message.fromMap(map)).toList();
    } catch (e, s) {
      DebugService.instance.error('DB: getMessages failed', e, s);
      rethrow;
    }
  }

  Future<void> insertMessage(Message message) async {
    try {
      final db = await database;
      await db.insert('messages', message.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      DebugService.instance.info('DB: message inserted id=${message.id}');
    } catch (e, s) {
      DebugService.instance.error('DB: insertMessage failed', e, s);
      rethrow;
    }
  }

  Future<void> deleteMessage(String id) async {
    final db = await database;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateMessageContent(String id, String content,
      {String? reasoning, String? metadata}) async {
    final db = await database;
    final values = <String, dynamic>{'content': content};
    if (reasoning != null) {
      values['reasoning'] = reasoning;
    }
    if (metadata != null) {
      values['metadata'] = metadata;
    }
    await db.update(
      'messages',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<String> exportToJson() async {
    final db = await database;
    final chats = await db.query('chats');
    final messages = await db.query('messages');
    final export = {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'chats': chats,
      'messages': messages,
    };
    return jsonEncode(export);
  }

  Future<void> importFromJson(String json) async {
    final db = await database;
    final data = jsonDecode(json) as Map<String, dynamic>;
    final chats = data['chats'] as List<dynamic>;
    final messages = data['messages'] as List<dynamic>;

    await db.transaction((txn) async {
      for (final chat in chats) {
        await txn.insert('chats', chat as Map<String, dynamic>);
      }
      for (final message in messages) {
        await txn.insert('messages', message as Map<String, dynamic>);
      }
    });
  }

  Future<String> getDatabaseFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'kino.db');
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('chats');
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isEmpty) return null;
    return maps.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSetting(String key) async {
    final db = await database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    final maps = await db.query('settings');
    return {
      for (final map in maps) map['key'] as String: map['value'] as String,
    };
  }
}
