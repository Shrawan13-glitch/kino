class AiModel {
  final String id;
  final String name;
  final String provider;
  final int contextLength;
  final double promptPrice;
  final double completionPrice;

  const AiModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.contextLength,
    required this.promptPrice,
    required this.completionPrice,
  });

  String get displayName => name.isNotEmpty ? name : id;

  String get shortId {
    final parts = id.split('/');
    return parts.length > 1 ? parts.sublist(1).join('/') : id;
  }

  bool get isFree => promptPrice == 0 && completionPrice == 0;

  factory AiModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final provider = id.contains('/') ? id.split('/').first : 'unknown';
    final pricing = json['pricing'] as Map<String, dynamic>? ?? {};

    return AiModel(
      id: id,
      name: (json['name'] as String?) ?? id,
      provider: (json['owned_by'] as String?) ?? provider,
      contextLength: (json['context_length'] as num?)?.toInt() ?? 0,
      promptPrice: double.tryParse((pricing['prompt'] ?? '0').toString()) ?? 0,
      completionPrice:
          double.tryParse((pricing['completion'] ?? '0').toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider,
        'context_length': contextLength,
        'pricing': {
          'prompt': promptPrice.toString(),
          'completion': completionPrice.toString(),
        },
      };
}
