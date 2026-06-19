import 'dart:convert';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/message.dart' show ToolCall;

class ToolCallBlock extends StatefulWidget {
  final ToolCall toolCall;
  final bool isStreaming;

  const ToolCallBlock({
    super.key,
    required this.toolCall,
    this.isStreaming = false,
  });

  @override
  State<ToolCallBlock> createState() => _ToolCallBlockState();
}

class _ToolCallBlockState extends State<ToolCallBlock>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.isStreaming && !widget.toolCall.completed) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(ToolCallBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStreaming &&
        !widget.toolCall.completed &&
        !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if ((!widget.isStreaming || widget.toolCall.completed) &&
        _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  IconData _getToolIcon(String name) {
    switch (name) {
      case 'web_search':
        return Icons.search_rounded;
      case 'fetch_url':
        return Icons.language_rounded;
      case 'read_file':
        return Icons.description_outlined;
      case 'write_file':
        return Icons.edit_note_rounded;
      case 'execute':
        return Icons.terminal_rounded;
      default:
        return Icons.extension_rounded;
    }
  }

  String _toolLabel(String name) {
    switch (name) {
      case 'web_search':
        return 'Web Search';
      case 'fetch_url':
        return 'Fetch URL';
      case 'read_file':
        return 'Read File';
      case 'write_file':
        return 'Write File';
      case 'execute':
        return 'Execute';
      default:
        return name
            .split('_')
            .map((word) => word[0].toUpperCase() + word.substring(1))
            .join(' ');
    }
  }

  Color _statusColor() {
    if (widget.toolCall.error) return AppColors.error;
    if (widget.toolCall.completed) return AppColors.success;
    if (widget.isStreaming) return AppColors.accent;
    return AppColors.textSecondary(context);
  }

  IconData _statusIcon() {
    if (widget.toolCall.error) return Icons.error_outline_rounded;
    if (widget.toolCall.completed) return Icons.check_circle_outline_rounded;
    if (widget.isStreaming) return Icons.hourglass_empty_rounded;
    return Icons.schedule_rounded;
  }

  String _statusLabel() {
    if (widget.toolCall.error) return 'Failed';
    if (widget.toolCall.completed) return 'Done';
    if (widget.isStreaming) return 'Running';
    return 'Pending';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceLight(context).withValues(alpha: 0.15)
            : AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _expanded
              ? _statusColor().withValues(alpha: 0.3)
              : AppColors.border(context).withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: _expanded
            ? [
                BoxShadow(
                  color: _statusColor().withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      // Tool Icon
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _statusColor().withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _getToolIcon(widget.toolCall.name),
                          size: 16,
                          color: _statusColor(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Tool Name
                      Expanded(
                        child: Text(
                          _toolLabel(widget.toolCall.name),
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Status Badge
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final opacity = widget.isStreaming &&
                                  !widget.toolCall.completed
                              ? 0.6 + (_pulseController.value * 0.4)
                              : 1.0;
                          return Opacity(
                            opacity: opacity,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _statusColor().withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _statusColor().withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _statusIcon(),
                                    size: 12,
                                    color: _statusColor(),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _statusLabel(),
                                    style: TextStyle(
                                      color: _statusColor(),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      // Expand Icon
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 20,
                        color: AppColors.textSecondary(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Expanded Content
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    _buildSection(
                      context,
                      'Arguments',
                      JsonEncoder.withIndent('  ')
                          .convert(widget.toolCall.arguments),
                      Icons.data_object_rounded,
                    ),
                    if (widget.toolCall.result != null) ...[
                      const SizedBox(height: 12),
                      _buildSection(
                        context,
                        widget.toolCall.error ? 'Error' : 'Result',
                        widget.toolCall.result!,
                        widget.toolCall.error
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_outline_rounded,
                      ),
                    ],
                  ],
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String label,
    String content,
    IconData icon,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: AppColors.textSecondary(context),
            ),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.background(context).withValues(alpha: 0.5)
                : AppColors.surfaceLight(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.toolCall.error && label == 'Error'
                  ? AppColors.error.withValues(alpha: 0.2)
                  : AppColors.border(context).withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Text(
            content,
            style: TextStyle(
              color: widget.toolCall.error && label == 'Error'
                  ? AppColors.error
                  : AppColors.textPrimary(context).withValues(alpha: 0.9),
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.5,
            ),
            maxLines: 30,
            overflow: TextOverflow.fade,
          ),
        ),
      ],
    );
  }
}
