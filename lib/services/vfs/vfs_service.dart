import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'vfs_node.dart';
import 'vfs_exception.dart';

class VfsService {
  VfsService._();
  static final VfsService _instance = VfsService._();
  factory VfsService() => _instance;

  String? _rootPath;
  bool _initialized = false;

  String get rootPath => _rootPath!;
  bool get initialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    final appDir = await getApplicationDocumentsDirectory();
    _rootPath = p.join(appDir.path, 'vfs');

    final dirs = [
      _rootPath!,
      p.join(_rootPath!, 'home'),
      p.join(_rootPath!, 'home', 'notes'),
      p.join(_rootPath!, 'home', 'documents'),
      p.join(_rootPath!, 'home', 'downloads'),
      p.join(_rootPath!, 'home', 'scripts'),
      p.join(_rootPath!, 'tools'),
      p.join(_rootPath!, 'tmp'),
    ];

    for (final d in dirs) {
      await Directory(d).create(recursive: true);
    }
    _initialized = true;
  }

  String _toAbsolute(String vfsPath) {
    final clean = vfsPath.startsWith('/') ? vfsPath.substring(1) : vfsPath;
    return p.join(_rootPath!, clean);
  }

  String _toVfs(String absolutePath) {
    final rel = p.relative(absolutePath, from: _rootPath!);
    return '/$rel';
  }

  String _sanitize(String name) {
    if (name.isEmpty) throw const VfsException('Name cannot be empty');
    if (name.contains('/') || name.contains('\\')) {
      throw const VfsException('Name cannot contain path separators');
    }
    return name;
  }

  Future<List<VfsNode>> list(String vfsPath) async {
    final abs = _toAbsolute(vfsPath);
    final dir = Directory(abs);
    if (!await dir.exists()) {
      throw VfsNotFoundException(vfsPath);
    }

    final entities = await dir.list().toList();
    final nodes = <VfsNode>[];

    for (final entity in entities) {
      final entityPath = _toVfs(entity.path);
      final node = VfsNode.fromEntity(entity, entityPath);
      if (!node.isHidden) {
        nodes.add(node);
      }
    }

    nodes.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return nodes;
  }

  Future<VfsNode> stat(String vfsPath) async {
    final abs = _toAbsolute(vfsPath);
    final entity = FileSystemEntity.typeSync(abs);
    if (entity == FileSystemEntityType.notFound) {
      throw VfsNotFoundException(vfsPath);
    }

    final stat = File(abs).statSync();
    return VfsNode(
      name: p.basename(abs),
      vfsPath: vfsPath,
      type: entity == FileSystemEntityType.directory
          ? VfsNodeType.directory
          : VfsNodeType.file,
      size: stat.size,
      modifiedAt: stat.modified,
    );
  }

  Future<String> readFileAsString(String vfsPath) async {
    final abs = _toAbsolute(vfsPath);
    final file = File(abs);
    if (!await file.exists()) throw VfsNotFoundException(vfsPath);
    return file.readAsString();
  }

  Future<Uint8List> readFileAsBytes(String vfsPath) async {
    final abs = _toAbsolute(vfsPath);
    final file = File(abs);
    if (!await file.exists()) throw VfsNotFoundException(vfsPath);
    return file.readAsBytes();
  }

  Future<void> writeFile(String vfsPath, dynamic content) async {
    final abs = _toAbsolute(vfsPath);
    final file = File(abs);
    await file.parent.create(recursive: true);

    if (content is String) {
      await file.writeAsString(content);
    } else if (content is List<int>) {
      await file.writeAsBytes(content);
    } else {
      throw const VfsException('Unsupported content type');
    }
  }

  Future<void> createDirectory(String vfsPath) async {
    final abs = _toAbsolute(vfsPath);
    final dir = Directory(abs);
    if (await dir.exists()) {
      throw VfsAlreadyExistsException(vfsPath);
    }
    await dir.create(recursive: true);
  }

  Future<void> delete(String vfsPath) async {
    final abs = _toAbsolute(vfsPath);
    final entity = FileSystemEntity.typeSync(abs);
    if (entity == FileSystemEntityType.notFound) {
      throw VfsNotFoundException(vfsPath);
    }

    if (entity == FileSystemEntityType.directory) {
      await Directory(abs).delete(recursive: true);
    } else {
      await File(abs).delete();
    }
  }

  Future<void> rename(String oldVfsPath, String newName) async {
    final abs = _toAbsolute(oldVfsPath);
    final entity = FileSystemEntity.typeSync(abs);
    if (entity == FileSystemEntityType.notFound) {
      throw VfsNotFoundException(oldVfsPath);
    }

    final parent = p.dirname(abs);
    final newAbs = p.join(parent, _sanitize(newName));
    await File(abs).rename(newAbs);
  }

  Future<void> move(String srcVfsPath, String destVfsPath) async {
    final srcAbs = _toAbsolute(srcVfsPath);
    final destAbs = _toAbsolute(destVfsPath);

    final entity = FileSystemEntity.typeSync(srcAbs);
    if (entity == FileSystemEntityType.notFound) {
      throw VfsNotFoundException(srcVfsPath);
    }

    await File(srcAbs).rename(destAbs);
  }

  Future<void> copy(String srcVfsPath, String destVfsPath) async {
    final srcAbs = _toAbsolute(srcVfsPath);
    final destAbs = _toAbsolute(destVfsPath);

    final entity = FileSystemEntity.typeSync(srcAbs);
    if (entity == FileSystemEntityType.notFound) {
      throw VfsNotFoundException(srcVfsPath);
    }

    if (entity == FileSystemEntityType.directory) {
      await _copyDirectory(Directory(srcAbs), Directory(destAbs));
    } else {
      await File(srcAbs).copy(destAbs);
    }
  }

  Future<void> _copyDirectory(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in src.list()) {
      final newPath = p.join(dest.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else {
        await File(entity.path).copy(newPath);
      }
    }
  }

  Future<bool> exists(String vfsPath) async {
    final abs = _toAbsolute(vfsPath);
    return FileSystemEntity.typeSync(abs) != FileSystemEntityType.notFound;
  }

  Future<void> makeExecutable(String vfsPath) async {
    final abs = _toAbsolute(vfsPath);
    final file = File(abs);
    if (!await file.exists()) throw VfsNotFoundException(vfsPath);
    await Process.run('chmod', ['+x', abs]);
  }

  Future<void> downloadFromUrl(String url, String destVfsPath,
      {void Function(int received, int total)? onProgress}) async {
    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw VfsException('Download failed: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      final bytes = <int>[];
      var received = 0;

      await for (final chunk in response) {
        bytes.addAll(chunk);
        received += chunk.length;
        onProgress?.call(received, totalBytes);
      }

      final abs = _toAbsolute(destVfsPath);
      final file = File(abs);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    } finally {
      httpClient.close();
    }
  }
}
