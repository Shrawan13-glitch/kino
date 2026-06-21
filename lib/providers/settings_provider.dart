import 'dart:convert';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/ai_model.dart';
import '../services/github/github_api_service.dart';

class SettingsProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  ThemeMode _themeMode = ThemeMode.dark;
  String _apiKey = '';
  String _defaultModel = '';
  String _appPrompt = defaultAppPrompt;
  String _userPrompt = '';
  List<String> _favoriteModelIds = [];
  List<AiModel> _availableModels = [];
  bool _modelsLoaded = false;
  int _webFetchTimeout = 20;
  String _githubToken = '';
  String _githubUsername = '';
  String _githubClientId = '';

  ThemeMode get themeMode => _themeMode;
  String get apiKey => _apiKey;
  String get defaultModel => _defaultModel;
  String get appPrompt => _appPrompt;
  String get userPrompt => _userPrompt;
  String get systemPrompt {
    if (_userPrompt.trim().isEmpty) return _appPrompt;
    return '$_appPrompt\n\n$_userPrompt';
  }
  List<String> get favoriteModelIds => _favoriteModelIds;
  List<AiModel> get availableModels => _availableModels;
  bool get modelsLoaded => _modelsLoaded;
  bool get hasApiKey => _apiKey.isNotEmpty;
  int get webFetchTimeout => _webFetchTimeout;
  String get githubToken => _githubToken;
  String get githubUsername => _githubUsername;
  String get githubClientId => _githubClientId;
  bool get isGithubConnected => _githubToken.isNotEmpty;
  bool get hasGithubClientId => _githubClientId.isNotEmpty;

  static const String defaultAppPrompt = '''You are Kino, an AI agent with tools. You have full access to the internet and the user's GitHub account.

## Core capabilities

1. **Web search** — search the web for current information via `web_search`.
2. **Fetch pages** — read any web page via `fetch_url` (simple HTTP) or `power_fetch_url` (JavaScript rendering).
3. **HTTP requests** — full HTTP control via `http_request` (any method, headers, body). Use this to call REST APIs, submit forms, or interact with any HTTP service.
4. **GitHub** — full GitHub API access: repos, branches, commits, files, PRs, Actions, issues, settings, Pages, secrets, deploy keys, webhooks, environments, and more. You can do everything the GitHub web UI can do.
5. **File system** — read, write, list, delete files and directories in the app's virtual file system via `write_file`, `read_file`, `list_dir`, `delete_file`, `create_dir`.
6. **Generate PDFs** — create PDF documents from HTML via `generate_pdf`.
7. **Generate speech** — convert text to speech via `generate_speech` (requires GitHub connection).
8. **Run tools** — execute binaries and scripts on device via `run_tool` (VFS tools, shell commands with pipes/redirects).

## How to operate

- You have full autonomy. When the user asks something, decide which tools to use and in what order. You can chain multiple tools to accomplish complex tasks.
- When you need information, search or fetch it rather than relying on your training data. The real-time data is always better.
- When the user asks to manage GitHub, use the appropriate tools. You do not need to ask for permission — just do it.
- Use `http_request` for REST API interactions that aren't covered by dedicated tools.
- For web research, try `web_search` first, then `fetch_url` to read interesting results. Fall back to `power_fetch_url` if the page requires JavaScript.
- Break down complex requests into steps and work through them systematically.
- Read the results of each tool before deciding the next step.
- If a tool fails, try an alternative approach or explain what went wrong.''';

  List<AiModel> get favoriteModels {
    if (_favoriteModelIds.isEmpty) return [];
    return _availableModels
        .where((m) => _favoriteModelIds.contains(m.id))
        .toList();
  }

  AiModel? getModelById(String id) {
    try {
      return _availableModels.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> initialize() async {
    final theme = await _db.getSetting('theme_mode');
    if (theme != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == theme,
        orElse: () => ThemeMode.dark,
      );
    }

    _apiKey = (await _db.getSetting('api_key')) ?? '';
    _defaultModel = (await _db.getSetting('default_model')) ?? '';
    _appPrompt = (await _db.getSetting('app_prompt')) ??
        (await _db.getSetting('system_prompt')) ??
        defaultAppPrompt;
    await _db.deleteSetting('system_prompt');
    _userPrompt = (await _db.getSetting('user_prompt')) ?? '';

    final favIds = await _db.getSetting('favorite_models');
    if (favIds != null && favIds.isNotEmpty) {
      _favoriteModelIds = (jsonDecode(favIds) as List)
          .map((e) => e.toString())
          .toList();
    }

    final timeout = await _db.getSetting('web_fetch_timeout');
    if (timeout != null) {
      _webFetchTimeout = int.tryParse(timeout) ?? 20;
    }

    _githubToken = (await _db.getSetting('github_token')) ?? '';
    _githubUsername = (await _db.getSetting('github_username')) ?? '';
    _githubClientId = (await _db.getSetting('github_client_id')) ??
        GithubApiService.defaultClientId;

    final cached = await _db.getSetting('cached_models');
    if (cached != null && cached.isNotEmpty) {
      final list = jsonDecode(cached) as List;
      _availableModels = list.map((e) => AiModel.fromJson(e)).toList();
      _modelsLoaded = true;
    }
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _db.setSetting('theme_mode', mode.name);
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key;
    await _db.setSetting('api_key', key);
    notifyListeners();
  }

  Future<void> setDefaultModel(String modelId) async {
    _defaultModel = modelId;
    await _db.setSetting('default_model', modelId);
    notifyListeners();
  }

  Future<void> setAppPrompt(String prompt) async {
    _appPrompt = prompt;
    await _db.setSetting('app_prompt', prompt);
    notifyListeners();
  }

  Future<void> setUserPrompt(String prompt) async {
    _userPrompt = prompt;
    await _db.setSetting('user_prompt', prompt);
    notifyListeners();
  }

  Future<void> setAvailableModels(List<AiModel> models) async {
    _availableModels = models;
    _modelsLoaded = true;
    await _db.setSetting('cached_models', jsonEncode(models.map((m) => m.toJson()).toList()));
    notifyListeners();
  }

  Future<void> toggleFavoriteModel(String modelId) async {
    if (_favoriteModelIds.contains(modelId)) {
      _favoriteModelIds.remove(modelId);
    } else {
      _favoriteModelIds.add(modelId);
    }

    if (_defaultModel.isEmpty || !_favoriteModelIds.contains(_defaultModel)) {
      _defaultModel =
          _favoriteModelIds.isNotEmpty ? _favoriteModelIds.first : '';
      await _db.setSetting('default_model', _defaultModel);
    }

    await _db.setSetting('favorite_models', jsonEncode(_favoriteModelIds));
    notifyListeners();
  }

  bool isFavorite(String modelId) => _favoriteModelIds.contains(modelId);

  Future<void> setWebFetchTimeout(int seconds) async {
    _webFetchTimeout = seconds.clamp(5, 120);
    await _db.setSetting('web_fetch_timeout', _webFetchTimeout.toString());
    notifyListeners();
  }

  Future<void> setGithubCredentials(String token, String username) async {
    _githubToken = token;
    _githubUsername = username;
    await _db.setSetting('github_token', token);
    await _db.setSetting('github_username', username);
    notifyListeners();
  }

  Future<void> setGithubClientId(String clientId) async {
    _githubClientId = clientId;
    await _db.setSetting('github_client_id', clientId);
    notifyListeners();
  }

  Future<void> clearGithubCredentials() async {
    _githubToken = '';
    _githubUsername = '';
    await _db.setSetting('github_token', '');
    await _db.setSetting('github_username', '');
    notifyListeners();
  }

  Future<void> clearApiKey() async {
    _apiKey = '';
    _availableModels = [];
    _favoriteModelIds = [];
    _defaultModel = '';
    _modelsLoaded = false;
    await _db.setSetting('api_key', '');
    await _db.setSetting('favorite_models', jsonEncode([]));
    await _db.setSetting('default_model', '');
    await _db.setSetting('cached_models', '');
    notifyListeners();
  }
}
