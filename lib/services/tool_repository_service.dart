import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'tool_registry.dart';

class ToolRepositoryService {
  ToolRepositoryService._();
  static final ToolRepositoryService _instance = ToolRepositoryService._();
  factory ToolRepositoryService() => _instance;

  static const String defaultRepoUrl =
      'https://raw.githubusercontent.com/Shrawan13-glitch/chatmorphism-tools/main';

  bool _loaded = false;
  String _repoUrl = defaultRepoUrl;

  String get repoUrl => _repoUrl;
  bool get loaded => _loaded;

  void setRepoUrl(String url) {
    _repoUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _loaded = false;
  }

  Future<List<ToolDefinition>> fetchTools() async {
    final manifestUrl = '$_repoUrl/tools.json';
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(manifestUrl));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        final body = await response.transform(utf8.decoder).join();
        return _parseManifest(body);
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('ToolRepository: failed to fetch tools from $manifestUrl: $e');
      rethrow;
    }
  }

  Future<void> loadIntoRegistry(ToolRegistry registry) async {
    try {
      final tools = await fetchTools();
      registry.loadFromRemote(tools);
      _loaded = true;
      debugPrint(
          'ToolRepository: loaded ${tools.length} tools from $_repoUrl');
    } catch (e) {
      debugPrint('ToolRepository: fallback to builtin tools');
      registry.loadBuiltins();
      _loaded = false;
    }
  }

  List<ToolDefinition> _parseManifest(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final toolsList = json['tools'] as List<dynamic>;
    final tools = <ToolDefinition>[];

    for (final item in toolsList) {
      final t = item as Map<String, dynamic>;
      final installTypeStr = t['install_type'] as String? ?? 'binary';

      tools.add(ToolDefinition(
        name: t['name'] as String,
        description: t['description'] as String? ?? '',
        version: t['version'] as String? ?? '1.0.0',
        downloadUrl: t['download_url'] as String? ?? '',
        installType: installTypeStr == 'archive'
            ? InstallType.archive
            : InstallType.binary,
        archiveBinaryPath: t['archive_binary_path'] as String?,
        extraPaths: t['extra_paths'] != null
            ? Map<String, String>.from(t['extra_paths'] as Map)
            : null,
        size: t['size'] as int? ?? 0,
        categories: (t['categories'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        isBuiltin: false,
      ));
    }

    return tools;
  }

}
