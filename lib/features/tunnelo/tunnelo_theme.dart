import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Палитра Tunnelo.
///
/// Глубокий градиент от индиго к мяте, карточки — матовое стекло, мятный
/// акцент и коралловое действие. Коралловым покрашено ровно одно: кнопка
/// подключения. Она и есть главный предмет на экране.
///
/// Стекло сделано честно: полупрозрачная подложка всегда достаточно плотная,
/// чтобы текст на ней читался. Красиво и нечитаемо — это не красиво.
abstract class TunneloColors {
  // Фон: градиент рисуется TunneloBackground, mist — его средний тон,
  // чтобы обычный Scaffold без градиента не выбивался.
  static const mist = Color(0xFF141B3D); // глубокий индиго
  static const mistDeep = Color(0xFF0C1230); // низ градиента
  static const mistWarm = Color(0xFF12403C); // мятный край градиента

  static const card = Color(0x14FFFFFF); // стекло: белый на 8%
  static const cardSolid = Color(0xFF1C2450); // плотная подложка под текст
  static const line = Color(0x26FFFFFF); // граница стекла

  static const sea = Color(0xFF5FE0B8); // мятный акцент
  static const seaDeep = Color(0xFF8CF0D0); // светлее — заголовки и цифры
  static const coral = Color(0xFFFF8A6B); // действие: подключиться
  static const coralSoft = Color(0xFFFFB7A0); // свечение вокруг кнопки

  static const text = Color(0xFFEAF6F1); // основной текст
  static const muted = Color(0xFF93AFA8); // подписи
  static const alert = Color(0xFFFF6B4A); // ошибка

  // Старые имена — чтобы не переписывать разом весь код.
  static const abyss = mistDeep;
  static const surface = card;
  static const surfaceHi = line;
  static const ringFar = sea;
  static const ringNear = coral;
  static const core = text;
}

/// Фон-градиент. Кладётся под содержимое экрана.
class TunneloBackground extends StatelessWidget {
  const TunneloBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [TunneloColors.mist, TunneloColors.mistDeep, TunneloColors.mistWarm],
        stops: [0.0, 0.55, 1.0],
      ),
    ),
    child: child,
  );
}

/// Экран с градиентом и прозрачной шапкой.
///
/// Градиент обязан быть под всем содержимым: стекло размывает то, что под
/// ним, и на плоском цвете выглядит грязным пятном.
class TunneloScaffold extends StatelessWidget {
  const TunneloScaffold({super.key, required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) => TunneloBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: TunneloColors.text,
        elevation: 0,
      ),
      body: body,
    ),
  );
}

/// Карточка из матового стекла.
///
/// Размытие берётся от того, что под ней, поэтому карточку нельзя класть
/// на пустой цвет — под ней должен быть градиент или картинка.
class TunneloGlass extends StatelessWidget {
  const TunneloGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 16),
    this.radius = 20,
    this.highlight = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  /// Подсветить рамку — для карточек, требующих внимания.
  final bool highlight;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: TunneloColors.card,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: highlight ? TunneloColors.coral : TunneloColors.line,
            width: highlight ? 1.4 : 1,
          ),
        ),
        child: child,
      ),
    ),
  );
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
