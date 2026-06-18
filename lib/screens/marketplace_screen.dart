import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/vfs_provider.dart';
import '../services/tool_registry.dart';
import '../services/tool_repository_service.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final _searchController = TextEditingController();
  final _repoUrlController = TextEditingController();
  String _searchQuery = '';
  bool _refreshing = false;
  String? _installingTool;

  @override
  void dispose() {
    _searchController.dispose();
    _repoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = context.watch<ToolRegistry>();
    final repo = context.read<ToolRepositoryService>();

    final filtered = _searchQuery.isEmpty
        ? registry.tools
        : registry.tools
            .where((t) =>
                t.name.contains(_searchQuery.toLowerCase()) ||
                t.description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                t.categories.any((c) => c.contains(_searchQuery.toLowerCase())))
            .toList();

    final installed = filtered.where((t) => registry.isInstalled(t.name)).toList();
    final available = filtered.where((t) => !registry.isInstalled(t.name)).toList();

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Tool Marketplace',
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_refreshing)
            Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.refresh_rounded,
                  color: AppColors.textSecondary(context)),
              onPressed: () => _refreshTools(context),
              tooltip: 'Refresh from repository',
            ),
          IconButton(
            icon: Icon(Icons.link,
                color: AppColors.textSecondary(context)),
            onPressed: () => _showRepoDialog(context, repo),
            tooltip: 'Set repository URL',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(context),
          if (!registry.hasLoaded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14,
                      color: AppColors.textSecondary(context).withValues(alpha: 0.5)),
                  const SizedBox(width: 6),
                  Text(
                    'Using built-in defaults — connect to repository for latest',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary(context).withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          if (registry.tools.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.store_outlined, size: 56,
                        color: AppColors.textSecondary(context).withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text('No tools found',
                        style: TextStyle(
                            color: AppColors.textSecondary(context).withValues(alpha: 0.6))),
                    if (_searchQuery.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: const Text('Clear search'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  if (installed.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Text('INSTALLED (${installed.length})',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary(context).withValues(alpha: 0.5),
                              letterSpacing: 1)),
                    ),
                    ...installed.map((t) => _ToolCard(
                          tool: t,
                          installed: true,
                          installing: _installingTool == t.name,
                          onInstall: null,
                          onUninstall: () => _uninstallTool(context, t.name),
                        )),
                    if (available.isNotEmpty) const SizedBox(height: 16),
                  ],
                  if (available.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Text('AVAILABLE (${available.length})',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary(context).withValues(alpha: 0.5),
                              letterSpacing: 1)),
                    ),
                    ...available.map((t) => _ToolCard(
                          tool: t,
                          installed: false,
                          installing: _installingTool == t.name,
                          onInstall: () => _installTool(context, t.name),
                          onUninstall: null,
                        )),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
        style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search tools...',
          hintStyle: TextStyle(
              color: AppColors.textSecondary(context).withValues(alpha: 0.5)),
          prefixIcon: Icon(Icons.search_rounded,
              color: AppColors.textSecondary(context), size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded,
                      color: AppColors.textSecondary(context), size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surface(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        ),
      ),
    );
  }

  Future<void> _refreshTools(BuildContext context) async {
    setState(() => _refreshing = true);
    final repo = context.read<ToolRepositoryService>();
    final registry = context.read<ToolRegistry>();
    await repo.loadIntoRegistry(registry);
    setState(() => _refreshing = false);
  }

  void _showRepoDialog(BuildContext context, ToolRepositoryService repo) {
    _repoUrlController.text = repo.repoUrl;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: Text('Repository URL',
            style: TextStyle(color: AppColors.textPrimary(context))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GitHub repo URL containing a tools.json manifest',
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context).withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _repoUrlController,
              autofocus: true,
              style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://raw.githubusercontent.com/...',
                hintStyle: TextStyle(
                    color: AppColors.textSecondary(context).withValues(alpha: 0.4)),
                filled: true,
                fillColor: AppColors.surfaceLight(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border(context)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary(context))),
          ),
          TextButton(
            onPressed: () {
              final url = _repoUrlController.text.trim();
              if (url.isNotEmpty) {
                repo.setRepoUrl(url);
                Navigator.pop(ctx);
                repo.loadIntoRegistry(context.read<ToolRegistry>());
              }
            },
            child: Text('Save',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _installTool(BuildContext context, String toolName) {
    setState(() => _installingTool = toolName);
    final vfs = context.read<VfsProvider>();
    final messenger = ScaffoldMessenger.of(context);

    vfs.installTool(toolName).then((_) {
      if (!mounted) return;
      setState(() => _installingTool = null);
      if (vfs.error != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(vfs.error!),
              backgroundColor: AppColors.error),
        );
      }
    });
  }

  void _uninstallTool(BuildContext context, String toolName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: Text('Uninstall $toolName?',
            style: TextStyle(color: AppColors.textPrimary(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary(context))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ToolRegistry>().markUninstalled(toolName);
            },
            child: Text('Uninstall',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final ToolDefinition tool;
  final bool installed;
  final bool installing;
  final VoidCallback? onInstall;
  final VoidCallback? onUninstall;

  const _ToolCard({
    required this.tool,
    required this.installed,
    required this.installing,
    this.onInstall,
    this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surfaceLight(context),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: installed
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.border(context),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.build_outlined,
              color: AppColors.primary, size: 22),
        ),
        title: Text(
          tool.name,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tool.description,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                _MarketTag(text: tool.version),
                _MarketTag(text: tool.sizeFormatted),
                ...tool.categories.take(2).map((c) => _MarketTag(text: c)),
                _MarketTag(text: tool.installTypeLabel),
              ],
            ),
          ],
        ),
        trailing: installing
            ? SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary))
            : installed
                ? IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: AppColors.textSecondary(context), size: 20),
                    onPressed: onUninstall,
                    tooltip: 'Uninstall',
                  )
                : TextButton(
                    onPressed: onInstall,
                    child: Text('Install',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ),
      ),
    );
  }
}

class _MarketTag extends StatelessWidget {
  final String text;
  const _MarketTag({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.border(context).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: AppColors.textSecondary(context),
        ),
      ),
    );
  }
}
