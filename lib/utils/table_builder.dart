import 'package:flutter/material.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

String _cleanCell(String data) {
  return data
      .replaceAll('<br>', '\n')
      .replaceAll('<br/>', '\n')
      .replaceAll('<br />', '\n')
      .replaceAll('<BR>', '\n')
      .replaceAll('</br>', '');
}

Widget tableWidget(
  BuildContext context,
  List<CustomTableRow> rows,
  TextStyle textStyle,
  GptMarkdownConfig config,
) {
  final ts = Theme.of(context);
  final border = ts.dividerColor;
  final headerBg = ts.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
  final textColor = ts.colorScheme.onSurface;
  final cols = rows.isEmpty ? 1 : rows.first.fields.length;

  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: TableBorder(
          horizontalInside: BorderSide(color: border, width: 0.5),
          verticalInside: BorderSide(color: border, width: 0.5),
        ),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        columnWidths: {
          for (int i = 0; i < cols; i++)
            i: MaxColumnWidth(
              IntrinsicColumnWidth(),
              FixedColumnWidth(100),
            ),
        },
        children: rows.map((row) {
          return TableRow(
            decoration: BoxDecoration(color: row.isHeader ? headerBg : null),
            children: row.fields.map((field) {
              final content = _cleanCell(field.data);
              final spans = MarkdownComponent.generate(
                context,
                content,
                config,
                true,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text.rich(
                  TextSpan(children: spans),
                  style: row.isHeader
                      ? textStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        )
                      : textStyle.copyWith(color: textColor),
                  textAlign: field.alignment,
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    ),
  );
}
