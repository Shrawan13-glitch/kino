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

  @override
  Widget build(BuildContext context) {
    final thinkingCount = widget.entries.whereType<ThinkingEntry>().length;
    final toolCount = widget.entries.whereType<ToolCallEntry>().length;
    final isActive = widget.entries.any((e) => e.isStreaming);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(isActive, thinkingCount, toolCount),
          if (_masterExpanded) ...[
            const SizedBox(height: 4),
            _buildTimeline(context),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(bool isActive, int thinkingCount, int toolCount) {
    return InkWell(
      onTap: () => setState(() => _masterExpanded = !_masterExpanded),
      borderRadius: BorderRadius.circular(2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status and counts - clean, minimal
            Text(
              isActive ? 'working' : 'work',
              style: TextStyle(
                color: AppColors.textSecondary(context).withValues(alpha: 0.5),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            if (thinkingCount > 0 || toolCount > 0) ...[
              const SizedBox(width: 6),
              Text(
                '·',
                style: TextStyle(
                  color: AppColors.textSecondary(context).withValues(alpha: 0.25),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${thinkingCount + toolCount}',
                style: TextStyle(
                  color: AppColors.textSecondary(context).withValues(alpha: 0.4),
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(
              _masterExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: AppColors.textSecondary(context).withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(BuildContext context) {
    final entries = widget.entries;
    return Container(
      padding: const EdgeInsets.only(left: 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < entries.length; i++)
            Padding(
              padding: EdgeInsets.only(
                top: i == 0 ? 0 : 2,
              ),
              child: _buildEntryContent(entries[i]),
            ),
        ],
      ),
    );
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

class _EntryFadeIn extends StatefulWidget {
  final Widget child;

  const _EntryFadeIn({required this.child, super.key});

  @override
  State<_EntryFadeIn> createState() => _EntryFadeInState();
}

class _EntryFadeInState extends State<_EntryFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _opacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
