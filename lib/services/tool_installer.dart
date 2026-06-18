import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'vfs/vfs_service.dart';
import 'tool_registry.dart';

class ToolInstaller {
  ToolInstaller._();
  static final ToolInstaller _instance = ToolInstaller._();
  factory ToolInstaller() => _instance;

  String get _vfsRoot => VfsService().rootPath;

  Future<String> install(ToolDefinition tool, {
    void Function(String status, double progress)? onProgress,
  }) async {
    if (tool.downloadUrl.isEmpty) {
      return 'No download URL for ${tool.name}';
    }

    final installType = tool.installType;
    final toolDir = '$_vfsRoot/tools';
    await Directory(toolDir).create(recursive: true);

    if (installType == InstallType.binary) {
      return _installBinary(tool, toolDir, onProgress);
    } else {
      return _installArchive(tool, toolDir, onProgress);
    }
  }

  Future<String> _installBinary(
    ToolDefinition tool,
    String toolDir,
    void Function(String status, double progress)? onProgress,
  ) async {
    final destPath = p.join(toolDir, tool.name);
    onProgress?.call('Downloading ${tool.name}...', 0);

    try {
      await _downloadFile(tool.downloadUrl, destPath, onProgress);
      await _makeExecutable(destPath);
      return '${tool.name} installed successfully';
    } catch (e) {
      return 'Failed to install ${tool.name}: $e';
    }
  }

  Future<String> _installArchive(
    ToolDefinition tool,
    String toolDir,
    void Function(String status, double progress)? onProgress,
  ) async {
    onProgress?.call('Downloading ${tool.name}...', 0);

    final tempDir = Directory(p.join(_vfsRoot, 'tmp', '.install_${tool.name}'));
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await tempDir.create(recursive: true);

    try {
      final archivePath = p.join(tempDir.path, 'archive.tar.gz');
      await _downloadFile(tool.downloadUrl, archivePath, onProgress);
      onProgress?.call('Extracting ${tool.name}...', 0.8);

      await _extractTarGz(archivePath, tempDir.path);

      final binaryName = tool.archiveBinaryPath ?? tool.name;
      final binarySrc = p.join(tempDir.path, binaryName);
      final binarySrcFile = File(binarySrc);

      if (!await binarySrcFile.exists()) {
        final found = await _findBinary(tempDir.path, tool.name);
        if (found == null) {
          return 'Installed ${tool.name} but couldn\'t find the main binary inside the archive at "$binaryName"';
        }
        final destPath = p.join(toolDir, tool.name);
        await File(found).copy(destPath);
        await _makeExecutable(destPath);

        if (tool.extraPaths != null) {
          for (final entry in tool.extraPaths!.entries) {
            final src = p.join(tempDir.path, entry.key);
            if (await Directory(src).exists()) {
              await _copyDirectory(Directory(src), Directory(p.join(toolDir, entry.value)));
            }
          }
        }

        return '${tool.name} installed successfully';
      }

      final destPath = p.join(toolDir, tool.name);
      await binarySrcFile.copy(destPath);
      await _makeExecutable(destPath);

      if (tool.extraPaths != null) {
        for (final entry in tool.extraPaths!.entries) {
          final src = p.join(tempDir.path, entry.key);
          if (await Directory(src).exists()) {
            await _copyDirectory(
              Directory(src),
              Directory(p.join(toolDir, entry.value)),
            );
          }
        }
      }

      return '${tool.name} installed successfully';
    } catch (e) {
      return 'Failed to install ${tool.name}: $e';
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<String?> _findBinary(String dir, String name) async {
    final dirObj = Directory(dir);
    if (!await dirObj.exists()) return null;

    await for (final entity in dirObj.list(recursive: true)) {
      if (entity is File && p.basename(entity.path) == name) {
        return entity.path;
      }
    }

    await for (final entity in dirObj.list(recursive: true)) {
      if (entity is File && !entity.path.endsWith('.so') && !entity.path.endsWith('.a')) {
        final stat = await entity.stat();
        if (stat.size > 1024 * 1024) {
          return entity.path;
        }
      }
    }

    return null;
  }

  Future<void> _downloadFile(
    String url,
    String destPath,
    void Function(String status, double progress)? onProgress,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final file = File(destPath);
      await file.parent.create(recursive: true);

      final totalBytes = response.contentLength;
      var received = 0;

      final sink = file.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call('Downloading...', received / totalBytes);
        }
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  Future<void> _extractTarGz(String archivePath, String destDir) async {
    final bytes = await File(archivePath).readAsBytes();
    final decompressed = GZipDecoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(decompressed);

    for (final entry in archive) {
      final outputPath = p.join(destDir, entry.name);

      if (entry.isFile) {
        final file = File(outputPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.content);
      } else if (entry.isDirectory) {
        await Directory(outputPath).create(recursive: true);
      }
    }
  }

  Future<void> _makeExecutable(String path) async {
    await Process.run('chmod', ['+x', path]);
  }

  Future<void> _copyDirectory(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in src.list()) {
      final newPath = p.join(dest.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }
}
