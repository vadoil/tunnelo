import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';

/// Фон главного экрана: вид вдоль туннеля.
///
/// Кольца той же формы, что в логотипе, медленно уходят к точке схода,
/// вдоль них дрейфуют редкие искры. Точка схода совпадает с кнопкой
/// подключения — она и есть свет в конце туннеля.
///
/// Всё держится на очень низкой контрастности (0.03–0.16): фон должен
/// читаться боковым зрением и не мешать тексту. Один контроллер, один
/// RepaintBoundary — экран не греет батарею.
class TunneloBackdrop extends StatefulWidget {
  const TunneloBackdrop({super.key, this.child, this.focus = const Alignment(0, -0.09)});

  final Widget? child;

  /// Куда сходится перспектива. По умолчанию — чуть ниже центра,
  /// там, где стоит кнопка подключения.
  final Alignment focus;

  @override
  State<TunneloBackdrop> createState() => _TunneloBackdropState();
}

class _TunneloBackdropState extends State<TunneloBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    // Полный проход кольца от края до центра — 22 секунды: движение
    // должно быть на грани заметности, иначе фон начинает отвлекать.
    _drift = AnimationController(vsync: this, duration: const Duration(seconds: 22))..repeat();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _drift,
            builder: (context, _) => CustomPaint(
              painter: _TunnelFieldPainter(
                t: reduceMotion ? 0.35 : _drift.value,
                focus: widget.focus,
              ),
              isComplex: true,
              willChange: !reduceMotion,
            ),
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _TunnelFieldPainter extends CustomPainter {
  _TunnelFieldPainter({required this.t, required this.focus});

  final double t;
  final Alignment focus;

  static const _rings = 7;
  static const _sparks = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final center = focus.alongSize(size);
    // Дальний край: диагональ, чтобы кольца рождались за пределами экрана.
    final maxR = math.sqrt(size.width * size.width + size.height * size.height) * 0.62;

    _paintDepth(canvas, size, center, maxR);
    _paintRings(canvas, center, maxR);
    _paintSparks(canvas, center, maxR);
  }

  /// Свечение в точке схода: дно туннеля светится ровно и глубоко.
  void _paintDepth(Canvas canvas, Size size, Offset center, double maxR) {
    final breath = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(
            (center.dx / size.width) * 2 - 1,
            (center.dy / size.height) * 2 - 1,
          ),
          radius: 0.85,
          colors: [
            TunneloColors.ringFar.withValues(alpha: 0.13 + 0.03 * breath),
            TunneloColors.abyss.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  /// Кольца уходят внутрь по нелинейному закону — так читается перспектива.
  void _paintRings(Canvas canvas, Offset center, double maxR) {
    for (var i = 0; i < _rings; i++) {
      final phase = (i / _rings + t) % 1.0;
      final r = maxR * math.pow(1 - phase, 2.1).toDouble();
      if (r < maxR * 0.03) continue;

      final depth = 1 - phase; // 1 — у края, 0 — у центра
      // Гаснут и на подлёте к центру, и при рождении у края:
      // ни одно кольцо не должен появляться рывком.
      // У самого центра кольца гасим: там стоит кнопка, и она должна
      // остаться самым ярким предметом на экране.
      final clearCenter = ((r / maxR - 0.20) / 0.14).clamp(0.0, 1.0);
      final fade = math.min(phase / 0.12, 1.0) * math.min((1 - phase) / 0.18, 1.0) * clearCenter;
      final color = Color.lerp(TunneloColors.ringNear, TunneloColors.ringFar, depth)!;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: r * 2, height: r * 2),
          Radius.circular(r * 0.34),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 + 1.6 * (1 - depth)
          ..color = color.withValues(alpha: (0.16 * (1 - depth * 0.55) * fade).clamp(0.0, 1.0)),
      );
    }
  }

  /// Искры — это трафик: редкие точки, идущие по стенке туннеля к центру.
  void _paintSparks(Canvas canvas, Offset center, double maxR) {
    for (var i = 0; i < _sparks; i++) {
      // Раскладка детерминированная: угол и скорость выведены из индекса,
      // чтобы картинка не «дёргалась» между кадрами.
      final angle = (i * 2.399963) % (2 * math.pi); // золотой угол
      final speed = 0.6 + (i % 5) * 0.14;
      final phase = (t * speed + i / _sparks) % 1.0;

      final r = maxR * math.pow(1 - phase, 2.4).toDouble();
      if (r < maxR * 0.05) continue;

      final depth = 1 - phase;
      final fade = math.min(phase / 0.15, 1.0) * math.min((1 - phase) / 0.25, 1.0);
      final pos = center + Offset(math.cos(angle) * r * 0.82, math.sin(angle) * r * 0.82);

      canvas.drawCircle(
        pos,
        (0.8 + 1.5 * (1 - depth)),
        Paint()
          ..color = TunneloColors.core.withValues(alpha: (0.30 * fade * (1 - depth * 0.6)).clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
      );
    }
  }

  @override
  bool shouldRepaint(_TunnelFieldPainter old) => old.t != t || old.focus != focus;
}
