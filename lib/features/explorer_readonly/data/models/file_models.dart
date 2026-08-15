class RemoteFileItem {
  final String name;
  final String path;
  final bool isDir;
  final int? size;
  final String? modifiedAt;

  RemoteFileItem({
    required this.name,
    required this.path,
    required this.isDir,
    this.size,
    this.modifiedAt,
  });

  factory RemoteFileItem.fromJson(Map<String, dynamic> json) => RemoteFileItem(
        name: json['name'] ?? '',
        path: json['path'] ?? '',
        isDir: json['is_dir'] ?? false,
        size: json['size'],
        modifiedAt: json['modified_at'],
      );
}
