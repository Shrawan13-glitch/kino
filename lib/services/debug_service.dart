import 'dart:collection';
import 'package:flutter/foundation.dart';

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;
  final String? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.stackTrace,
  });

  String get formatted =>
      '[${timestamp.toString().substring(11, 23)}] [$level] $message';
}

class DebugService extends ChangeNotifier {
  static final DebugService instance = DebugService._();
  DebugService._();

  final List<LogEntry> _logs = [];

  UnmodifiableListView<LogEntry> get logs => UnmodifiableListView(_logs);

  void info(String message) {
    _add('INFO', message);
  }

  void warn(String message) {
    _add('WARN', message);
  }

  void error(String message, [Object? error, StackTrace? stack]) {
    final sb = StringBuffer(message);
    if (error != null) sb.write(' | $error');
    _add('ERROR', sb.toString(), stack);
  }

  void _add(String level, String message, [StackTrace? stack]) {
    _logs.add(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      stackTrace: stack?.toString(),
    ));
    // Keep last 500 entries
    if (_logs.length > 500) {
      _logs.removeRange(0, _logs.length - 500);
    }
    notifyListeners();
    // Also print to console
    debugPrint('[Kino] [$level] $message');
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }
}
