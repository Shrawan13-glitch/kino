import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../constants.dart';

class AiResponse extends StatelessWidget {
  final String content;

  const AiResponse({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        padding: const EdgeInsets.only(right: 24),
        child: MarkdownBody(
          data: content,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            h1: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
            h2: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 19,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
            h3: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
            p: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 15,
              height: 1.6,
            ),
            strong: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
            em: TextStyle(
              fontStyle: FontStyle.italic,
              color: AppColors.textSecondary(context),
            ),
            code: TextStyle(
              backgroundColor: AppColors.surfaceLight(context),
              color: AppColors.accent,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            codeblockDecoration: BoxDecoration(
              color: AppColors.surfaceLight(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border(context)),
            ),
            codeblockPadding: const EdgeInsets.all(16),
            blockquoteDecoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: const Border(
                left: BorderSide(
                  color: AppColors.primary,
                  width: 3,
                ),
              ),
            ),
            blockquotePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            listBullet: const TextStyle(
              color: AppColors.primary,
              fontSize: 15,
            ),
            tableHead: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
            tableBody: TextStyle(
              color: AppColors.textSecondary(context),
            ),
            tableBorder: TableBorder.all(
              color: AppColors.border(context),
              width: 0.5,
            ),
            tableCellsPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8,
            ),
            horizontalRuleDecoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppColors.border(context),
                  width: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
