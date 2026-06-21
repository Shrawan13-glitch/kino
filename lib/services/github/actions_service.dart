// ignore_for_file: use_null_aware_elements
import 'github_client.dart';

class GithubActionsService {
  final GithubClient _client;

  GithubActionsService(this._client);

  Future<List<Map<String, dynamic>>> listWorkflows(
      String owner, String repo) async {
    final data = await _client.get('/repos/$owner/$repo/actions/workflows');
    return (data['workflows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> getWorkflow(
      String owner, String repo, dynamic workflowId) {
    return _client.get('/repos/$owner/$repo/actions/workflows/$workflowId');
  }

  Future<void> triggerWorkflow(
    String owner, String repo,
    String workflowId, {
    required String ref,
    Map<String, dynamic>? inputs,
  }) async {
    await _client.post(
      '/repos/$owner/$repo/actions/workflows/$workflowId/dispatches',
      body: {
        'ref': ref,
        if (inputs != null && inputs.isNotEmpty) 'inputs': inputs,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listWorkflowRuns(
    String owner, String repo, {
    String? workflowId,
    String? event,
    String? status,
    String? branch,
    int perPage = 30,
  }) async {
    String path;
    if (workflowId != null) {
      path = '/repos/$owner/$repo/actions/workflows/$workflowId/runs';
    } else {
      path = '/repos/$owner/$repo/actions/runs';
    }
    final data = await _client.get(path, query: {
      if (event != null) 'event': event,
      if (status != null) 'status': status,
      if (branch != null) 'branch': branch,
      'per_page': perPage.toString(),
    });
    return (data['workflow_runs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> getWorkflowRun(
      String owner, String repo, int runId) {
    return _client.get('/repos/$owner/$repo/actions/runs/$runId');
  }

  Future<String> getWorkflowRunLogs(
      String owner, String repo, int runId) async {
    final resp = await _client.getRaw(
        '/repos/$owner/$repo/actions/runs/$runId/logs');
    return resp.body;
  }

  Future<Map<String, dynamic>> getWorkflowRunAttemptLogs(
      String owner, String repo, int runId, int attempt) async {
    final resp = await _client.getRaw(
        '/repos/$owner/$repo/actions/runs/$runId/attempts/$attempt/logs');
    return {
      'run_id': runId,
      'attempt': attempt,
      'logs': resp.body,
    };
  }

  Future<void> cancelWorkflowRun(
      String owner, String repo, int runId) async {
    await _client.post(
        '/repos/$owner/$repo/actions/runs/$runId/cancel');
  }

  Future<void> rerunWorkflow(String owner, String repo, int runId) async {
    await _client.post(
        '/repos/$owner/$repo/actions/runs/$runId/rerun');
  }

  Future<List<Map<String, dynamic>>> listWorkflowRunArtifacts(
      String owner, String repo, int runId) async {
    final data =
        await _client.get('/repos/$owner/$repo/actions/runs/$runId/artifacts');
    return (data['artifacts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<List<int>> downloadArtifact(
      String owner, String repo, int artifactId) async {
    final data =
        await _client.get('/repos/$owner/$repo/actions/artifacts/$artifactId');
    final downloadUrl = data['archive_download_url'] as String?;
    if (downloadUrl == null) throw Exception('No download URL');

    final resp = await _client.getRaw(downloadUrl.replaceAll('https://api.github.com/', ''));
    return resp.bodyBytes;
  }

  Future<Map<String, dynamic>> getRepoSecret(
      String owner, String repo, String name) {
    return _client.get('/repos/$owner/$repo/actions/secrets/$name');
  }

  Future<List<Map<String, dynamic>>> listRepoSecrets(
      String owner, String repo) async {
    final data = await _client.get('/repos/$owner/$repo/actions/secrets');
    return (data['secrets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<void> createOrUpdateRepoSecret(
      String owner, String repo, String name, String value) {
    return _client.put('/repos/$owner/$repo/actions/secrets/$name', body: {
      'encrypted_value': value,
    });
  }

  Future<void> deleteRepoSecret(
      String owner, String repo, String name) {
    return _client.delete('/repos/$owner/$repo/actions/secrets/$name');
  }

  Future<Map<String, dynamic>> getRepoVariable(
      String owner, String repo, String name) {
    return _client.get('/repos/$owner/$repo/actions/variables/$name');
  }

  Future<List<Map<String, dynamic>>> listRepoVariables(
      String owner, String repo) async {
    final data = await _client.get('/repos/$owner/$repo/actions/variables');
    return (data['variables'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> createRepoVariable(
      String owner, String repo,
      String name, String value) {
    return _client.post('/repos/$owner/$repo/actions/variables', body: {
      'name': name,
      'value': value,
    });
  }

  Future<Map<String, dynamic>> updateRepoVariable(
      String owner, String repo,
      String name, String value) {
    return _client.patch('/repos/$owner/$repo/actions/variables/$name',
        body: {'value': value});
  }

  Future<void> deleteRepoVariable(
      String owner, String repo, String name) {
    return _client.delete('/repos/$owner/$repo/actions/variables/$name');
  }

  Future<Map<String, dynamic>> getWorkflowRunUsage(
      String owner, String repo, int runId) {
    return _client.get('/repos/$owner/$repo/actions/runs/$runId/timing');
  }

  Future<Map<String, dynamic>> getWorkflowUsage(
      String owner, String repo, dynamic workflowId) {
    return _client.get('/repos/$owner/$repo/actions/workflows/$workflowId/timing');
  }
}
