import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../providers/chat_provider.dart';
import '../screens/debug_screen.dart';

class Sidebar extends StatefulWidget {
  final VoidCallback onClose;

  const Sidebar({super.key, required this.onClose});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, // Full width
      decoration: BoxDecoration(
        color: AppColors.sidebarBg(context),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          const SizedBox(height: 12),
          Expanded(child: _buildChatList(context)),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 56, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Kino',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {
                  context.read<ChatProvider>().createChat();
                  widget.onClose();
                },
                icon: Icon(Icons.add_rounded,
                    color: AppColors.textPrimary(context)),
                splashRadius: 20,
                tooltip: 'New Chat',
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: Icon(Icons.close,
                    color: AppColors.textSecondary(context)),
                splashRadius: 20,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary(context),
            ),
            decoration: InputDecoration(
              hintText: 'Search chats...',
              hintStyle: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary(context).withValues(alpha: 0.5),
              ),
              prefixIcon: Icon(Icons.search_rounded,
                  size: 20, color: AppColors.textSecondary(context)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded,
                          size: 18,
                          color: AppColors.textSecondary(context)),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.inputBg(context),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        final chats = _searchQuery.isEmpty
            ? provider.chats
            : provider.chats
                .where((c) => c.title.toLowerCase().contains(_searchQuery))
                .toList();

        if (chats.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline,
                    color: AppColors.textSecondary(context).withValues(alpha: 0.4),
                    size: 40),
                const SizedBox(height: 12),
                Text(
                  _searchQuery.isNotEmpty
                      ? 'No matching chats'
                      : 'No conversations yet',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary(context).withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          itemCount: chats.length,
          itemBuilder: (context, index) {
            final chat = chats[index];
            final isActive = chat.id == provider.currentChat?.id;
            return _ChatTile(
              chat: chat,
              isActive: isActive,
              onTap: () {
                provider.selectChat(chat.id);
                widget.onClose();
              },
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
          _footerButton(
            context,
            icon: Icons.store_outlined,
            label: 'Marketplace',
            onTap: () => Navigator.of(context).pushNamed('/marketplace'),
          ),
          _footerButton(
            context,
            icon: Icons.folder_outlined,
            label: 'Files',
            onTap: () => Navigator.of(context).pushNamed('/vfs'),
          ),
          _footerButton(
            context,
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => Navigator.of(context).pushNamed('/settings'),
          ),
          _footerButton(
            context,
            icon: Icons.bug_report_outlined,
            label: 'Debug',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DebugScreen()),
            ),
            muted: true,
          ),
        ],
      ),
    );
  }

  Widget _footerButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool muted = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: muted
              ? AppColors.textSecondary(context).withValues(alpha: 0.5)
              : AppColors.textSecondary(context),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: muted
                    ? AppColors.textSecondary(context).withValues(alpha: 0.5)
                    : AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final dynamic chat;
  final bool isActive;
  final VoidCallback onTap;

  const _ChatTile({
    required this.chat,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d').format(chat.updatedAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          onLongPress: () => _showOptions(context),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
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
                          color: AppColors.textSecondary(context)
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isActive)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    final v = Navigator.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: AppColors.textSecondary(context).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.edit_outlined,
                  color: AppColors.textSecondary(context)),
              title: Text('Rename',
                  style: TextStyle(color: AppColors.textPrimary(context))),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.error),
              title: Text('Delete',
                  style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, v);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: chat.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: Text('Rename Chat',
            style: TextStyle(color: AppColors.textPrimary(context))),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Chat name',
            hintStyle: TextStyle(
                color: AppColors.textSecondary(context).withValues(alpha: 0.5)),
          ),
          style: TextStyle(color: AppColors.textPrimary(context)),
          onSubmitted: (_) {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(ctx);
              context.read<ChatProvider>().renameChat(chat.id, controller.text.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary(context))),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                context.read<ChatProvider>().renameChat(chat.id, controller.text.trim());
              }
            },
            child: Text('Rename',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, NavigatorState navigator) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: Text('Delete Chat',
            style: TextStyle(color: AppColors.textPrimary(context))),
        content: Text(
          'Are you sure you want to delete "${chat.title}"?',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary(context))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ChatProvider>().deleteChat(chat.id);
            },
            child: Text('Delete',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
