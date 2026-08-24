import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Палитра Tunnelo — выведена из иконки приложения: глубина туннеля,
/// кольца, уходящие к светящемуся ядру.
abstract class TunneloColors {
  static const abyss = Color(0xFF0B0F1E); // фон, дно туннеля
  static const surface = Color(0xFF161E38); // приподнятая поверхность
  static const surfaceHi = Color(0xFF1E2A4A); // границы, разделители
  static const ringFar = Color(0xFF4874EB); // дальние кольца
  static const ringNear = Color(0xFF56E6FF); // ближние кольца, акцент
  static const core = Color(0xFFEBFCFF); // ядро, текст
  static const muted = Color(0xFF8A97BE); // подписи
  static const alert = Color(0xFFFF6B6B); // ошибка
}

enum TunnelState { idle, working, success, error }

/// Кольца туннеля — единственный «громкий» элемент интерфейса.
///
/// В покое медленно дышат. При проверке кода бегут к центру. При успехе
/// вспыхивают и раскрываются. При ошибке дрожат и краснеют.
class TunnelRings extends StatefulWidget {
  const TunnelRings({
    super.key,
    this.state = TunnelState.idle,
    this.size = 220,
    this.rings = 5,
  });

  final TunnelState state;
  final double size;
  final int rings;

  @override
  State<TunnelRings> createState() => _TunnelRingsState();
}

class _TunnelRingsState extends State<TunnelRings> with TickerProviderStateMixin {
  late final AnimationController _loop;
  late final AnimationController _burst;

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
    _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  }

  @override
  void didUpdateWidget(TunnelRings old) {
    super.didUpdateWidget(old);
    if (widget.state != old.state) {
      switch (widget.state) {
        case TunnelState.working:
          _loop.duration = const Duration(milliseconds: 1600);
          _loop
            ..reset()
            ..repeat();
        case TunnelState.success:
          _loop.duration = const Duration(seconds: 6);
          _burst.forward(from: 0);
        case TunnelState.error:
          _burst.forward(from: 0);
        case TunnelState.idle:
          _loop.duration = const Duration(seconds: 6);
          _loop.repeat();
      }
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_loop, _burst]),
          builder: (context, _) => CustomPaint(
            painter: _TunnelPainter(
              t: reduceMotion ? 0 : _loop.value,
              burst: _burst.value,
              state: widget.state,
              rings: widget.rings,
            ),
          ),
        ),
      ),
    );
  }
}

class _TunnelPainter extends CustomPainter {
  _TunnelPainter({
    required this.t,
    required this.burst,
    required this.state,
    required this.rings,
  });

  final double t;
  final double burst;
  final TunnelState state;
  final int rings;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;

    final isError = state == TunnelState.error;
    final near = isError ? TunneloColors.alert : TunneloColors.ringNear;
    final far = isError ? const Color(0xFF8B3A4A) : TunneloColors.ringFar;

    // дрожание при ошибке
    final shake = isError && burst > 0 && burst < 1
        ? math.sin(burst * math.pi * 8) * 6 * (1 - burst)
        : 0.0;
    canvas.translate(shake, 0);

    // свечение ядра
    final glowR = maxR * (0.16 + 0.05 * math.sin(t * 2 * math.pi));
    final glowBoost = state == TunnelState.success ? (1 - burst) * 0.6 : 0.0;
    canvas.drawCircle(
      c,
      glowR * (1 + glowBoost * 2),
      Paint()
        ..color = near.withValues(alpha: 0.14 + glowBoost * 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, maxR * 0.22),
    );

    // кольца: каждое ползёт внутрь, ближайшее к центру растворяется
    for (var i = 0; i < rings; i++) {
      final phase = (i / rings + t) % 1.0;
      // нелинейно — перспектива туннеля
      final r = maxR * math.pow(1 - phase, 1.7).toDouble();
      if (r < maxR * 0.06) continue;

      final depth = 1 - phase; // 0 = близко к центру, 1 = край
      final opacity = (phase < 0.08 ? phase / 0.08 : 1.0) * (0.35 + 0.65 * (1 - depth));
      final color = Color.lerp(far, near, 1 - depth)!;
      final width = 2.0 + 2.4 * (1 - depth);

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: r * 2, height: r * 2),
        Radius.circular(r * 0.36),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0)),
      );
    }

    // ядро
    final coreR = maxR * 0.085 * (state == TunnelState.success ? 1 + burst * 0.6 : 1);
    canvas.drawCircle(
      c,
      coreR,
      Paint()..color = (isError ? TunneloColors.alert : TunneloColors.core).withValues(alpha: 0.95),
    );

    // вспышка успеха — расходящееся кольцо
    if (state == TunnelState.success && burst > 0 && burst < 1) {
      canvas.drawCircle(
        c,
        maxR * burst,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - burst)
          ..color = near.withValues(alpha: (1 - burst) * 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(_TunnelPainter old) =>
      old.t != t || old.burst != burst || old.state != state;
}
