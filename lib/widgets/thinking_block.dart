import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../constants.dart';
import '../utils/table_builder.dart';
import '../utils/blockquote_component.dart';

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

class _ThinkingBlockState extends State<ThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight(context).withValues(alpha: 0.12),
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
                  Text(
                    'thought',
                    style: TextStyle(
                      color: AppColors.textSecondary(context).withValues(alpha: 0.5),
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  if (widget.isStreaming && widget.content.isEmpty)
                    Text(
                      '...',
                      style: TextStyle(
                        color: AppColors.textSecondary(context).withValues(alpha: 0.35),
                        fontSize: 10,
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
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
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
                  : GptMarkdown(
                      widget.content,
                      tableBuilder: tableWidget,
                      components: [
                        ...MarkdownComponent.globalComponents.where((c) => c is! BlockQuote),
                        BeautifulBlockQuote(),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
