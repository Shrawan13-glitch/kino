import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/message.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/user_bubble.dart';
import '../widgets/ai_response.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/model_selector.dart';
import '../widgets/work_thread.dart';
import '../widgets/message_actions.dart';
import '../widgets/context_indicator.dart';
import '../models/thread_entry.dart';

class ChatScreen extends StatefulWidget {
  final VoidCallback onMenuTap;

  const ChatScreen({super.key, required this.onMenuTap});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollButton = false;
  Timer? _scrollDebounce;
  final Map<String, GlobalKey> _messageKeys = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scrollController.hasClients &&
        _scrollController.offset <
            _scrollController.position.maxScrollExtent - 200;
    if (show != _showScrollButton) {
      setState(() => _showScrollButton = show);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Stack(
                children: [
                  _buildMessageList(context),
                  // Fade effect at top
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 20,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.background(context),
                              AppColors.background(context).withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const ChatInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Consumer2<ChatProvider, SettingsProvider>(
      builder: (context, provider, settings, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.background(context).withValues(alpha: 0.95),
            border: Border(
              bottom: BorderSide(
                color: AppColors.border(context).withValues(alpha: 0.1),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // Left side - Menu button
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: widget.onMenuTap,
                  icon: Icon(Icons.menu_rounded,
                      color: AppColors.textPrimary(context), size: 22),
                  splashRadius: 20,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              ),
              
              // Center - Model selector
              Expanded(
                child: Center(
                  child: ModelSelector(
                    currentModelId: provider.currentChat?.model,
                    onModelChanged: (modelId) {
                      if (provider.currentChat != null) {
                        provider.setChatModel(modelId);
                      } else {
                        settings.setDefaultModel(modelId);
                      }
                    },
                  ),
                ),
              ),
              
              // Right side - Context indicator and menu
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (provider.contextInfo != null && provider.messages.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ContextIndicator(contextInfo: provider.contextInfo),
                    ),
                  if (provider.currentChat != null)
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded,
                            color: AppColors.textPrimary(context), size: 20),
                        color: AppColors.surface(context),
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: AppColors.border(context).withValues(alpha: 0.3),
                          ),
                        ),
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        onSelected: (value) {
                          if (value == 'delete') {
                            _showDeleteConfirmation(context);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline,
                                    color: AppColors.error, size: 20),
                                SizedBox(width: 12),
                                Text('Delete chat',
                                    style: TextStyle(color: AppColors.error)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageList(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        _scrollDebounce?.cancel();
        _scrollDebounce = Timer(const Duration(milliseconds: 80), () {
          if (!_scrollController.hasClients) return;
          final maxScroll = _scrollController.position.maxScrollExtent;
          final currentScroll = _scrollController.offset;
          if (maxScroll - currentScroll < 150) {
            if (provider.isGenerating) {
              _scrollController.jumpTo(maxScroll);
            } else {
              _scrollController.animateTo(
                maxScroll,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
              );
            }
          }
        });

        if (provider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }

        if (provider.messages.isEmpty && !provider.isGenerating) {
          return _buildEmptyState(context);
        }

        // Clean up stale message keys
        _messageKeys.removeWhere((id, _) =>
            !provider.messages.any((m) => m.id == id));

        return Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              itemCount: provider.messages.length,
              itemBuilder: (context, index) {
                final message = provider.messages[index];
                final isAssistant = message.isAssistant;
                final isStreaming = provider.isGenerating &&
                    index == provider.messages.length - 1 &&
                    message.isAssistant;

                if (isStreaming && message.entries.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: TypingIndicator(),
                  );
                }

                final repaintKey = isAssistant
                    ? _messageKeys.putIfAbsent(message.id, () => GlobalKey())
                    : null;

                return RepaintBoundary(
                  key: repaintKey,
                  child: Padding(
                    key: ValueKey(message.id),
                    padding: EdgeInsets.only(
                    bottom: message.isUser ? 16 : 28,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.isUser)
                        UserBubble(text: message.content)
                      else ...[
                        ..._buildContentSegments(context, message, isStreaming),
                        if (!isStreaming &&
                            message.entries.any((e) => e is TextEntry) &&
                            repaintKey != null)
                          MessageActions(
                            content: message.content,
                            repaintKey: repaintKey,
                            onRetry: () =>
                                provider.retryFromMessage(message.id),
                          ),
                      ],
                    ],
                  ),
                ),
              );
              },
            ),
            if (_showScrollButton)
              Positioned(
                bottom: 16,
                right: 20,
                child: GestureDetector(
                  onTap: _scrollToBottom,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surface(context).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.border(context).withValues(alpha: 0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary(context),
                      size: 24,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _buildContentSegments(
      BuildContext context, Message message, bool isStreaming) {
    final segments = <Widget>[];
    final workBuffer = <ThreadEntry>[];

    void flushWork() {
      if (workBuffer.isNotEmpty) {
        segments.add(WorkThread(entries: List.from(workBuffer)));
        workBuffer.clear();
      }
    }

    for (final entry in message.entries) {
      switch (entry) {
        case ThinkingEntry():
          workBuffer.add(entry);

        case ToolCallEntry():
          workBuffer.add(entry);

        case TextEntry(:final content, :final isStreaming):
          if (content.trim().isNotEmpty) {
            flushWork();
            segments.add(Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AiResponse(content: content, isStreaming: isStreaming),
            ));
          }
      }
    }
    flushWork();

    return segments;
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AppColors.bubbleGradientStart,
                    AppColors.bubbleGradientEnd,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Start a conversation',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Ask me anything, I\'m here to help',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary(context),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _buildSuggestionChip(context, '✨ Explain quantum computing'),
                _buildSuggestionChip(context, '📝 Write a poem'),
                _buildSuggestionChip(context, '✈️ Plan a trip to Japan'),
                _buildSuggestionChip(context, '🧠 Mind-blowing science fact'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(BuildContext context, String text) {
    return GestureDetector(
      onTap: () {
        context.read<ChatProvider>().sendMessage(text);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.border(context).withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Delete chat?',
            style: TextStyle(color: AppColors.textPrimary(ctx))),
        content: Text(
          'This will permanently delete this conversation.',
          style: TextStyle(color: AppColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary(ctx))),
          ),
          TextButton(
            onPressed: () {
              context.read<ChatProvider>().deleteChat(
                    context.read<ChatProvider>().currentChat!.id,
                  );
              Navigator.of(ctx).pop();
            },
            child: const Text('Delete',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
