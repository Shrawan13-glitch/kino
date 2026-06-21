// ignore_for_file: use_null_aware_elements
import 'github_client.dart';

class GithubRepoService {
  final GithubClient _client;

  GithubRepoService(this._client);

  Future<List<Map<String, dynamic>>> listRepos({
    String? type,
    String? sort,
    int perPage = 30,
  }) {
    return _client.getList('/user/repos', query: {
      if (type != null) 'type': type,
      if (sort != null) 'sort': sort,
      'per_page': perPage.toString(),
    });
  }

  Future<Map<String, dynamic>> getRepo(String owner, String repo) {
    return _client.get('/repos/$owner/$repo');
  }

  Future<Map<String, dynamic>> createRepo({
    required String name,
    String? description,
    bool isPrivate = true,
    bool autoInit = false,
  }) {
    return _client.post('/user/repos', body: {
      'name': name,
      'description': description ?? '',
      'private': isPrivate,
      'auto_init': autoInit,
    });
  }

  Future<Map<String, dynamic>> createOrgRepo({
    required String org,
    required String name,
    String? description,
    bool isPrivate = true,
  }) {
    return _client.post('/orgs/$org/repos', body: {
      'name': name,
      'description': description ?? '',
      'private': isPrivate,
    });
  }

  Future<void> deleteRepo(String owner, String repo) async {
    await _client.delete('/repos/$owner/$repo');
  }

  Future<List<Map<String, dynamic>>> searchRepos(String query,
      {int perPage = 10}) {
    return _client.getList('/search/repositories', query: {
      'q': query,
      'per_page': perPage.toString(),
    });
  }

  Future<Map<String, dynamic>> forkRepo(String owner, String repo,
      {String? organization}) {
    final body = organization != null ? {'organization': organization} : null;
    return _client.post('/repos/$owner/$repo/forks', body: body);
  }

  Future<List<Map<String, dynamic>>> listForks(String owner, String repo,
      {int perPage = 30}) {
    return _client.getList('/repos/$owner/$repo/forks',
        query: {'per_page': perPage.toString()});
  }

  Future<void> starRepo(String owner, String repo) {
    return _client.put('/user/starred/$owner/$repo');
  }

  Future<void> unstarRepo(String owner, String repo) {
    return _client.delete('/user/starred/$owner/$repo');
  }

  Future<bool> isStarred(String owner, String repo) async {
    try {
      await _client.get('/user/starred/$owner/$repo');
      return true;
    } on GithubApiException catch (e) {
      if (e.statusCode == 404) return false;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getRepoContents(String owner, String repo,
      {String path = ''}) {
    return _client.get('/repos/$owner/$repo/contents/$path');
  }

  Future<Map<String, dynamic>> updateRepo(String owner, String repo,
      {String? name,
      String? description,
      bool? isPrivate,
      String? homepage,
      bool? hasIssues,
      bool? hasProjects,
      bool? hasWiki,
      bool? isTemplate,
      bool? allowSquashMerge,
      bool? allowMergeCommit,
      bool? allowRebaseMerge,
      bool? allowAutoMerge,
      bool? deleteBranchOnMerge,
      bool? allowUpdateBranch,
      bool? useSquashPrTitleAsDefault,
      String? squashMergeCommitTitle,
      String? squashMergeCommitMessage,
      String? mergeCommitTitle,
      String? mergeCommitMessage,
      bool? archived,
      String? visibility}) {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (isPrivate != null) body['private'] = isPrivate;
    if (homepage != null) body['homepage'] = homepage;
    if (hasIssues != null) body['has_issues'] = hasIssues;
    if (hasProjects != null) body['has_projects'] = hasProjects;
    if (hasWiki != null) body['has_wiki'] = hasWiki;
    if (isTemplate != null) body['is_template'] = isTemplate;
    if (allowSquashMerge != null) body['allow_squash_merge'] = allowSquashMerge;
    if (allowMergeCommit != null) body['allow_merge_commit'] = allowMergeCommit;
    if (allowRebaseMerge != null) body['allow_rebase_merge'] = allowRebaseMerge;
    if (allowAutoMerge != null) body['allow_auto_merge'] = allowAutoMerge;
    if (deleteBranchOnMerge != null) {
      body['delete_branch_on_merge'] = deleteBranchOnMerge;
    }
    if (allowUpdateBranch != null) {
      body['allow_update_branch'] = allowUpdateBranch;
    }
    if (useSquashPrTitleAsDefault != null) {
      body['use_squash_pr_title_as_default'] = useSquashPrTitleAsDefault;
    }
    if (squashMergeCommitTitle != null) {
      body['squash_merge_commit_title'] = squashMergeCommitTitle;
    }
    if (squashMergeCommitMessage != null) {
      body['squash_merge_commit_message'] = squashMergeCommitMessage;
    }
    if (mergeCommitTitle != null) body['merge_commit_title'] = mergeCommitTitle;
    if (mergeCommitMessage != null) {
      body['merge_commit_message'] = mergeCommitMessage;
    }
    if (archived != null) body['archived'] = archived;
    if (visibility != null) body['visibility'] = visibility;
    return _client.patch('/repos/$owner/$repo', body: body);
  }

  Future<void> replaceTopics(String owner, String repo,
      List<String> topics) {
    return _client.put('/repos/$owner/$repo/topics', body: {
      'names': topics,
    });
  }

  Future<List<Map<String, dynamic>>> listCollaborators(String owner, String repo,
      {String? permission, int perPage = 30}) {
    return _client.getList('/repos/$owner/$repo/collaborators', query: {
      if (permission != null) 'permission': permission,
      'per_page': perPage.toString(),
    });
  }

  Future<Map<String, dynamic>> addCollaborator(String owner, String repo,
      String username, {String permission = 'push'}) {
    return _client.put('/repos/$owner/$repo/collaborators/$username',
        body: {'permission': permission});
  }

  Future<void> removeCollaborator(String owner, String repo,
      String username) {
    return _client.delete('/repos/$owner/$repo/collaborators/$username');
  }

  Future<Map<String, dynamic>> checkCollaborator(String owner, String repo,
      String username) async {
    try {
      final data = await _client.get(
          '/repos/$owner/$repo/collaborators/$username/permission');
      return data;
    } on GithubApiException catch (e) {
      if (e.statusCode == 404) return {'permission': 'none'};
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> listLanguages(String owner, String repo) async {
    final resp = await _client.get('/repos/$owner/$repo/languages');
    return resp.entries.map((e) => {'language': e.key, 'bytes': e.value}).toList();
  }

  Future<Map<String, dynamic>> getRepoStats(String owner, String repo,
      {String? stat}) async {
    final endpoint = stat != null
        ? '/repos/$owner/$repo/stats/$stat'
        : '/repos/$owner/$repo';
    return _client.get(endpoint);
  }
}
