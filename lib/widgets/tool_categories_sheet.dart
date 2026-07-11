import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/tool_category.dart';
import '../providers/settings_provider.dart';

class ToolCategoriesSheet extends StatelessWidget {
  const ToolCategoriesSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      builder: (_) => const ToolCategoriesSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final enabledCount = settings.enabledToolCategories.length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Text(
                  'Tools',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '$enabledCount enabled',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border(context)),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: ToolCategory.values.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 0.5, color: AppColors.border(context)),
              itemBuilder: (_, index) {
                final category = ToolCategory.values[index];
                final isEnabled = settings.isToolCategoryEnabled(category);
                final isGithub = isGithubCategory(category);
                final githubConnected = settings.isGithubConnected;

                return _ToolCategoryTile(
                  category: category,
                  isEnabled: isEnabled,
                  isGithub: isGithub,
                  githubConnected: githubConnected,
                  onToggle: () => settings.toggleToolCategory(category),
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class _ToolCategoryTile extends StatelessWidget {
  final ToolCategory category;
  final bool isEnabled;
  final bool isGithub;
  final bool githubConnected;
  final VoidCallback onToggle;

  const _ToolCategoryTile({
    required this.category,
    required this.isEnabled,
    required this.isGithub,
    required this.githubConnected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final locked = isGithub && !githubConnected;

    return InkWell(
      onTap: locked ? null : onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isEnabled
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.surfaceLight(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                category.icon,
                size: 18,
                color: isEnabled ? AppColors.primary : AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.label,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    category.description,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (locked)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed('/settings');
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Connect',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Switch(
                value: isEnabled,
                onChanged: (_) => onToggle(),
                activeThumbColor: AppColors.primary,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
                inactiveTrackColor: AppColors.surfaceLight(context),
              ),
          ],
        ),
      ),
    );
  }
}
