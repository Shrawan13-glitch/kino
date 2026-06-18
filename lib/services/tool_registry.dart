import 'package:flutter/foundation.dart';

class ToolDefinition {
  final String name;
  final String description;
  final String version;
  final int size;
  final List<String> categories;
  final Map<String, dynamic>? functionDefinition;

  const ToolDefinition({
    required this.name,
    required this.description,
    this.version = '1.0.0',
    this.size = 0,
    this.categories = const [],
    this.functionDefinition,
  });
}

class ToolRegistry extends ChangeNotifier {
  ToolRegistry._();
  static final ToolRegistry _instance = ToolRegistry._();
  factory ToolRegistry() => _instance;

  final List<ToolDefinition> _tools = [];

  List<ToolDefinition> get tools => List.unmodifiable(_tools);

  ToolDefinition? get(String name) {
    try {
      return _tools.firstWhere((t) => t.name == name);
    } catch (_) {
      return null;
    }
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

  void init() {
    _tools
      ..clear()
      ..addAll(builtinTools);
    notifyListeners();
  }

  static const List<ToolDefinition> builtinTools = [
    ToolDefinition(
      name: 'jq',
      description:
          'JSON processor — query, filter, transform, and format JSON data. Supports field access (.key), array iteration ([]), filtering (select), projection ({a: .x}), sorting, grouping, piping (|), and more. Provide a filter expression and optional file path. Use -r for raw string output.',
      version: '1.0.0',
      categories: ['data', 'json'],
      functionDefinition: {
        'parameters': {
          'type': 'object',
          'properties': {
            'args': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Arguments: [options] <filter> [file]. Options: -r (raw output), -c (compact). Filter examples:\n'
                  '  .key — get field\n'
                  '  .[] | select(.age > 30) | .name — filter & extract\n'
                  '  {name: .name, city: .address.city} — project fields\n'
                  '  sort_by(.age) | .[] | .name — sort then extract\n'
                  '  group_by(.city) — group by field\n'
                  '  del(.password) — remove a key\n'
                  '  keys — list object keys\n'
                  '  length — array length',
            },
          },
          'required': ['args'],
        },
      },
    ),
    ToolDefinition(
      name: 'json',
      description:
          'Alias for jq — query, filter, and transform JSON data. Usage: json <filter> [file]. Provides all jq operations: field access, array iteration, select, projection, sort, group, pipe.',
      categories: ['data', 'json'],
      functionDefinition: {
        'parameters': {
          'type': 'object',
          'properties': {
            'args': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Arguments: [options] <filter> [file]. Same as jq.',
            },
          },
          'required': ['args'],
        },
      },
    ),
    ToolDefinition(
      name: 'rg',
      description:
          'Recursively search file contents with regex. Fast file search supporting globs, context lines, count-only, invert match, fixed strings, and case-insensitive modes.',
      version: '1.0.0',
      categories: ['search', 'text'],
      functionDefinition: {
        'parameters': {
          'type': 'object',
          'properties': {
            'args': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Arguments: [options] <pattern> [path]. Options:\n'
                  '  -i — case-insensitive\n'
                  '  -n — show line numbers (default)\n'
                  '  -c — count matches per file\n'
                  '  -l — list filenames only\n'
                  '  -v — invert match\n'
                  '  -F — fixed string (no regex)\n'
                  '  -C N — show N context lines\n'
                  '  -g GLOB — file glob filter (e.g. "*.dart")\n'
                  '  --include-hidden — search dotfiles\n'
                  '  --max-depth N — max recursion depth\n'
                  '  --no-line-number — hide line numbers',
            },
          },
          'required': ['args'],
        },
      },
    ),
    ToolDefinition(
      name: 'search',
      description:
          'Alias for rg — recursive file content search with regex. See rg tool for usage.',
      categories: ['search', 'text'],
      functionDefinition: {
        'parameters': {
          'type': 'object',
          'properties': {
            'args': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Arguments: [options] <pattern> [path]. Same as rg.',
            },
          },
          'required': ['args'],
        },
      },
    ),
    ToolDefinition(
      name: 'sqlite3',
      description:
          'Query SQLite databases. Execute SQL queries against a database file. Provide database path and SQL query. Results are returned as formatted text.',
      version: '1.0.0',
      categories: ['data', 'database'],
      functionDefinition: {
        'parameters': {
          'type': 'object',
          'properties': {
            'args': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Arguments: [database_path] <SQL query>\n'
                  '  First positional arg: path to SQLite database file.\n'
                  '  Remaining args: SQL query (e.g. "SELECT * FROM users").\n'
                  '  If no database is specified, defaults to data.db.\n'
                  '  Alternately, pass the SQL query via stdin.',
            },
          },
          'required': ['args'],
        },
      },
    ),
  ];
}
