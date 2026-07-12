import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/ai_model.dart';
import '../services/openrouter_service.dart';
import '../providers/settings_provider.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  late TextEditingController _apiKeyController;
  late TextEditingController _searchController;
  final _focusNode = FocusNode();
  bool _obscureKey = true;
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  bool _apiKeyExpanded = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _searchController = TextEditingController();
    _apiKeyExpanded = !settings.hasApiKey;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Please enter an API key first');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final models = await OpenRouterService.fetchModels(key);
      if (!mounted) return;
      final settings = context.read<SettingsProvider>();
      await settings.setApiKey(key);
      await settings.setAvailableModels(models);
      setState(() {
        _isLoading = false;
        _apiKeyExpanded = false;
      });
    } on OpenRouterException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to connect: $e';
        _isLoading = false;
      });
    }
  }

  List<String> _getProviderGroups(List<AiModel> models) {
    final providers = <String>{};
    for (final m in models) {
      providers.add(m.provider);
    }
    final sorted = providers.toList()..sort();
    return sorted;
  }

  List<AiModel> _getFilteredModels(SettingsProvider settings, {String? provider}) {
    var models = settings.availableModels;
    if (provider != null) {
      models = models.where((m) => m.provider == provider).toList();
    }
    if (_searchQuery.isEmpty) return models;
    final q = _searchQuery.toLowerCase();
    return models.where((m) {
      return m.id.toLowerCase().contains(q) ||
          m.name.toLowerCase().contains(q) ||
          m.provider.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_rounded,
              color: AppColors.textSecondary(context)),
          splashRadius: 20,
        ),
        title: Text(
          'Providers',
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Divider(height: 0.5, color: AppColors.border(context)),
        ),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildApiKeySection(settings)),
                    if (settings.modelsLoaded) ...[
                      SliverToBoxAdapter(child: _buildSearchBar(settings)),
                      SliverToBoxAdapter(child: _buildFilterChips(settings)),
                      _buildModelGroups(settings),
                    ],
                    if (!settings.modelsLoaded && !_isLoading)
                      SliverToBoxAdapter(child: _buildEmptyState()),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildApiKeySection(SettingsProvider settings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _apiKeyExpanded = !_apiKeyExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: settings.hasApiKey
                      ? AppColors.success.withValues(alpha: 0.3)
                      : AppColors.border(context),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: settings.hasApiKey
                          ? AppColors.success.withValues(alpha: 0.15)
                          : AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      settings.hasApiKey
                          ? Icons.check_circle_outline_rounded
                          : Icons.vpn_key_rounded,
                      color: settings.hasApiKey
                          ? AppColors.success
                          : AppColors.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'OpenRouter API Key',
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (settings.hasApiKey && !_apiKeyExpanded)
                          Text(
                            '${settings.availableModels.length} models loaded',
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    _apiKeyExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary(context),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _apiKeyExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border(context)),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: TextField(
                              controller: _apiKeyController,
                              obscureText: _obscureKey,
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontSize: 14,
                                fontFamily: 'monospace',
                              ),
                              decoration: InputDecoration(
                                hintText: 'sk-or-v1-...',
                                hintStyle: TextStyle(
                                  color: AppColors.textSecondary(context),
                                  fontSize: 13,
                                ),
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                isDense: true,
                              ),
                              onChanged: (_) =>
                                  setState(() => _error = null),
                            ),
                          ),
                          Divider(
                              height: 0.5,
                              color: AppColors.border(context)),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: () => setState(
                                        () => _obscureKey = !_obscureKey),
                                    icon: Icon(
                                      _obscureKey
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                        _obscureKey ? 'Show' : 'Hide'),
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          AppColors.textSecondary(context),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  height: 38,
                                  child: FilledButton.icon(
                                    onPressed:
                                        _isLoading ? null : _loadModels,
                                    icon: _isLoading
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.cloud_download_rounded,
                                            size: 18),
                                    label: Text(settings.modelsLoaded
                                        ? 'Reload'
                                        : 'Load'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(SettingsProvider settings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: 'Search models...',
            hintStyle: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 14,
            ),
            prefixIcon: Icon(Icons.search_rounded,
                size: 20, color: AppColors.textSecondary(context)),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 18,
                        color: AppColors.textSecondary(context)),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
      ),
    );
  }

  Widget _buildFilterChips(SettingsProvider settings) {
    final freeCount =
        settings.availableModels.where((m) => m.isFree).length;
    final paidCount =
        settings.availableModels.where((m) => !m.isFree).length;
    final favCount = settings.favoriteModelIds.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterChip(
              label: 'All',
              count: settings.availableModels.length,
              isSelected: _searchQuery.isEmpty,
              onTap: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Free',
              count: freeCount,
              isSelected: false,
              onTap: () {
                _searchController.clear();
                setState(() => _searchQuery = '__free__');
              },
              color: AppColors.success,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Paid',
              count: paidCount,
              isSelected: false,
              onTap: () {
                _searchController.clear();
                setState(() => _searchQuery = '__paid__');
              },
              color: AppColors.accent,
            ),
            if (favCount > 0) ...[
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Selected',
                count: favCount,
                isSelected: false,
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '__favorites__');
                },
                color: AppColors.sendButton,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModelGroups(SettingsProvider settings) {
    List<AiModel> filteredModels;
    if (_searchQuery == '__free__') {
      filteredModels =
          settings.availableModels.where((m) => m.isFree).toList();
    } else if (_searchQuery == '__paid__') {
      filteredModels =
          settings.availableModels.where((m) => !m.isFree).toList();
    } else if (_searchQuery == '__favorites__') {
      filteredModels = settings.favoriteModels;
    } else {
      filteredModels = _getFilteredModels(settings);
    }

    if (filteredModels.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.search_off_rounded,
                  size: 48,
                  color: AppColors.textSecondary(context)
                      .withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text(
                'No models match your search',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_searchQuery.isNotEmpty &&
        !_searchQuery.startsWith('__')) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final model = filteredModels[index];
            return _buildModelTile(settings, model);
          },
          childCount: filteredModels.length,
        ),
      );
    }

    final providers = _getProviderGroups(filteredModels);
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '${filteredModels.length} models',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 12,
                ),
              ),
            );
          }
          final provider = providers[index - 1];
          final providerModels = filteredModels
              .where((m) => m.provider == provider)
              .toList();
          return _buildProviderGroup(
              settings, provider, providerModels);
        },
        childCount: providers.length + 1,
      ),
    );
  }

  Widget _buildProviderGroup(
    SettingsProvider settings,
    String provider,
    List<AiModel> models,
  ) {
    final freeCount = models.where((m) => m.isFree).length;
    final selectedCount =
        models.where((m) => settings.isFavorite(m.id)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  provider,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${models.length} models',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 11,
                ),
              ),
              if (freeCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$freeCount free',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              if (selectedCount > 0) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_circle_rounded,
                    size: 12, color: AppColors.primary),
                const SizedBox(width: 2),
                Text(
                  '$selectedCount',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        ...models.map((model) => _buildModelTile(settings, model)),
      ],
    );
  }

  Widget _buildModelTile(SettingsProvider settings, AiModel model) {
    final isFav = settings.isFavorite(model.id);
    final isDefault = settings.defaultModel == model.id;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => settings.toggleFavoriteModel(model.id),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isFav
                ? AppColors.primary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isFav
                        ? AppColors.primary
                        : AppColors.border(context),
                    width: 2,
                  ),
                  color: isFav ? AppColors.primary : Colors.transparent,
                ),
                child: isFav
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            model.displayName,
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isDefault)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'default',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (model.contextLength > 0)
                          Text(
                            '${_formatContext(model.contextLength)} ctx',
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 11,
                            ),
                          ),
                        if (model.isFree) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.success
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'free',
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(Icons.cloud_download_outlined,
                size: 56,
                color:
                    AppColors.textSecondary(context).withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              'No models loaded yet',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your OpenRouter API key and tap Load\nto discover available models',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatContext(int length) {
    if (length >= 1000000) {
      return '${(length / 1000000).toStringAsFixed(0)}M';
    } else if (length >= 1000) {
      return '${(length / 1000).toStringAsFixed(0)}K';
    }
    return length.toString();
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : AppColors.surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.4)
                : AppColors.border(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : AppColors.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                color: isSelected
                    ? color.withValues(alpha: 0.7)
                    : AppColors.textSecondary(context)
                        .withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
