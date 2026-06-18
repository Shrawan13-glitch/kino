import 'package:flutter/material.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.55, curve: Curves.easeOut),
    );

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.55, curve: Curves.easeOutCubic),
    ));

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2500), _navigateToHome);
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3D3799),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 112,
              height: 128,
              child: CustomPaint(
                painter: _KLogoPainter(),
              ),
            ),
            const SizedBox(height: 32),
            FadeTransition(
              opacity: _textOpacity,
              child: SlideTransition(
                position: _textSlide,
                child: Text(
                  'kino',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.92),
                    letterSpacing: 6,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final scaleX = size.width / 108;
    final scaleY = size.height / 108;
    final s = (scaleX + scaleY) / 2;

    paint.strokeWidth = 7 * s;
    canvas.drawLine(
      Offset(38 * scaleX, 16 * scaleY),
      Offset(38 * scaleX, 92 * scaleY),
      paint,
    );

    paint.strokeWidth = 6 * s;
    canvas.drawLine(
      Offset(44 * scaleX, 50 * scaleY),
      Offset(86 * scaleX, 20 * scaleY),
      paint,
    );

    canvas.drawLine(
      Offset(44 * scaleX, 58 * scaleY),
      Offset(86 * scaleX, 88 * scaleY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
