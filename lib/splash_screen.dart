import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geofence/home_page.dart';
import 'package:geofence/utils.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  SplashScreenState createState() => SplashScreenState();
}

class SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _iconScaleAnimation;
  late Animation<double> _iconRotationAnimation;
  late Animation<double> _glowPulseAnimation;
  late Animation<double> _textOpacityAnimation;
  late Animation<Offset> _textSlideAnimation;
  late Animation<double> _zoomAnimation;
  late Animation<double> _brandOpacityAnimation;
  late Animation<double> _bgScaleAnimation;

  @override
  void initState() {
    super.initState();

    // Intro → spin/text → Netflix zoom-out (~3.8s)
    _controller = AnimationController(
      duration: const Duration(milliseconds: 3800),
      vsync: this,
    );

    // Logo pops in, then settles (keep existing feel)
    _iconScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 40,
      ),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.55),
    ));

    // Full spin — same timing spirit as before
    _iconRotationAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * 3.14159,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.18, 0.52, curve: Curves.easeInOut),
    ));

    // Soft breathing glow around the logo
    _glowPulseAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.35, end: 1.0),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.7),
        weight: 50,
      ),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.15, 0.62, curve: Curves.easeInOut),
    ));

    // Wordmark reveal
    _textOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.48, 0.62, curve: Curves.easeOut),
    ));
    _textSlideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.48, 0.62, curve: Curves.easeOutCubic),
    ));

    // Netflix-style: brand rushes toward camera, then vanishes
    _zoomAnimation = Tween<double>(
      begin: 1.0,
      end: 18.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.68, 1.0, curve: Curves.easeInCubic),
    ));

    _brandOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 55),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 45,
      ),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.68, 1.0),
    ));

    // Background barely drifts in so the handoff feels cinematic
    _bgScaleAnimation = Tween<double>(
      begin: 1.08,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOut),
    ));

    _controller.forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 450), () {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => HomePage(openProfileOnLaunch: launchOpensProfile),
            ),
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

  Widget _buildGlowingLogo(double glowStrength) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer cyan bloom
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Opacity(
            opacity: (0.55 * glowStrength).clamp(0.0, 1.0),
            child: Image.asset(
              iconLimitlessLogo,
              width: 168,
              color: const Color(0xFF00E5FF),
            ),
          ),
        ),
        // Magenta / warm accent bloom
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Opacity(
            opacity: (0.4 * glowStrength).clamp(0.0, 1.0),
            child: Image.asset(
              iconLimitlessLogo,
              width: 158,
              color: const Color(0xFFFF4D8D),
            ),
          ),
        ),
        // Crisp logo on top
        Image.asset(
          iconLimitlessLogo,
          width: 150,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final brandScale =
              _iconScaleAnimation.value * _zoomAnimation.value;
          final brandOpacity = _brandOpacityAnimation.value *
              (_iconScaleAnimation.value <= 0 ? 0.0 : 1.0);

          return Stack(
            fit: StackFit.expand,
            children: [
              // Full-bleed futuristic background
              Transform.scale(
                scale: _bgScaleAnimation.value,
                child: Image.asset(
                  iconSplashBackground,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
              // Soft vignette so logo pops — aligned with the background circle
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.1,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                    ],
                    stops: const [0.45, 1.0],
                  ),
                ),
              ),

              // Infinity logo centered on the background circle, then Netflix zoom
              Opacity(
                opacity: brandOpacity.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: brandScale,
                  alignment: Alignment.center,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                        angle: _iconRotationAnimation.value,
                        child: _buildGlowingLogo(_glowPulseAnimation.value),
                      ),
                      // Wordmark just below the circle (does not shift the logo)
                      Transform.translate(
                        offset: const Offset(0, 78),
                        child: FadeTransition(
                          opacity: _textOpacityAnimation,
                          child: SlideTransition(
                            position: _textSlideAnimation,
                            child: Image.asset(
                              iconLimitlessWord,
                              width: 200,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
