import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/thread_entry.dart';

class TaskPlanBlock extends StatelessWidget {
  final TaskPlanEntry entry;

  const TaskPlanBlock({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final total = entry.tasks.length;
    final done = entry.tasks.where((t) => t.status == TaskStatus.completed).length;
    final inProgress = entry.tasks.where((t) => t.status == TaskStatus.inProgress).length;
    final failed = entry.tasks.where((t) => t.status == TaskStatus.failed).length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.border(context).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Icon(
                  Icons.checklist_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Task Plan',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '$done/$total · '
                  '${inProgress > 0 ? "$inProgress active" : ""}'
                  '${failed > 0 ? " · $failed failed" : ""}',
                  style: TextStyle(
                    color: AppColors.textSecondary(context).withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 12, endIndent: 12),
          ...entry.tasks.map((task) => _buildTaskRow(context, task)),
        ],
      ),
    );
  }

  Widget _buildTaskRow(BuildContext context, Task task) {
    final icon = switch (task.status) {
      TaskStatus.pending => Icons.circle_outlined,
      TaskStatus.inProgress => Icons.radio_button_checked,
      TaskStatus.completed => Icons.check_circle_rounded,
      TaskStatus.failed => Icons.cancel_rounded,
    };
    final iconColor = switch (task.status) {
      TaskStatus.pending => AppColors.textSecondary(context).withValues(alpha: 0.4),
      TaskStatus.inProgress => AppColors.accent,
      TaskStatus.completed => AppColors.success,
      TaskStatus.failed => AppColors.error,
    };
    final textColor = switch (task.status) {
      TaskStatus.completed => AppColors.textSecondary(context).withValues(alpha: 0.6),
      TaskStatus.failed => AppColors.error,
      _ => AppColors.textPrimary(context),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: task.status == TaskStatus.completed
                        ? FontWeight.w400
                        : FontWeight.w500,
                    decoration: task.status == TaskStatus.completed
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                if (task.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      task.description,
                      style: TextStyle(
                        color: AppColors.textSecondary(context)
                            .withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
