import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/thread_entry.dart';
import '../providers/chat_provider.dart';

class TodoWidget extends StatelessWidget {
  const TodoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<ChatProvider>().activeTaskPlan;
    if (plan == null) return const SizedBox.shrink();
    if (plan.tasks.every((t) => t.status == TaskStatus.completed)) {
      return const SizedBox.shrink();
    }
    return _TodoPanel(plan: plan);
  }
}

class _TodoPanel extends StatefulWidget {
  final TaskPlanEntry plan;
  const _TodoPanel({required this.plan});

  @override
  State<_TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends State<_TodoPanel>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final total = plan.tasks.length;
    final done = plan.tasks.where((t) => t.status == TaskStatus.completed).length;
    final inProgress = plan.tasks.where((t) => t.status == TaskStatus.inProgress);
    final currentTask = inProgress.isNotEmpty ? inProgress.first : plan.tasks.firstWhere(
      (t) => t.status == TaskStatus.pending,
      orElse: () => inProgress.isNotEmpty ? inProgress.first : plan.tasks.first,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.border(context).withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _expanded
                      ? _buildExpanded(context, plan, total, done)
                      : _buildCollapsed(context, plan, total, done, currentTask),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsed(
    BuildContext context,
    TaskPlanEntry plan,
    int total,
    int done,
    Task currentTask,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: currentTask.status == TaskStatus.inProgress
                  ? const Color(0xFFFFC107).withValues(alpha: 0.2)
                  : AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.checklist_rounded,
              size: 14,
              color: currentTask.status == TaskStatus.inProgress
                  ? const Color(0xFFFFC107)
                  : AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Todo',
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight(context),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$done/$total',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: currentTask.status == TaskStatus.inProgress
                        ? const Color(0xFFFFC107)
                        : AppColors.textSecondary(context).withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    currentTask.title,
                    style: TextStyle(
                      color: currentTask.status == TaskStatus.inProgress
                          ? const Color(0xFFFFC107)
                          : AppColors.textSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: LinearProgressIndicator(
              value: total > 0 ? done / total : 0,
              backgroundColor: AppColors.border(context).withValues(alpha: 0.3),
              color: const Color(0xFFFFC107),
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.keyboard_arrow_up_rounded,
            size: 18,
            color: AppColors.textSecondary(context).withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildExpanded(
    BuildContext context,
    TaskPlanEntry plan,
    int total,
    int done,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.checklist_rounded,
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Todo',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight(context),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$done/$total',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 60,
                child: LinearProgressIndicator(
                  value: total > 0 ? done / total : 0,
                  backgroundColor: AppColors.border(context).withValues(alpha: 0.3),
                  color: const Color(0xFFFFC107),
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.textSecondary(context).withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: 12, endIndent: 12),
        const SizedBox(height: 4),
        ...plan.tasks.map((task) => _buildTaskRow(context, task)),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildTaskRow(BuildContext context, Task task) {
    final isActive = task.status == TaskStatus.inProgress;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFFFC107).withValues(alpha: 0.1)
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: const Color(0xFFFFC107),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
