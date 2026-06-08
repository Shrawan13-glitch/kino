import 'result_types.dart';

class EngineResponse {
  final List<SearchResult> results;
  final List<AnswerResult> answers;
  final List<SuggestionResult> suggestions;

  EngineResponse({
    this.results = const [],
    this.answers = const [],
    this.suggestions = const [],
  });
}

abstract class SearchEngine {
  String get name;
  List<String> get categories;
  bool get paging;
  bool get timeRangeSupport;
  double get weight;

  Future<EngineResponse> search({
    required String query,
    int page = 1,
    String? timeRange,
  });

  Future<void> init() async {}
}
