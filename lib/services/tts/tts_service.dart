import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../github/github_auth_service.dart';
import '../github/github_api_service.dart';
import '../github/github_repo_service.dart';
import '../vfs/vfs_service.dart';
import '../debug_service.dart';
import 'tts_result.dart';

class TtsService {
  final GithubRepoService _repoService;
  final VfsService _vfs = VfsService();

  TtsService(GithubAuthService auth) : _repoService = GithubRepoService(auth);

  Future<String> generateSpeech({
    required List<TtsItem> items,
    required String outputPath,
  }) async {
    final stopwatch = Stopwatch()..start();
    final api = _repoService.api;

    try {
      DebugService.instance.info(
        'TTS: starting with ${items.length} item(s), output=$outputPath',
      );

      await _repoService.ensureRepoExists();

      final itemsJson = jsonEncode(items.map((i) => i.toJson()).toList());

      // Record the current latest run BEFORE we dispatch
      final beforeRunId = await api.getLatestDispatchRunId();
      DebugService.instance.info(
        'TTS: latest run before dispatch=$beforeRunId, triggering...',
      );

      await api.triggerWorkflow(itemsJson);

      // Wait for the new run to appear (the one we just triggered)
      DebugService.instance.info('TTS: waiting for new run to appear...');
      final runId = await api.awaitNewRun(beforeRunId);
      DebugService.instance.info('TTS: new run $runId detected');

      // Now poll that specific run until it completes
      DebugService.instance.info('TTS: waiting for run $runId to finish...');
      await _pollForSpecificRun(api, runId);
      DebugService.instance.info('TTS: run $runId completed');

      DebugService.instance.info('TTS: downloading artifact...');
      final zipBytes = await api.downloadArtifact(runId);

      final wavBytes = _extractWavFromZip(zipBytes);
      if (wavBytes == null) {
        return 'Error: no merged.wav found in workflow artifact. '
            'Check your workflow at ${await _repoService.getRepoUrl()}';
      }

      final resolvedPath =
          outputPath.startsWith('/') ? outputPath : '/$outputPath';
      await _vfs.writeFile(resolvedPath, wavBytes);

      final elapsed = stopwatch.elapsed;
      final sizeKb = (wavBytes.length / 1024).toStringAsFixed(1);

      return '✅ Speech generated (${elapsed.inSeconds}s, $sizeKb KB)\n'
          'Segments: ${items.length}\n'
          'File: $resolvedPath\n'
          'Voices used: ${items.map((i) => i.voice).toSet().join(', ')}';
    } catch (e, s) {
      DebugService.instance.error('TTS: failed', e, s);
      return 'Error: $e';
    }
  }

  Future<void> _pollForSpecificRun(
    GithubApiService api,
    int runId, {
    Duration pollInterval = const Duration(seconds: 10),
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final run = await api.getWorkflowRun(runId);

      if (run == null) {
        await Future.delayed(pollInterval);
        continue;
      }

      final status = run['status'] as String?;
      final conclusion = run['conclusion'] as String?;

      DebugService.instance.info(
        'TTS: run $runId status=$status conclusion=$conclusion',
      );

      if (status == 'completed') {
        if (conclusion == 'success') return;
        throw Exception(
          'Workflow $conclusion. Check: ${run['html_url']}',
        );
      }

      await Future.delayed(pollInterval);
    }

    throw Exception('TTS timed out after ${timeout.inSeconds}s');
  }

  Uint8List? _extractWavFromZip(List<int> zipBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      for (final file in archive) {
        if (file.name == 'merged.wav' && file.isFile) {
          return Uint8List.fromList(file.content as List<int>);
        }
      }
      return null;
    } catch (e) {
      DebugService.instance.error('TTS: failed to extract WAV from zip', e);
      return null;
    }
  }

  void dispose() {
    _repoService.dispose();
  }
}
