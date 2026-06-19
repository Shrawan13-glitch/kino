import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class BouncingDots extends StatefulWidget {
  const BouncingDots({super.key});

  @override
  State<BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<BouncingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Timer _timer;
  int _patternIndex = 0;

  static const _patterns = [
    '\u00B7\u00B7\u00B7',
    '\u22EE\u22F0\u22EF',
    '\u2022\u2022\u2022',
    '\u25C9\u25C9\u25C9',
    '\u25A1\u25A1\u25A1',
    '\u25B3\u25B3\u25B3',
    '\u25CB\u25CB\u25CB',
    '\u25CF\u25CF\u25CF',
    '\u2726\u2727\u2605',
    '\u272A\u272B\u272C',
    '\u25C7\u25C6\u25C7',
    '\u25D0\u25D1\u25D2',
    '\u25D3\u25D4\u25D5',
    '\u25D6\u25D7\u25D8',
    '\u25E2\u25E3\u25E4',
    '\u25E5\u25E6\u25E7',
    '\u25E8\u25E9\u25EA',
    '\u25EB\u25EC\u25ED',
    '\u25EE\u25EF\u25F0',
    '\u2234\u2235\u2234',
    '\u224B\u224B\u224B',
    '\u25B4\u25B5\u25B4',
    '\u25B8\u25B8\u25B8',
    '\u25C2\u25C2\u25C2',
    '\u25CA\u25CA\u25CA',
    '\u25CD\u25CD\u25CD',
    '\u25D9\u25D9\u25D9',
    '\u25DA\u25DB\u25DA',
    '\u25DC\u25DD\u25DE',
    '\u25DF\u25E0\u25E1',
    '\u223F\u223E\u223F',
    '\u2248\u2248\u2248',
    '\u2261\u2261\u2261',
    '\u2253\u2253\u2253',
    '\u221F\u2220\u221F',
    '\u29EB\u29EB\u29EB',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) {
        setState(() => _patternIndex = (_patternIndex + 1) % _patterns.length);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pattern = _patterns[_patternIndex];
    final chars = pattern.runes.map((r) => String.fromCharCode(r)).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        height: 16,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(chars.length, (i) {
                final phase = (i * 0.25 + _controller.value) * 2 * pi;
                final bounce = sin(phase) * 5;
                return Transform.translate(
                  offset: Offset(0, bounce),
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: i < chars.length - 1 ? 3 : 0,
                    ),
                    child: Text(
                      chars[i],
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
