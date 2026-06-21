import 'github_client.dart';
import 'github_auth_service.dart';
import 'repo_service.dart';
import 'branch_service.dart';
import 'commit_service.dart';
import 'content_service.dart';
import 'pr_service.dart';
import 'actions_service.dart';
import 'issue_service.dart';
import 'user_service.dart';
import 'settings_service.dart';
import '../debug_service.dart';

class GithubIntegrationService {
  final GithubAuthService _auth;
  late final GithubClient _client;
  late final GithubRepoService repos;
  late final GithubBranchService branches;
  late final GithubCommitService commits;
  late final GithubContentService contents;
  late final GithubPrService prs;
  late final GithubActionsService actions;
  late final GithubIssueService issues;
  late final GithubUserService users;
  late final GithubSettingsService settings;

  GithubIntegrationService(this._auth) {
    _client = GithubClient(_auth);
    repos = GithubRepoService(_client);
    branches = GithubBranchService(_client);
    commits = GithubCommitService(_client);
    contents = GithubContentService(_client);
    prs = GithubPrService(_client);
    actions = GithubActionsService(_client);
    issues = GithubIssueService(_client);
    users = GithubUserService(_client);
    settings = GithubSettingsService(_client);
  }

  bool get isConnected => _auth.isAuthenticated;

  Future<String> executeTool(
      String name, Map<String, dynamic> args) async {
    if (!isConnected) {
      return 'Error: GitHub not connected. Go to Settings to connect your GitHub account.';
    }

    try {
      return await _routeTool(name, args);
    } on GithubApiException catch (e) {
      DebugService.instance
          .error('GitHub tool $name failed', e);
      return 'GitHub API Error (${e.statusCode}): ${e.message}';
    } catch (e, s) {
      DebugService.instance
          .error('GitHub tool $name failed', e, s);
      return 'Error: $e';
    }
  }

