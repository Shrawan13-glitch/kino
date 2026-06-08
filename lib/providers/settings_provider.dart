import 'dart:convert';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/ai_model.dart';

class SettingsProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  ThemeMode _themeMode = ThemeMode.dark;
  String _apiKey = '';
  String _defaultModel = '';
  List<String> _favoriteModelIds = [];
  List<AiModel> _availableModels = [];
  bool _modelsLoaded = false;

  ThemeMode get themeMode => _themeMode;
  String get apiKey => _apiKey;
  String get defaultModel => _defaultModel;
  List<String> get favoriteModelIds => _favoriteModelIds;
  List<AiModel> get availableModels => _availableModels;
  bool get modelsLoaded => _modelsLoaded;
  bool get hasApiKey => _apiKey.isNotEmpty;

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

    final favIds = await _db.getSetting('favorite_models');
    if (favIds != null && favIds.isNotEmpty) {
      _favoriteModelIds = (jsonDecode(favIds) as List)
          .map((e) => e.toString())
          .toList();
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

  Future<void> setAvailableModels(List<AiModel> models) async {
    _availableModels = models;
    _modelsLoaded = true;
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

  Future<void> clearApiKey() async {
    _apiKey = '';
    _availableModels = [];
    _favoriteModelIds = [];
    _defaultModel = '';
    _modelsLoaded = false;
    await _db.setSetting('api_key', '');
    await _db.setSetting('favorite_models', jsonEncode([]));
    await _db.setSetting('default_model', '');
    notifyListeners();
  }
}
