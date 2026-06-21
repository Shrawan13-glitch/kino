// ignore_for_file: use_null_aware_elements
import 'github_client.dart';

class GithubSettingsService {
  final GithubClient _client;

  GithubSettingsService(this._client);

  // ── Environments ──

  Future<List<Map<String, dynamic>>> listEnvironments(
      String owner, String repo) async {
    final data = await _client.get('/repos/$owner/$repo/environments');
    return (data['environments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> getEnvironment(
      String owner, String repo, String env) {
    return _client.get('/repos/$owner/$repo/environments/$env');
  }

  Future<Map<String, dynamic>> createOrUpdateEnvironment(
      String owner, String repo, String env,
      {int? waitTimer, List<Map<String, dynamic>>? reviewers}) {
    final body = <String, dynamic>{};
    if (waitTimer != null || reviewers != null) {
      final protectionRules = <String, dynamic>{};
      if (waitTimer != null) protectionRules['wait_timer'] = waitTimer;
      if (reviewers != null) {
        protectionRules['reviewers'] = reviewers;
      }
      body['protection_rules'] = [protectionRules];
    }
    return _client.put('/repos/$owner/$repo/environments/$env', body: body);
  }

  Future<void> deleteEnvironment(
      String owner, String repo, String env) {
    return _client.delete('/repos/$owner/$repo/environments/$env');
  }

  Future<List<Map<String, dynamic>>> listEnvSecrets(
      String owner, String repo, String env) async {
    final data =
        await _client.get('/repos/$owner/$repo/environments/$env/secrets');
    return (data['secrets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<void> createOrUpdateEnvSecret(
      String owner, String repo, String env,
      String name, String value) {
    return _client.put(
        '/repos/$owner/$repo/environments/$env/secrets/$name',
        body: {'encrypted_value': value});
  }

  Future<void> deleteEnvSecret(
      String owner, String repo, String env, String name) {
    return _client.delete(
        '/repos/$owner/$repo/environments/$env/secrets/$name');
  }

  Future<List<Map<String, dynamic>>> listEnvVariables(
      String owner, String repo, String env) async {
    final data =
        await _client.get('/repos/$owner/$repo/environments/$env/variables');
    return (data['variables'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> createEnvVariable(
      String owner, String repo, String env,
      String name, String value) {
    return _client.post(
        '/repos/$owner/$repo/environments/$env/variables',
        body: {'name': name, 'value': value});
  }

  Future<Map<String, dynamic>> updateEnvVariable(
      String owner, String repo, String env,
      String name, String value) {
    return _client.patch(
        '/repos/$owner/$repo/environments/$env/variables/$name',
        body: {'value': value});
  }

  Future<void> deleteEnvVariable(
      String owner, String repo, String env, String name) {
    return _client.delete(
        '/repos/$owner/$repo/environments/$env/variables/$name');
  }

  // ── Branch Protection ──

  Future<Map<String, dynamic>> getBranchProtection(
      String owner, String repo, String branch) {
    return _client.get('/repos/$owner/$repo/branches/$branch/protection');
  }

  Future<Map<String, dynamic>> updateBranchProtection(
      String owner, String repo, String branch, {
    required bool requiredStatusChecks,
    String? strictStatusChecks,
    List<String>? statusCheckContexts,
    required bool enforceAdmins,
    required bool requiredPullRequestReviews,
    int? requiredApprovingReviewCount,
    bool? dismissStaleReviews,
    bool? requireCodeOwnerReviews,
    bool? restrictReviewDismissals,
    bool? requiredLinearHistory,
    bool? allowForcePushes,
    bool? allowDeletions,
    bool? blockCreations,
    bool? requiredConversationResolution,
    bool? lockBranch,
    bool? allowForkSyncing,
  }) {
    final body = <String, dynamic>{};
    if (requiredStatusChecks) {
      body['required_status_checks'] = {
        'strict': strictStatusChecks == 'strict',
        'contexts': statusCheckContexts ?? [],
      };
    } else {
      body['required_status_checks'] = null;
    }
    body['enforce_admins'] = enforceAdmins;
    if (requiredPullRequestReviews) {
      final reviews = <String, dynamic>{
        'dismiss_stale_reviews': dismissStaleReviews ?? false,
        'require_code_owner_reviews': requireCodeOwnerReviews ?? false,
      };
      if (requiredApprovingReviewCount != null) {
        reviews['required_approving_review_count'] =
            requiredApprovingReviewCount.clamp(1, 6);
      }
      if (restrictReviewDismissals != null) {
        reviews['restrict_dismissals'] = restrictReviewDismissals;
      }
      body['required_pull_request_reviews'] = reviews;
    } else {
      body['required_pull_request_reviews'] = null;
    }
    if (restrictReviewDismissals == true) {
      body['restrictions'] = {'users': <String>[], 'teams': <String>[]};
    }
    if (requiredLinearHistory != null) {
      body['required_linear_history'] = {'enabled': requiredLinearHistory};
    }
    if (allowForcePushes != null) {
      body['allow_force_pushes'] = {'enabled': allowForcePushes};
    }
    if (allowDeletions != null) {
      body['allow_deletions'] = {'enabled': allowDeletions};
    }
    if (blockCreations != null) {
      body['block_creations'] = {'enabled': blockCreations};
    }
    if (requiredConversationResolution != null) {
      body['required_conversation_resolution'] = {
        'enabled': requiredConversationResolution
      };
    }
    if (lockBranch != null) {
      body['lock_branch'] = {'enabled': lockBranch};
    }
    if (allowForkSyncing != null) {
      body['allow_fork_syncing'] = {'enabled': allowForkSyncing};
    }
    return _client.put('/repos/$owner/$repo/branches/$branch/protection',
        body: body);
  }

  Future<void> deleteBranchProtection(
      String owner, String repo, String branch) {
    return _client.delete('/repos/$owner/$repo/branches/$branch/protection');
  }

  Future<Map<String, dynamic>> getBranchRules(
      String owner, String repo, String branch) {
    return _client.get('/repos/$owner/$repo/branches/$branch/rules');
  }

  // ── Webhooks ──

  Future<List<Map<String, dynamic>>> listWebhooks(
      String owner, String repo) async {
    final data = await _client.get('/repos/$owner/$repo/hooks');
    if (data case {'hooks': List h}) return h.cast<Map<String, dynamic>>();
    return [data];
  }

  Future<Map<String, dynamic>> getWebhook(
      String owner, String repo, int hookId) {
    return _client.get('/repos/$owner/$repo/hooks/$hookId');
  }

  Future<Map<String, dynamic>> createWebhook(
    String owner, String repo, {
    required String url,
    required String contentType,
    String secret = '',
    List<String> events = const ['push'],
    bool active = true,
  }) {
    return _client.post('/repos/$owner/$repo/hooks', body: {
      'name': 'web',
      'active': active,
      'events': events,
      'config': {
        'url': url,
        'content_type': contentType,
        'secret': secret,
        'insecure_ssl': '0',
      },
    });
  }

  Future<Map<String, dynamic>> updateWebhook(
    String owner, String repo, int hookId, {
    String? url,
    String? contentType,
    String? secret,
    List<String>? events,
    bool? active,
  }) {
    final config = <String, dynamic>{};
    if (url != null) config['url'] = url;
    if (contentType != null) config['content_type'] = contentType;
    if (secret != null) config['secret'] = secret;
    final body = <String, dynamic>{};
    if (config.isNotEmpty) body['config'] = config;
    if (events != null) body['events'] = events;
    if (active != null) body['active'] = active;
    return _client.patch('/repos/$owner/$repo/hooks/$hookId', body: body);
  }

  Future<void> deleteWebhook(String owner, String repo, int hookId) {
    return _client.delete('/repos/$owner/$repo/hooks/$hookId');
  }

  Future<Map<String, dynamic>> testWebhook(
      String owner, String repo, int hookId) {
    return _client.post('/repos/$owner/$repo/hooks/$hookId/tests');
  }

  // ── Deploy Keys ──

  Future<List<Map<String, dynamic>>> listDeployKeys(
      String owner, String repo, {int perPage = 30}) async {
    return _client.getList('/repos/$owner/$repo/keys',
        query: {'per_page': perPage.toString()});
  }

  Future<Map<String, dynamic>> getDeployKey(
      String owner, String repo, int keyId) {
    return _client.get('/repos/$owner/$repo/keys/$keyId');
  }

  Future<Map<String, dynamic>> createDeployKey(
    String owner, String repo, {
    required String title,
    required String key,
    bool readOnly = true,
  }) {
    return _client.post('/repos/$owner/$repo/keys', body: {
      'title': title,
      'key': key,
      'read_only': readOnly,
    });
  }

  Future<void> deleteDeployKey(
      String owner, String repo, int keyId) {
    return _client.delete('/repos/$owner/$repo/keys/$keyId');
  }
}
