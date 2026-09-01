import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';

const _cyanGlow = Color(0xFF00E5FF);
const _goldGlow = Color(0xFFFFC43A);

class WhatsNewPage extends StatelessWidget {
  const WhatsNewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: colorAppBackground,
        appBar: AppBar(
          backgroundColor: colorAppBar,
          foregroundColor: Colors.white,
          title: myAppbarTitle("What's New"),
          bottom: const TabBar(
            indicatorColor: colorBlue,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(text: 'Free'),
              Tab(text: 'Paid'),
              Tab(text: 'Updates'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _FreeTab(),
            _PaidTab(),
            _ChangesTab(),
          ],
        ),
      ),
    );
  }
}

class _PaidTab extends StatelessWidget {
  const _PaidTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: const [
        _ServiceTile(
          image: _DistanceWheelHero(),
          title: 'Distance Wheel Monitoring',
          description:
              'Our newly launched IoT distance wheel was designed specifically for the sugarcane '
              'farming industry. It is used to automatically calculate wages. '
              'This device connects to a base station using WiFi and Bluetooth. '
              'The IOT controller features an LCD, keypad, 1500mA rechargeable battery, '
              'WiFi, Bluetooth, tag reader and distance sensor. It identifies the operator '
              'by tag and measures distance. Live distance is sent from the IOT device to the base '
              'station, then into the cloud. Use it to track operator movement, time and attendance, '
              'log shift distances, and calculate wage summaries from accurate wheel data instead of estimates.',
        ),
        SizedBox(height: 14),
        _ServiceTile(
          image: _IotArchitectureHero(),
          title: 'Base Station',
          description:
              'Limitless IoT is built as a hub-and-spoke network. The base station is the local master controller. '
              'The installation needs only 1 base station. This is the network administrator. '
              'Connect any amount of IOT monitors to it. '
              'An IOT monitor can be anything from a distance wheel to a vehicle or a boiling pot monitor telling '
              'you when the food is burning. The only limit is your imagination. '
              'The base station wirelessly connects to all IOT monitors using WiFi, '
              'pushing data to the cloud. It also keeps all IOT monitors in sync. '
              'Data flows from IOT → Base Station → Cloud → App, where you view live monitors, '
              'history reports, wages, geofence events, tracking, and alerts from one dashboard. '
              'Add more base stations as your operation grows. You can have multiple base stations on the same WiFi network '
              'as long as they are out of Bluetooth range of each other. Each site runs independently '
              'while your account keeps everything in one place.',
        ),
      ],
    );
  }
}

class _FreeTab extends StatelessWidget {
  const _FreeTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const _FreeServicesHeader(),
        const SizedBox(height: 16),
        const _ServiceTile(
          image: _AssetHero(iconThirdPartyIot, size: 100),
          title: 'Third Party IOT Devices',
          description:
              'Use the app free of charge for all third-party IOT smart home devices. We support Shelly, Tasmota, and SONOFF protocols. '
              'At Limitless IOT we focus on control. If you need to be in full control, you are in the right place. '
              'We offer you more control over your devices and more features than most IOT networking apps. '
              'Feel free to contact us to request features. We put all customers first, even the ones enjoying a free ride.',
        ),
        const SizedBox(height: 14),
        const _ServiceTile(
          image: _AssetHero(iconGeofenceNoBackground, size: 108),
          title: 'GeoFence Diesel Rebate',
          description:
              'Draw and manage geofence zones on the map using your phone\'s GPS — '
              'no extra hardware required. Create polygon or circle fences, label them, '
              'and use them for vehicle tracking enter/exit events and diesel rebate reporting. '
              'Get a report for when you entered and exited the geofence and how much diesel you '
              'used inside the fence. This is based on the fuel consumption and rebate setting in the Settings page.',
        ),
        const SizedBox(height: 14),
     
      ],
    );
  }
}

class _FreeServicesHeader extends StatelessWidget {
  const _FreeServicesHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            iconItsFree,
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 72,
              height: 72,
              color: colorTile,
              alignment: Alignment.center,
              child: const Icon(Icons.celebration, color: _goldGlow, size: 36),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            'Free Services',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontFamily: 'Poppins',
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// Futuristic header with a centred asset image (Free tab tiles).
class _AssetHero extends StatelessWidget {
  final String asset;
  final double size;

