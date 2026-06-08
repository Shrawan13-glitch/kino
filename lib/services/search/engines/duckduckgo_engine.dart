import 'package:http/http.dart' as http;
import '../engine.dart';
import '../result_types.dart';

class DuckDuckGoEngine extends SearchEngine {
  @override
  String get name => 'duckduckgo';

  @override
  List<String> get categories => ['general', 'web'];

  @override
  bool get paging => true;

  @override
  bool get timeRangeSupport => false;

  @override
  double get weight => 1.0;

  static const String _baseUrl = 'https://html.duckduckgo.com/html';
  final http.Client _client = http.Client();
  String _userAgent = '';

  @override
  Future<void> init() async {
    _userAgent =
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  }

  @override
  Future<EngineResponse> search({
    required String query,
    int page = 1,
    String? timeRange,
  }) async {
    if (query.length >= 500) {
      return EngineResponse();
    }

    try {
      final body = <String, String>{
        'q': query,
      };

      if (page == 1) {
        body['b'] = '';
      }

      final response = await _client.post(
        Uri.parse(_baseUrl),
        headers: {
          'User-Agent': _userAgent,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Referer': _baseUrl,
        },
        body: body,
      );

      if (response.statusCode != 200) {
        return EngineResponse();
      }

      return _parseHtml(response.body);
    } catch (e) {
      return EngineResponse();
    }
  }

  EngineResponse _parseHtml(String html) {
    final results = <SearchResult>[];

    final links = _extractBetweenAll(html, 'class="result__a"', '</a>');
    for (final linkHtml in links) {
      final url = _extractHref(linkHtml);
      final title = _extractText(linkHtml);

      if (url.isEmpty || title.isEmpty) continue;

      results.add(SearchResult(
        url: url,
        title: title.trim(),
        content: '',
        engine: name,
      ));
    }

    final snippets = _extractBetweenAll(html, 'class="result__snippet"', '</a>');
    for (int i = 0; i < snippets.length && i < results.length; i++) {
      results[i].content = _stripHtmlTags(snippets[i]).trim();
    }

    return EngineResponse(results: results);
  }

  String _extractHref(String html) {
    final match = RegExp(r'href="([^"]+)"').firstMatch(html);
    if (match == null) return '';
    String url = match.group(1) ?? '';
    url = Uri.decodeComponent(url);
    return url;
  }

  String _extractText(String html) {
    return _stripHtmlTags(html);
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
