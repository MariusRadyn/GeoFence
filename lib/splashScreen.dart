import 'package:flutter/material.dart';
import 'package:geofence/homePage.dart';
import 'package:geofence/main.dart';
import 'package:geofence/utils.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _iconScaleAnimation;
  late Animation<double> _iconRotationAnimation;
  late Animation<double> _textOpacityAnimation;
  late Animation<Offset> _textSlideAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    // Icon animations
    _iconScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.2),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0),
        weight: 20,
      ),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeInOut),
    ));
    _iconRotationAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * 3.14159, // Full rotation in radians
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 0.7, curve: Curves.easeInOut),
    ));

    // Text animations
    _textOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.6, 0.8, curve: Curves.easeIn),
    ));
    _textSlideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.6, 0.8, curve: Curves.easeInOut),
    ));

    // Start the animation
    _controller.forward();

    // Navigate to main screen after animation completes
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 1500), () {
           Navigator.of(context).pushReplacement(
             //MaterialPageRoute(builder: (_) => AuthGate()),
             MaterialPageRoute(builder: (_) => HomePage()),
           );
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: APP_BACKGROUND_COLOR,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Stack(
                children: [

                  // Center everything relative to screen
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {

                        final centerY = constraints.maxHeight * 0.45;
                        final spacing = 50.0; // 👈 adjust this for vertical spacing
                        final offsetY = 100;

                        return Stack(
                          children: [

                            // =====================
                            // Animated App Icon
                            // =====================
                            Positioned(
                              top: centerY - offsetY, // move upward from center
                              left: 0,
                              right: 0,
                              child: Center(
                                child: AnimatedBuilder(
                                  animation: _controller,
                                  builder: (context, child) {
                                    return Transform.scale(
                                      scale: _iconScaleAnimation.value,
                                      child: Transform.rotate(
                                        angle: _iconRotationAnimation.value,
                                        child: Image.asset(
                                          ICON_LIMITLESS_LOGO,
                                          width: 150,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),

                            // =====================
                            // Animated App Name
                            // =====================
                            Positioned(
                              top: centerY - offsetY + spacing,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: AnimatedBuilder(
                                  animation: _controller,
                                  builder: (context, child) {
                                    return FadeTransition(
                                      opacity: _textOpacityAnimation,
                                      child: SlideTransition(
                                        position: _textSlideAnimation,
                                        child: Image.asset(
                                          ICON_LIMITLESS_WORD,
                                          width: 200,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}