import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/chat_provider.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    context.read<ChatProvider>().sendMessage(text);
    _controller.clear();
    setState(() => _hasText = false);
  }

  @override
  Widget build(BuildContext context) {
    final isGenerating = context.watch<ChatProvider>().isGenerating;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        border: Border(
          top: BorderSide(color: AppColors.border(context), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: AppColors.inputBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.border(context),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 15,
                          height: 1.4,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Message ChatMorphism...',
                          hintStyle: TextStyle(
                            color: AppColors.textSecondary(context),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12,
                          ),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    if (_hasText)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4, right: 4),
                        child: AnimatedOpacity(
                          opacity: _hasText ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 150),
                          child: IconButton(
                            onPressed: isGenerating ? null : _send,
                            icon: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AppColors.bubbleGradientStart,
                                    AppColors.bubbleGradientEnd,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: isGenerating
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.arrow_upward_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                            ),
                            splashRadius: 20,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
