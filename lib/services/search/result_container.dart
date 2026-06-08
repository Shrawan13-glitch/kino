import 'engine.dart';
import 'result_types.dart';

class ResultContainer {
  final Map<int, SearchResult> _resultMap = {};
  final List<AnswerResult> _answers = [];
  final List<SuggestionResult> _suggestions = [];

  void extend(String? engineName, EngineResponse response) {
    for (final result in response.results) {
      result.engine = result.engine ?? engineName;
      _mergeResult(result);
    }

    _answers.addAll(response.answers);
    _suggestions.addAll(response.suggestions);
  }

  void _mergeResult(SearchResult result) {
    final key = result.url.hashCode;
    if (_resultMap.containsKey(key)) {
      final existing = _resultMap[key]!;
      if (result.content.length > existing.content.length) {
        existing.content = result.content;
      }
    } else {
      _resultMap[key] = result;
    }
  }

  List<SearchResult> getOrderedResults() {
    final results = _resultMap.values.toList();
    results.sort((a, b) => b.content.length.compareTo(a.content.length));
    return results;
  }

  List<AnswerResult> get answers => List.unmodifiable(_answers);
  List<SuggestionResult> get suggestions => List.unmodifiable(_suggestions);
  int get totalResults => _resultMap.length;
}
