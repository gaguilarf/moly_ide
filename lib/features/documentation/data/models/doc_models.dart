class DocItemModel {
  final String title;
  final String path;
  final String category;
  final String? contentSnippet;

  DocItemModel({
    required this.title,
    required this.path,
    required this.category,
    this.contentSnippet,
  });

  factory DocItemModel.fromJson(Map<String, dynamic> json) => DocItemModel(
        title: json['title'] ?? '',
        path: json['path'] ?? '',
        category: json['category'] ?? 'General',
        contentSnippet: json['content_snippet'],
      );
}
