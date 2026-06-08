import 'package:flutter/material.dart';
import '../constants.dart';
import '../utils/markdown/renderer.dart';

class ThinkingBlock extends StatefulWidget {
  final String content;
  final bool isStreaming;

  const ThinkingBlock({
    super.key,
    required this.content,
    this.isStreaming = false,
  });

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    if (widget.isStreaming) {
      _glowController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2000),
      )..repeat();
    }
  }

  @override
  void didUpdateWidget(ThinkingBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStreaming && !oldWidget.isStreaming) {
      _glowController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2000),
      )..repeat();
    } else if (!widget.isStreaming && oldWidget.isStreaming) {
      _glowController.dispose();
    }
  }

  @override
  void dispose() {
    try {
      if (_glowController.isAnimating || _glowController.isCompleted) {
        _glowController.dispose();
      }
    } catch (_) {}
    super.dispose();
  }

  Widget _buildGlowOverlay(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, _) {
        final pos = _glowController.value;
        return Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    AppColors.primary.withValues(alpha: 0.12),
                    Colors.transparent,
                    Colors.transparent,
                  ],
                  stops: [
                    0.0,
                    (pos - 0.15).clamp(0.0, 1.0),
                    pos.clamp(0.0, 1.0),
                    (pos + 0.15).clamp(0.0, 1.0),
                    1.0,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceLight(context).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isStreaming
                  ? AppColors.primary.withValues(alpha: 0.25)
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        '\u{1F4AD}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _expanded ? 'Thinking' : 'Thinking...',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      if (widget.isStreaming)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _buildPulseDot(),
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
                  child: widget.isStreaming
                      ? Text(
                          widget.content +
                              (widget.content.isNotEmpty ? ' ...' : ''),
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 12,
                            height: 1.5,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : MarkdownRender(
                          data: widget.content,
                          style: MarkdownStyle(
                            textColor: AppColors.textSecondary(context),
                            secondaryTextColor: AppColors.textSecondary(context),
                            codeColor: AppColors.accent,
                            codeBackground: AppColors.surfaceLight(context).withValues(alpha: 0.5),
                            bodySize: 12,
                            codeSize: 11,
                            lineHeight: 1.5,
                            blockquoteBar: AppColors.textSecondary(context),
                            blockquoteBg: AppColors.textSecondary(context).withValues(alpha: 0.06),
                            hrColor: AppColors.border(context).withValues(alpha: 0.3),
                            checkboxBorder: AppColors.textSecondary(context).withValues(alpha: 0.4),
                          ),
                        ),
                ),
            ],
          ),
        ),
        if (widget.isStreaming) _buildGlowOverlay(context),
      ],
    );
  }

  Widget _buildPulseDot() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, _) {
        final pulse = (1 - (_glowController.value * 2 - 1).abs()).clamp(0.3, 1.0);
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withValues(alpha: pulse),
          ),
        );
      },
    );
  }
}
