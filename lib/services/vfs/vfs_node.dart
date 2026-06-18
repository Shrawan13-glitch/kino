import 'dart:io';
import 'package:intl/intl.dart';

enum VfsNodeType { file, directory }

class VfsNode {
  final String name;
  final String vfsPath;
  final VfsNodeType type;
  final int size;
  final DateTime modifiedAt;
  final bool isHidden;

  const VfsNode({
    required this.name,
    required this.vfsPath,
    required this.type,
    required this.size,
    required this.modifiedAt,
    this.isHidden = false,
  });

  bool get isDirectory => type == VfsNodeType.directory;
  bool get isFile => type == VfsNodeType.file;

  String? get extension {
    if (isDirectory) return null;
    final dot = name.lastIndexOf('.');
    if (dot == -1) return null;
    return name.substring(dot + 1).toLowerCase();
  }

  String get sizeFormatted {
    if (isDirectory) {
      if (size == 0) return '';
      return _formatSize(size);
    }
    return _formatSize(size);
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get modifiedFormatted {
    final now = DateTime.now();
    final diff = now.difference(modifiedAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(modifiedAt);
  }

  bool get isTextFile {
    if (isDirectory) return false;
    final textExts = {
      'txt', 'md', 'json', 'csv', 'xml', 'yaml', 'yml',
      'py', 'js', 'ts', 'dart', 'java', 'kt', 'swift',
      'sh', 'bash', 'zsh', 'fish',
      'html', 'css', 'scss', 'less',
      'cfg', 'conf', 'ini', 'toml',
      'log', 'env', 'gitignore',
      'sql', 'r', 'go', 'rs',
    };
    return extension != null && textExts.contains(extension);
  }

  bool get isImage {
    if (isDirectory) return false;
    return const {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg'}
        .contains(extension);
  }

  bool get isVideo {
    if (isDirectory) return false;
    return const {'mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm'}
        .contains(extension);
  }

  bool get isAudio {
    if (isDirectory) return false;
    return const {'mp3', 'wav', 'ogg', 'flac', 'aac', 'wma', 'm4a'}
        .contains(extension);
  }

  bool get isArchive {
    if (isDirectory) return false;
    return const {'zip', 'tar', 'gz', 'bz2', 'xz', '7z', 'rar'}
        .contains(extension);
  }

  factory VfsNode.fromEntity(FileSystemEntity entity, String vfsPath) {
    final stat = entity.statSync();
    return VfsNode(
      name: entity.uri.pathSegments.last,
      vfsPath: vfsPath,
      type: entity is Directory ? VfsNodeType.directory : VfsNodeType.file,
      size: stat.size,
      modifiedAt: stat.modified,
      isHidden: entity.uri.pathSegments.last.startsWith('.'),
    );
  }
}
