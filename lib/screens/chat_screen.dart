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
import '../widgets/thinking_block.dart';
import '../widgets/tool_call_block.dart';
import '../utils/content_parser.dart' show ContentParser;

class ChatScreen extends StatefulWidget {
  final VoidCallback onMenuTap;

  const ChatScreen({super.key, required this.onMenuTap});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollButton = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
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
            _buildContextBar(context),
            Expanded(child: _buildMessageList(context)),
            const ChatInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildContextBar(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final info = provider.contextInfo;
    if (info == null || provider.messages.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        border: Border(
          bottom: BorderSide(color: AppColors.border(context), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.list_alt_rounded,
              size: 11, color: AppColors.textSecondary(context).withValues(alpha: 0.5)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              info,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary(context).withValues(alpha: 0.5),
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Consumer2<ChatProvider, SettingsProvider>(
      builder: (context, provider, settings, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.background(context),
            border: Border(
              bottom: BorderSide(color: AppColors.border(context), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onMenuTap,
                icon: Icon(Icons.menu_rounded,
                    color: AppColors.textSecondary(context)),
                splashRadius: 20,
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 4),
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
              if (provider.currentChat != null)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz_rounded,
                      color: AppColors.textSecondary(context)),
                  color: AppColors.surface(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppColors.border(context)),
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
                          SizedBox(width: 8),
                          Text('Delete chat',
                              style: TextStyle(color: AppColors.error)),
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final maxScroll = _scrollController.position.maxScrollExtent;
            final currentScroll = _scrollController.offset;
            if (maxScroll - currentScroll < 150) {
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

        return Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              itemCount: provider.messages.length,
              itemBuilder: (context, index) {
                final message = provider.messages[index];
                final isStreaming = provider.isGenerating &&
                    index == provider.messages.length - 1 &&
                    message.isAssistant;

                if (isStreaming && message.content.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: TypingIndicator(),
                  );
                }

                return RepaintBoundary(
                  child: Padding(
                    key: ValueKey(message.id),
                    padding: EdgeInsets.only(
                    bottom: message.isUser ? 12 : 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.isUser)
                        UserBubble(text: message.content)
                      else ...[
                        ..._buildContentSegments(context, message, isStreaming),
                      ],
                    ],
                  ),
                ),
              );
              },
            ),
            if (_showScrollButton)
              Positioned(
                bottom: 8,
                right: 16,
                child: GestureDetector(
                  onTap: _scrollToBottom,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surface(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border(context)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      color: AppColors.textSecondary(context),
                      size: 20,
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

    // Native reasoning from provider API
    if (message.reasoning != null && message.reasoning!.isNotEmpty) {
      segments.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ThinkingBlock(
          content: message.reasoning!,
          isStreaming: isStreaming && message.content.isEmpty,
        ),
      ));
    }

    // Tool calls
    if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
      for (final tc in message.toolCalls!) {
        segments.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ToolCallBlock(
            toolCall: tc,
            isStreaming: !tc.completed && !tc.error,
          ),
        ));
      }
    }

    // Always parse content for think tags — handles both streaming chunks
    // and legacy messages in one unified path
    final sanitized = ContentParser.sanitize(message.content);
    final result = ContentParser.parse(sanitized);
    bool hasTextSegments = false;
    for (final seg in result.segments) {
      if (seg.isThinking) {
        segments.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ThinkingBlock(content: seg.content, isStreaming: false),
        ));
      } else if (seg.content.isNotEmpty) {
        segments.add(AiResponse(content: seg.content, isStreaming: isStreaming));
        hasTextSegments = true;
      }
    }
    if (result.streamingThought != null) {
      segments.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ThinkingBlock(
          content: result.streamingThought!,
          isStreaming: true,
        ),
      ));
    }

    // If no thinking at all, show content directly
    if (!hasTextSegments &&
        result.streamingThought == null &&
        message.content.isNotEmpty &&
        (message.reasoning == null || message.reasoning!.isEmpty)) {
      segments.add(AiResponse(content: message.content, isStreaming: isStreaming));
    }

    return segments;
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 24),
            Text(
              'How can I help you today?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Ask me anything — I\'m here to assist!',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildSuggestionChip(context, 'Explain quantum computing like I\'m 10'),
                _buildSuggestionChip(context, 'Write a poem about the future of AI'),
                _buildSuggestionChip(context, 'Help me plan a 5-day trip to Japan'),
                _buildSuggestionChip(context, 'What\'s the meaning of life?'),
                _buildSuggestionChip(context, 'Debug this Flutter code: final list = [1, 2, 3]; list.add(4);'),
                _buildSuggestionChip(context, 'Tell me a mind-blowing science fact'),
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
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
