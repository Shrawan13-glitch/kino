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
          ...entry.tasks.map((task) => _TaskRow(task: task)),
        ],
      ),
    );
  }
}

class _TaskRow extends StatefulWidget {
  final Task task;
  const _TaskRow({required this.task});

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> with SingleTickerProviderStateMixin {
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  @override
  void initState() {
    super.initState();
    if (widget.task.status == TaskStatus.inProgress) {
      _startPulse();
    }
  }

  @override
  void didUpdateWidget(_TaskRow old) {
    super.didUpdateWidget(old);
    if (widget.task.status == TaskStatus.inProgress && _pulseController == null) {
      _startPulse();
    } else if (widget.task.status != TaskStatus.inProgress && _pulseController != null) {
      _pulseController?.dispose();
      _pulseController = null;
      _pulseAnimation = null;
    }
  }

  void _startPulse() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
    );
    _pulseController!.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isActive = task.status == TaskStatus.inProgress;

    if (!isActive || _pulseController == null) {
      return _buildRow(context, task, 0.0);
    }

    return AnimatedBuilder(
      animation: _pulseController!,
      builder: (context, _) {
        return _buildRow(context, task, _pulseAnimation?.value ?? 0.0);
      },
    );
  }

  Widget _buildRow(BuildContext context, Task task, double highlightAlpha) {
    final isActive = task.status == TaskStatus.inProgress;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFFFFC107).withValues(alpha: highlightAlpha * 0.2)
            : null,
        borderRadius: BorderRadius.circular(8),
        border: isActive
            ? Border(
                left: BorderSide(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.7),
                  width: 3,
                ),
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                switch (task.status) {
                  TaskStatus.pending => Icons.circle_outlined,
                  TaskStatus.inProgress => Icons.radio_button_checked,
                  TaskStatus.completed => Icons.check_circle_rounded,
                  TaskStatus.failed => Icons.cancel_rounded,
                },
                size: 18,
                color: switch (task.status) {
                  TaskStatus.pending => AppColors.textSecondary(context).withValues(alpha: 0.4),
                  TaskStatus.inProgress => const Color(0xFFFFC107),
                  TaskStatus.completed => AppColors.success,
                  TaskStatus.failed => AppColors.error,
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      color: switch (task.status) {
                        TaskStatus.inProgress => const Color(0xFFFFC107),
                        TaskStatus.completed => AppColors.textSecondary(context).withValues(alpha: 0.6),
                        TaskStatus.failed => AppColors.error,
                        _ => AppColors.textPrimary(context),
                      },
                      fontSize: 13,
                      fontWeight: isActive
                          ? FontWeight.w600
                          : task.status == TaskStatus.completed
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
                          color: isActive
                              ? const Color(0xFFFFC107).withValues(alpha: 0.7)
                              : AppColors.textSecondary(context)
                                  .withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (isActive)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: const Color(0xFFFFC107),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
