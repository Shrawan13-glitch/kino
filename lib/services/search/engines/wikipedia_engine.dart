import 'dart:convert';
import 'package:http/http.dart' as http;
import '../engine.dart';
import '../result_types.dart';

class WikipediaEngine extends SearchEngine {
  @override
  String get name => 'wikipedia';

  @override
  List<String> get categories => ['general', 'web'];

  @override
  bool get paging => false;

  @override
  bool get timeRangeSupport => false;

  @override
  double get weight => 0.8;

  final http.Client _client = http.Client();

  static const String _apiUrl = 'https://en.wikipedia.org/w/api.php';
  static const String _restUrl = 'https://en.wikipedia.org/api/rest_v1/page/summary';

  @override
  Future<EngineResponse> search({
    required String query,
    int page = 1,
    String? timeRange,
  }) async {
    try {
      final searchResult = await _searchTitles(query);
      if (searchResult.isEmpty) return EngineResponse();

      final results = <SearchResult>[];
      for (final title in searchResult.take(3)) {
        final summary = await _getSummary(title);
        if (summary != null) {
          results.add(summary);
        }
      }

      return EngineResponse(results: results);
    } catch (e) {
      return EngineResponse();
    }
  }

  Future<List<String>> _searchTitles(String query) async {
    final url = Uri.parse(_apiUrl).replace(queryParameters: {
      'action': 'query',
      'list': 'search',
      'srsearch': query,
      'srlimit': '3',
      'format': 'json',
      'origin': '*',
    });

    final response = await _client.get(url, headers: {
      'User-Agent': 'ChatMorphism/1.0',
      'Accept': 'application/json',
    });

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final queryResult = data['query'] as Map<String, dynamic>?;
    if (queryResult == null) return [];

    final searchList = queryResult['search'] as List?;
    if (searchList == null) return [];

    return searchList
        .map((s) => (s as Map<String, dynamic>)['title'] as String)
        .toList();
  }

  Future<SearchResult?> _getSummary(String title) async {
    final url = Uri.parse('$_restUrl/${Uri.encodeComponent(title)}');
    final response = await _client.get(url, headers: {
      'User-Agent': 'ChatMorphism/1.0',
      'Accept': 'application/json',
    });

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final pageUrl = data['content_urls']?['desktop']?['page'] as String?;

    return SearchResult(
      url: pageUrl ?? 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title)}',
      title: data['title'] as String? ?? title,
      content: data['extract'] as String? ?? '',
      engine: name,
      thumbnail: data['thumbnail']?['source'] as String?,
    );
  }
}
