class VfsException implements Exception {
  final String message;
  final String? path;

  const VfsException(this.message, {this.path});

  @override
  String toString() => path != null ? 'VfsException($path): $message' : 'VfsException: $message';
}

class VfsNotFoundException extends VfsException {
  const VfsNotFoundException(String path) : super('Path not found', path: path);
}

class VfsAlreadyExistsException extends VfsException {
  const VfsAlreadyExistsException(String path) : super('Already exists', path: path);
}

class VfsPermissionException extends VfsException {
  const VfsPermissionException(String path) : super('Permission denied', path: path);
}
