import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/thread_entry.dart';

class TaskPlanBanner extends StatelessWidget {
  final TaskPlanEntry plan;
  final VoidCallback? onTap;

  const TaskPlanBanner({super.key, required this.plan, this.onTap});

  @override
  Widget build(BuildContext context) {
    final total = plan.tasks.length;
    final done = plan.tasks.where((t) => t.status == TaskStatus.completed).length;
    final inProgress = plan.tasks.where((t) => t.status == TaskStatus.inProgress);
    final currentTask = inProgress.isNotEmpty ? inProgress.first.title : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight(context),
          border: Border(
            bottom: BorderSide(
              color: AppColors.border(context).withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: currentTask != null
                    ? const Color(0xFFFFC107).withValues(alpha: 0.2)
                    : AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.checklist_rounded,
                size: 16,
                color: currentTask != null ? const Color(0xFFFFC107) : AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Task Plan — $done/$total · ${currentTask ?? "done"}',
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (currentTask != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFC107),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              currentTask,
                              style: TextStyle(
                                color: const Color(0xFFFFC107).withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 60,
              child: LinearProgressIndicator(
                value: total > 0 ? done / total : 0,
                backgroundColor: AppColors.border(context).withValues(alpha: 0.3),
                color: const Color(0xFFFFC107),
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.textSecondary(context).withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
