import '../engine.dart';
import 'duckduckgo_engine.dart';
import 'wikipedia_engine.dart';
import 'mojeek_engine.dart';

class EngineConfig {
  final String name;
  final bool enabled;
  final double weight;

  EngineConfig({
    required this.name,
    this.enabled = true,
    this.weight = 1.0,
  });
}

class EngineRegistry {
  final Map<String, SearchEngine> _engines = {};
  final Map<String, EngineConfig> _configs = {};

  EngineRegistry() {
    _registerDefaults();
  }

  void _registerDefaults() {
    final engines = <SearchEngine>[
      DuckDuckGoEngine(),
      WikipediaEngine(),
      MojeekEngine(),
    ];

    for (final engine in engines) {
      _engines[engine.name] = engine;
      _configs[engine.name] = EngineConfig(name: engine.name);
    }
  }

  void configure(List<EngineConfig> configs) {
    for (final config in configs) {
      _configs[config.name] = config;
      if (_engines.containsKey(config.name)) {
        _engines[config.name]!.weight;
      }
    }
  }

  List<SearchEngine> get activeEngines {
    return _engines.values
        .where((e) => _configs[e.name]?.enabled ?? true)
        .toList();
  }

  List<SearchEngine> getEnginesByCategory(String category) {
    return activeEngines.where((e) => e.categories.contains(category)).toList();
  }

  SearchEngine? getEngine(String name) => _engines[name];

  Future<void> initAll() async {
    for (final engine in _engines.values) {
      await engine.init();
    }
  }
}
