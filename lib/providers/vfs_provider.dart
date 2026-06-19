import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import '../services/vfs/vfs_service.dart';
import '../services/vfs/vfs_node.dart';
import '../services/vfs/vfs_exception.dart';

class BreadcrumbItem {
  final String path;
  final String label;
  const BreadcrumbItem(this.path, this.label);
}

class VfsProvider extends ChangeNotifier {
  final VfsService _vfs = VfsService();
  final Map<String, String> _clipboard = {};
  bool _isCut = false;

  String _currentPath = '/';
  List<VfsNode> _entries = [];
  bool _isLoading = false;
  String? _error;
  String? _statusMessage;
  Timer? _statusTimer;

  String get currentPath => _currentPath;
  List<VfsNode> get entries => _entries;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get statusMessage => _statusMessage;
  bool get hasClipboard => _clipboard.isNotEmpty;
  bool get isCut => _isCut;

  String get currentDirName {
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'VFS';
    return parts.last;
  }

  List<BreadcrumbItem> get breadcrumbs {
    if (_currentPath == '/') {
      return [const BreadcrumbItem('/', 'VFS')];
    }
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    final items = [const BreadcrumbItem('/', 'VFS')];
    var path = '';
    for (final part in parts) {
      path = '$path/$part';
      items.add(BreadcrumbItem(path, part));
    }
    return items;
  }

  Future<void> init() async {
    await _vfs.init();
    await navigateTo('/');
  }

  Future<void> navigateTo(String path) async {
    _setLoading(true);
    _error = null;
    try {
      _currentPath = path;
      _entries = await _vfs.list(path);
    } on VfsException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Failed to load directory: $e';
    }
    _setLoading(false);
  }

  Future<void> navigateUp() async {
    if (_currentPath == '/') return;
    final parent = p.dirname(_currentPath);
    if (parent.isEmpty || parent == '.') {
      await navigateTo('/');
    } else {
      await navigateTo(parent);
    }
  }

  Future<void> refresh() => navigateTo(_currentPath);

  Future<void> createFile(String name) async {
    try {
      final path = '$_currentPath/$name';
      await _vfs.writeFile(path, '');
      _showStatus('Created file: $name');
      await refresh();
    } on VfsException catch (e) {
      _error = e.message;
      notifyListeners();
    }
  }

  Future<void> createDirectory(String name) async {
    try {
      final path = '$_currentPath/$name';
      await _vfs.createDirectory(path);
      _showStatus('Created folder: $name');
      await refresh();
    } on VfsException catch (e) {
      _error = e.message;
      notifyListeners();
    }
  }

  Future<void> delete(String name) async {
    try {
      final path = '$_currentPath/$name';
      await _vfs.delete(path);
      _showStatus('Deleted: $name');
      await refresh();
    } on VfsException catch (e) {
      _error = e.message;
      notifyListeners();
    }
  }

  Future<void> rename(String oldName, String newName) async {
    try {
      final path = '$_currentPath/$oldName';
      await _vfs.rename(path, newName);
      _showStatus('Renamed to: $newName');
      await refresh();
    } on VfsException catch (e) {
      _error = e.message;
      notifyListeners();
    }
  }

  void copy(String name) {
    _clipboard['source'] = '$_currentPath/$name';
    _isCut = false;
    notifyListeners();
    _showStatus('Copied: $name');
  }

  void cut(String name) {
    _clipboard['source'] = '$_currentPath/$name';
    _isCut = true;
    notifyListeners();
    _showStatus('Cut: $name');
  }

  Future<void> paste() async {
    if (!hasClipboard) return;
    try {
      final source = _clipboard['source']!;
      final dest = '$_currentPath/${p.basename(source)}';

      if (_isCut) {
        await _vfs.move(source, dest);
      } else {
        await _vfs.copy(source, dest);
      }

      _clipboard.clear();
      _isCut = false;
      _showStatus('Pasted to $currentDirName');
      await refresh();
    } on VfsException catch (e) {
      _error = e.message;
      notifyListeners();
    }
  }

  void clearClipboard() {
    _clipboard.clear();
    _isCut = false;
    notifyListeners();
  }

  Future<VfsNode?> stat(String name) async {
    try {
      return await _vfs.stat('$_currentPath/$name');
    } catch (_) {
      return null;
    }
  }

  Future<String> readFile(String name) async {
    try {
      return await _vfs.readFileAsString('$_currentPath/$name');
    } on VfsException catch (e) {
      _error = e.message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> writeFile(String name, String content) async {
    try {
      await _vfs.writeFile('$_currentPath/$name', content);
      _showStatus('Saved: $name');
      await refresh();
    } on VfsException catch (e) {
      _error = e.message;
      notifyListeners();
    }
  }

  Future<Uint8List> readFileBytes(String name) async {
    return await _vfs.readFileAsBytes('$_currentPath/$name');
  }

  Future<void> share(String name) async {
    try {
      final path = '$_currentPath/$name';
      final abs = '${_vfs.rootPath}$path';
      final file = XFile(abs);
      await SharePlus.instance.share(
        ShareParams(files: [file]),
      );
    } catch (e) {
      _error = 'Failed to share: $e';
      notifyListeners();
    }
  }

  Future<void> downloadToDevice(String name) async {
    try {
      final path = '$_currentPath/$name';
      final abs = '${_vfs.rootPath}$path';
      final file = XFile(abs);
      await SharePlus.instance.share(
        ShareParams(files: [file]),
      );
      _showStatus('Shared: $name');
    } catch (e) {
      _error = 'Failed to share: $e';
      notifyListeners();
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _showStatus(String message) {
    _statusMessage = message;
    notifyListeners();
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(seconds: 3), () {
      _statusMessage = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }
}
