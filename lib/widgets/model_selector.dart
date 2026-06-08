import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/settings_provider.dart';

class ModelSelector extends StatelessWidget {
  final String? currentModelId;
  final ValueChanged<String> onModelChanged;

  const ModelSelector({
    super.key,
    required this.currentModelId,
    required this.onModelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    if (!settings.hasApiKey || settings.favoriteModels.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentModel = currentModelId != null
        ? settings.getModelById(currentModelId!)
        : null;
    final displayName = currentModel?.displayName ??
        currentModelId ??
        settings.defaultModel;

    return GestureDetector(
      onTap: () => _showModelPicker(context, settings),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _shortName(displayName),
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.swap_horiz_rounded,
              size: 14,
              color: AppColors.textSecondary(context).withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  void _showModelPicker(BuildContext context, SettingsProvider settings) {
    final favorites = settings.favoriteModels;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
                    'Select Model',
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${favorites.length} selected',
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
                itemCount: favorites.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 0.5, color: AppColors.border(context)),
                itemBuilder: (_, index) {
                  final model = favorites[index];
                  final isSelected = model.id ==
                      (currentModelId ?? settings.defaultModel);
                  final isDefault = settings.defaultModel == model.id;

                  return InkWell(
                    onTap: () {
                      onModelChanged(model.id);
                      Navigator.pop(ctx);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      model.displayName,
                                      style: TextStyle(
                                        color: AppColors.textPrimary(context),
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                    if (isDefault)
                                      Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'default',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  model.provider,
                                  style: TextStyle(
                                    color: AppColors.textSecondary(context),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle_rounded,
                                color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  String _shortName(String name) {
    if (name.length <= 14) return name;
    return '${name.substring(0, 12)}..';
  }
}
