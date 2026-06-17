import 'package:flutter/material.dart';
import '../constants.dart';
import '../services/debug_service.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final _scrollController = ScrollController();
  String _filter = '';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = DebugService.instance.logs;
    final filtered = _filter.isEmpty
        ? logs
        : logs.where((l) => l.message.toLowerCase().contains(_filter.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        title: Text('Debug Logs',
            style: TextStyle(color: AppColors.textPrimary(context))),
        iconTheme:
            IconThemeData(color: AppColors.textSecondary(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.error),
            onPressed: () {
              DebugService.instance.clear();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Filter logs...',
                hintStyle: TextStyle(
                    color: AppColors.textSecondary(context).withValues(alpha: 0.5)),
                prefixIcon: Icon(Icons.search,
                    color: AppColors.textSecondary(context).withValues(alpha: 0.5),
                    size: 20),
                filled: true,
                fillColor: AppColors.surfaceLight(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 13,
                fontFamily: 'monospace',
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No logs',
                      style: TextStyle(
                          color: AppColors.textSecondary(context).withValues(alpha: 0.5)),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final entry = filtered[i];
                      final color = switch (entry.level) {
                        'ERROR' => AppColors.error,
                        'WARN' => AppColors.primary,
                        _ => AppColors.textSecondary(context),
                      };
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: GestureDetector(
                          onLongPress: () {
                            if (entry.stackTrace != null) {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: AppColors.surface(context),
                                  content: SingleChildScrollView(
                                    child: SelectableText(
                                      entry.stackTrace!,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                        color: AppColors.textPrimary(ctx),
                                      ),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                          child: Text(
                            entry.formatted,
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: color,
                              height: 1.4,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
