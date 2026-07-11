import 'package:flutter/material.dart';

enum ToolCategory {
  webNetwork('Web & Network', Icons.language_rounded, 'Search the web, fetch pages, make HTTP requests'),
  virtualFileSystem('File System', Icons.folder_rounded, 'Read, write, list, and delete files'),
  contentGeneration('Generation', Icons.picture_as_pdf_rounded, 'Generate PDFs and speech audio'),
  taskPlanning('Task Planning', Icons.checklist_rounded, 'Break down complex tasks into steps'),
  githubCore('GitHub Core', Icons.code_rounded, 'Repos, branches, commits, PRs, issues'),
  githubCicd('GitHub CI/CD', Icons.rocket_launch_rounded, 'Actions, workflows, secrets, environments'),
  githubSettings('GitHub Admin', Icons.settings_rounded, 'Repo settings, collaborators, webhooks, pages');

  final String label;
  final IconData icon;
  final String description;

  const ToolCategory(this.label, this.icon, this.description);
}

const Map<ToolCategory, List<String>> kToolsByCategory = {
  ToolCategory.webNetwork: [
    'web_search',
    'fetch_url',
    'power_fetch_url',
    'http_request',
  ],
  ToolCategory.virtualFileSystem: [
    'write_file',
    'read_file',
    'list_dir',
    'delete_file',
    'create_dir',
  ],
  ToolCategory.contentGeneration: [
    'generate_pdf',
    'generate_speech',
  ],
  ToolCategory.taskPlanning: [
    'create_task_plan',
    'update_task_status',
    'clear_task_plan',
  ],
  ToolCategory.githubCore: [
    'github_list_repos',
    'github_get_repo',
    'github_create_repo',
    'github_delete_repo',
    'github_update_repo',
    'github_search_repos',
    'github_fork_repo',
    'github_star_repo',
    'github_unstar_repo',
    'github_list_branches',
    'github_create_branch',
    'github_delete_branch',
    'github_merge_branches',
    'github_list_commits',
    'github_get_commit',
    'github_compare_commits',
    'github_read_file',
    'github_write_file',
    'github_delete_file',
    'github_list_contents',
    'github_list_pull_requests',
    'github_get_pull_request',
    'github_create_pull_request',
    'github_merge_pull_request',
    'github_update_pull_request',
    'github_list_issues',
    'github_create_issue',
    'github_create_issue_comment',
    'github_get_user',
  ],
  ToolCategory.githubCicd: [
    'github_list_workflows',
    'github_trigger_workflow',
    'github_list_workflow_runs',
    'github_get_workflow_run',
    'github_get_workflow_logs',
    'github_cancel_workflow_run',
    'github_rerun_workflow',
    'github_list_artifacts',
    'github_list_secrets',
    'github_create_secret',
    'github_delete_secret',
    'github_list_variables',
    'github_create_variable',
    'github_update_variable',
    'github_delete_variable',
    'github_list_environments',
    'github_create_environment',
    'github_delete_environment',
    'github_list_env_secrets',
    'github_create_env_secret',
    'github_delete_env_secret',
    'github_list_env_variables',
    'github_create_env_variable',
    'github_update_env_variable',
    'github_delete_env_variable',
  ],
  ToolCategory.githubSettings: [
    'github_update_repo_settings',
    'github_replace_topics',
    'github_list_collaborators',
    'github_add_collaborator',
    'github_remove_collaborator',
    'github_get_branch_protection',
    'github_update_branch_protection',
    'github_delete_branch_protection',
    'github_list_webhooks',
    'github_create_webhook',
    'github_delete_webhook',
    'github_list_deploy_keys',
    'github_create_deploy_key',
    'github_delete_deploy_key',
    'github_get_pages',
    'github_enable_pages',
    'github_update_pages',
    'github_delete_pages',
    'github_list_pages_builds',
    'github_request_pages_build',
  ],
};

bool isGithubCategory(ToolCategory category) {
  return category == ToolCategory.githubCore ||
      category == ToolCategory.githubCicd ||
      category == ToolCategory.githubSettings;
}