  Future<String> _routeTool(
      String name, Map<String, dynamic> args) async {
    switch (name) {
      // ── Repos ──
      case 'github_list_repos':
        final data = await repos.listRepos(
          type: args['type'] as String?,
          sort: args['sort'] as String?,
        );
        return _formatRepoList(data);

      case 'github_get_repo':
        final data = await repos.getRepo(
          args['owner'] as String,
          args['repo'] as String,
        );
        return _formatRepoDetail(data);

      case 'github_create_repo':
        final data = await repos.createRepo(
          name: args['name'] as String,
          description: args['description'] as String?,
          isPrivate: args['private'] as bool? ?? true,
          autoInit: args['auto_init'] as bool? ?? false,
        );
        return 'Repository created: ${data['html_url']}\n'
            'Name: ${data['name']}\n'
            'Description: ${data['description'] ?? '(none)'}\n'
            'Visibility: ${data['private'] == true ? 'private' : 'public'}';

      case 'github_delete_repo':
        await repos.deleteRepo(
          args['owner'] as String,
          args['repo'] as String,
        );
        return 'Repository ${args['owner']}/${args['repo']} has been deleted.';

      case 'github_update_repo':
        final data = await repos.updateRepo(
          args['owner'] as String,
          args['repo'] as String,
          name: args['name'] as String?,
          description: args['description'] as String?,
          isPrivate: args['private'] as bool?,
        );
        return 'Repository updated: ${data['html_url']}';

      case 'github_search_repos':
        final data = await repos.searchRepos(
          args['query'] as String,
          perPage: (args['limit'] as int?)?.clamp(1, 50) ?? 10,
        );
        return _formatSearchResults(data, args['query'] as String);

      case 'github_fork_repo':
        final data = await repos.forkRepo(
          args['owner'] as String,
          args['repo'] as String,
          organization: args['organization'] as String?,
        );
        return 'Fork created: ${data['html_url']}';

      case 'github_star_repo':
        await repos.starRepo(
          args['owner'] as String,
          args['repo'] as String,
        );
        return 'Starred ${args['owner']}/${args['repo']}';

      case 'github_unstar_repo':
        await repos.unstarRepo(
          args['owner'] as String,
          args['repo'] as String,
        );
        return 'Unstarred ${args['owner']}/${args['repo']}';

      // ── Branches ──
      case 'github_list_branches':
        final data = await branches.listBranches(
          args['owner'] as String,
          args['repo'] as String,
        );
        if (data.isEmpty) return 'No branches found.';
        return 'Branches for ${args['owner']}/${args['repo']}:\n'
            '${data.map((b) => '- ${b['name']}').join('\n')}';

      case 'github_create_branch':
        final data = await branches.createBranch(
          args['owner'] as String,
          args['repo'] as String,
          args['branch_name'] as String,
          args['sha'] as String,
        );
        return 'Branch "${args['branch_name']}" created at ${data['ref']}';

      case 'github_delete_branch':
        await branches.deleteBranch(
          args['owner'] as String,
          args['repo'] as String,
          args['branch'] as String,
        );
        return 'Branch "${args['branch']}" deleted.';

      case 'github_merge_branches':
        final data = await branches.mergeBranch(
          args['owner'] as String,
          args['repo'] as String,
          base: args['base'] as String,
          head: args['head'] as String,
          commitMessage: args['commit_message'] as String?,
        );
        return 'Merge successful: ${data['sha']}\n'
            'Message: ${data['commit']['message']}';

      // ── Commits ──
      case 'github_list_commits':
        final data = await commits.listCommits(
          args['owner'] as String,
          args['repo'] as String,
          branch: args['branch'] as String?,
          path: args['path'] as String?,
          perPage: (args['limit'] as int?) ?? 30,
        );
        return _formatCommitList(data, args['owner'] as String,
            args['repo'] as String);

      case 'github_get_commit':
        final data = await commits.getCommit(
          args['owner'] as String,
          args['repo'] as String,
          args['sha'] as String,
        );
        return _formatCommitDetail(data);

      case 'github_compare_commits':
        final data = await commits.compareCommits(
          args['owner'] as String,
          args['repo'] as String,
          args['base'] as String,
          args['head'] as String,
        );
        final status = data['status'] as String?;
        final aheadBy = data['ahead_by'] ?? 0;
        final behindBy = data['behind_by'] ?? 0;
        final files = data['files'] as List<dynamic>? ?? [];
        return 'Comparison: ${args['base']}...${args['head']}\n'
            'Status: $status\n'
            'Ahead by: $aheadBy commits\n'
            'Behind by: $behindBy commits\n'
            'Files changed: ${files.length}\n'
            '${files.map((f) => '  ${f['status']}: ${f['filename']} (+${f['additions']}/-${f['deletions']})').join('\n')}';

      // ── File Content ──
      case 'github_read_file':
        final result = await contents.readFile(
          args['owner'] as String,
          args['repo'] as String,
          args['path'] as String,
        );
        return 'File: ${args['path']}\n'
            'SHA: ${result['sha']}\n'
            '---\n${result['content']}';

      case 'github_write_file':
        final sha = args['sha'] as String?;
        Map<String, dynamic> data;
        if (sha != null) {
          data = await contents.updateFile(
            args['owner'] as String,
            args['repo'] as String,
            args['path'] as String,
            message: args['message'] as String,
            content: args['content'] as String,
            sha: sha,
            branch: args['branch'] as String?,
          );
        } else {
          data = await contents.createFile(
            args['owner'] as String,
            args['repo'] as String,
            args['path'] as String,
            message: args['message'] as String,
            content: args['content'] as String,
            branch: args['branch'] as String?,
          );
        }
        return 'File ${sha != null ? 'updated' : 'created'}: ${data['content']['html_url'] ?? args['path']}\n'
            'Commit: ${data['commit']['sha']}';

      case 'github_delete_file':
        await contents.deleteFile(
          args['owner'] as String,
          args['repo'] as String,
          args['path'] as String,
          message: args['message'] as String,
          sha: args['sha'] as String,
          branch: args['branch'] as String?,
        );
        return 'File "${args['path']}" deleted.';

      case 'github_list_contents':
        final data = await contents.getContents(
          args['owner'] as String,
          args['repo'] as String,
          args['path'] as String? ?? '',
        );
        return _formatContentsList(data);

      // ── Pull Requests ──
      case 'github_list_pull_requests':
        final data = await prs.listPullRequests(
          args['owner'] as String,
          args['repo'] as String,
          state: args['state'] as String? ?? 'open',
        );
        return _formatPrList(data, args['owner'] as String,
            args['repo'] as String);

      case 'github_get_pull_request':
        final data = await prs.getPullRequest(
          args['owner'] as String,
          args['repo'] as String,
          (args['number'] as num).toInt(),
        );
        return _formatPrDetail(data);

      case 'github_create_pull_request':
        final data = await prs.createPullRequest(
          args['owner'] as String,
          args['repo'] as String,
          title: args['title'] as String,
          head: args['head'] as String,
          base: args['base'] as String,
          body: args['body'] as String?,
          draft: args['draft'] as bool? ?? false,
        );
        return 'Pull request created: ${data['html_url']}\n'
            'Title: ${data['title']}\n'
            'Number: #${data['number']}';

      case 'github_merge_pull_request':
        final data = await prs.mergePullRequest(
          args['owner'] as String,
          args['repo'] as String,
          (args['number'] as num).toInt(),
          commitTitle: args['commit_title'] as String?,
          mergeMethod: args['merge_method'] as String? ?? 'merge',
        );
        return 'Pull request merged: ${data['sha']}\n'
            'Message: ${data['message']}';

      case 'github_update_pull_request':
        final data = await prs.updatePullRequest(
          args['owner'] as String,
          args['repo'] as String,
          (args['number'] as num).toInt(),
          title: args['title'] as String?,
          body: args['body'] as String?,
          state: args['state'] as String?,
        );
        return 'Pull request #${data['number']} updated: ${data['html_url']}';

      // ── Issues ──
      case 'github_list_issues':
        final data = await issues.listIssues(
          args['owner'] as String,
          args['repo'] as String,
          state: args['state'] as String? ?? 'open',
          label: args['label'] as String?,
        );
        return _formatIssueList(data);

      case 'github_create_issue':
        final data = await issues.createIssue(
          args['owner'] as String,
          args['repo'] as String,
          title: args['title'] as String,
          body: args['body'] as String?,
          labels: (args['labels'] as List?)?.cast<String>(),
        );
        return 'Issue created: ${data['html_url']}\n'
            'Title: ${data['title']}\n'
            'Number: #${data['number']}';

      case 'github_create_issue_comment':
        final data = await issues.createIssueComment(
          args['owner'] as String,
          args['repo'] as String,
          (args['issue_number'] as num).toInt(),
          body: args['body'] as String,
        );
        return 'Comment added: ${data['html_url']}';

      // ── Actions ──
      case 'github_list_workflows':
        final data = await actions.listWorkflows(
          args['owner'] as String,
          args['repo'] as String,
        );
        if (data.isEmpty) return 'No workflows found.';
        return 'Workflows for ${args['owner']}/${args['repo']}:\n'
            '${data.map((w) => '- ${w['name']} (${w['state']}) [${w['path']}]').join('\n')}';

      case 'github_trigger_workflow':
        await actions.triggerWorkflow(
          args['owner'] as String,
          args['repo'] as String,
          args['workflow_id'] as String,
          ref: args['ref'] as String? ?? 'main',
          inputs: args['inputs'] as Map<String, dynamic>?,
        );
        return 'Workflow "${args['workflow_id']}" triggered on ${args['ref'] ?? 'main'}';

      case 'github_list_workflow_runs':
        final data = await actions.listWorkflowRuns(
          args['owner'] as String,
          args['repo'] as String,
          workflowId: args['workflow_id'] as String?,
          status: args['status'] as String?,
          event: args['event'] as String?,
          branch: args['branch'] as String?,
        );
        return _formatWorkflowRunList(data);

      case 'github_get_workflow_run':
        final data = await actions.getWorkflowRun(
          args['owner'] as String,
          args['repo'] as String,
          (args['run_id'] as num).toInt(),
        );
        return _formatWorkflowRunDetail(data);

      case 'github_get_workflow_logs':
        final logs = await actions.getWorkflowRunLogs(
          args['owner'] as String,
          args['repo'] as String,
          (args['run_id'] as num).toInt(),
        );
        final truncated = logs.length > 100000
            ? '${logs.substring(0, 100000)}\n\n[Logs truncated at 100KB]'
            : logs;
        return 'Workflow logs for run #${args['run_id']}:\n---\n$truncated';

      case 'github_cancel_workflow_run':
        await actions.cancelWorkflowRun(
          args['owner'] as String,
          args['repo'] as String,
          (args['run_id'] as num).toInt(),
        );
        return 'Workflow run #${args['run_id']} cancelled.';

      case 'github_rerun_workflow':
        await actions.rerunWorkflow(
          args['owner'] as String,
          args['repo'] as String,
          (args['run_id'] as num).toInt(),
        );
        return 'Workflow run #${args['run_id']} rerun triggered.';

      case 'github_list_artifacts':
        final data = await actions.listWorkflowRunArtifacts(
          args['owner'] as String,
          args['repo'] as String,
          (args['run_id'] as num).toInt(),
        );
        if (data.isEmpty) return 'No artifacts found.';
        return 'Artifacts for run #${args['run_id']}:\n'
            '${data.map((a) => '- ${a['name']} (${_formatSize(a['size_in_bytes'] as int? ?? 0)})').join('\n')}';

      case 'github_get_user':
        if (args['username'] != null) {
          final data = await users.getUser(args['username'] as String);
          return _formatUser(data);
        }
        final data = await users.getAuthenticatedUser();
        return _formatUser(data);

      // ── Repo Settings ──
      case 'github_update_repo_settings':
        final data = await repos.updateRepo(
          args['owner'] as String,
          args['repo'] as String,
          homepage: args['homepage'] as String?,
          hasIssues: args['has_issues'] as bool?,
          hasProjects: args['has_projects'] as bool?,
          hasWiki: args['has_wiki'] as bool?,
          allowSquashMerge: args['allow_squash_merge'] as bool?,
          allowMergeCommit: args['allow_merge_commit'] as bool?,
          allowRebaseMerge: args['allow_rebase_merge'] as bool?,
          allowAutoMerge: args['allow_auto_merge'] as bool?,
          deleteBranchOnMerge: args['delete_branch_on_merge'] as bool?,
          archived: args['archived'] as bool?,
          visibility: args['visibility'] as String?,
        );
        return 'Repository settings updated.\n'
            '${_formatRepoDetail(data)}';

      case 'github_replace_topics':
        await repos.replaceTopics(
          args['owner'] as String,
          args['repo'] as String,
          (args['topics'] as List).cast<String>(),
        );
        return 'Topics replaced for ${args['owner']}/${args['repo']}.';

      // ── Collaborators ──
      case 'github_list_collaborators':
        final data = await repos.listCollaborators(
          args['owner'] as String,
          args['repo'] as String,
          permission: args['permission'] as String?,
        );
        if (data.isEmpty) return 'No collaborators found.';
        return 'Collaborators for ${args['owner']}/${args['repo']}:\n'
            '${data.map((c) => '- @${c['login']} (${c['role_name'] ?? c['permissions']})').join('\n')}';

      case 'github_add_collaborator':
        await repos.addCollaborator(
          args['owner'] as String,
          args['repo'] as String,
          args['username'] as String,
          permission: args['permission'] as String? ?? 'push',
        );
        return '@${args['username']} added to ${args['owner']}/${args['repo']}.';

      case 'github_remove_collaborator':
        await repos.removeCollaborator(
          args['owner'] as String,
          args['repo'] as String,
          args['username'] as String,
        );
        return '@${args['username']} removed from ${args['owner']}/${args['repo']}.';

      // ── Secrets ──
      case 'github_list_secrets':
        final data = await actions.listRepoSecrets(
          args['owner'] as String,
          args['repo'] as String,
        );
        if (data.isEmpty) return 'No secrets found.';
        return 'Secrets for ${args['owner']}/${args['repo']}:\n'
            '${data.map((s) => '- ${s['name']} (updated: ${s['updated_at']})').join('\n')}';

      case 'github_create_secret':
        await actions.createOrUpdateRepoSecret(
          args['owner'] as String,
          args['repo'] as String,
          (args['name'] as String).toUpperCase(),
          args['value'] as String,
        );
        return 'Secret "${(args['name'] as String).toUpperCase()}" saved to ${args['owner']}/${args['repo']}.';

      case 'github_delete_secret':
        await actions.deleteRepoSecret(
          args['owner'] as String,
          args['repo'] as String,
          args['name'] as String,
        );
        return 'Secret "${args['name']}" deleted from ${args['owner']}/${args['repo']}.';

      // ── Variables ──
      case 'github_list_variables':
        final data = await actions.listRepoVariables(
          args['owner'] as String,
          args['repo'] as String,
        );
        if (data.isEmpty) return 'No variables found.';
        return 'Variables for ${args['owner']}/${args['repo']}:\n'
            '${data.map((v) => '- ${v['name']} = ${v['value']}').join('\n')}';

      case 'github_create_variable':
        final vdata = await actions.createRepoVariable(
          args['owner'] as String,
          args['repo'] as String,
          (args['name'] as String).toUpperCase(),
          args['value'] as String,
        );
        return 'Variable "${vdata['name']}" created on ${args['owner']}/${args['repo']}.';

      case 'github_update_variable':
        await actions.updateRepoVariable(
          args['owner'] as String,
          args['repo'] as String,
          args['name'] as String,
          args['value'] as String,
        );
        return 'Variable "${args['name']}" updated on ${args['owner']}/${args['repo']}.';

      case 'github_delete_variable':
        await actions.deleteRepoVariable(
          args['owner'] as String,
          args['repo'] as String,
          args['name'] as String,
        );
        return 'Variable "${args['name']}" deleted from ${args['owner']}/${args['repo']}.';

      // ── Environments ──
      case 'github_list_environments':
        final edata = await settings.listEnvironments(
          args['owner'] as String,
          args['repo'] as String,
        );
        if (edata.isEmpty) return 'No environments found.';
        return 'Environments for ${args['owner']}/${args['repo']}:\n'
            '${edata.map((e) => '- ${e['name']}').join('\n')}';

      case 'github_create_environment':
        final envResult = await settings.createOrUpdateEnvironment(
          args['owner'] as String,
          args['repo'] as String,
          args['env'] as String,
          waitTimer: (args['wait_timer'] as num?)?.toInt(),
        );
        return 'Environment "${args['env']}" created/updated.\n'
            'URL: ${envResult['html_url']}';

      case 'github_delete_environment':
        await settings.deleteEnvironment(
          args['owner'] as String,
          args['repo'] as String,
          args['env'] as String,
        );
        return 'Environment "${args['env']}" deleted.';

      case 'github_list_env_secrets':
        final esData = await settings.listEnvSecrets(
          args['owner'] as String,
          args['repo'] as String,
          args['env'] as String,
        );
        if (esData.isEmpty) {
          return 'No secrets in environment "${args['env']}".';
        }
        return 'Secrets for environment "${args['env']}":\n'
            '${esData.map((s) => '- ${s['name']}').join('\n')}';

      case 'github_create_env_secret':
        await settings.createOrUpdateEnvSecret(
          args['owner'] as String,
          args['repo'] as String,
          args['env'] as String,
          (args['name'] as String).toUpperCase(),
          args['value'] as String,
        );
        return 'Secret "${(args['name'] as String).toUpperCase()}" saved to '
            'environment "${args['env']}".';

      case 'github_delete_env_secret':
        await settings.deleteEnvSecret(
          args['owner'] as String,
          args['repo'] as String,
          args['env'] as String,
          args['name'] as String,
        );
        return 'Secret "${args['name']}" deleted from environment "${args['env']}".';

      case 'github_list_env_variables':
        final evData = await settings.listEnvVariables(
          args['owner'] as String,
          args['repo'] as String,
          args['env'] as String,
        );
        if (evData.isEmpty) {
          return 'No variables in environment "${args['env']}".';
        }
        return 'Variables for environment "${args['env']}":\n'
            '${evData.map((v) => '- ${v['name']} = ${v['value']}').join('\n')}';

      case 'github_create_env_variable':
        final evResult = await settings.createEnvVariable(
          args['owner'] as String,
          args['repo'] as String,
          args['env'] as String,
          (args['name'] as String).toUpperCase(),
          args['value'] as String,
        );
        return 'Variable "${evResult['name']}" created in environment "${args['env']}".';

      case 'github_update_env_variable':
        await settings.updateEnvVariable(
          args['owner'] as String,
          args['repo'] as String,
          args['env'] as String,
          args['name'] as String,
          args['value'] as String,
        );
        return 'Variable "${args['name']}" updated in environment "${args['env']}".';

      case 'github_delete_env_variable':
        await settings.deleteEnvVariable(
          args['owner'] as String,
          args['repo'] as String,
          args['env'] as String,
          args['name'] as String,
        );
        return 'Variable "${args['name']}" deleted from environment "${args['env']}".';

      // ── Branch Protection ──
      case 'github_get_branch_protection':
        final bpResult = await settings.getBranchProtection(
          args['owner'] as String,
          args['repo'] as String,
          args['branch'] as String,
        );
        return _formatBranchProtection(bpResult);

      case 'github_update_branch_protection':
        final bpData = await settings.updateBranchProtection(
          args['owner'] as String,
          args['repo'] as String,
          args['branch'] as String,
          requiredStatusChecks:
              args['required_status_checks'] as bool? ?? false,
          requiredPullRequestReviews:
              args['required_pull_request_reviews'] as bool? ?? false,
          requiredApprovingReviewCount:
              (args['required_approving_review_count'] as num?)?.toInt(),
          dismissStaleReviews: args['dismiss_stale_reviews'] as bool?,
          requireCodeOwnerReviews:
              args['require_code_owner_reviews'] as bool?,
          enforceAdmins: args['enforce_admins'] as bool? ?? false,
          requiredLinearHistory:
              args['required_linear_history'] as bool?,
          allowForcePushes: args['allow_force_pushes'] as bool?,
          allowDeletions: args['allow_deletions'] as bool?,
          requiredConversationResolution:
              args['required_conversation_resolution'] as bool?,
        );
        return 'Branch protection updated for ${args['branch']}: '
            '${_summarizeProtection(bpData)}';

      case 'github_delete_branch_protection':
        await settings.deleteBranchProtection(
          args['owner'] as String,
          args['repo'] as String,
          args['branch'] as String,
        );
        return 'Branch protection removed from "${args['branch']}".';

      // ── Webhooks ──
      case 'github_list_webhooks':
        final whData = await settings.listWebhooks(
          args['owner'] as String,
          args['repo'] as String,
        );
        if (whData.isEmpty) return 'No webhooks found.';
        return 'Webhooks for ${args['owner']}/${args['repo']}:\n'
            '${whData.map((h) => '  #${h['id']}: ${h['config']['url']} (events: ${(h['events'] as List).join(', ')})').join('\n')}';

      case 'github_create_webhook':
        final whResult = await settings.createWebhook(
          args['owner'] as String,
          args['repo'] as String,
          url: args['url'] as String,
          contentType: args['content_type'] as String? ?? 'json',
          secret: args['secret'] as String? ?? '',
          events: (args['events'] as List?)?.cast<String>() ?? ['push'],
        );
        return 'Webhook #${whResult['id']} created: ${whResult['config']['url']}';

      case 'github_delete_webhook':
        await settings.deleteWebhook(
          args['owner'] as String,
          args['repo'] as String,
          (args['hook_id'] as num).toInt(),
        );
        return 'Webhook #${args['hook_id']} deleted.';

      // ── Deploy Keys ──
      case 'github_list_deploy_keys':
        final dkData = await settings.listDeployKeys(
          args['owner'] as String,
          args['repo'] as String,
        );
        if (dkData.isEmpty) return 'No deploy keys found.';
        return 'Deploy keys for ${args['owner']}/${args['repo']}:\n'
            '${dkData.map((k) => '  #${k['id']}: ${k['title']} (${k['key'].substring(0, 30)}...)').join('\n')}';

      case 'github_create_deploy_key':
        final dkResult = await settings.createDeployKey(
          args['owner'] as String,
          args['repo'] as String,
          title: args['title'] as String,
          key: args['key'] as String,
          readOnly: args['read_only'] as bool? ?? true,
        );
        return 'Deploy key "${dkResult['title']}" created (id: ${dkResult['id']}).';

      case 'github_delete_deploy_key':
        await settings.deleteDeployKey(
          args['owner'] as String,
          args['repo'] as String,
          (args['key_id'] as num).toInt(),
        );
        return 'Deploy key #${args['key_id']} deleted.';

      default:
        return 'Unknown GitHub tool: $name';
    }
  }

