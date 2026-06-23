import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart';
import '../database/database_helper.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/thread_entry.dart';
import '../services/openrouter_provider.dart';
import '../services/generation_manager.dart';
import '../services/openrouter_service.dart';
import '../services/search/search_service.dart';
import '../services/search/webfetch_service.dart';
import '../services/vfs/vfs_service.dart';
import '../services/github/github_auth_service.dart';
import '../services/github/github_integration_service.dart';
import '../services/github/github_tool_service.dart';
import '../services/tts/tts_service.dart';
import '../services/tts/tts_result.dart';
import '../utils/content_parser.dart';
import 'settings_provider.dart';
import '../services/debug_service.dart';
import '../services/tool_execution.dart';
import '../services/vfs/vfs_shell.dart';
import '../services/http_service.dart';
import '../services/foreground_service.dart';

class ChatProvider extends ChangeNotifier {
  final SettingsProvider _settingsProvider;
  final DatabaseHelper _db = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();
  final OpenRouterProvider _provider = OpenRouterProvider();
  final GenerationManager _genManager = GenerationManager();
  late final SearchService _searchService;
  late final WebFetchService _webFetchService;
  final ToolExecutionService _toolExec = ToolExecutionService();
  final VfsShell _vfsShell = VfsShell();
  final GithubAuthService _githubAuth = GithubAuthService();
  final HttpService _httpService = HttpService();
  GithubIntegrationService? _githubIntegration;
  TtsService? _ttsService;
  Message? _activeAiMessage;

  ChatProvider(this._settingsProvider) {
    _searchService = SearchService();
    _webFetchService = WebFetchService();
  }

  GithubAuthService get githubAuth => _githubAuth;

