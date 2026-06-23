class ShellResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const ShellResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get success => exitCode == 0;

  String get combined {
    if (stdout.trim().isNotEmpty) return stdout.trim();
    return stderr.trim();
  }

  String get full {
    final parts = <String>[];
    if (stdout.trim().isNotEmpty) parts.add('STDOUT:\n$stdout');
    if (stderr.trim().isNotEmpty) parts.add('STDERR:\n$stderr');
    parts.add('Exit code: $exitCode');
    return parts.join('\n\n');
  }

  static const ok = ShellResult(exitCode: 0, stdout: '', stderr: '');
  static ShellResult testTrue() => ok;
  static ShellResult testFalse() => const ShellResult(exitCode: 1, stdout: '', stderr: '');
}
