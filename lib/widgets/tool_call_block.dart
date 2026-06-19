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

  String _toolLabel(String name) {
    // Convert snake_case to readable format
    return name.replaceAll('_', ' ');
  }

  String _getStatusText() {
    if (widget.toolCall.error) return 'error';
    if (widget.toolCall.completed) return 'done';
    if (widget.isStreaming) return 'running';
    return 'pending';
  }

  Color _getStatusColor(BuildContext context) {
    if (widget.toolCall.error) {
      return AppColors.error.withValues(alpha: 0.7);
    }
    return AppColors.textSecondary(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  // Tool name - monospace, low opacity
                  Expanded(
                    child: Text(
                      _toolLabel(widget.toolCall.name),
                      style: TextStyle(
                        color: AppColors.textSecondary(context).withValues(alpha: 0.65),
                        fontSize: 11,
                        fontFamily: 'monospace',
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  // Status text - minimal, inline
                  Text(
                    _getStatusText(),
                    style: TextStyle(
                      color: _getStatusColor(context).withValues(alpha: 0.5),
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Expand indicator
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 14,
                    color: AppColors.textSecondary(context).withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),
          // Expanded content - clean, no heavy containers
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Arguments
                  _buildDetailSection(
                    context,
                    'input',
                    JsonEncoder.withIndent('  ')
                        .convert(widget.toolCall.arguments),
                  ),
                  // Result or Error
                  if (widget.toolCall.result != null) ...[
                    const SizedBox(height: 8),
                    _buildDetailSection(
                      context,
                      widget.toolCall.error ? 'error' : 'output',
                      widget.toolCall.result!,
                      isError: widget.toolCall.error,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(
    BuildContext context,
    String label,
    String content, {
    bool isError = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label - minimal, monospace
        Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 1),
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context).withValues(alpha: 0.4),
              fontSize: 9,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
          ),
        ),
        // Content - subtle background, clean
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.background(context).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            content,
            style: TextStyle(
              color: isError
                  ? AppColors.error.withValues(alpha: 0.85)
                  : AppColors.textSecondary(context).withValues(alpha: 0.8),
              fontSize: 11,
              fontFamily: 'monospace',
              height: 1.4,
            ),
            maxLines: 50,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
