import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/thread_entry.dart';
import '../models/message.dart' show ToolCall;
import 'thinking_block.dart';
import 'tool_call_block.dart';

class WorkThread extends StatefulWidget {
  final List<ThreadEntry> entries;

  const WorkThread({super.key, required this.entries});

  @override
  State<WorkThread> createState() => _WorkThreadState();
}

class _WorkThreadState extends State<WorkThread> {
  bool _masterExpanded = true;

  @override
  Widget build(BuildContext context) {
    final thinkingCount =
        widget.entries.whereType<ThinkingEntry>().length;
    final toolCount = widget.entries.whereType<ToolCallEntry>().length;
    final isActive = widget.entries.any((e) => e.isStreaming);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(thinkingCount, toolCount, isActive),
          if (_masterExpanded) _buildTimeline(context),
        ],
      ),
    );
  }

  Widget _buildHeader(int thinkingCount, int toolCount, bool isActive) {
    return InkWell(
      onTap: () => setState(() => _masterExpanded = !_masterExpanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: isActive ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isActive ? 'Working...' : 'Thinking + Working',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${thinkingCount + toolCount}',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _masterExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: AppColors.textSecondary(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(BuildContext context) {
    final entries = widget.entries;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1, thickness: 1),
        for (int i = 0; i < entries.length; i++)
          _buildEntryRow(entries[i], i, entries.length, context),
      ],
    );
  }

  Widget _buildEntryRow(ThreadEntry entry, int index, int count, BuildContext context) {
    final isFirst = index == 0;
    final isLast = index == count - 1;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 2,
                      color: AppColors.border(context),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildNode(entry, context)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: isFirst ? 10 : 6,
                bottom: isLast ? 10 : 4,
                right: 12,
              ),
              child: _buildEntryContent(entry),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNode(ThreadEntry entry, BuildContext context) {
    switch (entry) {
      case ThinkingEntry(:final isStreaming):
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isStreaming
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.5),
          ),
        );

      case ToolCallEntry(:final toolName, :final isExecuting):
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: isExecuting
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.surface(context),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: AppColors.border(context),
              width: 1,
            ),
          ),
          child: Icon(
            _toolIcon(toolName),
            size: 12,
            color: isExecuting
                ? AppColors.primary
                : AppColors.textSecondary(context),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  IconData _toolIcon(String name) {
    switch (name) {
      case 'web_search':
        return Icons.search_rounded;
      case 'fetch_url':
        return Icons.language_rounded;
      default:
        return Icons.code_rounded;
    }
  }

  Widget _buildEntryContent(ThreadEntry entry) {
    switch (entry) {
      case ThinkingEntry(:final content, :final isStreaming):
        return ThinkingBlock(
          content: content,
          isStreaming: isStreaming,
        );

      case ToolCallEntry(
          :final toolCallId,
          :final toolName,
          :final toolArguments,
          :final completed,
          :final error,
          :final result,
          :final isExecuting,
        ):
        return ToolCallBlock(
          toolCall: ToolCall(
            id: toolCallId,
            name: toolName,
            arguments: toolArguments,
            completed: completed,
            error: error,
            result: result,
          ),
          isStreaming: isExecuting,
        );

      default:
        return const SizedBox.shrink();
    }
  }
}
