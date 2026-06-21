enum TaskStatus { pending, inProgress, completed, failed }

class Task {
  final String id;
  final String title;
  final String description;
  TaskStatus status;

  Task({
    required this.id,
    required this.title,
    this.description = '',
    this.status = TaskStatus.pending,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status.name,
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        status: TaskStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => TaskStatus.pending,
        ),
      );
}

sealed class ThreadEntry {
  const ThreadEntry();
  Map<String, dynamic> toJson();
  bool get isStreaming;

  static ThreadEntry fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'thinking' => ThinkingEntry.fromJson(json),
      'text' => TextEntry.fromJson(json),
      'tool_call' => ToolCallEntry.fromJson(json),
      'task_plan' => TaskPlanEntry.fromJson(json),
      _ => throw ArgumentError('Unknown entry type: ${json['type']}'),
    };
  }

  static List<ThreadEntry> listFromJson(List<dynamic> jsonList) {
    return jsonList
        .map((e) => ThreadEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static List<Map<String, dynamic>> listToJson(List<ThreadEntry> entries) {
    return entries.map((e) => e.toJson()).toList();
  }
}

class ThinkingEntry extends ThreadEntry {
  String content;
  @override
  final bool isStreaming;

  ThinkingEntry(this.content, {this.isStreaming = false});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'thinking',
        'content': content,
      };

  factory ThinkingEntry.fromJson(Map<String, dynamic> json) =>
      ThinkingEntry(json['content'] as String);
}

class TextEntry extends ThreadEntry {
  String content;
  @override
  final bool isStreaming;

  TextEntry(this.content, {this.isStreaming = false});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'text',
        'content': content,
      };

  factory TextEntry.fromJson(Map<String, dynamic> json) =>
      TextEntry(json['content'] as String);
}

class ToolCallEntry extends ThreadEntry {
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> toolArguments;
  bool completed;
  bool error;
  String? result;
  bool isExecuting;

  ToolCallEntry({
    required this.toolCallId,
    required this.toolName,
    required this.toolArguments,
    this.completed = false,
    this.error = false,
    this.result,
    this.isExecuting = false,
  });

  @override
  bool get isStreaming => isExecuting;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'tool_call',
        'tool_call_id': toolCallId,
        'tool_name': toolName,
        'tool_arguments': toolArguments,
        'completed': completed,
        'error': error,
        'result': result,
      };

  factory ToolCallEntry.fromJson(Map<String, dynamic> json) =>
      ToolCallEntry(
        toolCallId: json['tool_call_id'] as String,
        toolName: json['tool_name'] as String,
        toolArguments:
            (json['tool_arguments'] as Map<String, dynamic>?) ?? {},
        completed: json['completed'] as bool? ?? false,
        error: json['error'] as bool? ?? false,
        result: json['result'] as String?,
      );
}

class TaskPlanEntry extends ThreadEntry {
  List<Task> tasks;

  TaskPlanEntry({required this.tasks});

  @override
  bool get isStreaming => false;

  void updateTaskStatus(String taskId, TaskStatus status) {
    final task = tasks.firstWhere((t) => t.id == taskId);
    task.status = status;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'task_plan',
        'tasks': tasks.map((t) => t.toJson()).toList(),
      };

  factory TaskPlanEntry.fromJson(Map<String, dynamic> json) =>
      TaskPlanEntry(
        tasks: (json['tasks'] as List<dynamic>)
            .map((t) => Task.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}
