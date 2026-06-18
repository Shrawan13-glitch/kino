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
import '../services/debug_service.dart';
import '../services/tool_execution.dart';
import '../services/tool_registry.dart';

class ChatProvider extends ChangeNotifier {
  final SettingsProvider _settingsProvider;
  final DatabaseHelper _db = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();
  final OpenRouterProvider _provider = OpenRouterProvider();
  final GenerationManager _genManager = GenerationManager();
  late final SearchService _searchService;
  late final WebFetchService _webFetchService;
  final ToolExecutionService _toolExec = ToolExecutionService();

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
    DebugService.instance.info('createChat: id=${chat.id} model=${chat.model}');
    _currentChat = chat;
    _messages = [];
    notifyListeners();
    return chat;
  }

  Future<void> selectChat(String id) async {
    if (_currentChat?.id == id) return;

    DebugService.instance.info('selectChat: id=$id');
    cancelGeneration();

    _isLoading = true;
    notifyListeners();

    _currentChat = _chats.firstWhere((c) => c.id == id);
    _messages = await _db.getMessages(id);
    DebugService.instance.info('selectChat: loaded ${_messages.length} messages');
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

    DebugService.instance.info('sendMessage: content="${content.trim()}" chat=${_currentChat?.id ?? 'null'}');

    // Cancel any ongoing generation before sending a new message
    if (_isGenerating) {
      cancelGeneration();
    }

    if (!_settingsProvider.hasApiKey) {
      DebugService.instance.error('sendMessage: no API key configured');
      await _showError('No API key configured. Add one in Settings > Providers.');
      return;
    }

    if (_currentChat == null) {
      await createChat();
    }

    final chatId = _currentChat!.id;
    final isDraft = _chats.every((c) => c.id != chatId);
    final now = DateTime.now();
    final model = _effectiveModel;

    DebugService.instance.info('sendMessage: chatId=$chatId isDraft=$isDraft model="$model"');

    if (model.isEmpty) {
      DebugService.instance.error('sendMessage: model is empty');
      await _showError('No model selected. Select one in Settings > Providers.');
      return;
    }

    try {
      if (isDraft) {
        _currentChat = _currentChat!.copyWith(
          title: _truncateTitle(content),
          updatedAt: now,
          model: model,
        );
        await _db.insertChat(_currentChat!);
        DebugService.instance.info('sendMessage: chat inserted title="${_currentChat!.title}"');
        _chats.insert(0, _currentChat!);
      }

      final userMessage = Message(
        id: _uuid.v4(),
        chatId: chatId,
        role: 'user',
        content: content.trim(),
        createdAt: now,
      );

      DebugService.instance.info('sendMessage: inserting userMessage id=${userMessage.id}');
      await _db.insertMessage(userMessage);
      DebugService.instance.info('sendMessage: userMessage inserted');
      _messages.add(userMessage);

      if (!isDraft) {
        _currentChat = _currentChat!.copyWith(updatedAt: now);
        await _db.updateChat(_currentChat!);
        _chats.removeWhere((c) => c.id == chatId);
        _chats.insert(0, _currentChat!);
      }

      notifyListeners();
      DebugService.instance.info('sendMessage: calling _generateResponse');
      await _generateResponse(chatId, model);
    } catch (e, s) {
      DebugService.instance.error('sendMessage: exception', e, s);
      await _showError('Failed to send message: $e');
    }
  }

  Future<void> _generateResponse(String chatId, String model) async {
    DebugService.instance.info('_generateResponse: chatId=$chatId model="$model" messages=${_messages.length}');
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

    final toolDefinitions = _buildToolDefinitions();
    final baseMessages = _buildApiMessages();

    DebugService.instance.info('_generateResponse: inserting aiMessage id=${aiMessage.id}');
    await _db.insertMessage(aiMessage);
    _messages.add(aiMessage);
    notifyListeners();

    try {
      DebugService.instance.info('_generateResponse: calling _genManager.generate');
      final stream = _genManager.generate(
        provider: _provider,
        apiKey: _settingsProvider.apiKey,
        model: model,
        baseMessages: baseMessages,
        toolDefinitions: toolDefinitions,
        executeTool: (name, args) => _executeTool(name, args),
      );

      stream.listen(
        (event) {
          if (event is GenError) {
            DebugService.instance.error('_generateResponse: GenError: ${event.message}');
          }
          _queueGenerationEvent(event, aiMessage);
        },
        onDone: () async {
          DebugService.instance.info('_generateResponse: stream done');
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
          DebugService.instance.info('_generateResponse: completed');
        },
        onError: (e) async {
          DebugService.instance.error('_generateResponse: stream error', e);
          _messages.remove(aiMessage);
          await _db.deleteMessage(aiMessage.id);
          await _insertErrorMessage(chatId, 'Error: $e');
          _isGenerating = false;
          notifyListeners();
        },
      );
    } catch (e, s) {
      DebugService.instance.error('_generateResponse: exception', e, s);
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
    return <Map<String, dynamic>>[
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
      OpenRouterService.makeToolDefinition(
        name: 'run_tool',
        description:
            'Execute a command-line tool from the VFS /tools/ directory. Use this to run Python scripts, process media with ffmpeg, search with ripgrep, query JSON with jq, etc. Returns stdout, stderr, and exit code. Console output is truncated at ~50KB; write large output to a file instead (e.g. python3 script.py > /home/output.txt).',
        parameters: {
          'type': 'object',
          'properties': {
            'tool': {
              'type': 'string',
              'description':
                  'Name of the tool to run (e.g. "python3", "ffmpeg", "rg"). Tools are in /tools/. Use list_dir to see available tools.',
            },
            'args': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Command-line arguments to pass to the tool',
            },
            'stdin': {
              'type': 'string',
              'description':
                  'Optional stdin input (useful for piping data into tools)',
            },
            'timeout': {
              'type': 'integer',
              'description': 'Timeout in seconds (default 30, max 120)',
            },
          },
          'required': ['tool', 'args'],
        },
      ),
      OpenRouterService.makeToolDefinition(
        name: 'write_file',
        description:
            'Write content to a file in the VFS. Creates parent directories if needed. Use this to save scripts, notes, data, or any text content.',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description':
                  'File path in VFS (e.g. "/home/notes/note.txt" or "scripts/analyze.py"). Relative paths are under /home/.',
            },
            'content': {
              'type': 'string',
              'description': 'The text content to write to the file',
            },
          },
          'required': ['path', 'content'],
        },
      ),
      OpenRouterService.makeToolDefinition(
        name: 'read_file',
        description:
            'Read the contents of a file from the VFS. Returns the file content as text. Large files over ~50KB are truncated; use run_tool with head or a Python script to process them in chunks.',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description':
                  'File path in VFS (e.g. "/home/notes/note.txt" or "scripts/analyze.py")',
            },
          },
          'required': ['path'],
        },
      ),
      OpenRouterService.makeToolDefinition(
        name: 'list_dir',
        description:
            'List contents of a directory in the VFS. Shows files and directories with sizes. Use this to explore the VFS, find tools, browse user files, etc.',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description':
                  'Directory path in VFS (e.g. "/home", "/tools", "/home/notes"). Defaults to "/home".',
            },
          },
          'required': [],
        },
      ),
      OpenRouterService.makeToolDefinition(
        name: 'delete_file',
        description:
            'Delete a file or directory from the VFS. Directories are deleted recursively.',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Path of the file or directory to delete',
            },
          },
          'required': ['path'],
        },
      ),
      OpenRouterService.makeToolDefinition(
        name: 'create_dir',
        description:
            'Create a directory in the VFS. Creates parent directories as needed.',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Path of the directory to create',
            },
          },
          'required': ['path'],
        },
      ),
      ...ToolRegistry().getAgentToolDefinitions(),
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

      case 'run_tool':
        final tool = arguments['tool'] as String?;
        final args = (arguments['args'] as List?)?.cast<String>() ?? <String>[];
        final stdin = arguments['stdin'] as String?;
        final timeoutSec = arguments['timeout'] as int? ?? 30;
        if (tool == null || tool.isEmpty) {
          return 'Error: tool parameter is required for run_tool';
        }
        final result = await _toolExec.runTool(
          tool,
          args,
          stdin: stdin,
          timeout: Duration(seconds: timeoutSec.clamp(1, 120)),
        );
        return result.success ? result.stdout : result.full;

      case 'write_file':
        final path = arguments['path'] as String?;
        final content = arguments['content'] as String?;
        if (path == null || content == null) {
          return 'Error: path and content parameters are required for write_file';
        }
        return await _toolExec.writeFile(path, content);

      case 'read_file':
        final path = arguments['path'] as String?;
        if (path == null) {
          return 'Error: path parameter is required for read_file';
        }
        return await _toolExec.readFile(path);

      case 'list_dir':
        final path = arguments['path'] as String? ?? '/home';
        final listing = await _toolExec.listDirectory(path);
        return 'Contents of $path:\n$listing';

      case 'delete_file':
        final path = arguments['path'] as String?;
        if (path == null) {
          return 'Error: path parameter is required for delete_file';
        }
        return await _toolExec.deleteFile(path);

      case 'create_dir':
        final path = arguments['path'] as String?;
        if (path == null) {
          return 'Error: path parameter is required for create_dir';
        }
        return await _toolExec.createDirectory(path);

      default:
        final registry = ToolRegistry();
        final tool = registry.get(name);
        if (tool != null) {
          final args =
              (arguments['args'] as List?)?.cast<String>() ?? <String>[];
          final result = await _toolExec.runTool(
            name,
            args,
            stdin: arguments['stdin'] as String?,
            timeout: Duration(
                seconds: (arguments['timeout'] as int? ?? 30).clamp(1, 120)),
          );
          return result.success ? result.stdout : result.full;
        }
        return 'Unknown tool: $name. Available tools: web_search, fetch_url, run_tool, write_file, read_file, list_dir, delete_file, create_dir.';
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
    DebugService.instance.info('_insertErrorMessage: chatId=$chatId content="$content"');
    final msg = Message(
      id: _uuid.v4(),
      chatId: chatId,
      role: 'assistant',
      content: content,
      createdAt: DateTime.now(),
    );
    try {
      await _db.insertMessage(msg);
      _messages.add(msg);
      DebugService.instance.info('_insertErrorMessage: done');
    } catch (e, s) {
      DebugService.instance.error('_insertErrorMessage: DB insert failed', e, s);
    }
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

  Future<void> _showError(String message) async {
    DebugService.instance.error('_showError: $message');
    if (_currentChat == null) {
      await createChat();
    }
    await _insertErrorMessage(_currentChat!.id, message);
    notifyListeners();
  }

  String _truncateTitle(String text) {
    if (text.length <= 40) return text;
    return '${text.substring(0, 40)}...';
  }
}
