import 'dart:async';
import 'engine.dart';
import 'result_container.dart';
import 'engines/engine_registry.dart';

class SearchService {
  final EngineRegistry _registry;
  static const Duration _timeout = Duration(seconds: 12);

  SearchService() : _registry = EngineRegistry();

  EngineRegistry get registry => _registry;

  Future<void> init() async {
    await _registry.initAll();
  }

  void configure(List<EngineConfig> configs) {
    _registry.configure(configs);
  }

  Future<ResultContainer> search(String query, {List<String>? categories}) async {
    final container = ResultContainer();
    final engines = categories != null
        ? categories.expand((c) => _registry.getEnginesByCategory(c)).toSet().toList()
        : _registry.activeEngines;

    if (engines.isEmpty) return container;

    final futures = <Future<void>>[];
    for (final engine in engines) {
      futures.add(_searchEngine(engine, query, container));
    }

    await Future.wait(futures);
    return container;
  }

  Future<void> _searchEngine(
    SearchEngine engine,
    String query,
    ResultContainer container,
  ) async {
    try {
      final response = await engine
          .search(query: query)
          .timeout(_timeout, onTimeout: () => EngineResponse());
      container.extend(engine.name, response);
    } catch (_) {}
  }
}
