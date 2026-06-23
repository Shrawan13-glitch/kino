import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../vfs/vfs_ast.dart';

class BashRematch {
  List<String> matches = [];
  @override
  String toString() => matches.isEmpty ? '' : matches.join(' ');
}

class Job {
  final int id;
  final String command;
  final Process process;
  String status;
  int exitCode;

  Job(this.id, this.command, this.process, this.status) : exitCode = -1;
}

class ShellState {
  String cwd = '/';
  String previousCwd = '/';
  final List<String> dirStack = [];
  int lastExitCode = 0;
  String lastError = '';
  final Map<String, bool> setFlags = {};

  final Map<String, String> env = {
    'HOME': '/',
    'SHELL': '/bin/sh',
    'USER': 'kino',
    'TERM': 'xterm-256color',
    'PS1': r'\u@\h:\w\$ ',
    'PS2': '> ',
    'PS4': '+ ',
  };

  final Map<String, String> aliases = {};
  final Map<String, List<String>> arrays = {};
  final Map<String, AstNode> functions = {};
  final List<String> history = [];
  static const int historyMax = 1000;

  final Map<String, bool> shopt = {
    'dotglob': false,
    'extglob': false,
    'nullglob': false,
    'failglob': false,
    'globstar': false,
    'nocaseglob': false,
    'histexpand': false,
    'cdable_vars': false,
    'cdspell': false,
    'checkwinsize': false,
    'cmdhist': true,
    'expand_aliases': true,
    'gnu_errfmt': false,
    'histappend': true,
    'hostcomplete': true,
    'huponexit': false,
    'interactive_comments': true,
    'lithist': false,
    'localvars': true,
    'mailwarn': false,
    'no_empty_cmd_completion': false,
    'norc': false,
    'restricted_shell': false,
    'shift_verbose': false,
    'sourcepath': true,
    'xpg_echo': false,
    'nocasematch': false,
    'pipefail': false,
    'autocd': false,
    'checkhash': false,
    'checkjobs': false,
    'direxpand': false,
    'dirspell': false,
    'execfail': false,
    'extdebug': false,
    'extquote': true,
    'force_fignore': true,
    'globskipdots': true,
    'histreedit': false,
    'histverify': false,
    'inherit_errexit': false,
    'lastpipe': false,
    'login_shell': false,
    'noexpand_translation': false,
    'patsub_replacement': false,
    'progcomp': true,
    'progcomp_alias': false,
    'promptvars': true,
    'syslog_history': false,
  };

  int breakDepth = 0;
  int continueDepth = 0;
  bool returnFromFunction = false;
  bool exitRequested = false;

  final Map<String, Map<String, String>> assocArrays = {};
  int nextJobId = 1;
  String? globIgnore;
  final Map<String, List<String>> completions = {};
  final Map<int, Job> jobs = {};
  final BashRematch bashRematch = BashRematch();
  List<String> positionalParams = [];
  int lastBgPid = 0;
  int getoptsIndex = 0;
  int getoptsPos = 0;

  final Stopwatch shellTimer = Stopwatch()..start();

  String pipeStatusString = '0';
  String underscore = '';
  final Random random = Random();

  final Map<String, String> hashTable = {};
  int umask = 0022;

  final Map<String, String> traps = {};

  static const Map<int, String> signalNames = {
    0: 'EXIT', 1: 'SIGHUP', 2: 'SIGINT', 3: 'SIGQUIT', 4: 'SIGILL',
    5: 'SIGTRAP', 6: 'SIGABRT', 7: 'SIGBUS', 8: 'SIGFPE', 9: 'SIGKILL',
    10: 'SIGUSR1', 11: 'SIGSEGV', 12: 'SIGUSR2', 13: 'SIGPIPE', 14: 'SIGALRM',
    15: 'SIGTERM', 16: 'SIGSTKFLT', 17: 'SIGCHLD', 18: 'SIGCONT', 19: 'SIGSTOP',
    20: 'SIGTSTP', 21: 'SIGTTIN', 22: 'SIGTTOU',
  };

  int get pid => 1;

