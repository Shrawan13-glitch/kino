import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/chat_provider.dart';

class ContextIndicator extends StatefulWidget {
  final String? contextInfo;

  const ContextIndicator({super.key, this.contextInfo});

  @override
  State<ContextIndicator> createState() => _ContextIndicatorState();
}

class _ContextIndicatorState extends State<ContextIndicator> {
  Timer? _autoCloseTimer;

  double get _contextPercentage {
    // Parse context info to get percentage
    // Format: "model-name · 12.5K / 128K" or "model-name · 10 / 200K"
    if (widget.contextInfo == null) return 0;
    
    try {
      // Split by · to separate model name from usage
      final parts = widget.contextInfo!.split('·');
      if (parts.length < 2) return 0;
      
      // Get the usage part (e.g., "12.5K / 128K" or "10 / 200K")
      final usage = parts[1].trim();
      final usageParts = usage.split('/');
      if (usageParts.length != 2) return 0;
      
      final usedPart = usageParts[0].trim().toUpperCase();
      final totalPart = usageParts[1].trim().toUpperCase();
      
      // Parse used value
      var used = 0.0;
      if (usedPart.contains('M')) {
        used = (double.tryParse(usedPart.replaceAll('M', '').replaceAll(',', '')) ?? 0) * 1000;
      } else if (usedPart.contains('K')) {
        used = double.tryParse(usedPart.replaceAll('K', '').replaceAll(',', '')) ?? 0;
      } else {
        // Plain number without K or M - treat as actual value
        used = (double.tryParse(usedPart.replaceAll(',', '')) ?? 0) / 1000;
      }
      
      // Parse total value
      var total = 1.0;
      if (totalPart.contains('M')) {
        total = (double.tryParse(totalPart.replaceAll('M', '').replaceAll(',', '')) ?? 1) * 1000;
      } else if (totalPart.contains('K')) {
        total = double.tryParse(totalPart.replaceAll('K', '').replaceAll(',', '')) ?? 1;
      } else {
        // Plain number without K or M - treat as actual value
        total = (double.tryParse(totalPart.replaceAll(',', '')) ?? 1) / 1000;
      }
      
      return (used / total).clamp(0.0, 1.0);
    } catch (e) {
      return 0;
    }
  }

  Color get _contextColor {
    final percentage = _contextPercentage;
    if (percentage < 0.5) return AppColors.success;
    if (percentage < 0.75) return AppColors.accent;
    return AppColors.error;
  }

  void _showContextModal() {
    // Close keyboard before opening modal
    FocusScope.of(context).unfocus();
    
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => const _ContextModal(),
    ).then((_) {
      if (context.mounted) FocusScope.of(context).unfocus();
    });

    // Auto-close after 4 seconds
    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.contextInfo == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: _showContextModal,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                value: _contextPercentage,
                strokeWidth: 2.5,
                backgroundColor:
                    AppColors.border(context).withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(_contextColor),
              ),
            ),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: _contextColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextModal extends StatelessWidget {
  const _ContextModal();

  double _parseContextPercentage(String? contextInfo) {
    // Parse context info to get percentage
    // Format: "model-name · 12.5K / 128K" or "model-name · 10 / 200K"
    if (contextInfo == null) return 0;
    
    try {
      // Split by · to separate model name from usage
      final parts = contextInfo.split('·');
      if (parts.length < 2) return 0;
      
      // Get the usage part (e.g., "12.5K / 128K" or "10 / 200K")
      final usage = parts[1].trim();
      final usageParts = usage.split('/');
      if (usageParts.length != 2) return 0;
      
      final usedPart = usageParts[0].trim().toUpperCase();
      final totalPart = usageParts[1].trim().toUpperCase();
      
      // Parse used value
      var used = 0.0;
      if (usedPart.contains('M')) {
        used = (double.tryParse(usedPart.replaceAll('M', '').replaceAll(',', '')) ?? 0) * 1000;
      } else if (usedPart.contains('K')) {
        used = double.tryParse(usedPart.replaceAll('K', '').replaceAll(',', '')) ?? 0;
      } else {
        // Plain number without K or M - treat as actual value
        used = (double.tryParse(usedPart.replaceAll(',', '')) ?? 0) / 1000;
      }
      
      // Parse total value
      var total = 1.0;
      if (totalPart.contains('M')) {
        total = (double.tryParse(totalPart.replaceAll('M', '').replaceAll(',', '')) ?? 1) * 1000;
      } else if (totalPart.contains('K')) {
        total = double.tryParse(totalPart.replaceAll('K', '').replaceAll(',', '')) ?? 1;
      } else {
        // Plain number without K or M - treat as actual value
        total = (double.tryParse(totalPart.replaceAll(',', '')) ?? 1) / 1000;
      }
      
      return (used / total).clamp(0.0, 1.0);
    } catch (e) {
      return 0;
    }
  }

  Color _getContextColor(double percentage) {
    if (percentage < 0.5) return AppColors.success;
    if (percentage < 0.75) return AppColors.accent;
    return AppColors.error;
  }

  String _getStatusMessage(double percentage) {
    if (percentage < 0.5) {
      return 'Plenty of context available for your conversation';
    } else if (percentage < 0.75) {
      return 'Context usage is moderate, still good room available';
    } else if (percentage < 0.9) {
      return 'Context is getting full, consider starting a new chat';
    } else {
      return 'Context limit nearly reached, new chat recommended';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        final contextInfo = provider.contextInfo ?? '';
        final percentage = _parseContextPercentage(contextInfo);
        final color = _getContextColor(percentage);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.border(context).withValues(alpha: 0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with close button
                Row(
                  children: [
                    Text(
                      'Context Usage',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight(context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Circular progress indicator
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: percentage,
                          strokeWidth: 8,
                          backgroundColor:
                              AppColors.border(context).withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(percentage * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          Text(
                            'used',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Context info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight(context).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              contextInfo,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary(context),
                                fontFamily: 'monospace',
                                letterSpacing: 0.3,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Status message
                Text(
                  _getStatusMessage(percentage),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary(context),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
