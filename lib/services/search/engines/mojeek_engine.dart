import 'package:http/http.dart' as http;
import '../engine.dart';
import '../result_types.dart';

class MojeekEngine extends SearchEngine {
  @override
  String get name => 'mojeek';

  @override
  List<String> get categories => ['general', 'web'];

  @override
  bool get paging => true;

  @override
  bool get timeRangeSupport => true;

  @override
  double get weight => 0.9;

  final http.Client _client = http.Client();

  static const String _baseUrl = 'https://www.mojeek.com/search';

  @override
  Future<EngineResponse> search({
    required String query,
    int page = 1,
    String? timeRange,
  }) async {
    try {
      final args = <String, String>{
        'q': query,
        'safe': '0',
      };

      if (page > 1) {
        args['s'] = '${10 * (page - 1)}';
      }

      final url = Uri.parse(_baseUrl).replace(queryParameters: args);
      final response = await _client.get(url, headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      });

      if (response.statusCode != 200) return EngineResponse();
      return _parseHtml(response.body);
    } catch (e) {
      return EngineResponse();
    }
  }

  EngineResponse _parseHtml(String html) {
    final results = <SearchResult>[];

    final items = _extractBetweenAll(html, '<!--rs-->', '<!--re-->');
    for (final item in items) {
      final urlMatch = RegExp(r'class="ob"\s*href="([^"]+)"').firstMatch(item);
      final titleMatch = RegExp(r'class="title"[^>]*>([^<]+)<').firstMatch(item);
      final contentMatch = RegExp(r'class="s">(.*?)</p>', dotAll: true).firstMatch(item);

      final url = urlMatch?.group(1) ?? '';
      final title = titleMatch?.group(1)?.trim() ?? '';
      final content = contentMatch != null
          ? _stripHtmlTags(contentMatch.group(1) ?? '').trim()
          : '';

      if (url.isNotEmpty && title.isNotEmpty) {
        results.add(SearchResult(
          url: url,
          title: title,
          content: content,
          engine: name,
        ));
      }
    }

    return EngineResponse(results: results);
  }

  String _stripHtmlTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _extractBetweenAll(String html, String start, String end) {
    final result = <String>[];
    int pos = 0;
    while (true) {
      final startIdx = html.indexOf(start, pos);
      if (startIdx == -1) break;
      final endIdx = html.indexOf(end, startIdx + start.length);
      if (endIdx == -1) break;
      result.add(html.substring(startIdx, endIdx + end.length));
      pos = endIdx + end.length;
    }
    return result;
  }
}
