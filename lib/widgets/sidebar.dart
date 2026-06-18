import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../providers/chat_provider.dart';
import '../screens/debug_screen.dart';

class Sidebar extends StatelessWidget {
  final VoidCallback onClose;

  const Sidebar({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: AppColors.sidebarBg(context),
        border: Border(
          right: BorderSide(color: AppColors.border(context), width: 0.5),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          const SizedBox(height: 8),
          _buildNewChatButton(context),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(child: _buildChatList(context)),
          const Divider(height: 1),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 56, 12, 0),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome,
              color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Text(
            'ChatMorphism',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary(context),
                ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close,
                color: AppColors.textSecondary(context)),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildNewChatButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: () {
            context.read<ChatProvider>().createChat();
            onClose();
          },
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('New Chat'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimary(context),
            backgroundColor: AppColors.surfaceLight(context),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.border(context)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatList(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        if (provider.chats.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline,
                    color: AppColors.textSecondary(context).withValues(alpha: 0.4),
                    size: 40),
                const SizedBox(height: 12),
                Text(
                  'No conversations yet',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary(context).withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: provider.chats.length,
          itemBuilder: (context, index) {
            final chat = provider.chats[index];
            final isActive = chat.id == provider.currentChat?.id;
            return _ChatTile(
              chat: chat,
              isActive: isActive,
              onTap: () {
                provider.selectChat(chat.id);
                onClose();
              },
              onDelete: () => provider.deleteChat(chat.id),
            );
          },
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed('/marketplace');
            },
            icon: const Icon(Icons.store_outlined, size: 20),
            label: const Text('Marketplace'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary(context),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed('/vfs');
            },
            icon: const Icon(Icons.folder_outlined, size: 20),
            label: const Text('Files'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary(context),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed('/settings');
            },
            icon: const Icon(Icons.settings_outlined, size: 20),
            label: const Text('Settings'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary(context),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DebugScreen()),
              );
            },
            icon: Icon(Icons.bug_report_outlined,
                size: 18, color: AppColors.textSecondary(context).withValues(alpha: 0.5)),
            label: Text('Debug',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context).withValues(alpha: 0.5))),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final dynamic chat;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ChatTile({
    required this.chat,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d').format(chat.updatedAt);
    final activeTextColor = isActive
        ? AppColors.primary
        : AppColors.textSecondary(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 18,
                  color: activeTextColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w400,
                          color: isActive
                              ? AppColors.textPrimary(context)
                              : AppColors.textSecondary(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isActive)
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.primary.withValues(alpha: 0.6),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
