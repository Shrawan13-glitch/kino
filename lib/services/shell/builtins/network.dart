import 'dart:async';
import 'dart:io' show SocketException;
import 'package:http/http.dart' as http;
import '../shell_builtin.dart';
import '../shell_result.dart';

Map<String, BuiltinFunction> networkBuiltins() => {
      'curl': _cmdCurl,
    };

Future<ShellResult> _cmdCurl(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return const ShellResult(
      exitCode: 1, stdout: '',
      stderr: 'curl: try \'curl --help\' for more information',
    );
  }

  var url = '';
  var method = 'GET';
  final headers = <String, String>{};
  var data = '';
  var outputFile = '';
  var silent = false;
  var verbose = false;
  var includeHeaders = false;
  var followRedirects = false;
  var maxRedirects = 50;
  var timeoutSeconds = 30;

  var i = 0;
  while (i < args.length) {
    final arg = args[i];
    if (!arg.startsWith('-')) {
      url = arg;
      i++;
      continue;
    }

    if (arg == '--') { i++; break; }

    if (arg == '-X' || arg == '--request') {
      if (i + 1 >= args.length) return _curlError('$arg requires argument');
      method = args[i + 1].toUpperCase();
      i += 2;
      continue;
    }

    if (arg == '-d' || arg == '--data' || arg == '--data-raw') {
      if (i + 1 >= args.length) return _curlError('$arg requires argument');
      if (data.isNotEmpty) data += '&';
      data += args[i + 1];
      i += 2;
      continue;
    }

    if (arg == '-H' || arg == '--header') {
      if (i + 1 >= args.length) return _curlError('$arg requires argument');
      final hdr = args[i + 1];
      final colon = hdr.indexOf(':');
      if (colon > 0) {
        headers[hdr.substring(0, colon).trim()] =
            hdr.substring(colon + 1).trim();
      }
      i += 2;
      continue;
    }

    if (arg == '-o' || arg == '--output') {
      if (i + 1 >= args.length) return _curlError('$arg requires argument');
      outputFile = args[i + 1];
      i += 2;
      continue;
    }

    if (arg == '-s' || arg == '--silent') { silent = true; i++; continue; }
    if (arg == '-v' || arg == '--verbose') { verbose = true; i++; continue; }
    if (arg == '-i' || arg == '--include') { includeHeaders = true; i++; continue; }
    if (arg == '-L' || arg == '--location') { followRedirects = true; i++; continue; }

    if (arg == '--max-redirs') {
      if (i + 1 >= args.length) return _curlError('$arg requires argument');
      maxRedirects = int.tryParse(args[i + 1]) ?? 50;
      i += 2;
      continue;
    }

    if (arg == '--connect-timeout') {
      if (i + 1 >= args.length) return _curlError('$arg requires argument');
      timeoutSeconds = int.tryParse(args[i + 1]) ?? 30;
      i += 2;
      continue;
    }

    if (arg == '-k' || arg == '--insecure') { i++; continue; }
    if (arg == '-f' || arg == '--fail') { i++; continue; }

    return _curlError('curl: unknown option $arg');
  }

  if (url.isEmpty) return _curlError('curl: no URL specified');

  if (data.isNotEmpty && method == 'GET') method = 'POST';

  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'https://$url';
  }

  final parsed = Uri.tryParse(url);
  if (parsed == null) return _curlError('curl: malformed URL: $url');

  final errBuf = StringBuffer();
  if (!silent && verbose) errBuf.writeln('* Host: ${parsed.host}');
  if (!silent && verbose) errBuf.writeln('* Method: $method');
  if (!silent && verbose) errBuf.writeln('* URL: $url');

  try {
    var redirectCount = 0;
    var currentUri = parsed;
    late http.Response response;

    while (true) {
      final client = http.Client();
      try {
        final request = http.Request(method, currentUri);
        request.headers.addAll(headers);
        if (data.isNotEmpty) {
          request.body = data;
          if (!request.headers.containsKey('Content-Type')) {
            request.headers['Content-Type'] =
                'application/x-www-form-urlencoded';
          }
        }

        final streamed = await client.send(request).timeout(
          Duration(seconds: timeoutSeconds),
        );
        response = await http.Response.fromStream(streamed);

        if (!silent && verbose) {
          errBuf.writeln('* HTTP ${response.statusCode}');
          for (final entry in response.headers.entries) {
            errBuf.writeln('< ${entry.key}: ${entry.value}');
          }
          errBuf.writeln(
              '* Response body (${response.body.length} bytes)');
        }

        if (followRedirects &&
            redirectCount < maxRedirects &&
            (response.statusCode == 301 ||
                response.statusCode == 302 ||
                response.statusCode == 303 ||
                response.statusCode == 307 ||
                response.statusCode == 308)) {
          final location = response.headers['location'];
          if (location != null && location.isNotEmpty) {
            redirectCount++;
            currentUri = currentUri.resolve(location);
            if (!silent && verbose) {
              errBuf.writeln(
                  '* Redirect #$redirectCount to: $currentUri');
            }
            client.close();
            continue;
          }
        }
      } finally {
        client.close();
      }
      break;
    }

    final responseBody = response.body;
    final responseHeaders = response.headers;

    var stdout = '';
    if (includeHeaders) {
      stdout +=
          'HTTP/${response.statusCode} ${response.reasonPhrase}\n';
      for (final entry in responseHeaders.entries) {
        stdout += '${entry.key}: ${entry.value}\n';
      }
      stdout += '\n';
    }
    stdout += responseBody;

    if (outputFile.isNotEmpty) {
      final target = ctx.expander.resolvePath(outputFile);
      try {
        await ctx.vfs.writeFile(target, responseBody);
      } catch (e) {
        return ShellResult(
          exitCode: 1, stdout: '',
          stderr: '${errBuf}curl: Failed to write to $outputFile: $e\n',
        );
      }
      if (silent) {
        stdout = '';
      } else if (!includeHeaders) {
        stdout = responseBody.length <= 1024 ? responseBody : '';
        if (responseBody.length > 1024) {
          errBuf.writeln(
            '* Response body written to $outputFile ($responseBody.length bytes)',
          );
        }
      }
    }

    final stderr = errBuf.toString();
    final exitCode = response.statusCode >= 400 ? 1 : 0;

    return ShellResult(
        exitCode: exitCode, stdout: stdout, stderr: stderr);
  } on SocketException catch (e) {
    return ShellResult(
      exitCode: 6, stdout: '',
      stderr:
          '${errBuf}curl: Could not resolve host: ${parsed.host} (${e.message})\n',
    );
  } on TimeoutException {
    return ShellResult(
      exitCode: 28, stdout: '',
      stderr: '${errBuf}curl: Connection timed out after ${timeoutSeconds}s\n',
    );
  } on Exception catch (e) {
    return ShellResult(
      exitCode: 7, stdout: '',
      stderr: '${errBuf}curl: Connection failed: $e\n',
    );
  } catch (e) {
    return ShellResult(
      exitCode: 1, stdout: '',
      stderr: '${errBuf}curl: Error: $e\n',
    );
  }
}

ShellResult _curlError(String msg) {
  return ShellResult(exitCode: 1, stdout: '', stderr: '$msg\n');
}
