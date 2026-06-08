class SearchResult {
  String url;
  String title;
  String content;
  String? engine;
  String? imgSrc;
  String? thumbnail;
  DateTime? publishedDate;
  String? category;

  SearchResult({
    required this.url,
    required this.title,
    required this.content,
    this.engine,
    this.imgSrc,
    this.thumbnail,
    this.publishedDate,
    this.category,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'content': content,
        'engine': engine,
        'img_src': imgSrc,
        'thumbnail': thumbnail,
        'published_date': publishedDate?.toIso8601String(),
        'category': category,
      };
}

class AnswerResult {
  final String answer;
  final String? url;
  final String? engine;

  AnswerResult({required this.answer, this.url, this.engine});

  Map<String, dynamic> toJson() => {
        'answer': answer,
        'url': url,
        'engine': engine,
      };
}

class SuggestionResult {
  final String suggestion;
  SuggestionResult({required this.suggestion});
}
