import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/settings_provider.dart';

class SystemPromptScreen extends StatefulWidget {
  const SystemPromptScreen({super.key});

  @override
  State<SystemPromptScreen> createState() => _SystemPromptScreenState();
}

class _SystemPromptScreenState extends State<SystemPromptScreen> {
  late TextEditingController _controller;
  bool _hasChanges = false;
  bool _showExamples = true;

  static const _examples = [
    'You are a friendly and concise assistant. Keep responses under 3 paragraphs.',
    'Answer in bullet points. Be direct and avoid fluff.',
    'You are a writing coach. Give constructive feedback with specific suggestions.',
    'You are a code reviewer. Focus on security, performance, and readability.',
    'Speak like a pirate. Arrr!',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<SettingsProvider>().userPrompt,
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
    final changed = _controller.text != settings.userPrompt;
    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
    if (_controller.text.isNotEmpty && _showExamples) {
      setState(() => _showExamples = false);
    } else if (_controller.text.isEmpty && !_showExamples) {
      setState(() => _showExamples = true);
    }
  }

  void _applyExample(String example) {
    _controller.text = example;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: example.length),
    );
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
          'Custom Instructions',
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
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.edit_note_rounded,
                          color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Custom Instructions',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tell the model how to behave, what to avoid, and your preferences',
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
                                hintText: 'E.g. "You are a helpful assistant that speaks formally..."',
                                hintStyle: TextStyle(
                                  color: AppColors.textSecondary(context).withValues(alpha: 0.4),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                        if (_showExamples && _controller.text.isEmpty)
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Divider(
                                    height: 0.5,
                                    color: AppColors.border(context)),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(Icons.auto_awesome_rounded,
                                        size: 13,
                                        color: AppColors.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Need inspiration?',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _examples.map((ex) {
                                    return GestureDetector(
                                      onTap: () => _applyExample(ex),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceLight(context),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: AppColors.border(context)
                                                .withValues(alpha: 0.4),
                                          ),
                                        ),
                                        child: Text(
                                          ex.length > 50
                                              ? '${ex.substring(0, 50)}...'
                                              : ex,
                                          style: TextStyle(
                                            color: AppColors.textSecondary(context),
                                            fontSize: 12,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: AppColors.border(context)
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.text_fields_rounded,
                                  size: 14,
                                  color: AppColors.textSecondary(context)
                                      .withValues(alpha: 0.5)),
                              const SizedBox(width: 6),
                              Text(
                                '$_charCount chars',
                                style: TextStyle(
                                  color: AppColors.textSecondary(context)
                                      .withValues(alpha: 0.5),
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.token_rounded,
                                  size: 14,
                                  color: AppColors.textSecondary(context)
                                      .withValues(alpha: 0.5)),
                              const SizedBox(width: 6),
                              Text(
                                '~$_estimatedTokens tokens',
                                style: TextStyle(
                                  color: AppColors.textSecondary(context)
                                      .withValues(alpha: 0.5),
                                  fontSize: 11,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _hasChanges
                                      ? AppColors.primary
                                      : AppColors.success.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _hasChanges ? 'Unsaved' : 'Saved',
                                style: TextStyle(
                                  color: _hasChanges
                                      ? AppColors.primary
                                      : AppColors.success.withValues(alpha: 0.5),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
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
                        onPressed: _charCount > 0 || settings.userPrompt.isNotEmpty
                            ? () {
                                HapticFeedback.lightImpact();
                                _controller.clear();
                                settings.setUserPrompt('');
                                setState(() => _hasChanges = false);
                              }
                            : null,
                        icon: const Icon(Icons.restart_alt_rounded, size: 16),
                        label: const Text('Clear'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary(context),
                          side: BorderSide(
                            color: (_charCount > 0 || settings.userPrompt.isNotEmpty)
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
                                settings.setUserPrompt(_controller.text);
                                setState(() => _hasChanges = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Row(
                                      children: [
                                        Icon(Icons.check_circle_rounded,
                                            color: Colors.white, size: 18),
                                        SizedBox(width: 8),
                                        Text('Instructions saved'),
                                      ],
                                    ),
                                    backgroundColor: AppColors.primary,
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
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor:
                              AppColors.primary.withValues(alpha: 0.4),
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