  String lookupVar(String name) {
    if (env.containsKey(name)) return env[name]!;
    if (name == '?') return lastExitCode.toString();
    if (name == r'$') return pid.toString();
    if (name == '!') return lastBgPid.toString();
    if (name == '0') return 'kino';
    if (name == '#') return positionalParams.length.toString();
    if (name == '@') return positionalParams.join(' ');
    if (name == '*') return positionalParams.join(' ');
    if (name.length == 1 && name.codeUnitAt(0) >= 49 && name.codeUnitAt(0) <= 57) {
      final idx = int.parse(name) - 1;
      return idx < positionalParams.length ? positionalParams[idx] : '';
    }
    if (name == 'RANDOM') return random.nextInt(32768).toString();
    if (name == 'LINENO') return '0';
    if (name == 'SECONDS') return shellTimer.elapsed.inSeconds.toString();
    if (name == 'EPOCHREALTIME') return (DateTime.now().microsecondsSinceEpoch / 1000000).toStringAsFixed(6);
    if (name == 'EPOCHSECONDS') return (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    if (name == 'HOSTNAME') {
      try { return Platform.localHostname; } catch (_) { return 'localhost'; }
    }
    if (name == 'OSTYPE') {
      if (Platform.isAndroid) return 'linux-android';
      if (Platform.isLinux) return 'linux-gnu';
      if (Platform.isMacOS) return 'darwin';
      if (Platform.isWindows) return 'windows';
      return 'unknown';
    }
    if (name == 'BASHPID') return pid.toString();
    if (name == '_') return underscore;
    if (name == '-') return currentFlags();
    if (name == 'PIPESTATUS') return pipeStatusString;
    if (name == 'BASH_VERSION') return '5.2.26(1)-kino';
    if (name == 'BASH_VERSINFO') return '5';
    if (name == 'MACHTYPE') {
      if (Platform.isAndroid) return 'aarch64-unknown-linux-android';
      return Platform.localHostname.contains('arm') ? 'aarch64-unknown-linux-gnu' : 'x86_64-unknown-linux-gnu';
    }
    if (name == 'BASH_SUBSHELL') return '0';
    if (name == 'BASH_REMATCH') return bashRematch.toString();
    if (name == 'GLOBIGNORE') return globIgnore ?? '';
    if (arrays.containsKey(name)) {
      final arr = arrays[name]!;
      return arr.isNotEmpty ? arr.join(' ') : '';
    }
    if (assocArrays.containsKey(name)) {
      final arr = assocArrays[name]!;
      return arr.values.isNotEmpty ? arr.values.join(' ') : '';
    }
    return '';
  }

  String currentFlags() {
    var flags = '';
    if (setFlags['-e'] == true) flags += 'e';
    if (setFlags['-x'] == true) flags += 'x';
    if (setFlags['-u'] == true) flags += 'u';
    if (setFlags['-v'] == true) flags += 'v';
    return flags.isEmpty ? 'hB' : '${flags}hB';
  }

  int getArithVar(String name) {
    final val = lookupVar(name);
    if (val.isNotEmpty) {
      final parsed = int.tryParse(val);
      if (parsed != null) return parsed;
    }
    if (arrays.containsKey(name) && arrays[name]!.isNotEmpty) {
      final parsed = int.tryParse(arrays[name]!.last);
      if (parsed != null) return parsed;
    }
    return 0;
  }

  void setArithVar(String name, int val) {
    env[name] = val.toString();
  }

  String expandPrompt(String ps) {
    return ps
        .replaceAll(r'\h', _getHostname())
        .replaceAll(r'\H', _getHostname())
        .replaceAll(r'\u', env['USER'] ?? 'kino')
        .replaceAll(r'\w', cwd)
        .replaceAll(r'\W', p.basename(cwd))
        .replaceAll(r'\d', _dateFormat())
        .replaceAll(r'\t', _timeFormat('HH:mm:ss'))
        .replaceAll(r'\@', _timeFormat('hh:mm am'))
        .replaceAll(r'\A', _timeFormat('HH:mm'))
        .replaceAll(r'\s', 'kino')
        .replaceAll(r'\v', '1.0')
        .replaceAll(r'\V', '1.0.0')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\e', '\x1b')
        .replaceAll(r'\\', '\\')
        .replaceAll(r'\$', env['USER'] == 'root' ? '#' : r'$')
        .replaceAll(r'\!', (history.length + 1).toString())
        .replaceAll(r'\#', (history.length + 1).toString());
  }

  String _getHostname() {
    try { return Platform.localHostname; } catch (_) { return 'localhost'; }
  }

  String _dateFormat() {
    final now = DateTime.now();
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[now.weekday % 7]} ${months[now.month - 1]} ${now.day.toString().padLeft(2, ' ')}';
  }

  String _timeFormat(String fmt) {
    final now = DateTime.now();
    return fmt
        .replaceAll('HH', now.hour.toString().padLeft(2, '0'))
        .replaceAll('mm', now.minute.toString().padLeft(2, '0'))
        .replaceAll('ss', now.second.toString().padLeft(2, '0'))
        .replaceAll('hh', (now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour)).toString().padLeft(2, '0'))
        .replaceAll('am', now.hour < 12 ? 'am' : 'pm');
  }
}
