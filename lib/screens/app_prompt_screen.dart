import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/settings_provider.dart';

class AppPromptScreen extends StatefulWidget {
  const AppPromptScreen({super.key});

  @override
  State<AppPromptScreen> createState() => _AppPromptScreenState();
}

class _AppPromptScreenState extends State<AppPromptScreen> {
  late TextEditingController _controller;
  bool _hasChanges = false;
  bool _showDefaultPreview = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<SettingsProvider>().appPrompt,
    );
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final settings = context.read<SettingsProvider>();
    final changed = _controller.text != settings.appPrompt;
    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
  }

  int get _charCount => _controller.text.length;
  int get _estimatedTokens => (_charCount / 4).round();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_rounded,
              color: AppColors.textSecondary(context)),
          splashRadius: 20,
        ),
        title: Text(
          'Behavior Prompt',
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Divider(height: 0.5, color: AppColors.border(context)),
        ),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.tune_rounded,
                          color: AppColors.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Behavior Prompt',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Shapes how the model thinks and structures its responses',
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: AppColors.accent.withValues(alpha: 0.7)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This is prepended to your custom instructions. '
                          'Changing it affects how the model structures its responses.',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border(context)),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: TextField(
                              controller: _controller,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontSize: 14,
                                height: 1.6,
                              ),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _showDefaultPreview = !_showDefaultPreview),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: AppColors.border(context).withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.description_outlined,
                                    size: 14,
                                    color: AppColors.textSecondary(context)
                                        .withValues(alpha: 0.5)),
                                const SizedBox(width: 6),
                                Text(
                                  'Default prompt',
                                  style: TextStyle(
                                    color: AppColors.textSecondary(context)
                                        .withValues(alpha: 0.6),
                                    fontSize: 12,
                                  ),
                                ),
                                const Spacer(),
                                Row(
                                  children: [
                                    Icon(Icons.text_fields_rounded,
                                        size: 13,
                                        color: AppColors.textSecondary(context)
                                            .withValues(alpha: 0.4)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$_charCount chars',
                                      style: TextStyle(
                                        color: AppColors.textSecondary(context)
                                            .withValues(alpha: 0.4),
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.token_rounded,
                                        size: 13,
                                        color: AppColors.textSecondary(context)
                                            .withValues(alpha: 0.4)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '~$_estimatedTokens tokens',
                                      style: TextStyle(
                                        color: AppColors.textSecondary(context)
                                            .withValues(alpha: 0.4),
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: _hasChanges
                                            ? AppColors.accent
                                            : AppColors.success.withValues(alpha: 0.5),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _hasChanges ? 'Modified' : 'Default',
                                      style: TextStyle(
                                        color: _hasChanges
                                            ? AppColors.accent
                                            : AppColors.success.withValues(alpha: 0.5),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      _showDefaultPreview
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      size: 18,
                                      color: AppColors.textSecondary(context)
                                          .withValues(alpha: 0.4),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showDefaultPreview)
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Divider(
                                    height: 0.5,
                                    color: AppColors.border(context)),
                                const SizedBox(height: 10),
                                Text(
                                  'Original default prompt',
                                  style: TextStyle(
                                    color: AppColors.textSecondary(context)
                                        .withValues(alpha: 0.6),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceLight(context),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    SettingsProvider.defaultAppPrompt,
                                    style: TextStyle(
                                      color: AppColors.textSecondary(context)
                                          .withValues(alpha: 0.7),
                                      fontSize: 12,
                                      height: 1.5,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.info_outline_rounded,
                                        size: 12,
                                        color: AppColors.textSecondary(context)
                                            .withValues(alpha: 0.4)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'The default is always used as base. Your edits extend it.',
                                      style: TextStyle(
                                        color: AppColors.textSecondary(context)
                                            .withValues(alpha: 0.4),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _hasChanges
                            ? () {
                                HapticFeedback.lightImpact();
                                _controller.text = SettingsProvider.defaultAppPrompt;
                                settings.setAppPrompt(SettingsProvider.defaultAppPrompt);
                                setState(() => _hasChanges = false);
                              }
                            : null,
                        icon: const Icon(Icons.restart_alt_rounded, size: 16),
                        label: const Text('Reset'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary(context),
                          side: BorderSide(
                            color: _hasChanges
                                ? AppColors.border(context)
                                : AppColors.border(context).withValues(alpha: 0.3),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _hasChanges
                            ? () {
                                HapticFeedback.mediumImpact();
                                settings.setAppPrompt(_controller.text);
                                setState(() => _hasChanges = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Row(
                                      children: [
                                        Icon(Icons.check_circle_rounded,
                                            color: Colors.white, size: 18),
                                        SizedBox(width: 8),
                                        Text('Behavior prompt updated'),
                                      ],
                                    ),
                                    backgroundColor: AppColors.accent,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            : null,
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Save'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          disabledBackgroundColor:
                              AppColors.accent.withValues(alpha: 0.4),
                          disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
