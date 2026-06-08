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
    if (widget.isStreaming) {
      _pulseController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..repeat();
    }
  }

  @override
  void didUpdateWidget(ToolCallBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStreaming && !oldWidget.isStreaming) {
      _pulseController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..repeat();
    } else if (!widget.isStreaming && oldWidget.isStreaming) {
      _pulseController.dispose();
    }
  }

  @override
  void dispose() {
    try {
      if (_pulseController.isAnimating || _pulseController.isCompleted) {
        _pulseController.dispose();
      }
    } catch (_) {}
    super.dispose();
  }

  IconData _getToolIcon(String name) {
    switch (name) {
      case 'web_search':
        return Icons.search_rounded;
      case 'fetch_url':
        return Icons.language_rounded;
      default:
        return Icons.code_rounded;
    }
  }

  String _toolLabel(String name) {
    switch (name) {
      case 'web_search':
        return 'Web Search';
      case 'fetch_url':
        return 'Fetch URL';
      default:
        return name;
    }
  }

  Color _statusColor() {
    if (widget.toolCall.error) return AppColors.error;
    if (widget.toolCall.completed) return AppColors.primary;
    return AppColors.textSecondary(context);
  }

  String _statusLabel() {
    if (widget.toolCall.error) return 'Failed';
    if (widget.toolCall.completed) return 'Done';
    if (widget.isStreaming) return 'Running...';
    return 'Pending';
  }

  Widget _buildStatusDot() {
    if (widget.isStreaming) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, _) {
          final pulse = (1 - (_pulseController.value * 2 - 1).abs())
              .clamp(0.4, 1.0);
          return Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: pulse),
            ),
          );
        },
      );
    }
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _statusColor(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isStreaming
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.border(context).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _getToolIcon(widget.toolCall.name),
                    size: 14,
                    color: _statusColor(),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _toolLabel(widget.toolCall.name),
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _statusLabel(),
                    style: TextStyle(
                      color: _statusColor().withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  if (!widget.toolCall.completed && !widget.toolCall.error)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _buildStatusDot(),
                    ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: AppColors.textSecondary(context),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Arguments
                  _buildSection(
                    context,
                    'Arguments',
                    JsonEncoder.withIndent('  ')
                        .convert(widget.toolCall.arguments),
                    Icons.settings_rounded,
                  ),
                  const SizedBox(height: 6),
                  // Result
                  if (widget.toolCall.result != null)
                    _buildSection(
                      context,
                      widget.toolCall.error ? 'Error' : 'Result',
                      widget.toolCall.result!,
                      widget.toolCall.error
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String label, String content, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: AppColors.textSecondary(context)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.background(context).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            content,
            style: TextStyle(
              color: widget.toolCall.error
                  ? AppColors.error
                  : AppColors.textSecondary(context),
              fontSize: 11,
              fontFamily: 'monospace',
              height: 1.4,
            ),
            maxLines: 20,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