  String _formatRepoList(List<Map<String, dynamic>> repos) {
    if (repos.isEmpty) return 'No repositories found.';
    return 'Repositories:\n${repos.map((r) {
      return '- ${r['full_name']} (${r['visibility'] ?? (r['private'] == true ? 'private' : 'public')})'
          ' ${r['fork'] == true ? '[fork]' : ''}'
          ' ★${r['stargazers_count'] ?? 0}'
          ' ${r['description'] ?? ''}';
    }).join('\n')}';
  }

  String _formatRepoDetail(Map<String, dynamic> r) {
    return 'Repository: ${r['full_name']}\n'
        'Description: ${r['description'] ?? '(none)'}\n'
        'URL: ${r['html_url']}\n'
        'Visibility: ${r['private'] == true ? 'private' : 'public'}\n'
        'Default branch: ${r['default_branch']}\n'
        'Stars: ${r['stargazers_count']}  Forks: ${r['forks_count']}\n'
        'Language: ${r['language'] ?? '(none)'}\n'
        'Topics: ${(r['topics'] as List?)?.join(', ') ?? '(none)'}\n'
        'Open issues: ${r['open_issues_count']}\n'
        'License: ${r['license'] != null ? r['license']['spdx_id'] : '(none)'}\n'
        'Created: ${r['created_at']}\n'
        'Updated: ${r['updated_at']}\n'
        'Size: ${_formatSize(r['size'] as int? ?? 0)}';
  }

  String _formatSearchResults(
      List<Map<String, dynamic>> data, String query) {
    if (data.isEmpty) return 'No repositories found for "$query".';
    final sb = StringBuffer();
    sb.writeln('Search results for "$query":');
    for (var i = 0; i < data.length; i++) {
      final r = data[i];
      sb.writeln('${i + 1}. ${r['full_name']}');
      sb.writeln('   ${r['description'] ?? '(no description)'}');
      sb.writeln('   ★${r['stargazers_count']}  ${r['language'] ?? ''}');
      sb.writeln('   ${r['html_url']}');
    }
    return sb.toString().trim();
  }

  String _formatCommitList(List<Map<String, dynamic>> commits,
      String owner, String repo) {
    if (commits.isEmpty) return 'No commits found.';
    return 'Recent commits for $owner/$repo:\n${commits.map((c) {
      final sha = (c['sha'] as String).substring(0, 7);
      final msg = (c['commit']['message'] as String).split('\n').first;
      final author = c['commit']['author']['name'] ?? 'Unknown';
      final date = c['commit']['author']['date'] ?? '';
      return '$sha - $msg ($author, $date)';
    }).join('\n')}';
  }

  String _formatCommitDetail(Map<String, dynamic> c) {
    final sha = c['sha'] as String;
    final msg = c['commit']['message'] as String? ?? '';
    final author = c['commit']['author'] as Map<String, dynamic>? ?? {};
    final committer = c['commit']['committer'] as Map<String, dynamic>? ?? {};
    final stats = c['stats'] as Map<String, dynamic>?;
    final files = c['files'] as List<dynamic>? ?? [];
    return 'Commit: $sha\n'
        'Message: ${msg.trim().split('\n').first}\n'
        'Author: ${author['name']} <${author['email']}>\n'
        'Date: ${author['date']}\n'
        'Committer: ${committer['name']}\n'
        '${stats != null ? 'Stats: +${stats['additions']} -${stats['deletions']} (${stats['total']} changes)' : ''}\n'
        'Files changed (${files.length}):\n'
        '${files.map((f) => '  ${f['status']}: ${f['filename']} (+${f['additions']}/-${f['deletions']})').join('\n')}';
  }

  String _formatPrList(List<Map<String, dynamic>> prs, String owner,
      String repo) {
    if (prs.isEmpty) return 'No pull requests found.';
    return 'Pull requests for $owner/$repo:\n${prs.map((pr) {
      return '#${pr['number']} - ${pr['title']}\n'
          '  State: ${pr['state']} | By: ${pr['user']['login']} | '
          '${pr['head']['ref']} -> ${pr['base']['ref']}\n'
          '  ${pr['html_url']}';
    }).join('\n')}';
  }

  String _formatPrDetail(Map<String, dynamic> pr) {
    return 'PR #${pr['number']}: ${pr['title']}\n'
        'URL: ${pr['html_url']}\n'
        'State: ${pr['state']} | Draft: ${pr['draft'] ?? false}\n'
        'Author: ${pr['user']['login']}\n'
        'Base: ${pr['base']['ref']} <- Head: ${pr['head']['ref']}\n'
        'Created: ${pr['created_at']}\n'
        'Body:\n${pr['body'] ?? '(no description)'}';
  }

  String _formatIssueList(List<Map<String, dynamic>> issues) {
    if (issues.isEmpty) return 'No issues found.';
    return 'Issues:\n${issues.map((i) {
      return '#${i['number']} - ${i['title']} [${i['state']}] '
          'by ${i['user']['login']}';
    }).join('\n')}';
  }

  String _formatWorkflowRunList(List<Map<String, dynamic>> runs) {
    if (runs.isEmpty) return 'No workflow runs found.';
    return 'Workflow runs:\n${runs.map((r) {
      final name = r['name'] ?? r['workflow_id'] ?? '(unnamed)';
      return '#${r['run_number']} - $name\n'
          '  Status: ${r['status'] ?? 'unknown'}'
          '${r['conclusion'] != null ? ' | Conclusion: ${r['conclusion']}' : ''}\n'
          '  Trigger: ${r['event']} | Branch: ${r['head_branch']}\n'
          '  ${r['html_url'] ?? ''}';
    }).join('\n')}';
  }

  String _formatWorkflowRunDetail(Map<String, dynamic> r) {
    return 'Workflow run #${r['id']}:\n'
        'Name: ${r['name'] ?? r['workflow_id']}\n'
        'Status: ${r['status']}\n'
        'Conclusion: ${r['conclusion'] ?? 'N/A'}\n'
        'Event: ${r['event']}\n'
        'Branch: ${r['head_branch']}\n'
        'Commit: ${r['head_sha']}\n'
        'Run number: ${r['run_number']}\n'
        'URL: ${r['html_url'] ?? ''}\n'
        'Created: ${r['created_at']}\n'
        'Updated: ${r['updated_at']}\n'
        'Duration: ${r['run_started_at'] != null ? '${r['updated_at']}' : 'N/A'}';
  }

  String _formatUser(Map<String, dynamic> u) {
    return 'User: ${u['login']} (${u['name'] ?? '(no name)'})\n'
        'ID: ${u['id']}\n'
        'URL: ${u['html_url']}\n'
        'Bio: ${u['bio'] ?? '(none)'}\n'
        'Public repos: ${u['public_repos']} | '
        'Followers: ${u['followers']} | Following: ${u['following']}\n'
        'Company: ${u['company'] ?? '(none)'}\n'
        'Location: ${u['location'] ?? '(none)'}\n'
        'Blog: ${u['blog'] ?? '(none)'}\n'
        'Created: ${u['created_at']}';
  }

  String _formatContentsList(dynamic data) {
    if (data is List) {
      if (data.isEmpty) return 'Directory is empty.';
      return 'Contents:\n${data.map((e) {
        final type = e['type'] == 'dir' ? '📁' : '📄';
        return '$type ${e['name']} (${e['type']})';
      }).join('\n')}';
    }
    if (data is Map<String, dynamic>) {
      if (data.containsKey('type')) {
        return 'File: ${data['name']} (${_formatSize(data['size'] as int? ?? 0)})';
      }
      return data['message'] as String? ?? 'OK';
    }
    return 'No contents found.';
  }

  String _formatBranchProtection(Map<String, dynamic> bp) {
    final rules = <String>[];
    if (bp['required_status_checks'] != null) {
      rules.add('✓ Required status checks');
    }
    if (bp['required_pull_request_reviews'] != null) {
      final rev = bp['required_pull_request_reviews'] as Map<String, dynamic>;
      rules.add(
          '✓ Required PR reviews (${rev['required_approving_review_count'] ?? '?'} approvals)');
    }
    if (bp['enforce_admins'] != null) {
      rules.add('✓ Enforced on admins');
    }
    if (bp['required_linear_history'] != null) {
      rules.add('✓ Linear history required');
    }
    if (bp['allow_force_pushes'] != null) {
      rules.add(
          '${bp['allow_force_pushes']['enabled'] == true ? '⚠' : '✓'} Force pushes');
    }
    if (bp['allow_deletions'] != null) {
      rules.add(
          '${bp['allow_deletions']['enabled'] == true ? '⚠' : '✓'} Deletions');
    }
    if (bp['required_conversation_resolution'] != null) {
      rules.add('✓ Required conversation resolution');
    }
    if (rules.isEmpty) rules.add('No protection rules configured.');
    return 'Branch protection for "${bp['url']?.toString().split('/branches/').last ?? '?'}":\n'
        '${rules.join('\n')}';
  }

  String _summarizeProtection(Map<String, dynamic> bp) {
    final enabled = <String>[];
    if (bp['required_status_checks'] != null) {
      enabled.add('status checks');
    }
    if (bp['required_pull_request_reviews'] != null) {
      enabled.add('PR reviews');
    }
    if (bp['enforce_admins'] != null && bp['enforce_admins']['enabled'] == true) {
      enabled.add('admin enforcement');
    }
    if (enabled.isEmpty) return 'all rules removed';
    return enabled.join(', ');
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  void dispose() {
    _client.dispose();
  }
}
