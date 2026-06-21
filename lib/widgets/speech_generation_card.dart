import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../constants.dart';

enum _CardPhase { loading, morphing, revealing, playing }

class SpeechGenerationCard extends StatefulWidget {
  final bool isCompleted;
  final String? result;
  final String vfsPath;

  const SpeechGenerationCard({
    super.key,
    this.isCompleted = false,
    this.result,
    this.vfsPath = '',
  });

  @override
  State<SpeechGenerationCard> createState() => _SpeechGenerationCardState();
}

class _SpeechGenerationCardState extends State<SpeechGenerationCard>
    with TickerProviderStateMixin {
  late AnimationController _animController;
  late AnimationController _fadeController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Random _rng = Random(42);

  _CardPhase _phase = _CardPhase.loading;

  static const int _dotCount = 40;
  late List<_Dot> _dots;

  static const int _patternCount = 23;
  final List<List<Offset>> _patternTargets = [];

  ProcessingState _audioState = ProcessingState.idle;
  bool _audioPlaying = false;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;

  static const _statusTexts = [
    'Generating',
    'Synthesizing',
    'Making',
    'Waving',
    'Tuning',
    'Processing',
    'Assembling',
    'Shaping',
    'Crafting',
    'Breathing',
    'Resonating',
    'Channeling',
    'Weaving',
    'Forming',
    'Melding',
    'Conjuring',
  ];

  static const _dotColors = [
    Color(0xFF6C63FF),
    Color(0xFF7C73FF),
    Color(0xFF8B83FF),
    Color(0xFF5C53E8),
    Color(0xFF4C43D0),
    Color(0xFF9B93FF),
    Color(0xFFABA3FF),
    Color(0xFF7B73FF),
    Color(0xFF4FC3F7),
    Color(0xFF6FCFF7),
    Color(0xFF8FDAFF),
  ];

  Timer? _patternTimer;
  Timer? _typewriterTimer;
  int _statusCycleIndex = 0;
  String _displayedText = '';
  int _charIndex = 0;
  bool _erasing = false;
  bool _showDone = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeController.addListener(() {
      if (mounted) setState(() {});
    });
    _generatePatterns();
    _initDots();
    _setupAudio();

    if (widget.isCompleted) {
      _phase = _CardPhase.playing;
      _fadeController.value = 1.0;
      _loadAudio();
    } else {
      _startPatternCycle();
      _startTypewriter();
    }
  }

  void _setupAudio() {
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _audioState = state.processingState;
          _audioPlaying = state.playing;
        });
      }
    });
    _audioPlayer.positionStream.listen((pos) {
      if (mounted) setState(() => _audioPosition = pos);
    });
    _audioPlayer.durationStream.listen((dur) {
      if (mounted) setState(() => _audioDuration = dur ?? Duration.zero);
    });
  }

  Future<void> _loadAudio() async {
    if (widget.vfsPath.isEmpty) return;
    final appDir = await getApplicationDocumentsDirectory();
    final clean = widget.vfsPath.startsWith('/')
        ? widget.vfsPath.substring(1)
        : widget.vfsPath;
    final absPath = p.join(appDir.path, 'vfs', clean);
    final file = File(absPath);
    if (await file.exists()) {
      await _audioPlayer.setAudioSource(AudioSource.uri(Uri.file(absPath)));
    }
  }

  void _generatePatterns() {
    for (var p = 0; p < _patternCount; p++) {
      _patternTargets.add(_generatePattern(p, _dotCount));
    }
  }

  List<Offset> _generatePattern(int index, int n) {
    final targets = <Offset>[];
    switch (index) {
      case 0:
        for (var i = 0; i < n; i++) {
          final a = i / n * 2 * pi;
          targets.add(Offset(0.5 + 0.35 * cos(a), 0.5 + 0.35 * sin(a)));
        }
      case 1:
        for (var i = 0; i < n; i++) {
          if (i < 6) {
            final a = i / 6 * 2 * pi;
            targets.add(Offset(0.35 + 0.08 * cos(a), 0.3 + 0.08 * sin(a)));
          } else if (i < 12) {
            final a = (i - 6) / 6 * 2 * pi;
            targets.add(Offset(0.65 + 0.08 * cos(a), 0.3 + 0.08 * sin(a)));
          } else {
            final t = (i - 12) / (n - 12);
            final a = pi * (0.8 + t * 0.4);
            targets.add(Offset(0.5 + 0.2 * sin(a), 0.65 + 0.12 * (1 - cos(a))));
          }
        }
      case 2:
        for (var i = 0; i < n; i++) {
          final x = i / n;
          final wave = sin(x * 6 * pi) + sin(x * 10 * pi + 1) * 0.5;
          targets.add(Offset(0.1 + x * 0.8, 0.5 + wave * 0.15));
        }
      case 3:
        for (var i = 0; i < n; i++) {
          final bar = (i * 5 ~/ n);
          final bh = 0.15 + 0.25 * sin(bar * 1.5 + index * 0.5);
          final x = (bar + 0.5) / 5;
          final yf = (i % (n ~/ 5)) / (n ~/ 5);
          targets.add(Offset(x, 0.5 - bh * 0.5 + yf * bh));
        }
      case 4:
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          final x = 0.5 + 0.3 * (16 * pow(sin(t), 3)).toDouble();
          final y = 0.5 - 0.3 * (13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)).toDouble();
          final s = 0.018;
          targets.add(Offset(0.5 + (x - 0.5) * s * 15, 0.5 + (y - 0.5) * s * 15));
        }
      case 5:
        for (var i = 0; i < n; i++) {
          final t = i / n * 4 * pi;
          final r = 0.05 + 0.3 * (i / n);
          targets.add(Offset(0.5 + r * cos(t), 0.5 + r * sin(t)));
        }
      case 6:
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          final r = 0.35 / (1 + 0.5 * cos(2 * t));
          targets.add(Offset(0.5 + r * cos(t), 0.5 + r * sin(t)));
        }
      case 7:
        for (var i = 0; i < n; i++) {
          final side = (i * 3 ~/ n);
          final pos = (i % (n ~/ 3)) / (n ~/ 3.toDouble());
          double x, y;
          if (side == 0) {
            x = 0.2 + pos * 0.6;
            y = 0.75 - pos * 0.6;
          } else if (side == 1) {
            x = 0.8 - pos * 0.6;
            y = 0.15 + pos * 0.6;
          } else {
            x = 0.2 + pos * 0.6;
            y = 0.75;
          }
          targets.add(Offset(x, y));
        }
      case 8:
        final seed = Random(index * 7 + 13);
        for (var i = 0; i < n; i++) {
          targets.add(Offset(0.1 + 0.8 * seed.nextDouble(), 0.1 + 0.8 * seed.nextDouble()));
        }
      case 9:
        for (var i = 0; i < n; i++) {
          final ring = (i * 2 ~/ n);
          final ir = i % (n ~/ 2);
          final cnt = n ~/ 2;
          final a = ir / cnt * 2 * pi;
          final r = ring == 0 ? 0.15 : 0.33;
          targets.add(Offset(0.5 + r * cos(a), 0.5 + r * sin(a)));
        }
      case 10:
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          final x = 0.5 + 0.3 * sin(t) / (1 + pow(cos(t), 2));
          final y = 0.5 + 0.2 * sin(t) * cos(t) / (1 + pow(cos(t), 2));
          targets.add(Offset(x.toDouble(), y.toDouble()));
        }
      case 11:
        for (var i = 0; i < n; i++) {
          final x = i / n;
          final y = 0.5 + 0.1 * sin(x * 8 * pi) + 0.05 * sin(x * 16 * pi);
          targets.add(Offset(x, y));
        }
      case 12:
        for (var i = 0; i < n; i++) {
          final x = i / n;
          final freq = 4 + 4 * (i / n);
          final w1 = 0.12 * sin(x * freq * pi);
          final w2 = 0.08 * sin(x * freq * 2 * pi + 1.5);
          targets.add(Offset(x, 0.5 + w1 + w2));
        }
      case 13:
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          final r = 0.3 + 0.1 * cos(t * 2) + 0.05 * cos(t * 3);
          targets.add(Offset(0.5 + r * cos(t), 0.5 + r * sin(t) * 0.7));
        }
      case 14:
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi - pi / 2;
          final pts = 5;
          final r = (i % (n ~/ pts) == 0) ? 0.35 : 0.15;
          targets.add(Offset(0.5 + r * cos(t), 0.5 + r * sin(t)));
        }
      case 15:
        final cols = 8;
        for (var i = 0; i < n; i++) {
          final row = i ~/ cols;
          final col = i % cols;
          targets.add(Offset(0.06 + col * 0.125, 0.06 + row * 0.125));
        }
      case 16:
        for (var i = 0; i < n; i++) {
          final a = i / n * 2 * pi;
          final r = 0.05 + 0.3 * (i / n);
          targets.add(Offset(0.5 + r * cos(a), 0.5 + r * sin(a)));
        }
      case 17:
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          final r = 0.35;
          targets.add(Offset(0.5 + r * cos(t), 0.5 + r * sin(t)));
        }
      case 18:
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          final r = 0.3 * (0.5 + 0.5 * sin(t * 3)) * (1 + 0.3 * cos(t * 4));
          targets.add(Offset(0.5 + r * cos(t), 0.5 + r * sin(t) * 0.7));
        }
      case 19:
        for (var i = 0; i < n; i++) {
          final t = i / n * 6 * pi;
          final r = 0.05 + 0.32 * (i / n);
          final sp = 0.03 * (1 - i / n);
          final a = t + sp * sin(t * 3);
          targets.add(Offset(0.5 + r * cos(a), 0.5 + r * sin(a)));
        }
      case 20:
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          targets.add(Offset(0.5 + 0.35 * sin(3 * t + 0.5), 0.5 + 0.35 * sin(2 * t)));
        }
      case 21:
        for (var i = 0; i < n; i++) {
          final a = i / n * 2 * pi;
          final r = 0.15 + 0.2 * ((i % 12) / 12);
          targets.add(Offset(0.5 + r * cos(a), 0.5 + r * sin(a)));
        }
      case 22: // Thumbs up
        // Thumb: 2 columns × 6 rows (12 dots)
        for (var row = 0; row < 6; row++) {
          final t = row / 5;
          final y = 0.16 + t * 0.32;
          targets.add(Offset(0.28 + t * 0.02, y));
          targets.add(Offset(0.34 + t * 0.02, y));
        }
        // Knuckle bridge (2 dots)
        targets.add(const Offset(0.28, 0.46));
        targets.add(const Offset(0.34, 0.46));
        // Fist: two concentric rings (26 dots)
        for (var i = 8; i < n; i++) {
          final ring = ((i - 8) * 2 ~/ (n - 8));
          final ir = (i - 8) % ((n - 8) ~/ 2);
          final cnt = (n - 8) ~/ 2;
          final a = ir / cnt * 2 * pi;
          final r = ring == 0 ? 0.14 : 0.22;
          targets.add(Offset(0.52 + r * cos(a), 0.58 + r * sin(a) * 0.8));
        }
      default:
        for (var i = 0; i < n; i++) {
          targets.add(const Offset(0.5, 0.5));
        }
    }
    return targets;
  }

  void _initDots() {
    _dots = List.generate(_dotCount, (i) {
      return _Dot(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        targetX: 0.5,
        targetY: 0.5,
        color: _dotColors[i % _dotColors.length].withValues(alpha: 0.75 + 0.25 * _rng.nextDouble()),
        radius: 4.0 + _rng.nextDouble() * 3.0,
        speed: 0.02 + _rng.nextDouble() * 0.03,
      );
    });
  }

  void _startPatternCycle() {
    _patternTimer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (!mounted || _phase != _CardPhase.loading) return;
      setState(() {
        _currentPattern = (_currentPattern + 1) % 22;
        _setPatternTargets(_currentPattern);
        _resetTypewriter();
      });
    });
  }

  void _resetTypewriter() {
    _erasing = true;
  }

  int _currentPattern = 0;

  void _setPatternTargets(int idx) {
    final targets = _patternTargets[idx];
    for (var i = 0; i < _dotCount && i < targets.length; i++) {
      _dots[i].targetX = targets[i].dx;
      _dots[i].targetY = targets[i].dy;
    }
  }

  void _startTypewriter() {
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted || (_phase != _CardPhase.loading && _phase != _CardPhase.morphing)) return;
      setState(() {
        final currentWord = _statusTexts[_statusCycleIndex];
        if (_erasing) {
          if (_charIndex > 0) {
            _charIndex--;
            _displayedText = currentWord.substring(0, _charIndex);
          } else {
            _erasing = false;
            _statusCycleIndex = (_statusCycleIndex + 1) % _statusTexts.length;
          }
        } else if (_charIndex < currentWord.length) {
          _charIndex++;
          _displayedText = currentWord.substring(0, _charIndex);
        }
      });
    });
  }

  void _startMorph() {
    _phase = _CardPhase.morphing;
    _patternTimer?.cancel();
    _typewriterTimer?.cancel();
    _displayedText = '';
    _charIndex = 0;
    _showDone = false;

    // Move dots to thumbs up
    _setPatternTargets(22);

    // After dots settle, show "Done"
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _showDone = true);
    });

    // Start crossfade to player
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() => _phase = _CardPhase.revealing);
      _fadeController.forward();
      _loadAudio();
    });

    Future.delayed(const Duration(milliseconds: 3400), () {
      if (!mounted) return;
      setState(() => _phase = _CardPhase.playing);
    });
  }

  @override
  void didUpdateWidget(SpeechGenerationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCompleted && !oldWidget.isCompleted && _phase == _CardPhase.loading) {
      _startMorph();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _fadeController.dispose();
    _audioPlayer.dispose();
    _patternTimer?.cancel();
    _typewriterTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = 260.0;
        final fadeValue = _fadeController.value;
        final revealing = _phase == _CardPhase.revealing;
        final showDots = _phase != _CardPhase.playing;
        final showPlayer = revealing || _phase == _CardPhase.playing;
        final dotsOpacity = revealing ? 1.0 - fadeValue : 1.0;
        final playerOpacity = revealing ? fadeValue : 1.0;
        final showLoadingText = _phase == _CardPhase.loading;
        final showDoneText = _showDone && _phase != _CardPhase.playing;
        final textOpacity = _phase == _CardPhase.revealing
            ? 1.0 - fadeValue
            : 1.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.08),
                AppColors.primary.withValues(alpha: 0.03),
                AppColors.accent.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: height,
                width: width,
                child: Stack(
                  children: [
                    Opacity(
                      opacity: showDots ? dotsOpacity : 0,
                      child: IgnorePointer(
                        ignoring: !showDots,
                        child: AnimatedBuilder(
                          animation: _animController,
                          builder: (context, _) {
                            _updateDots();
                            return CustomPaint(
                              painter: _DotPainter(_dots),
                              size: Size(width, height),
                            );
                          },
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: showPlayer ? playerOpacity : 0,
                      child: IgnorePointer(
                        ignoring: !showPlayer,
                        child: _buildPlayer(context),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showLoadingText)
                      Opacity(
                        opacity: textOpacity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_displayedText...',
                              style: TextStyle(
                                color: AppColors.primary.withValues(alpha: 0.85),
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'generating audio, please wait',
                              style: TextStyle(
                                color: AppColors.textSecondary(context).withValues(alpha: 0.45),
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (showDoneText)
                      Opacity(
                        opacity: textOpacity,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.3, end: 1.0),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.elasticOut,
                          builder: (context, scale, child) {
                            return Transform.scale(scale: scale, child: child);
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.primary,
                                size: 30,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Done',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlayer(BuildContext context) {
    final progress = _audioDuration.inMilliseconds > 0
        ? _audioPosition.inMilliseconds / _audioDuration.inMilliseconds
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // CD icon at top center
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.35),
                  AppColors.primary.withValues(alpha: 0.1),
                ],
              ),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Filename below CD
          Text(
            widget.vfsPath.split('/').last,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 12),
          // Seekable progress bar with time labels
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                _formatDuration(_audioPosition),
                style: TextStyle(
                  color: AppColors.textSecondary(context).withValues(alpha: 0.6),
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: AppColors.primary.withValues(alpha: 0.15),
                    thumbColor: AppColors.primary,
                    overlayColor: AppColors.primary.withValues(alpha: 0.12),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: (v) {
                      final ms = (v * _audioDuration.inMilliseconds).round();
                      _audioPlayer.seek(Duration(milliseconds: ms));
                    },
                  ),
                ),
              ),
              Text(
                _formatDuration(_audioDuration),
                style: TextStyle(
                  color: AppColors.textSecondary(context).withValues(alpha: 0.6),
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Play/Pause button centered
          GestureDetector(
            onTap: () {
              if (_audioPlaying) {
                _audioPlayer.pause();
              } else if (_audioState == ProcessingState.completed) {
                _audioPlayer.seek(Duration.zero);
                _audioPlayer.play();
              } else {
                _audioPlayer.play();
              }
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
              child: Icon(
                _audioPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: AppColors.primary,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _updateDots() {
    for (final dot in _dots) {
      dot.x += (dot.targetX - dot.x) * dot.speed;
      dot.y += (dot.targetY - dot.y) * dot.speed;
    }
  }
}

class _Dot {
  double x, y, targetX, targetY;
  final Color color;
  final double radius;
  final double speed;

  _Dot({
    required this.x,
    required this.y,
    required this.targetX,
    required this.targetY,
    required this.color,
    required this.radius,
    required this.speed,
  });
}

class _DotPainter extends CustomPainter {
  final List<_Dot> dots;

  _DotPainter(this.dots);

  @override
  void paint(Canvas canvas, Size size) {
    for (final dot in dots) {
      final px = dot.x * size.width;
      final py = dot.y * size.height;
      final paint = Paint()
        ..color = dot.color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(Offset(px, py), dot.radius, paint);

      final glowPaint = Paint()
        ..color = dot.color.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(px, py), dot.radius * 2.5, glowPaint);
    }
  }

  @override
  bool shouldRepaint(_DotPainter oldDelegate) => true;
}
