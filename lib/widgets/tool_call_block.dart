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

class _ToolCallBlockState extends State<ToolCallBlock> {
  bool _expanded = false;

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
    if (widget.toolCall.error) return 'failed';
    if (widget.toolCall.completed) return 'done';
    if (widget.isStreaming) return 'running...';
    return 'pending';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getToolIcon(widget.toolCall.name),
                    size: 10,
                    color: _statusColor().withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _toolLabel(widget.toolCall.name),
                    style: TextStyle(
                      color: AppColors.textSecondary(context).withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _statusLabel(),
                    style: TextStyle(
                      color: _statusColor().withValues(alpha: 0.4),
                      fontSize: 9,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 12,
                    color: AppColors.textSecondary(context).withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    context,
                    'args',
                    JsonEncoder.withIndent('  ')
                        .convert(widget.toolCall.arguments),
                  ),
                  if (widget.toolCall.result != null) ...[
                    const SizedBox(height: 4),
                    _buildSection(
                      context,
                      widget.toolCall.error ? 'error' : 'result',
                      widget.toolCall.result!,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String label, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context).withValues(alpha: 0.5),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.background(context).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            content,
            style: TextStyle(
                color: widget.toolCall.error
                    ? AppColors.error
                    : AppColors.textSecondary(context).withValues(alpha: 0.85),
                fontSize: 12,
              fontFamily: 'monospace',
              height: 1.3,
            ),
            maxLines: 20,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
