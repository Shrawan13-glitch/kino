import 'dart:async';
import 'package:flutter/material.dart';
import '../constants.dart';

class ContextIndicator extends StatefulWidget {
  final String? contextInfo;

  const ContextIndicator({super.key, this.contextInfo});

  @override
  State<ContextIndicator> createState() => _ContextIndicatorState();
}

class _ContextIndicatorState extends State<ContextIndicator> {
  bool _isExpanded = false;
  Timer? _autoCloseTimer;

  double get _contextPercentage {
    // Parse context info to get percentage
    // Assuming format like "12.5k/128k tokens"
    if (widget.contextInfo == null) return 0;
    
    try {
      final parts = widget.contextInfo!.split('/');
      if (parts.length != 2) return 0;
      
      final usedStr = parts[0].trim().replaceAll('k', '').replaceAll(',', '');
      final totalStr = parts[1].trim().split(' ')[0].replaceAll('k', '').replaceAll(',', '');
      
      final used = double.tryParse(usedStr) ?? 0;
      final total = double.tryParse(totalStr) ?? 1;
      
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

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });

    if (_isExpanded) {
      _autoCloseTimer?.cancel();
      _autoCloseTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _isExpanded) {
          setState(() {
            _isExpanded = false;
          });
        }
      });
    }
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
      onTap: _toggleExpanded,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: _isExpanded ? 16 : 6,
          vertical: _isExpanded ? 10 : 6,
        ),
        decoration: BoxDecoration(
          color: _isExpanded
              ? AppColors.surfaceLight(context)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(_isExpanded ? 12 : 20),
          border: _isExpanded
              ? Border.all(
                  color: AppColors.border(context).withValues(alpha: 0.3),
                  width: 1,
                )
              : null,
        ),
        child: _isExpanded ? _buildExpandedView() : _buildCircularIndicator(),
      ),
    );
  }

  Widget _buildCircularIndicator() {
    return SizedBox(
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
    );
  }

  Widget _buildExpandedView() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            value: _contextPercentage,
            strokeWidth: 2,
            backgroundColor:
                AppColors.border(context).withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(_contextColor),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          widget.contextInfo!,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
            fontFamily: 'monospace',
            letterSpacing: 0.2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
