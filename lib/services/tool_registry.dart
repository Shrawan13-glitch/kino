import 'package:flutter/foundation.dart';

enum InstallType { binary, archive }

class ToolDefinition {
  final String name;
  final String description;
  final String version;
  final String downloadUrl;
  final InstallType installType;
  final String? archiveBinaryPath;
  final Map<String, String>? extraPaths;
  final int size;
  final List<String> categories;
  final bool isBuiltin;
  final Map<String, dynamic>? functionDefinition;

  const ToolDefinition({
    required this.name,
    required this.description,
    this.version = '1.0.0',
    required this.downloadUrl,
    this.installType = InstallType.binary,
    this.archiveBinaryPath,
    this.extraPaths,
    this.size = 0,
    this.categories = const [],
    this.isBuiltin = true,
    this.functionDefinition,
  });

  String get vfsPath => '/tools/$name';

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get installTypeLabel =>
      installType == InstallType.binary ? 'Binary' : 'Archive';
}

class ToolRegistry extends ChangeNotifier {
  ToolRegistry._();
  static final ToolRegistry _instance = ToolRegistry._();
  factory ToolRegistry() => _instance;

  final List<ToolDefinition> _tools = [];
  final Set<String> _installed = {};
  bool _loaded = false;

  List<ToolDefinition> get tools => List.unmodifiable(_tools);
  List<ToolDefinition> get installed =>
      _tools.where((t) => _installed.contains(t.name)).toList();
  List<ToolDefinition> get available =>
      _tools.where((t) => !_installed.contains(t.name)).toList();

  bool get hasLoaded => _loaded;

  bool isInstalled(String name) => _installed.contains(name);

  void markInstalled(String name) {
    _installed.add(name);
    notifyListeners();
  }

  void markUninstalled(String name) {
    _installed.remove(name);
    notifyListeners();
  }

  ToolDefinition? get(String name) {
    try {
      return _tools.firstWhere((t) => t.name == name);
    } catch (_) {
      return null;
    }
  }

  void loadFromRemote(List<ToolDefinition> tools) {
    _tools
      ..clear()
      ..addAll(tools);
    _loaded = true;
    notifyListeners();
  }

  void loadBuiltins() {
    _tools
      ..clear()
      ..addAll(builtinTools);
    _loaded = false;
    notifyListeners();
  }

  List<Map<String, dynamic>> getAgentToolDefinitions() {
    return _tools.map((tool) {
      return {
        'type': 'function',
        'function': {
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.functionDefinition?['parameters'] ?? {
            'type': 'object',
            'properties': {
              'args': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': 'Command-line arguments',
              },
            },
            'required': ['args'],
          },
        },
      };
    }).toList();
  }

  List<ToolDefinition> get builtinTools => const [
        ToolDefinition(
          name: 'python3',
          description:
              'Python 3 interpreter for running scripts, data processing, automation, and more.',
          version: '3.14.0',
          downloadUrl:
              'https://github.com/astral-sh/python-build-standalone/releases/download/20250106/cpython-3.14.0a3+20250106-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz',
          installType: InstallType.archive,
          archiveBinaryPath: 'python/bin/python3',
          extraPaths: {
            'python/lib': 'python_lib',
          },
          size: 26214400,
          categories: ['runtime', 'scripting'],
        ),
        ToolDefinition(
          name: 'ffmpeg',
          description:
              'Media processing toolkit for video/audio conversion, compression, editing, and analysis.',
          version: '8.1.1',
          downloadUrl:
              'https://github.com/hzw1199/Android-FFmpeg-Prebuilt/releases/download/v8.1.1/ffmpeg-8.1.1-arm64-v8a.tar.gz',
          installType: InstallType.archive,
          archiveBinaryPath: 'ffmpeg-8.1.1-arm64-v8a/bin/ffmpeg',
          extraPaths: {
            'ffmpeg-8.1.1-arm64-v8a/bin': 'ffmpeg_bin',
          },
          size: 8388608,
          categories: ['media', 'conversion'],
        ),
        ToolDefinition(
          name: 'rg',
          description:
              'ripgrep — recursively search directories for a regex pattern. Extremely fast.',
          version: '14.1.0',
          downloadUrl:
              'https://github.com/BurntSushi/ripgrep/releases/download/14.1.0/ripgrep-14.1.0-aarch64-unknown-linux-gnu.tar.gz',
          installType: InstallType.archive,
          archiveBinaryPath: 'ripgrep-14.1.0-aarch64-unknown-linux-gnu/rg',
          size: 5242880,
          categories: ['search', 'text'],
        ),
        ToolDefinition(
          name: 'jq',
          description:
              'Command-line JSON processor — query, filter, and transform JSON data.',
          version: '1.7.1',
          downloadUrl:
              'https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-arm64',
          installType: InstallType.binary,
          size: 3145728,
          categories: ['data', 'json'],
        ),
        ToolDefinition(
          name: 'curl',
          description:
              'Transfer data from or to a server using HTTP, FTP, and more.',
          version: '8.9.0',
          downloadUrl:
              'https://github.com/moparisthebest/static-curl/releases/download/v8.9.0/curl-aarch64',
          installType: InstallType.binary,
          size: 4194304,
          categories: ['network', 'download'],
        ),
        ToolDefinition(
          name: 'sqlite3',
          description:
              'Lightweight SQL database engine — query and manipulate SQLite databases.',
          version: '3.46.0',
          downloadUrl:
              'https://github.com/nalgeon/sqlite/releases/download/3.46.0/sqlite3-linux-arm64',
          installType: InstallType.binary,
          size: 2097152,
          categories: ['data', 'database'],
        ),
      ];
}
