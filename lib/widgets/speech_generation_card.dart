import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../constants.dart';
import 'audio_player_widget.dart';

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
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final Random _rng = Random(42);

  static const int _dotCount = 36;
  late List<_Dot> _dots;
  int _currentPattern = 0;
  double _patternProgress = 0.0;

  static const int _patternCount = 22;
  final List<List<Offset>> _patternTargets = [];

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

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    _generatePatterns();
    _initDots();
    _startPatternCycle();
    _startTypewriter();
  }

  void _generatePatterns() {
    for (var p = 0; p < _patternCount; p++) {
      _patternTargets.add(_generatePattern(p, _dotCount));
    }
  }

  List<Offset> _generatePattern(int index, int n) {
    final targets = <Offset>[];
    switch (index % _patternCount) {
      case 0: // Circle
        for (var i = 0; i < n; i++) {
          final a = i / n * 2 * pi;
          targets.add(Offset(0.5 + 0.35 * cos(a), 0.5 + 0.35 * sin(a)));
        }
      case 1: // Smiley face
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
      case 2: // Sound wave
        for (var i = 0; i < n; i++) {
          final x = i / n;
          final wave = sin(x * 6 * pi) * 0.15 +
              sin(x * 10 * pi + 1) * 0.08;
          targets.add(Offset(0.1 + x * 0.8, 0.5 + wave));
        }
      case 3: // Equalizer bars
        for (var i = 0; i < n; i++) {
          final bar = (i * 5 ~/ n);
          final barHeight = 0.15 + 0.25 * sin(bar * 1.5 + index * 0.5);
          final x = (bar + 0.5) / 5;
          final yFrac = (i % (n ~/ 5)) / (n ~/ 5);
          targets.add(Offset(x, 0.5 - barHeight * 0.5 + yFrac * barHeight));
        }
      case 4: // Heart
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          final x = 0.5 + 0.3 * (16 * pow(sin(t), 3)).toDouble();
          final y = 0.5 - 0.3 * (13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)).toDouble();
          final scale = 0.018;
          targets.add(Offset(0.5 + (x - 0.5) * scale * 15, 0.5 + (y - 0.5) * scale * 15));
        }
      case 5: // Spiral
        for (var i = 0; i < n; i++) {
          final t = i / n * 4 * pi;
          final r = 0.05 + 0.3 * (i / n);
          targets.add(Offset(0.5 + r * cos(t), 0.5 + r * sin(t)));
        }
      case 6: // Diamond
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          final r = 0.35 / (1 + 0.5 * cos(2 * t));
          targets.add(Offset(0.5 + r * cos(t), 0.5 + r * sin(t)));
        }
      case 7: // Triangle
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
      case 8: // Scatter
        final seed = Random(index * 7 + 13);
        for (var i = 0; i < n; i++) {
          targets.add(Offset(0.1 + 0.8 * seed.nextDouble(), 0.1 + 0.8 * seed.nextDouble()));
        }
      case 9: // Concentric rings
        for (var i = 0; i < n; i++) {
          final ring = (i * 2 ~/ n);
          final inRing = i % (n ~/ 2);
          final count = n ~/ 2;
          final a = inRing / count * 2 * pi;
          final r = ring == 0 ? 0.15 : 0.33;
          targets.add(Offset(0.5 + r * cos(a), 0.5 + r * sin(a)));
        }
      case 10: // Infinity
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          final x = 0.5 + 0.3 * sin(t) / (1 + pow(cos(t), 2));
          final y = 0.5 + 0.2 * sin(t) * cos(t) / (1 + pow(cos(t), 2));
          targets.add(Offset(x.toDouble(), y.toDouble()));
        }
      case 11: // Wavy mouth
        for (var i = 0; i < n; i++) {
          final x = i / n;
          final y = 0.5 + 0.1 * sin(x * 8 * pi) + 0.05 * sin(x * 16 * pi);
          targets.add(Offset(x, y));
        }
      case 12: // Double wave (voice)
        for (var i = 0; i < n; i++) {
          final x = i / n;
          final freq = 4 + 4 * (i / n);
          final wave1 = 0.12 * sin(x * freq * pi);
          final wave2 = 0.08 * sin(x * freq * 2 * pi + 1.5);
          targets.add(Offset(x, 0.5 + wave1 + wave2));
        }
      case 13: // Ear shape (simplified)
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          final r = 0.3 + 0.1 * cos(t * 2) + 0.05 * cos(t * 3);
          targets.add(Offset(0.5 + r * cos(t), 0.5 + r * sin(t) * 0.7));
        }
      case 14: // Star
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi - pi / 2;
          final points = 5;
          final r = (i % (n ~/ points) == 0) ? 0.35 : 0.15;
          targets.add(Offset(0.5 + r * cos(t), 0.5 + r * sin(t)));
        }
      case 15: // Grid
        final cols = 6;
        for (var i = 0; i < n; i++) {
          final row = i ~/ cols;
          final col = i % cols;
          targets.add(Offset(0.12 + col * 0.152, 0.12 + row * 0.152));
        }
      case 16: // Explosion
        for (var i = 0; i < n; i++) {
          final a = i / n * 2 * pi;
          final r = 0.05 + 0.3 * (i / n);
          targets.add(Offset(0.5 + r * cos(a), 0.5 + r * sin(a)));
        }
      case 17: // Yin-yang
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          final r = 0.35;
          final x = 0.5 + r * cos(t);
          final y = 0.5 + r * sin(t);
          targets.add(Offset(x, y));
        }
      case 18: // Butterfly
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          final r = 0.3 * (0.5 + 0.5 * sin(t * 3)) * (1 + 0.3 * cos(t * 4));
          targets.add(Offset(0.5 + r * cos(t), 0.5 + r * sin(t) * 0.7));
        }
      case 19: // Spiral galaxy
        for (var i = 0; i < n; i++) {
          final t = i / n * 6 * pi;
          final r = 0.05 + 0.32 * (i / n);
          final spread = 0.03 * (1 - i / n);
          final a = t + spread * sin(t * 3);
          targets.add(Offset(0.5 + r * cos(a), 0.5 + r * sin(a)));
        }
      case 20: // Sine + cosine Lissajous
        for (var i = 0; i < n; i++) {
          final t = i / n * 2 * pi;
          targets.add(Offset(0.5 + 0.35 * sin(3 * t + 0.5), 0.5 + 0.35 * sin(2 * t)));
        }
      case 21: // Pulse (expanding circle)
        for (var i = 0; i < n; i++) {
          final a = i / n * 2 * pi;
          final r = 0.15 + 0.2 * ((i % 12) / 12);
          targets.add(Offset(0.5 + r * cos(a), 0.5 + r * sin(a)));
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
      if (!mounted) return;
      setState(() {
        _currentPattern = (_currentPattern + 1) % _patternCount;
        _patternProgress = 0.0;
        final targets = _patternTargets[_currentPattern];
        for (var i = 0; i < _dotCount && i < targets.length; i++) {
          _dots[i].targetX = targets[i].dx;
          _dots[i].targetY = targets[i].dy;
        }
      });
    });
  }

  void _startTypewriter() {
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted) return;
      setState(() {
        final currentWord = _statusTexts[_statusCycleIndex];
        if (!_erasing) {
          if (_charIndex < currentWord.length) {
            _charIndex++;
            _displayedText = currentWord.substring(0, _charIndex);
          } else {
            _erasing = true;
          }
        } else {
          if (_charIndex > 0) {
            _charIndex--;
            _displayedText = currentWord.substring(0, _charIndex);
          } else {
            _erasing = false;
            _statusCycleIndex = (_statusCycleIndex + 1) % _statusTexts.length;
          }
        }
      });
    });
  }

  @override
  void didUpdateWidget(SpeechGenerationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCompleted && !oldWidget.isCompleted) {
      _patternTimer?.cancel();
      _typewriterTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _patternTimer?.cancel();
    _typewriterTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCompleted) {
      return AudioPlayerWidget(vfsPath: widget.vfsPath);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = 260.0;

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
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _animController,
                      builder: (context, _) {
                        return Text(
                          '$_displayedText...',
                          style: TextStyle(
                            color: AppColors.primary.withValues(alpha: 0.85),
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        );
                      },
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

  void _updateDots() {
    _patternProgress = (_patternProgress + 0.005).clamp(0.0, 1.0);
    for (final dot in _dots) {
      final speed = dot.speed;
      dot.x += (dot.targetX - dot.x) * speed;
      dot.y += (dot.targetY - dot.y) * speed;
    }
  }
}

class _Dot {
  double x;
  double y;
  double targetX;
  double targetY;
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

      // Subtle glow
      final glowPaint = Paint()
        ..color = dot.color.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(px, py), dot.radius * 2.5, glowPaint);
    }
  }

  @override
  bool shouldRepaint(_DotPainter oldDelegate) => true;
}
