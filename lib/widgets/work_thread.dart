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

class _WorkThreadState extends State<WorkThread>
    with SingleTickerProviderStateMixin {
  bool _masterExpanded = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
    if (widget.entries.any((e) => e.isStreaming)) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(WorkThread old) {
    super.didUpdateWidget(old);
    final wasActive = old.entries.any((e) => e.isStreaming);
    final isActive = widget.entries.any((e) => e.isStreaming);
    if (isActive && !wasActive) {
      _pulseController.repeat(reverse: true);
    } else if (!isActive && wasActive) {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thinkingCount =
        widget.entries.whereType<ThinkingEntry>().length;
    final toolCount = widget.entries.whereType<ToolCallEntry>().length;
    final isActive = widget.entries.any((e) => e.isStreaming);
    final total = thinkingCount + toolCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(isActive, total),
          if (_masterExpanded) _buildTimeline(context),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isActive, int total) {
    return InkWell(
      onTap: () => setState(() => _masterExpanded = !_masterExpanded),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, _) {
                final alpha = isActive ? _pulseAnimation.value : 0.5;
                return Text(
                  isActive ? 'working...' : 'thoughts + tools',
                  style: TextStyle(
                    color: AppColors.textSecondary(context).withValues(alpha: alpha),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                );
              },
            ),
            if (total > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$total',
                style: TextStyle(
                  color: AppColors.textSecondary(context).withValues(alpha: 0.35),
                  fontSize: 10,
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              _masterExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: AppColors.textSecondary(context).withValues(alpha: 0.35),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < entries.length; i++)
          _buildEntryRow(entries[i], i, entries.length, context),
      ],
    );
  }

  Widget _buildEntryRow(ThreadEntry entry, int index, int count, BuildContext context) {
    final isLast = index == count - 1;

    return Padding(
      padding: EdgeInsets.only(
        left: 4,
        top: index == 0 ? 0 : 1,
        bottom: isLast ? 0 : 1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 8),
            child: _buildNode(entry, context),
          ),
          Expanded(
            child: _EntryFadeIn(
              key: ValueKey('entry_$index'),
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
        return Text(
          '●',
          style: TextStyle(
            fontSize: 7,
            color: isStreaming
                ? AppColors.textSecondary(context).withValues(alpha: 0.5)
                : AppColors.textSecondary(context).withValues(alpha: 0.25),
          ),
        );

      case ToolCallEntry(:final isExecuting):
        return Text(
          '▶',
          style: TextStyle(
            fontSize: 7,
            color: isExecuting
                ? AppColors.textSecondary(context).withValues(alpha: 0.5)
                : AppColors.textSecondary(context).withValues(alpha: 0.25),
          ),
        );

      default:
        return const SizedBox.shrink();
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
