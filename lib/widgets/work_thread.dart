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
  bool _masterExpanded = false;
  DateTime? _startTime;
  int? _elapsedSeconds;

  @override
  void initState() {
    super.initState();
    _checkAndRecordTime();
  }

  @override
  void didUpdateWidget(WorkThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkAndRecordTime();
  }

  void _checkAndRecordTime() {
    final isActive = widget.entries.any((e) => e.isStreaming);
    if (isActive) {
      _startTime ??= DateTime.now();
      _elapsedSeconds = null;
    } else {
      if (_startTime != null && _elapsedSeconds == null) {
        _elapsedSeconds = DateTime.now().difference(_startTime!).inSeconds;
      }
    }
  }

  int? _findActiveEntryIndex() {
    int? index;
    for (int i = 0; i < widget.entries.length; i++) {
      if (widget.entries[i].isStreaming) index = i;
    }
    return index;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thinkingCount = widget.entries.whereType<ThinkingEntry>().length;
    final toolCount = widget.entries.whereType<ToolCallEntry>().length;
    final isActive = widget.entries.any((e) => e.isStreaming);
    final totalSteps = thinkingCount + toolCount;
    final expanded = _masterExpanded || isActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(isActive, totalSteps, expanded),
        if (expanded) ...[
          const SizedBox(height: 8),
          _buildTimeline(context),
        ],
      ],
    );
  }

  Widget _buildHeader(bool isActive, int totalSteps, bool expanded) {
    return InkWell(
      onTap: () => setState(() => _masterExpanded = !_masterExpanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isActive
                  ? 'Working...'
                  : (_elapsedSeconds != null
                      ? 'Done in ${_elapsedSeconds}s'
                      : 'Done'),
              style: TextStyle(
                color: isActive
                    ? AppColors.primary
                    : AppColors.textSecondary(context).withValues(alpha: 0.7),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (totalSteps > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$totalSteps step${totalSteps > 1 ? 's' : ''}',
                style: TextStyle(
                  color: AppColors.textSecondary(context).withValues(alpha: 0.45),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
            const SizedBox(width: 4),
            AnimatedRotation(
              duration: const Duration(milliseconds: 200),
              turns: expanded ? 0.5 : 0,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: AppColors.textSecondary(context).withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(BuildContext context) {
    final entries = widget.entries;
    final activeIndex = _findActiveEntryIndex();

    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: AppColors.border(context).withValues(alpha: 0.2),
            width: 2,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < entries.length; i++)
            Padding(
              padding: EdgeInsets.only(
                top: i == 0 ? 0 : 4,
                bottom: i == entries.length - 1 ? 0 : 4,
              ),
              child: _buildEntryContent(entries[i],
                  isActiveEntry: i == activeIndex),
            ),
        ],
      ),
    );
  }

  Widget _buildEntryContent(ThreadEntry entry, {bool isActiveEntry = false}) {
    switch (entry) {
      case ThinkingEntry(:final content, :final isStreaming):
        return ThinkingBlock(
          content: content,
          isStreaming: isStreaming,
          autoExpanded: isActiveEntry,
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
          autoExpanded: isActiveEntry,
        );

      default:
        return const SizedBox.shrink();
    }
  }
}