  void initGithub() {
    if (_settingsProvider.isGithubConnected) {
      _githubAuth.restore(
        _settingsProvider.githubToken,
        _settingsProvider.githubUsername,
      );
      _githubIntegration = GithubIntegrationService(_githubAuth);
      _ttsService = TtsService(_githubAuth);
    } else {
      _githubIntegration = null;
      _ttsService = null;
    }
    GithubToolService.ensureInitialized();
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

  bool get hasActiveTaskPlan => _currentChat?.hasActiveTaskPlan ?? false;

  TaskPlanEntry? get activeTaskPlan => _currentChat?.taskPlan;
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

    initGithub();
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
    _migrateTaskPlanFromMessages();

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

  Future<void> renameChat(String id, String newTitle) async {
    final index = _chats.indexWhere((c) => c.id == id);
    if (index == -1) return;

    _chats[index] = _chats[index].copyWith(
      title: newTitle,
      updatedAt: DateTime.now(),
    );

    if (_currentChat?.id == id) {
      _currentChat = _chats[index];
    }

    await _db.updateChat(_chats[index]);
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
    ForegroundService.stop();
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

    await ForegroundService.start();

    final aiMessage = Message(
      id: _uuid.v4(),
      chatId: chatId,
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
    );
    _activeAiMessage = aiMessage;

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
          _activeAiMessage = null;
          notifyListeners();
          await ForegroundService.stop();
          DebugService.instance.info('_generateResponse: completed');
        },
        onError: (e) async {
          DebugService.instance.error('_generateResponse: stream error', e);
          _activeAiMessage = null;
          _messages.remove(aiMessage);
          await _db.deleteMessage(aiMessage.id);
          await _insertErrorMessage(chatId, 'Error: $e');
          _isGenerating = false;
          notifyListeners();
          await ForegroundService.stop();
        },
      );
    } catch (e, s) {
      DebugService.instance.error('_generateResponse: exception', e, s);
      _activeAiMessage = null;
      _messages.remove(aiMessage);
      await _db.deleteMessage(aiMessage.id);
      await _insertErrorMessage(chatId, 'Connection error: $e');
      _isGenerating = false;
      notifyListeners();
      await ForegroundService.stop();
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
            'Fetch and read text content of a web page. Uses a simple HTTP request. May fail on sites that require JavaScript or have bot protection (Cloudflare, etc.). Returns stripped text up to ~50KB.',
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
        name: 'power_fetch_url',
        description:
            'Fetch a web page using a headless WebView (full browser engine). Renders JavaScript and bypasses most bot protection. Slower but more reliable than fetch_url. Returns stripped text up to ~50KB.',
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
        name: 'http_request',
        description:
            'Make a full HTTP request to any URL with complete control. '
            'Supports all methods, custom headers, request body, timeout, and redirect control. '
            'Returns status code, response headers, and response body. '
            'Use this to interact with REST APIs, submit forms, download data, '
            'or access any HTTP endpoint. For simple page fetching, prefer fetch_url or power_fetch_url.',
        parameters: {
          'type': 'object',
          'properties': {
            'url': {
              'type': 'string',
              'description': 'The full URL to request (e.g. https://api.example.com/data)',
            },
            'method': {
              'type': 'string',
              'description':
                  'HTTP method: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS (default: GET)',
              'enum': ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'],
            },
            'headers': {
              'type': 'object',
              'description':
                  'Custom HTTP headers as key-value pairs. '
                  'Use this to set Authorization, Content-Type, Accept, etc. '
                  'Example: {"Authorization": "Bearer token123", "Content-Type": "application/json"}',
              'additionalProperties': {'type': 'string'},
            },
            'body': {
              'type': 'string',
              'description':
                  'Request body as a string. For JSON APIs, pass a JSON string. '
                  'For form submissions, pass URL-encoded data. '
                  'Content-Type is auto-set if not specified: application/json for JSON-looking bodies, '
                  'application/x-www-form-urlencoded for form data, text/plain otherwise.',
            },
            'timeout': {
              'type': 'integer',
              'description': 'Request timeout in seconds (default: 30, max: 120)',
              'minimum': 1,
              'maximum': 120,
            },
            'follow_redirects': {
              'type': 'boolean',
              'description': 'Whether to automatically follow redirects (default: true). '
                  'Set to false to inspect redirect locations manually.',
            },
          },
          'required': ['url'],
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
                  'File path in VFS. Can be absolute (e.g. "/notes/todo.txt") or relative to VFS root (e.g. "notes/todo.txt"). All paths resolve to VFS root.',
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
            'Read the contents of a file from the VFS. Returns the file content as text. Large files over ~50KB are truncated; read in chunks using read_file with offset.',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description':
                  'File path in VFS (e.g. "/notes/todo.txt" or "notes/todo.txt")',
            },
          },
          'required': ['path'],
        },
      ),
      OpenRouterService.makeToolDefinition(
        name: 'list_dir',
        description:
            'List contents of a directory in the VFS. Shows files and directories with sizes. Use this to explore the VFS and find files.',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description':
                  'Directory path in VFS (e.g. "/" or "projects"). Defaults to root "/".',
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
      OpenRouterService.makeToolDefinition(
        name: 'generate_pdf',
        description:
            'Generate a PDF document from HTML content. Renders HTML with full CSS support using native WebView. '
            'Provide a full HTML page including <html>, <head>, and <body> tags. Uses CSS page-break for multi-page.',
        parameters: {
          'type': 'object',
          'properties': {
            'html': {
              'type': 'string',
              'description':
                  'Full HTML document content to render as PDF. Must include <!DOCTYPE html>, <html>, <head>, and <body> tags. '
                  'Use CSS page-break-after: always for multi-page documents. Supports full CSS styling.',
            },
            'output': {
              'type': 'string',
              'description':
                  'Output PDF file path in VFS (e.g. "report.pdf" or "documents/report.pdf")',
            },
          },
          'required': ['html', 'output'],
        },
      ),
      OpenRouterService.makeToolDefinition(
        name: 'generate_speech',
        description:
            'Generate high-quality speech audio from text using ShryneTTS. '
            'Converts text to natural-sounding speech with multiple voice options. '
            'Supports multi-segment generation — provide an items array for podcast-style output '
            'with different voices and speeds per segment. Requires GitHub connection.',
        parameters: {
          'type': 'object',
          'properties': {
            'items': {
              'type': 'array',
              'description':
                  'Array of speech segments. Each item has: text (required), voice (optional, default "af_sky"), '
                  'speed (optional, default 1.0). For podcasts, provide multiple items with different voices.',
              'items': {
                'type': 'object',
                'properties': {
                  'text': {
                    'type': 'string',
                    'description': 'Text to speak for this segment',
                  },
                  'voice': {
                    'type': 'string',
                    'description':
                        'Voice ID. American English female: af_bella, af_sky, af_sarah, af_nicole, af_heart, af_river. '
                        'American English male: am_adam, am_echo, am_liam, am_michael, am_onyx. '
                        'British English female: bf_alice, bf_emma, bf_lily. '
                        'British English male: bm_daniel, bm_george, bm_lewis. Default: "af_sky"',
                  },
                  'speed': {
                    'type': 'number',
                    'description': 'Speech speed from 0.5 to 2.0. Default: 1.0',
                  },
                },
                'required': ['text'],
              },
            },
            'output': {
              'type': 'string',
              'description':
                  'Output WAV file path in VFS (e.g. "speech.wav" or "podcasts/episode.wav")',
            },
          },
          'required': ['items', 'output'],
        },
      ),

      OpenRouterService.makeToolDefinition(
        name: 'create_task_plan',
        description:
            'Break down a complex query or project into a structured todo list. '
            'IMPORTANT: Only ONE todo list can be active at a time per chat. '
            'If a todo list already exists with incomplete tasks, new tasks are APPENDED '
            'to the existing list — they do NOT replace it. '
            'To create a fresh standalone plan, complete all existing tasks first. '
            'Create the plan first, then work through each task sequentially, '
            'updating their status as you go. '
            'When all tasks are completed the todo list is automatically cleared.',
        parameters: {
          'type': 'object',
          'properties': {
            'tasks': {
              'type': 'array',
              'description':
                  'Array of tasks to perform, in order. If a plan already exists, '
                  'these are appended to it. Each task must have a brief unique id, '
                  'a short title, and a one-line description of what to do.',
              'items': {
                'type': 'object',
                'properties': {
                  'id': {
                    'type': 'string',
                    'description': 'Unique identifier for this task (e.g. "1", "research", "setup")',
                  },
                  'title': {
                    'type': 'string',
                    'description': 'Short task title (e.g. "Research topic", "Create repo")',
                  },
                  'description': {
                    'type': 'string',
                    'description': 'One-line description of what this task involves',
                  },
                },
                'required': ['id', 'title'],
              },
            },
          },
          'required': ['tasks'],
        },
      ),
      OpenRouterService.makeToolDefinition(
        name: 'update_task_status',
        description:
            'Update the status of a task in the current todo list. '
            'Call this when you complete a task, start working on one, or if one fails. '
            'When ALL tasks are marked completed, the todo list is automatically cleared. '
            'The user will see the task list update in real-time.',
        parameters: {
          'type': 'object',
          'properties': {
            'task_id': {
              'type': 'string',
              'description': 'The task id from the plan you created',
            },
            'status': {
              'type': 'string',
              'description': 'New status: "completed" when done, "in_progress" when starting, '
                  '"failed" if something went wrong',
              'enum': ['pending', 'in_progress', 'completed', 'failed'],
            },
          },
          'required': ['task_id', 'status'],
        },
      ),
      OpenRouterService.makeToolDefinition(
        name: 'clear_task_plan',
        description:
            'Clear the entire todo list, removing all tasks. '
            'Use this when you want to discard the current plan and start fresh. '
            'After calling this, you can create a new plan with create_task_plan.',
        parameters: {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      ),

      OpenRouterService.makeToolDefinition(
        name: 'execute_bash',
        description:
            'Run a bash command in the VFS shell. Supports all common bash built-ins (cd, pwd, ls, cat, '
            'echo, mkdir, rm, cp, mv, touch, head, tail, export, env, etc.) as well as external '
            'commands via the system shell (/bin/sh). The shell maintains state across calls: '
            'the current working directory, environment variables, and directory stack persist. '
            'Use cd to navigate, pipes and redirects work naturally. '
            'The working directory is rooted in the VFS (virtual file system) so all paths are '
            'VFS-relative. Use this to explore the filesystem, run scripts, manipulate files, '
            'and execute any command that would work in a normal shell.',
        parameters: {
          'type': 'object',
          'properties': {
            'command': {
              'type': 'string',
              'description':
                  'The bash command to execute. Can be a simple command (ls -la), '
                  'compound command with pipes (cat file | grep foo), '
                  'or chained commands (cd /projects && npm install). '
                  'State is persisted between calls: cwd, env vars, dir stack.',
            },
          },
          'required': ['command'],
        },
      ),

      if (_githubIntegration != null) ...GithubToolService.toolDefinitions,
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
        final fetchUrl = arguments['url'] as String?;
        if (fetchUrl == null || fetchUrl.isEmpty) {
          return 'Error: url parameter is required for fetch_url';
        }
        final fetchContent = await _webFetchService.fetchContent(
          fetchUrl,
          timeoutSeconds: _settingsProvider.webFetchTimeout,
        );
        if (fetchContent == null) {
          return 'Failed to fetch content from $fetchUrl. The page may be unreachable, blocked, or requires JavaScript. Try power_fetch_url instead.';
        }
        return 'Content from $fetchUrl:\n\n$fetchContent';

      case 'power_fetch_url':
        final powerUrl = arguments['url'] as String?;
        if (powerUrl == null || powerUrl.isEmpty) {
          return 'Error: url parameter is required for power_fetch_url';
        }
        final powerContent = await _webFetchService.powerFetchContent(
          powerUrl,
          timeoutSeconds: _settingsProvider.webFetchTimeout,
        );
        if (powerContent == null) {
          return 'Failed to fetch content from $powerUrl. The page may be unreachable or requires login.';
        }
        return 'Content from $powerUrl:\n\n$powerContent';

      case 'http_request':
        final requestUrl = arguments['url'] as String?;
        if (requestUrl == null || requestUrl.isEmpty) {
          return 'Error: url parameter is required for http_request';
        }
        final method = (arguments['method'] as String? ?? 'GET').toUpperCase();
        final headers = arguments['headers'] as Map<String, dynamic>?;
        final body = arguments['body'] as String?;
        final timeout = arguments['timeout'] as int? ?? 30;
        final followRedirects = arguments['follow_redirects'] as bool? ?? true;

        final stringHeaders = <String, String>{};
        if (headers != null) {
          for (final e in headers.entries) {
            if (e.value is String) {
              stringHeaders[e.key] = e.value as String;
            }
          }
        }

        try {
          final response = await _httpService.request(
            url: requestUrl,
            method: method,
            headers: stringHeaders.isNotEmpty ? stringHeaders : null,
            body: body,
            timeout: Duration(seconds: timeout.clamp(1, 120)),
            followRedirects: followRedirects,
          );
          return response.toString();
        } catch (e) {
          return 'HTTP request failed: $e';
        }

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
        final path = arguments['path'] as String? ?? '/';
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

      case 'generate_pdf':
        final html = arguments['html'] as String?;
        final output = arguments['output'] as String?;
        if (html == null || html.isEmpty) {
          return 'Error: html parameter is required for generate_pdf';
        }
        if (output == null || output.isEmpty) {
          return 'Error: output path is required for generate_pdf';
        }

        try {
          final converter = HtmlToPdfConverter();
          final pdfBytes = await converter.convertHtmlToPdfBytes(
            html: html,
            pageSize: PdfPageSize.a4,
          );

          final vfs = VfsService();
          final resolved = output.startsWith('/') ? output : '/$output';
          await vfs.writeFile(resolved, pdfBytes);

          return 'PDF generated successfully: $resolved (${pdfBytes.length} bytes)';
        } catch (e) {
          return 'Error generating PDF: $e';
        }

      case 'generate_speech':
        if (!_settingsProvider.isGithubConnected) {
          return 'Error: GitHub not connected. Go to Settings > ShryneTTS to connect your GitHub account. '
              'A public repository will be created on your account to run TTS generation via GitHub Actions.';
        }

        final itemsRaw = arguments['items'];
        if (itemsRaw == null || (itemsRaw is List && itemsRaw.isEmpty)) {
          return 'Error: items parameter is required for generate_speech';
        }

        final itemsList = itemsRaw as List;
        final ttsItems = itemsList.map((item) {
          final map = item as Map<String, dynamic>;
          return TtsItem(
            text: map['text'] as String? ?? '',
            voice: map['voice'] as String? ?? 'af_sky',
            speed: (map['speed'] as num?)?.toDouble() ?? 1.0,
          );
        }).toList();

        final outputPath = arguments['output'] as String? ?? 'speech.wav';

        _ttsService ??= TtsService(_githubAuth);
        return await _ttsService!.generateSpeech(
          items: ttsItems,
          outputPath: outputPath,
        );

      case 'clear_task_plan':
        if (_currentChat?.taskPlan == null) {
          return 'No todo list to clear.';
        }
        _currentChat = _currentChat!.copyWith(taskPlan: null);
        await _db.updateChat(_currentChat!);
        notifyListeners();
        return 'Todo list cleared. You can now create a new plan.';

      case 'create_task_plan':
        final tasksRaw = arguments['tasks'] as List?;
        if (tasksRaw == null || tasksRaw.isEmpty) {
          return 'Error: tasks parameter is required for create_task_plan';
        }
        final newTasks = tasksRaw.map((t) {
          final map = t as Map<String, dynamic>;
          return Task(
            id: map['id'] as String,
            title: map['title'] as String,
            description: map['description'] as String? ?? '',
          );
        }).toList();

        TaskPlanEntry planEntry;
        if (_currentChat?.taskPlan != null &&
            _currentChat!.taskPlan!.tasks
                .any((t) => t.status == TaskStatus.inProgress || t.status == TaskStatus.pending)) {
          final existing = _currentChat!.taskPlan!;
          existing.tasks.addAll(newTasks);
          planEntry = existing;
        } else {
          planEntry = TaskPlanEntry(tasks: newTasks);
        }

        _currentChat = _currentChat!.copyWith(taskPlan: planEntry);
        _saveTaskPlan();
        _activeAiMessage?.entries.add(TaskPlanEntry(tasks: List.from(planEntry.tasks)));
        notifyListeners();
        return 'Task plan created with ${newTasks.length} tasks. Start working through them and update their status with update_task_status as you complete each one.';

      case 'update_task_status':
        final taskId = arguments['task_id'] as String?;
        final statusStr = arguments['status'] as String?;
        if (taskId == null || statusStr == null) {
          return 'Error: task_id and status parameters are required for update_task_status';
        }
        final status = TaskStatus.values.firstWhere(
          (s) => s.name == statusStr,
          orElse: () => TaskStatus.pending,
        );
        if (_currentChat?.taskPlan == null) {
          return 'Error: no task plan found. Create one first with create_task_plan.';
        }
        _currentChat!.taskPlan!.updateTaskStatus(taskId, status);
        notifyListeners();

        final taskName =
            _currentChat!.taskPlan!.tasks.firstWhere((t) => t.id == taskId).title;

        // Update the entry in the active message for persistence
        if (_activeAiMessage != null) {
          for (final entry in _activeAiMessage!.entries) {
            if (entry is TaskPlanEntry) {
              entry.updateTaskStatus(taskId, status);
            }
          }
        }

        if (_currentChat!.isTaskPlanComplete) {
          _currentChat = _currentChat!.copyWith(taskPlan: null);
          await _db.updateChat(_currentChat!);
          return 'Task "$taskName" marked as $statusStr. All tasks completed! The todo list has been cleared.';
        }

        _saveTaskPlan();
        return 'Task "$taskName" updated to $statusStr.';

      case 'execute_bash':
        final bashCommand = arguments['command'] as String?;
        if (bashCommand == null || bashCommand.isEmpty) {
          return 'Error: command parameter is required for execute_bash';
        }
        final shellResult = await _vfsShell.execute(bashCommand);
        return shellResult.full;

      default:
        if (name.startsWith('github_')) {
          if (_githubIntegration == null) {
            return 'Error: GitHub not connected. Go to Settings to connect your GitHub account.';
          }
          return await _githubIntegration!.executeTool(name, arguments);
        }
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

  void _migrateTaskPlanFromMessages() {
    if (_currentChat?.taskPlan != null) return;
    if (_messages.isEmpty) return;

    TaskPlanEntry? latestPlan;
    for (final msg in _messages.reversed) {
      for (final entry in msg.entries.reversed) {
        if (entry is TaskPlanEntry) {
          latestPlan = entry;
          break;
        }
      }
      if (latestPlan != null) break;
    }

    if (latestPlan == null) return;
    if (latestPlan.tasks.every((t) => t.status == TaskStatus.completed)) return;

    _currentChat = _currentChat!.copyWith(taskPlan: latestPlan);
    _saveTaskPlan();
  }

  Future<void> _saveTaskPlan() async {
    if (_currentChat == null) return;
    await _db.updateChat(_currentChat!);
  }

}
