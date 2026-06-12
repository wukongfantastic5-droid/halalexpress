import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_screen.dart';
import 'package:http/http.dart' as http;
import 'widgets/bunny_icon.dart';

class InitializeScreen extends StatefulWidget {
  const InitializeScreen({super.key});

  @override
  State<InitializeScreen> createState() => _InitializeScreenState();
}

class _InitializeScreenState extends State<InitializeScreen>
    with SingleTickerProviderStateMixin {
  final int minSplashTimeMs = 3000;

  late AnimationController _mainController;
  late Animation<double> _scaleIn;
  late Animation<double> _logoPulse;
  late Animation<double> _ringRotate;
  late Animation<double> _textFade;
  @override
  void initState() {
    super.initState();
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _scaleIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );

    _logoPulse = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
      ),
    );

    _ringRotate = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 1.0, curve: Curves.linear),
      ),
    );

    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.4, 0.7, curve: Curves.easeOut),
      ),
    );

    _mainController.forward();
    startInit();
  }

  @override
  void dispose() {
    _mainController.dispose();
    super.dispose();
  }

  Future<void> startInit() async {
    // Request install permission at app launch (Android only)
    if (Platform.isAndroid) {
      try {
        final allowed = await MethodChannel("com.kampungrider/install_permission")
            .invokeMethod<bool>("canRequestPackageInstalls");
        if (allowed != true && mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: Text(
                "Kebenaran Pemasangan",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
              content: Text(
                "Sila benarkan \"Pasang aplikasi tidak diketahui\" untuk memasang kemas kini aplikasi pada masa hadapan.",
                style: GoogleFonts.poppins(fontSize: 13),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    MethodChannel("com.kampungrider/install_permission")
                        .invokeMethod("openInstallSettings");
                  },
                  child: Text("Buka Seting", style: GoogleFonts.poppins()),
                ),
              ],
            ),
          );
        }
      } catch (_) {}
    }

    final startTime = DateTime.now();

    try {
      await http
          .get(Uri.parse("https://jsonplaceholder.typicode.com/todos/1"))
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      // silently ignore
    }

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;

    if (elapsed < minSplashTimeMs) {
      await Future.delayed(Duration(milliseconds: minSplashTimeMs - elapsed));
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D7377),
              Color(0xFF14919B),
              Color(0xFF14C38E),
            ],
          ),
        ),
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: _mainController,
              builder: (context, _) {
                return Stack(
                  children: [
                    // Decorative circles
                    Positioned(
                      top: -80,
                      left: -80,
                      child: Container(
                        width: 250 + _scaleIn.value * 50,
                        height: 250 + _scaleIn.value * 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -120,
                      right: -60,
                      child: Container(
                        width: 350,
                        height: 350,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.04),
                        ),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Animated logo
                            Transform.scale(
                              scale: _scaleIn.value,
                              child: SizedBox(
                                width: 140,
                                height: 140,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Outer rotating ring
                                    Transform.rotate(
                                      angle: _ringRotate.value * 6.28,
                                      child: CustomPaint(
                                        size: const Size(140, 140),
                                        painter: _RingPainter(
                                          color: Colors.white.withOpacity(0.15),
                                          progress: 0.3,
                                        ),
                                      ),
                                    ),
                                    // Middle pulsing ring
                                    Transform.scale(
                                      scale: 0.85 + (_logoPulse.value * 0.05),
                                      child: Container(
                                        width: 120,
                                        height: 120,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.12),
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Bunny logo with glow
                                    Container(
                                      width: 100,
                                      height: 100,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF14C38E)
                                                .withOpacity(0.5),
                                            blurRadius: 30,
                                            spreadRadius: 5,
                                          ),
                                        ],
                                      ),
                                      child: Transform.scale(
                                        scale: _logoPulse.value,
                                        child: BunnyIcon(
                                          size: 100,
                                          color: Colors.white,
                                          accentColor: const Color(0xFF14C38E),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 36),
                            // Title text
                            FadeTransition(
                              opacity: _textFade,
                              child: Column(
                                children: [
                                  Text(
                                    "BunnyFresh",
                                    style: GoogleFonts.poppins(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 1.5,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "Sedia Membantu Anda",
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Colors.white.withOpacity(0.7),
                                      fontWeight: FontWeight.w300,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 50),
                            // Loading dots
                            _LoadingDots(),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;
  final double progress;

  _RingPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.width / 2 - 4,
    );

    canvas.drawArc(rect, -1.57, 6.28 * progress, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final delay = i * 0.15;
            final t = (_controller.value - delay).clamp(0.0, 1.0);
            final scale = (t < 0.5 ? t * 2 : 2 - t * 2).clamp(0.3, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
