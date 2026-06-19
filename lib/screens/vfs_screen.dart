import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/vfs_provider.dart';
import '../services/vfs/vfs_node.dart';

class VfsScreen extends StatefulWidget {
  final String initialPath;
  const VfsScreen({super.key, this.initialPath = '/'});

  @override
  State<VfsScreen> createState() => _VfsScreenState();
}

class _VfsScreenState extends State<VfsScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vfs = context.read<VfsProvider>();
      if (vfs.currentPath != widget.initialPath) {
        vfs.navigateTo(widget.initialPath);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VfsProvider>(
      builder: (context, vfs, _) {
        return PopScope(
          canPop: vfs.currentPath == '/',
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              vfs.navigateUp();
            }
          },
          child: Scaffold(
            backgroundColor: AppColors.background(context),
            appBar: _buildAppBar(context, vfs),
            body: Column(
              children: [
                _buildBreadcrumb(context, vfs),
                _buildStatusBar(vfs),
                Expanded(
                  child: _buildBody(context, vfs),
                ),
              ],
            ),
            floatingActionButton: _buildFab(context, vfs),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, VfsProvider vfs) {
    return AppBar(
      backgroundColor: AppColors.surface(context),
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () {
          if (vfs.currentPath == '/') {
            Navigator.of(context).maybePop();
          } else {
            vfs.navigateUp();
          }
        },
      ),
      title: Text(
        vfs.currentDirName,
        style: TextStyle(
          color: AppColors.textPrimary(context),
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      actions: [
        if (vfs.hasClipboard)
          IconButton(
            icon: Icon(Icons.paste_rounded,
                color: AppColors.primary),
            onPressed: () => vfs.paste(),
            tooltip: 'Paste here',
          ),
        if (vfs.hasClipboard)
          IconButton(
            icon: Icon(Icons.close,
                color: AppColors.textSecondary(context), size: 18),
            onPressed: () => vfs.clearClipboard(),
            tooltip: 'Clear clipboard',
          ),
        IconButton(
          icon: Icon(Icons.refresh_rounded,
              color: AppColors.textSecondary(context)),
          onPressed: () => vfs.refresh(),
        ),
      ],
    );
  }

  Widget _buildBreadcrumb(BuildContext context, VfsProvider vfs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        border: Border(
          bottom: BorderSide(color: AppColors.border(context), width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: vfs.breadcrumbs.map((item) {
            final isLast = item.path == vfs.currentPath;
            return Row(
              children: [
                if (item.path != '/')
                  Icon(Icons.chevron_right,
                      size: 16, color: AppColors.textSecondary(context).withValues(alpha: 0.4)),
                GestureDetector(
                  onTap: isLast ? null : () => vfs.navigateTo(item.path),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
                        color: isLast
                            ? AppColors.primary
                            : AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildStatusBar(VfsProvider vfs) {
    if (vfs.statusMessage == null && vfs.error == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: vfs.error != null
          ? AppColors.error.withValues(alpha: 0.1)
          : AppColors.success.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(
            vfs.error != null ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: vfs.error != null ? AppColors.error : AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              vfs.error ?? vfs.statusMessage ?? '',
              style: TextStyle(
                fontSize: 13,
                color: vfs.error != null
                    ? AppColors.error
                    : AppColors.success,
              ),
            ),
          ),
          if (vfs.error != null)
            GestureDetector(
              onTap: () => context.read<VfsProvider>().refresh(),
              child: Text('Retry',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, VfsProvider vfs) {
    if (vfs.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      );
    }

    if (vfs.entries.isEmpty) {
      return _buildEmptyState(context, vfs);
    }

    return RefreshIndicator(
      onRefresh: () => vfs.refresh(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: vfs.entries.length,
        itemBuilder: (context, index) {
          return _FileTile(
            node: vfs.entries[index],
            onTap: () => _onNodeTap(context, vfs, vfs.entries[index]),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, VfsProvider vfs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 56,
            color: AppColors.textSecondary(context).withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            vfs.currentPath == '/' ? 'VFS is empty' : 'This folder is empty',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary(context).withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to create files and folders',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary(context).withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildFab(BuildContext context, VfsProvider vfs) {
    return FloatingActionButton(
      onPressed: () => _showCreateOptions(context, vfs),
      backgroundColor: AppColors.primary,
      child: const Icon(Icons.add_rounded, color: Colors.white),
    );
  }

  void _onNodeTap(BuildContext context, VfsProvider vfs, VfsNode node) {
    if (node.isDirectory) {
      vfs.navigateTo(node.vfsPath);
    } else if (node.isTextFile) {
      _openTextFile(context, vfs, node);
    } else {
      vfs.share(node.name);
    }
  }

  void _openTextFile(BuildContext context, VfsProvider vfs, VfsNode node) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TextEditorScreen(node: node),
      ),
    );
  }

  void _showCreateOptions(BuildContext context, VfsProvider vfs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.textSecondary(ctx).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
              child: Text('Create New',
                  style: TextStyle(
                      color: AppColors.textPrimary(ctx),
                      fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: Icon(Icons.insert_drive_file_outlined,
                  color: AppColors.textSecondary(ctx)),
              title: Text('File',
                  style: TextStyle(color: AppColors.textPrimary(ctx))),
              onTap: () {
                Navigator.pop(ctx);
                _showCreateDialog(context, vfs, isFile: true);
              },
            ),
            ListTile(
              leading: Icon(Icons.folder_outlined,
                  color: AppColors.textSecondary(ctx)),
              title: Text('Folder',
                  style: TextStyle(color: AppColors.textPrimary(ctx))),
              onTap: () {
                Navigator.pop(ctx);
                _showCreateDialog(context, vfs, isFile: false);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(
      BuildContext context, VfsProvider vfs, {required bool isFile}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: Text(
          isFile ? 'Create File' : 'Create Folder',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isFile ? 'filename.txt' : 'folder name',
            hintStyle: TextStyle(color: AppColors.textSecondary(context).withValues(alpha: 0.5)),
          ),
          style: TextStyle(color: AppColors.textPrimary(context)),
          onSubmitted: (_) {
            if (controller.text.isNotEmpty) {
              Navigator.pop(ctx);
              if (isFile) {
                vfs.createFile(controller.text);
              } else {
                vfs.createDirectory(controller.text);
              }
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
              if (controller.text.isNotEmpty) {
                Navigator.pop(ctx);
                if (isFile) {
                  vfs.createFile(controller.text);
                } else {
                  vfs.createDirectory(controller.text);
                }
              }
            },
            child: Text('Create',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

}

class _FileTile extends StatelessWidget {
  final VfsNode node;
  final VoidCallback onTap;

  const _FileTile({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final iconData = _iconForNode(node);
    final iconColor = node.isDirectory
        ? AppColors.accent
        : AppColors.textSecondary(context);

    return GestureDetector(
      onLongPress: () {
        final vfs = context.read<VfsProvider>();
        showModalBottomSheet(
          context: context,
          backgroundColor: AppColors.surface(context),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => _buildOptionsSheet(ctx, vfs),
        );
      },
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(iconData, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (node.sizeFormatted.isNotEmpty)
                      Text(
                        node.sizeFormatted,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary(context).withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                node.modifiedFormatted,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context).withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionsSheet(BuildContext context, VfsProvider vfs) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.textSecondary(context).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                Icon(_iconForNode(node),
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (!node.isDirectory) ...[
            ListTile(
              leading: Icon(Icons.share_outlined,
                  color: AppColors.textSecondary(context)),
              title: Text('Share',
                  style: TextStyle(color: AppColors.textPrimary(context))),
              onTap: () {
                Navigator.pop(context);
                vfs.share(node.name);
              },
            ),
            ListTile(
              leading: Icon(Icons.download_outlined,
                  color: AppColors.textSecondary(context)),
              title: Text('Download to device',
                  style: TextStyle(color: AppColors.textPrimary(context))),
              onTap: () {
                Navigator.pop(context);
                vfs.downloadToDevice(node.name);
              },
            ),
          ],
          ListTile(
            leading: Icon(Icons.copy_outlined,
                color: AppColors.textSecondary(context)),
            title:
                Text('Copy', style: TextStyle(color: AppColors.textPrimary(context))),
            onTap: () {
              Navigator.pop(context);
              vfs.copy(node.name);
            },
          ),
          ListTile(
            leading: Icon(Icons.content_cut_outlined,
                color: AppColors.textSecondary(context)),
            title:
                Text('Cut', style: TextStyle(color: AppColors.textPrimary(context))),
            onTap: () {
              Navigator.pop(context);
              vfs.cut(node.name);
            },
          ),
          ListTile(
            leading: Icon(Icons.drive_file_rename_outline,
                color: AppColors.textSecondary(context)),
            title: Text('Rename',
                style: TextStyle(color: AppColors.textPrimary(context))),
            onTap: () {
              Navigator.pop(context);
              _showRenameDialog(context, vfs);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: AppColors.error),
            title: Text('Delete', style: TextStyle(color: AppColors.error)),
            onTap: () {
              Navigator.pop(context);
              _confirmDelete(context, vfs);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, VfsProvider vfs) {
    final controller = TextEditingController(text: node.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: Text('Rename',
            style: TextStyle(color: AppColors.textPrimary(context))),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'New name',
            hintStyle: TextStyle(
                color: AppColors.textSecondary(context).withValues(alpha: 0.5)),
          ),
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary(context))),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty &&
                  controller.text != node.name) {
                Navigator.pop(ctx);
                vfs.rename(node.name, controller.text);
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

  void _confirmDelete(BuildContext context, VfsProvider vfs) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: Text('Delete',
            style: TextStyle(color: AppColors.textPrimary(context))),
        content: Text(
          node.isDirectory
              ? 'Delete "${node.name}" and all its contents?'
              : 'Delete "${node.name}"?',
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
              vfs.delete(node.name);
            },
            child: Text('Delete',
                style:
                    TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _TextEditorScreen extends StatefulWidget {
  final VfsNode node;
  const _TextEditorScreen({required this.node});

  @override
  State<_TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<_TextEditorScreen> {
  late TextEditingController _controller;
  bool _hasChanges = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final vfs = context.read<VfsProvider>();
      final content = await vfs.readFile(widget.node.name);
      _controller.text = content;
    } catch (_) {
      _controller.text = '// Error loading file';
    }
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_hasChanges) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surface(context),
                  title: Text('Unsaved changes',
                      style: TextStyle(
                          color: AppColors.textPrimary(context))),
                  content: Text('Save before leaving?',
                      style: TextStyle(
                          color: AppColors.textSecondary(context))),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                      },
                      child: Text('Discard',
                          style: TextStyle(color: AppColors.error)),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _saveAndExit();
                      },
                      child: Text('Save',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              );
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          widget.node.name,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        actions: [
          if (_hasChanges)
            TextButton.icon(
              onPressed: _saveAndExit,
              icon: Icon(Icons.save_rounded,
                  color: AppColors.primary, size: 18),
              label: Text('Save',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                color: AppColors.textPrimary(context),
                height: 1.5,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
                filled: false,
              ),
              onChanged: (_) {
                if (!_hasChanges) setState(() => _hasChanges = true);
              },
            ),
    );
  }

  Future<void> _saveAndExit() async {
    final vfs = context.read<VfsProvider>();
    await vfs.writeFile(widget.node.name, _controller.text);
    if (mounted) Navigator.pop(context);
  }
}

IconData _iconForNode(VfsNode node) {
  if (node.isDirectory) return Icons.folder_rounded;

  switch (node.extension) {
    case 'dart':
    case 'py':
    case 'js':
    case 'ts':
    case 'java':
    case 'kt':
    case 'swift':
    case 'go':
    case 'rs':
    case 'rb':
      return Icons.code_rounded;
    case 'md':
      return Icons.article_rounded;
    case 'json':
    case 'xml':
    case 'yaml':
    case 'yml':
    case 'csv':
    case 'toml':
      return Icons.data_object_rounded;
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
    case 'svg':
      return Icons.image_rounded;
    case 'mp4':
    case 'avi':
    case 'mkv':
    case 'mov':
    case 'webm':
      return Icons.videocam_rounded;
    case 'mp3':
    case 'wav':
    case 'ogg':
    case 'flac':
      return Icons.audiotrack_rounded;
    case 'zip':
    case 'tar':
    case 'gz':
    case 'rar':
    case '7z':
      return Icons.folder_zip_rounded;
    case 'pdf':
      return Icons.picture_as_pdf_rounded;
    case 'html':
    case 'htm':
      return Icons.web_rounded;
    case 'sh':
    case 'bash':
      return Icons.terminal_rounded;
    case 'sql':
    case 'db':
    case 'sqlite':
      return Icons.storage_rounded;
    case 'env':
      return Icons.settings_rounded;
    case 'log':
      return Icons.article_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}
