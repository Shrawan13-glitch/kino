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
  bool _obscureKey = true;
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _apiKeyController = TextEditingController(text: settings.apiKey);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
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
      setState(() => _isLoading = false);
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

  List<AiModel> _filteredModels(SettingsProvider settings) {
    final models = settings.availableModels;
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
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              _buildApiKeySection(context, settings),
              const SizedBox(height: 24),
              if (settings.hasApiKey) _buildModelsSection(context, settings),
            ],
          );
        },
      ),
    );
  }

  Widget _buildApiKeySection(BuildContext context, SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'OPENROUTER API KEY',
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              Divider(height: 0.5, color: AppColors.border(context)),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 18,
                        ),
                        label: Text(_obscureKey ? 'Show' : 'Hide'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary(context),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 38,
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _loadModels,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_download_rounded,
                                size: 18),
                        label:
                            Text(settings.modelsLoaded ? 'Reload' : 'Load'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
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
    );
  }

  Widget _buildModelsSection(
      BuildContext context, SettingsProvider settings) {
    if (!settings.modelsLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.cloud_download_outlined,
                  size: 48,
                  color:
                      AppColors.textSecondary(context).withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text(
                'Tap "Load" to fetch available models',
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

    final filtered = _filteredModels(settings);
    final totalCount = settings.availableModels.length;
    final favCount = settings.favoriteModelIds.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'AVAILABLE MODELS',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Text(
              '$favCount selected',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search $totalCount models...',
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 20,
                        color: AppColors.textSecondary(context)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              Divider(height: 0.5, color: AppColors.border(context)),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No models match your search',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 13,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 0.5, color: AppColors.border(context)),
                    itemBuilder: (context, index) {
                      final model = filtered[index];
                      final isFav = settings.isFavorite(model.id);
                      final isDefault = settings.defaultModel == model.id;

                      return _ModelTile(
                        model: model,
                        isFavorite: isFav,
                        isDefault: isDefault,
                        onToggle: () => settings.toggleFavoriteModel(model.id),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModelTile extends StatelessWidget {
  final AiModel model;
  final bool isFavorite;
  final bool isDefault;
  final VoidCallback onToggle;

  const _ModelTile({
    required this.model,
    required this.isFavorite,
    required this.isDefault,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isFavorite
                      ? AppColors.primary
                      : AppColors.border(context),
                  width: 2,
                ),
                color: isFavorite ? AppColors.primary : Colors.transparent,
              ),
              child: isFavorite
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
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
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
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        model.provider,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 11,
                        ),
                      ),
                      if (model.contextLength > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${_formatContext(model.contextLength)} ctx',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (model.isFree) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
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
            Text(
              model.shortId,
              style: TextStyle(
                color: AppColors.textSecondary(context).withValues(alpha: 0.5),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
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
