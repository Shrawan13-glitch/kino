import 'thread_entry.dart';
import 'dart:convert';

class Chat {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  String? model;
  String? systemPrompt;
  TaskPlanEntry? taskPlan;

  Chat({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.model,
    this.systemPrompt,
    this.taskPlan,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'model': model,
      'system_prompt': systemPrompt,
      'task_plan': taskPlan != null ? jsonEncode(taskPlan!.toJson()) : null,
    };
  }

  factory Chat.fromMap(Map<String, dynamic> map) {
    TaskPlanEntry? taskPlan;
    final taskPlanStr = map['task_plan'] as String?;
    if (taskPlanStr != null && taskPlanStr.isNotEmpty) {
      try {
        final json = jsonDecode(taskPlanStr) as Map<String, dynamic>;
        taskPlan = TaskPlanEntry.fromJson(json);
      } catch (_) {}
    }
    return Chat(
      id: map['id'] as String,
      title: map['title'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      model: map['model'] as String?,
      systemPrompt: map['system_prompt'] as String?,
      taskPlan: taskPlan,
    );
  }

  Chat copyWith({
    String? title,
    DateTime? updatedAt,
    String? model,
    String? systemPrompt,
    TaskPlanEntry? taskPlan,
  }) {
    return Chat(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      taskPlan: taskPlan ?? this.taskPlan,
    );
  }

  bool get hasActiveTaskPlan {
    if (taskPlan == null) return false;
    return taskPlan!.tasks.any(
      (t) => t.status == TaskStatus.inProgress || t.status == TaskStatus.pending,
    );
  }

  bool get isTaskPlanComplete {
    if (taskPlan == null) return true;
    return taskPlan!.tasks.every((t) => t.status == TaskStatus.completed);
  }
}
