/// 嗅探到的页面资源
class SniffedResource {
  final String url;
  final SniffType type;
  final String? mimeType;
  final int? size;
  final String? title;

  const SniffedResource({
    required this.url,
    required this.type,
    this.mimeType,
    this.size,
    this.title,
  });

  factory SniffedResource.fromJson(Map<String, dynamic> json) {
    return SniffedResource(
      url: json['url'] as String? ?? '',
      type: _parseType(json['type'] as String?),
      mimeType: json['mime'] as String?,
      size: json['size'] as int?,
      title: json['title'] as String?,
    );
  }

  static SniffType _parseType(String? s) {
    switch (s) {
      case 'video':
        return SniffType.video;
      case 'audio':
        return SniffType.audio;
      case 'image':
        return SniffType.image;
      case 'css':
        return SniffType.css;
      case 'js':
        return SniffType.js;
      case 'font':
        return SniffType.font;
      default:
        return SniffType.other;
    }
  }
}

/// 自动嗅探发现媒体后的提示（供 UI 显示「发现 N 个视频/音频」横幅）
class SniffHint {
  final int videoCount;
  final int audioCount;

  const SniffHint({this.videoCount = 0, this.audioCount = 0});

  int get mediaCount => videoCount + audioCount;

  String get message {
    final parts = <String>[];
    if (videoCount > 0) parts.add('$videoCount 个视频');
    if (audioCount > 0) parts.add('$audioCount 个音频');
    return '发现 ${parts.join('、')}，点击查看';
  }
}

enum SniffType {
  video,
  audio,
  image,
  css,
  js,
  font,
  other;

  String get label {
    switch (this) {
      case SniffType.video:
        return '视频';
      case SniffType.audio:
        return '音频';
      case SniffType.image:
        return '图片';
      case SniffType.css:
        return '样式';
      case SniffType.js:
        return '脚本';
      case SniffType.font:
        return '字体';
      case SniffType.other:
        return '其他';
    }
  }
}
