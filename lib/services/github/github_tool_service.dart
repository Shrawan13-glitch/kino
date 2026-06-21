import '../openrouter_service.dart';

class GithubToolService {
  static bool _initialized = false;

  static void ensureInitialized() {
    if (!_initialized) {
      _initialized = true;
    }
  }

  static List<Map<String, dynamic>> get toolDefinitions => [
        // ── Repos ──
        OpenRouterService.makeToolDefinition(
          name: 'github_list_repos',
          description:
              'List repositories for the authenticated user. Optionally filter by type (all, owner, public, private, member) and sort (full_name, created, updated, pushed).',
          parameters: {
            'type': 'object',
            'properties': {
              'type': {
                'type': 'string',
                'description':
                    'Type of repos: all, owner, public, private, member (default: all)',
                'enum': ['all', 'owner', 'public', 'private', 'member'],
              },
              'sort': {
                'type': 'string',
                'description': 'Sort by: full_name, created, updated, pushed',
                'enum': ['full_name', 'created', 'updated', 'pushed'],
              },
            },
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_get_repo',
          description:
              'Get detailed information about a specific repository including description, stars, forks, language, topics, and more.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {
                'type': 'string',
                'description': 'Repository owner (user or org)',
              },
              'repo': {
                'type': 'string',
                'description': 'Repository name',
              },
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_create_repo',
          description:
              'Create a new repository for the authenticated user. Set private: false for public repos.',
          parameters: {
            'type': 'object',
            'properties': {
              'name': {
                'type': 'string',
                'description': 'Repository name',
              },
              'description': {
                'type': 'string',
                'description': 'Repository description',
              },
              'private': {
                'type': 'boolean',
                'description': 'Whether repo is private (default: true)',
              },
              'auto_init': {
                'type': 'boolean',
                'description':
                    'Auto-initialize with README (default: false)',
              },
            },
            'required': ['name'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_delete_repo',
          description:
              'Delete a repository. WARNING: This is permanent and cannot be undone.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {
                'type': 'string',
                'description': 'Repository owner',
              },
              'repo': {
                'type': 'string',
                'description': 'Repository name to delete',
              },
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_update_repo',
          description:
              'Update repository settings like name, description, or visibility.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'name': {
                'type': 'string',
                'description': 'New repository name',
              },
              'description': {
                'type': 'string',
                'description': 'New description',
              },
              'private': {
                'type': 'boolean',
                'description': 'Change visibility',
              },
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_search_repos',
          description:
              'Search for repositories on GitHub. Returns matching repos with metadata.',
          parameters: {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Search query (supports GitHub search syntax)',
              },
              'limit': {
                'type': 'integer',
                'description': 'Max results (default: 10, max: 50)',
              },
            },
            'required': ['query'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_fork_repo',
          description: 'Fork a repository to your account or an organization.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {
                'type': 'string',
                'description': 'Owner of the repo to fork',
              },
              'repo': {
                'type': 'string',
                'description': 'Name of the repo to fork',
              },
              'organization': {
                'type': 'string',
                'description':
                    'Optional organization to fork to (default: your account)',
              },
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_star_repo',
          description: 'Star a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_unstar_repo',
          description: 'Unstar a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
            },
            'required': ['owner', 'repo'],
          },
        ),

        // ── Branches ──
        OpenRouterService.makeToolDefinition(
          name: 'github_list_branches',
          description: 'List all branches in a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_create_branch',
          description:
              'Create a new branch in a repository from a given SHA.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'branch_name': {
                'type': 'string',
                'description': 'Name for the new branch',
              },
              'sha': {
                'type': 'string',
                'description':
                    'SHA of the commit to base the branch on. Use github_get_repo to find the default branch SHA.',
              },
            },
            'required': ['owner', 'repo', 'branch_name', 'sha'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_delete_branch',
          description: 'Delete a branch from a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'branch': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'branch'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_merge_branches',
          description: 'Merge a branch into another branch.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'base': {
                'type': 'string',
                'description': 'Base branch (the one receiving changes)',
              },
              'head': {
                'type': 'string',
                'description': 'Head branch (the one being merged in)',
              },
              'commit_message': {
                'type': 'string',
                'description': 'Optional custom commit message',
              },
            },
            'required': ['owner', 'repo', 'base', 'head'],
          },
        ),

        // ── Commits ──
        OpenRouterService.makeToolDefinition(
          name: 'github_list_commits',
          description:
              'List commits in a repository. Optionally filter by branch or file path.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'branch': {
                'type': 'string',
                'description': 'Branch name to filter by',
              },
              'path': {
                'type': 'string',
                'description':
                    'Only commits that touch this file path',
              },
              'limit': {
                'type': 'integer',
                'description': 'Max commits to return (default: 30)',
              },
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_get_commit',
          description:
              'Get detailed information about a specific commit including stats and files changed.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'sha': {
                'type': 'string',
                'description': 'Commit SHA',
              },
            },
            'required': ['owner', 'repo', 'sha'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_compare_commits',
          description:
              'Compare two commits or branches. Shows diff and commit list between them.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'base': {
                'type': 'string',
                'description': 'Base ref (commit SHA or branch name)',
              },
              'head': {
                'type': 'string',
                'description': 'Head ref (commit SHA or branch name)',
              },
            },
            'required': ['owner', 'repo', 'base', 'head'],
          },
        ),

        // ── File Content ──
        OpenRouterService.makeToolDefinition(
          name: 'github_read_file',
          description:
              'Read a file from a repository. Returns the file content and metadata.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'path': {
                'type': 'string',
                'description': 'File path in the repository',
              },
            },
            'required': ['owner', 'repo', 'path'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_write_file',
          description:
              'Create or update a file in a repository. Creates a new commit with the change. If the file already exists, provide the sha from github_read_file.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'path': {
                'type': 'string',
                'description': 'File path in the repository',
              },
              'content': {
                'type': 'string',
                'description': 'File content as text',
              },
              'message': {
                'type': 'string',
                'description': 'Commit message',
              },
              'sha': {
                'type': 'string',
                'description':
                    'Required when updating an existing file. Get this from github_read_file.',
              },
              'branch': {
                'type': 'string',
                'description':
                    'Optional branch name (defaults to default branch)',
              },
            },
            'required': ['owner', 'repo', 'path', 'content', 'message'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_delete_file',
          description:
              'Delete a file from a repository. Creates a commit with the deletion.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'path': {
                'type': 'string',
                'description': 'File path to delete',
              },
              'message': {
                'type': 'string',
                'description': 'Commit message',
              },
              'sha': {
                'type': 'string',
                'description':
                    'File SHA from github_read_file or github_get_repo',
              },
              'branch': {
                'type': 'string',
                'description': 'Optional branch name',
              },
            },
            'required': ['owner', 'repo', 'path', 'message', 'sha'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_list_contents',
          description:
              'List the contents of a directory in a repository. Use this to explore repo structure.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'path': {
                'type': 'string',
                'description':
                    'Directory path (empty for root). Default: ""',
              },
            },
            'required': ['owner', 'repo'],
          },
        ),

        // ── Pull Requests ──
        OpenRouterService.makeToolDefinition(
          name: 'github_list_pull_requests',
          description:
              'List pull requests in a repository. Filter by state (open, closed, all).',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'state': {
                'type': 'string',
                'description': 'PR state: open, closed, all (default: open)',
                'enum': ['open', 'closed', 'all'],
              },
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_get_pull_request',
          description:
              'Get detailed information about a specific pull request.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'number': {
                'type': 'integer',
                'description': 'Pull request number',
              },
            },
            'required': ['owner', 'repo', 'number'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_create_pull_request',
          description: 'Create a new pull request.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'title': {
                'type': 'string',
                'description': 'PR title',
              },
              'head': {
                'type': 'string',
                'description':
                    'Branch name containing your changes',
              },
              'base': {
                'type': 'string',
                'description': 'Branch you want to merge into',
              },
              'body': {
                'type': 'string',
                'description': 'PR description / body text',
              },
              'draft': {
                'type': 'boolean',
                'description': 'Create as draft PR (default: false)',
              },
            },
            'required': ['owner', 'repo', 'title', 'head', 'base'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_merge_pull_request',
          description: 'Merge a pull request. Supports merge, squash, and rebase strategies.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'number': {
                'type': 'integer',
                'description': 'PR number to merge',
              },
              'merge_method': {
                'type': 'string',
                'description':
                    'Merge method: merge, squash, rebase (default: merge)',
                'enum': ['merge', 'squash', 'rebase'],
              },
              'commit_title': {
                'type': 'string',
                'description': 'Optional custom commit title',
              },
            },
            'required': ['owner', 'repo', 'number'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_update_pull_request',
          description:
              'Update a pull request (title, body, state, base branch).',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'number': {'type': 'integer'},
              'title': {'type': 'string'},
              'body': {'type': 'string'},
              'state': {
                'type': 'string',
                'enum': ['open', 'closed'],
              },
            },
            'required': ['owner', 'repo', 'number'],
          },
        ),

        // ── Issues ──
        OpenRouterService.makeToolDefinition(
          name: 'github_list_issues',
          description:
              'List issues in a repository. Optionally filter by state (open, closed, all) or label.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'state': {
                'type': 'string',
                'description': 'Issue state (default: open)',
                'enum': ['open', 'closed', 'all'],
              },
              'label': {
                'type': 'string',
                'description': 'Filter by label name',
              },
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_create_issue',
          description:
              'Create a new issue in a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'title': {'type': 'string'},
              'body': {
                'type': 'string',
                'description': 'Issue body/description',
              },
              'labels': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': 'Labels to apply',
              },
            },
            'required': ['owner', 'repo', 'title'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_create_issue_comment',
          description:
              'Add a comment to an issue or pull request.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'issue_number': {
                'type': 'integer',
                'description': 'Issue or PR number',
              },
              'body': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'issue_number', 'body'],
          },
        ),

        // ── Actions ──
        OpenRouterService.makeToolDefinition(
          name: 'github_list_workflows',
          description:
              'List all GitHub Actions workflows in a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_trigger_workflow',
          description:
              'Trigger a GitHub Actions workflow. Provide the workflow filename (e.g., "main.yml") or ID.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'workflow_id': {
                'type': 'string',
                'description':
                    'Workflow file name (e.g., "ci.yml") or workflow ID',
              },
              'ref': {
                'type': 'string',
                'description':
                    'Branch/tag name to run on (default: main)',
              },
              'inputs': {
                'type': 'object',
                'description':
                    'Workflow inputs as key-value pairs (for workflow_dispatch)',
              },
            },
            'required': ['owner', 'repo', 'workflow_id'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_list_workflow_runs',
          description:
              'List workflow runs. Optionally filter by workflow, status, event, or branch.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'workflow_id': {
                'type': 'string',
                'description': 'Optional: filter by workflow file name or ID',
              },
              'status': {
                'type': 'string',
                'description':
                    'Filter by status: queued, in_progress, completed, success, failure, cancelled',
              },
              'event': {
                'type': 'string',
                'description': 'Filter by event: push, pull_request, workflow_dispatch, etc.',
              },
              'branch': {
                'type': 'string',
                'description': 'Filter by branch name',
              },
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_get_workflow_run',
          description:
              'Get detailed information about a specific workflow run including its status, conclusion, and URL.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'run_id': {
                'type': 'integer',
                'description': 'Workflow run ID',
              },
            },
            'required': ['owner', 'repo', 'run_id'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_get_workflow_logs',
          description:
              'Get the logs for a workflow run. Use this to debug failed workflows.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'run_id': {
                'type': 'integer',
                'description': 'Workflow run ID to get logs for',
              },
            },
            'required': ['owner', 'repo', 'run_id'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_cancel_workflow_run',
          description: 'Cancel a running workflow run.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'run_id': {'type': 'integer'},
            },
            'required': ['owner', 'repo', 'run_id'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_rerun_workflow',
          description: 'Rerun a failed or cancelled workflow run.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'run_id': {'type': 'integer'},
            },
            'required': ['owner', 'repo', 'run_id'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_list_artifacts',
          description:
              'List artifacts from a workflow run.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'run_id': {'type': 'integer'},
            },
            'required': ['owner', 'repo', 'run_id'],
          },
        ),
        // ── Repo Settings ──
        OpenRouterService.makeToolDefinition(
          name: 'github_update_repo_settings',
          description:
              'Configure repository settings: enable/disable issues, wiki, projects; '
              'configure merge strategies (squash, merge, rebase, auto-merge); '
              'set visibility; archive/unarchive; set homepage. Leave fields null to keep current values.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'homepage': {
                'type': 'string',
                'description': 'Repository website URL',
              },
              'has_issues': {
                'type': 'boolean',
                'description': 'Enable/disable Issues tab',
              },
              'has_projects': {
                'type': 'boolean',
                'description': 'Enable/disable Projects tab',
              },
              'has_wiki': {
                'type': 'boolean',
                'description': 'Enable/disable Wiki tab',
              },
              'allow_squash_merge': {
                'type': 'boolean',
                'description': 'Allow squash merging PRs',
              },
              'allow_merge_commit': {
                'type': 'boolean',
                'description': 'Allow merge commits in PRs',
              },
              'allow_rebase_merge': {
                'type': 'boolean',
                'description': 'Allow rebase merging PRs',
              },
              'allow_auto_merge': {
                'type': 'boolean',
                'description': 'Allow auto-merge for PRs',
              },
              'delete_branch_on_merge': {
                'type': 'boolean',
                'description': 'Auto-delete head branches after merge',
              },
              'archived': {
                'type': 'boolean',
                'description': 'Archive the repository (makes it read-only)',
              },
              'visibility': {
                'type': 'string',
                'description': 'Change repo visibility',
                'enum': ['public', 'private', 'internal'],
              },
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_replace_topics',
          description:
              'Replace all topics on a repository with a new list.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'topics': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': 'New list of topics',
              },
            },
            'required': ['owner', 'repo', 'topics'],
          },
        ),

        // ── Collaborators ──
        OpenRouterService.makeToolDefinition(
          name: 'github_list_collaborators',
          description:
              'List collaborators on a repository with their permission levels.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'permission': {
                'type': 'string',
                'description':
                    'Filter by permission: pull, push, admin, maintain, triage',
              },
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_add_collaborator',
          description:
              'Add a collaborator to a repository with a specific permission level.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'username': {
                'type': 'string',
                'description': 'GitHub username to add',
              },
              'permission': {
                'type': 'string',
                'description':
                    'Permission level: pull, push, admin, maintain, triage (default: push)',
                'enum': ['pull', 'push', 'admin', 'maintain', 'triage'],
              },
            },
            'required': ['owner', 'repo', 'username'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_remove_collaborator',
          description: 'Remove a collaborator from a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'username': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'username'],
          },
        ),

        // ── Actions Secrets ──
        OpenRouterService.makeToolDefinition(
          name: 'github_list_secrets',
          description:
              'List all Actions secrets for a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_create_secret',
          description:
              'Create or update a GitHub Actions repository secret.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'name': {
                'type': 'string',
                'description': 'Secret name (uppercase and underscores)',
              },
              'value': {
                'type': 'string',
                'description': 'Secret value',
              },
            },
            'required': ['owner', 'repo', 'name', 'value'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_delete_secret',
          description: 'Delete a GitHub Actions repository secret.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'name': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'name'],
          },
        ),

        // ── Actions Variables ──
        OpenRouterService.makeToolDefinition(
          name: 'github_list_variables',
          description:
              'List all GitHub Actions variables for a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_create_variable',
          description:
              'Create a new GitHub Actions variable for a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'name': {
                'type': 'string',
                'description': 'Variable name',
              },
              'value': {
                'type': 'string',
                'description': 'Variable value',
              },
            },
            'required': ['owner', 'repo', 'name', 'value'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_update_variable',
          description: 'Update a GitHub Actions variable value.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'name': {'type': 'string'},
              'value': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'name', 'value'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_delete_variable',
          description: 'Delete a GitHub Actions variable.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'name': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'name'],
          },
        ),

        // ── Environments ──
        OpenRouterService.makeToolDefinition(
          name: 'github_list_environments',
          description:
              'List all environments in a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_create_environment',
          description:
              'Create or update a deployment environment with optional protection rules '
              '(wait timer in minutes, required reviewers).',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'env': {
                'type': 'string',
                'description': 'Environment name',
              },
              'wait_timer': {
                'type': 'integer',
                'description':
                    'Optional: wait time in minutes before deployments proceed',
              },
            },
            'required': ['owner', 'repo', 'env'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_delete_environment',
          description: 'Delete a deployment environment.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'env': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'env'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_list_env_secrets',
          description:
              'List all secrets for a deployment environment.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'env': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'env'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_create_env_secret',
          description:
              'Create or update a secret for a deployment environment.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'env': {'type': 'string'},
              'name': {'type': 'string'},
              'value': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'env', 'name', 'value'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_delete_env_secret',
          description: 'Delete a secret from a deployment environment.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'env': {'type': 'string'},
              'name': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'env', 'name'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_list_env_variables',
          description:
              'List all variables for a deployment environment.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'env': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'env'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_create_env_variable',
          description:
              'Create a new variable for a deployment environment.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'env': {'type': 'string'},
              'name': {'type': 'string'},
              'value': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'env', 'name', 'value'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_update_env_variable',
          description: 'Update a variable in a deployment environment.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'env': {'type': 'string'},
              'name': {'type': 'string'},
              'value': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'env', 'name', 'value'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_delete_env_variable',
          description: 'Delete a variable from a deployment environment.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'env': {'type': 'string'},
              'name': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'env', 'name'],
          },
        ),

        // ── Branch Protection ──
        OpenRouterService.makeToolDefinition(
          name: 'github_get_branch_protection',
          description:
              'Get the branch protection rules for a specific branch.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'branch': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'branch'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_update_branch_protection',
          description:
              'Enable or update branch protection rules: require PR reviews, status checks, '
              'linear history, force push restrictions, and more. Set a flag to false/null to disable it.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'branch': {'type': 'string'},
              'required_status_checks': {
                'type': 'boolean',
                'description':
                    'Require status checks to pass before merging',
              },
              'required_pull_request_reviews': {
                'type': 'boolean',
                'description':
                    'Require pull request reviews before merging',
              },
              'required_approving_review_count': {
                'type': 'integer',
                'description': 'Number of required reviewers (1-6)',
              },
              'dismiss_stale_reviews': {
                'type': 'boolean',
                'description':
                    'Dismiss approving reviews when new commits are pushed',
              },
              'require_code_owner_reviews': {
                'type': 'boolean',
                'description': 'Require review from code owners',
              },
              'enforce_admins': {
                'type': 'boolean',
                'description':
                    'Apply rules to administrators too',
              },
              'required_linear_history': {
                'type': 'boolean',
                'description': 'Prevent squash/merge commits',
              },
              'allow_force_pushes': {
                'type': 'boolean',
                'description': 'Allow force pushes to the branch',
              },
              'allow_deletions': {
                'type': 'boolean',
                'description': 'Allow deletions of the branch',
              },
              'required_conversation_resolution': {
                'type': 'boolean',
                'description':
                    'Require all conversations to be resolved before merging',
              },
            },
            'required': ['owner', 'repo', 'branch'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_delete_branch_protection',
          description: 'Remove all branch protection rules from a branch.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'branch': {'type': 'string'},
            },
            'required': ['owner', 'repo', 'branch'],
          },
        ),

        // ── Webhooks ──
        OpenRouterService.makeToolDefinition(
          name: 'github_list_webhooks',
          description: 'List all webhooks configured on a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_create_webhook',
          description:
              'Create a new webhook on a repository. The webhook will POST JSON payloads to the given URL.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'url': {
                'type': 'string',
                'description': 'The URL to receive webhook payloads',
              },
              'content_type': {
                'type': 'string',
                'description':
                    'Payload format: json or form (default: json)',
              },
              'secret': {
                'type': 'string',
                'description': 'Optional webhook secret',
              },
              'events': {
                'type': 'array',
                'items': {'type': 'string'},
                'description':
                    'Events to trigger on (default: ["push"])',
              },
            },
            'required': ['owner', 'repo', 'url'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_delete_webhook',
          description: 'Delete a webhook from a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'hook_id': {
                'type': 'integer',
                'description': 'Webhook ID to delete',
              },
            },
            'required': ['owner', 'repo', 'hook_id'],
          },
        ),

        // ── Deploy Keys ──
        OpenRouterService.makeToolDefinition(
          name: 'github_list_deploy_keys',
          description: 'List all deploy keys on a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
            },
            'required': ['owner', 'repo'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_create_deploy_key',
          description:
              'Add a new deploy key to a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'title': {
                'type': 'string',
                'description': 'A name for the deploy key',
              },
              'key': {
                'type': 'string',
                'description': 'The public SSH key content',
              },
              'read_only': {
                'type': 'boolean',
                'description': 'If true, key has read-only access (default: true)',
              },
            },
            'required': ['owner', 'repo', 'title', 'key'],
          },
        ),
        OpenRouterService.makeToolDefinition(
          name: 'github_delete_deploy_key',
          description: 'Remove a deploy key from a repository.',
          parameters: {
            'type': 'object',
            'properties': {
              'owner': {'type': 'string'},
              'repo': {'type': 'string'},
              'key_id': {
                'type': 'integer',
                'description': 'Deploy key ID to remove',
              },
            },
            'required': ['owner', 'repo', 'key_id'],
          },
        ),

        OpenRouterService.makeToolDefinition(
          name: 'github_get_user',
          description:
              'Get information about the authenticated GitHub user or any GitHub user.',
          parameters: {
            'type': 'object',
            'properties': {
              'username': {
                'type': 'string',
                'description':
                    'Optional: username to look up. If empty, returns authenticated user info.',
              },
            },
          },
        ),
      ];
}
