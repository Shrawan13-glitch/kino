import 'package:flutter/material.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

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
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {for (int i = 0; i < cols; i++) i: const FixedColumnWidth(280)},
      children: rows.map((row) {
        return TableRow(
          decoration: BoxDecoration(color: row.isHeader ? headerBg : null),
          children: row.fields.map((field) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                field.data,
                style: textStyle.copyWith(
                  fontWeight: row.isHeader ? FontWeight.w600 : null,
                  color: textColor,
                ),
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