  const _AssetHero(this.asset, {required this.size});

  @override
  Widget build(BuildContext context) {
    return _FuturisticHeroShell(
      lightWell: false,
      child: Center(
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            Icons.devices,
            size: size * 0.75,
            color: colorOrange,
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final Widget image;
  final String title;
  final String description;

  const _ServiceTile({
    required this.image,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _cyanGlow.withValues(alpha: 0.45),
            colorTile,
            _goldGlow.withValues(alpha: 0.25),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _cyanGlow.withValues(alpha: 0.12),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(1),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colorTile,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 168, child: image),
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    _cyanGlow.withValues(alpha: 0.7),
                    _goldGlow.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 18,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [_cyanGlow, colorBlue],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _cyanGlow.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.45,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dark HUD shell with grid, corner brackets, and optional white image well.
class _FuturisticHeroShell extends StatelessWidget {
  final Widget child;
  final bool lightWell;

  const _FuturisticHeroShell({
    required this.child,
    this.lightWell = true,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _FuturisticHeroPainter(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (lightWell)
            Center(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _cyanGlow.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _cyanGlow.withValues(alpha: 0.25),
                      blurRadius: 20,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: child,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: child,
            ),
          // Top status chip
          Positioned(
            top: 10,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _cyanGlow.withValues(alpha: 0.4)),
              ),
              child: const Text(
                'IOT',
                style: TextStyle(
                  color: _cyanGlow,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FuturisticHeroPainter extends CustomPainter {
  const _FuturisticHeroPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Deep space gradient
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF061018),
          colorAppBar,
          const Color(0xFF0B1F33),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    // Perspective grid floor
    final gridPaint = Paint()
      ..color = _cyanGlow.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final horizon = size.height * 0.62;
    for (var i = -6; i <= 6; i++) {
      final x = size.width * 0.5 + i * 36;
      canvas.drawLine(
        Offset(x, horizon),
        Offset(size.width * 0.5 + i * 72, size.height),
        gridPaint,
      );
    }
    for (var j = 0; j < 5; j++) {
      final y = horizon + j * 22;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // Radial glow centre
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          _cyanGlow.withValues(alpha: 0.14),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width / 2, size.height * 0.45),
        radius: size.width * 0.45,
      ));
    canvas.drawRect(rect, glow);

    _drawCornerBracket(canvas, const Offset(10, 10), 22, flipX: false, flipY: false);
    _drawCornerBracket(canvas, Offset(size.width - 10, 10), 22, flipX: true, flipY: false);
    _drawCornerBracket(canvas, Offset(10, size.height - 10), 22, flipX: false, flipY: true);
    _drawCornerBracket(canvas, Offset(size.width - 10, size.height - 10), 22, flipX: true, flipY: true);
  }

  void _drawCornerBracket(
    Canvas canvas,
    Offset origin,
    double len, {
    required bool flipX,
    required bool flipY,
  }) {
    final sx = flipX ? -1.0 : 1.0;
    final sy = flipY ? -1.0 : 1.0;
    final path = Path()
      ..moveTo(origin.dx, origin.dy + sy * len)
      ..lineTo(origin.dx, origin.dy)
      ..lineTo(origin.dx + sx * len, origin.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = _goldGlow.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _cyanGlow.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DistanceWheelHero extends StatelessWidget {
  const _DistanceWheelHero();

  @override
  Widget build(BuildContext context) {
    return const _FuturisticHeroShell(
      lightWell: false,
      child: Center(child: _DistanceWheelImage(size: 120)),
    );
  }
}

class _DistanceWheelImage extends StatelessWidget {
  final double size;

  const _DistanceWheelImage({required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      iconWheel,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.album_outlined,
        size: size * 0.75,
        color: colorOrange,
      ),
    );
  }
}

class _IotArchitectureHero extends StatelessWidget {
  const _IotArchitectureHero();

  @override
  Widget build(BuildContext context) {
    return _FuturisticHeroShell(
      lightWell: false,
      child: CustomPaint(
        painter: _IotNetworkLinesPainter(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 4,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'BASE STATION',
                    style: TextStyle(
                      color: _cyanGlow,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 2),
                  _archImage(iconBase, 44),
                ],
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _deviceNode('Wheel', iconWheel, 32),
                  _deviceNode('Monitor', iconIot, 32),
                  _deviceNode('Vehicle', iconVehicle, 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _archImage(String asset, double size) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.devices, size: size * 0.8, color: colorOrange),
    );
  }

  static Widget _deviceNode(String label, String asset, double size) {
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _cyanGlow.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(
                  color: _cyanGlow.withValues(alpha: 0.15),
                  blurRadius: 8,
                ),
              ],
            ),
            child: _archImage(asset, size),
          ),
          const SizedBox(height: 3),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 8,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }
}

class _IotNetworkLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final hub = Offset(size.width / 2, 34);
    final deviceY = size.height - 24;
    final left = Offset(size.width * 0.18, deviceY);
    final center = Offset(size.width / 2, deviceY);
    final right = Offset(size.width * 0.82, deviceY);

    final glowPaint = Paint()
      ..color = _cyanGlow.withValues(alpha: 0.2)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    final linePaint = Paint()
      ..color = _cyanGlow.withValues(alpha: 0.85)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final device in [left, center, right]) {
      canvas.drawLine(hub, device, glowPaint);
      canvas.drawLine(hub, device, linePaint);
    }

    final dotPaint = Paint()..color = _goldGlow;
    for (final t in [0.3, 0.55, 0.78]) {
      for (final device in [left, center, right]) {
        final point = Offset.lerp(hub, device, t)!;
        canvas.drawCircle(point, 2.5, dotPaint);
        canvas.drawCircle(
          point,
          5,
          Paint()..color = _goldGlow.withValues(alpha: 0.25),
        );
      }
    }

    // Hub pulse ring
    canvas.drawCircle(
      hub,
      18,
      Paint()
        ..color = _cyanGlow.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChangesTab extends StatelessWidget {
  const _ChangesTab();

  static const _updates = <_WhatsNewItem>[
    _WhatsNewItem(
      title: 'Distance Wheel IoT firmware',
      date: 'Aug 2026',
      bullets: [
        'Live Monitor exits on any key and notifies the app to disconnect',
        'Connect / Disconnect button label toggles with connection state',
        'Pair mode enters after exactly five Stop presses (within 5 seconds)',
        'Re-pair waits for fresh Bluetooth WiFi credentials when base WiFi changes',
        'WiFi reconnects properly after SSID or password update during pairing',
        'Live and calibration tick counts stay aligned (forward-only; sensor state reset on start)',
        'Live communication keeps the latest tick count even if publish briefly falls behind',
        'Live entry no longer reboots after pairing; settings save safely on the main loop',
        'Live screen shows distance and tick count while rolling',
      ],
    ),
    _WhatsNewItem(
      title: 'GeoFence map overhaul',
      date: 'Aug 2026',
      bullets: [
        'Undo while drawing and editing fences',
        'Circle and polygon shapes with draggable handles',
        'Fence name labels always visible on the map',
        'Satellite view and quick fence list picker',
      ],
    ),
    _WhatsNewItem(
      title: 'Smarter vehicle tracking',
      date: 'Aug 2026',
      bullets: [
        'Geofence enter/exit events with distance summaries',
        'Rebate and diesel cost estimates in history reports',
        'Vehicle selector in the tracking app bar',
      ],
    ),
    _WhatsNewItem(
      title: 'Online shop',
      date: 'Aug 2026',
      bullets: [
        'Browse Limitless IoT products in-app',
        'Product detail pages with discount ribbons',
        'Bob Pay checkout and Bob Go delivery rates',
      ],
    ),
    _WhatsNewItem(
      title: 'Settings & splash polish',
      date: 'Aug 2026',
      bullets: [
        'GPS check interval with battery guidance',
        'Auto-save settings fields on blur',
        'Refreshed splash animation and branding',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _updates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _updates[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorTile,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                  Text(
                    item.date,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...item.bullets.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: colorOrange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          b,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.35,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WhatsNewItem {
  final String title;
  final String date;
  final List<String> bullets;

  const _WhatsNewItem({
    required this.title,
    required this.date,
    required this.bullets,
  });
}
