import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import 'tool_categories_sheet.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  late AnimationController _morphController;
  late Animation<double> _morphAnimation;

  bool _hasText = false;

  static const double _collapsedHeight = 52;
  static const double _expandedHeight = 180;
  static const double _collapsedRadius = 28;
  static const double _expandedRadius = 24;

  @override
  void initState() {
    super.initState();
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 260),
    );
    _morphAnimation = CurvedAnimation(
      parent: _morphController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _morphController.forward();
      } else {
        if (_controller.text.trim().isEmpty) {
          _morphController.reverse();
        }
      }
    });

    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
    });
  }

  @override
  void dispose() {
    _morphController.dispose();
    _focusNode.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    context.read<ChatProvider>().sendMessage(text);
    _controller.clear();
    setState(() => _hasText = false);
    _focusNode.unfocus();
  }

  void _stop() {
    context.read<ChatProvider>().cancelGeneration();
  }

  bool _isProviderConfigured(SettingsProvider settings) {
    return settings.hasApiKey &&
        settings.modelsLoaded &&
        settings.favoriteModels.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    if (!_isProviderConfigured(settings)) {
      return _buildUnconfiguredState();
    }

    return AnimatedBuilder(
      animation: _morphAnimation,
      builder: (context, child) {
        final t = _morphAnimation.value;
        final isExpanded = t > 0.01;

        final currentHeight =
            _collapsedHeight + (_expandedHeight - _collapsedHeight) * t;
        final currentRadius =
            _collapsedRadius + (_expandedRadius - _collapsedRadius) * t;

        return Container(
          margin: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            8 + MediaQuery.of(context).padding.bottom * t,
          ),
          child: Container(
            height: currentHeight,
            constraints: isExpanded
                ? const BoxConstraints(maxHeight: _expandedHeight)
                : null,
            decoration: BoxDecoration(
              color: AppColors.pillBg(context),
              borderRadius: BorderRadius.circular(currentRadius),
              border: Border.all(
                color: isExpanded
                    ? AppColors.primary.withValues(alpha: 0.3 * t + 0.1)
                    : AppColors.border(context).withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08 + 0.04 * t),
                  blurRadius: 16 + 8 * t,
                  offset: Offset(0, 2 + 4 * t),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(currentRadius),
              child: isExpanded
                  ? _buildExpandedLayout(t)
                  : _buildCollapsedLayout(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollapsedLayout() {
    final isGenerating = context.watch<ChatProvider>().isGenerating;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          _buildPlusButton(size: 36),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              onTap: () {
                _morphController.forward();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _focusNode.requestFocus();
                });
              },
              child: Text(
                'Type a message...',
                style: TextStyle(
                  color: AppColors.textSecondary(context).withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          if (!isGenerating) ...[
            _buildMicButton(size: 36),
            const SizedBox(width: 4),
            _buildSendButton(size: 36),
          ],
          if (isGenerating) ...[
            _buildMicButton(size: 36),
            const SizedBox(width: 4),
            _buildStopButton(size: 36),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedLayout(double t) {
    final isGenerating = context.watch<ChatProvider>().isGenerating;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            scrollController: _scrollController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            textInputAction: TextInputAction.newline,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Type a message...',
              hintStyle: TextStyle(
                color:
                    AppColors.textSecondary(context).withValues(alpha: 0.6),
                fontWeight: FontWeight.w400,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              isDense: true,
            ),
            onSubmitted: isGenerating ? null : (_) => _send(),
          ),
        ),
        _buildExpandedToolbar(isGenerating),
      ],
    );
  }

  Widget _buildExpandedToolbar(bool isGenerating) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: Row(
        children: [
          _buildPlusButton(size: 34),
          const Spacer(),
          if (!isGenerating) ...[
            _buildMicButton(size: 34),
            const SizedBox(width: 4),
            _buildSendButton(size: 34),
          ],
          if (isGenerating) ...[
            _buildMicButton(size: 34),
            const SizedBox(width: 4),
            _buildStopButton(size: 34),
          ],
        ],
      ),
    );
  }

  Widget _buildPlusButton({required double size}) {
    return IconButton(
      onPressed: () => ToolCategoriesSheet.show(context),
      icon: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.surface(context).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(size / 2),
        ),
        child: Icon(
          Icons.add_rounded,
          color: AppColors.textSecondary(context),
          size: size * 0.55,
        ),
      ),
      splashRadius: size / 2,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: size,
        minHeight: size,
      ),
    );
  }

  Widget _buildMicButton({required double size}) {
    return IconButton(
      onPressed: () {},
      icon: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.surface(context).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(size / 2),
        ),
        child: Icon(
          Icons.mic_none_rounded,
          color: AppColors.textSecondary(context),
          size: size * 0.55,
        ),
      ),
      splashRadius: size / 2,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: size,
        minHeight: size,
      ),
    );
  }

  Widget _buildSendButton({required double size}) {
    return IconButton(
      onPressed: _send,
      icon: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.sendButton,
          borderRadius: BorderRadius.circular(size / 2),
          boxShadow: [
            BoxShadow(
              color: AppColors.sendButton.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.arrow_upward_rounded,
          color: Colors.white,
          size: size * 0.55,
        ),
      ),
      splashRadius: size / 2,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: size,
        minHeight: size,
      ),
    );
  }

  Widget _buildStopButton({required double size}) {
    return IconButton(
      onPressed: _stop,
      icon: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(size / 2),
          border: Border.all(
            color: AppColors.error.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: const Icon(
          Icons.stop_rounded,
          color: AppColors.error,
        ),
      ),
      splashRadius: size / 2,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: size,
        minHeight: size,
      ),
    );
  }

  Widget _buildUnconfiguredState() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        border: Border(
          top: BorderSide(
            color: AppColors.border(context).withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pushNamed('/models'),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.vpn_key_rounded,
                          color: AppColors.primary, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Set up a provider to start chatting',
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded,
                          color: AppColors.textSecondary(context),
                          size: 14),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
