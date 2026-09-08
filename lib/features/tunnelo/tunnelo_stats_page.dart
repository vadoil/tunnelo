import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Статистика подключения.
///
/// Показываем то, что человеку понятно: скорость сейчас, сколько скачано
/// за сеанс и сколько трафика осталось по подписке. Память, горутины и
/// прочие внутренности ядра сюда не выносим — это данные для отладки,
/// а не для человека.
class TunneloStatsPage extends HookConsumerWidget {
  const TunneloStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsNotifierProvider).value;
    final profile = ref.watch(activeProfileProvider).value;
    final info = profile is RemoteProfileEntity ? profile.subInfo : null;

    // История скорости для графика. Держим последние 60 отсчётов — этого
    // хватает на минуту наблюдения и не жрёт память.
    final history = useState<List<double>>(const []);
    final down = stats?.downlink.toInt() ?? 0;
    useEffect(() {
      final next = [...history.value, down.toDouble()];
      history.value = next.length > 60 ? next.sublist(next.length - 60) : next;
      return null;
    }, [down]);

    return TunneloScaffold(
      title: 'Статистика',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SpeedCard(
            down: down,
            up: stats?.uplink.toInt() ?? 0,
            history: history.value,
          ),
          const SizedBox(height: 12),
          TunneloGlass(
            child: Row(
              children: [
                Expanded(
                  child: _Cell(
                    label: 'Скачано за сеанс',
                    value: (stats?.downlinkTotal.toInt() ?? 0).size(),
                  ),
                ),
                Container(width: 1, height: 38, color: TunneloColors.line),
                Expanded(
                  child: _Cell(
                    label: 'Отправлено',
                    value: (stats?.uplinkTotal.toInt() ?? 0).size(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TunneloGlass(
            child: Row(
              children: [
                Expanded(
                  child: _Cell(
                    label: 'Соединений',
                    value: '${stats?.connectionsOut ?? 0}',
                  ),
                ),
                Container(width: 1, height: 38, color: TunneloColors.line),
                Expanded(
                  child: _Cell(
                    label: 'Трафик подписки',
                    value: info == null || info.total <= 0
                        ? 'Безлимит'
                        : info.consumption.size(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Счётчики сеанса обнуляются при переподключении. Трафик подписки '
            'считает сервер и обновляет раз в несколько минут.',
            style: TextStyle(color: TunneloColors.muted, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _SpeedCard extends StatelessWidget {
  const _SpeedCard({required this.down, required this.up, required this.history});

  final int down;
  final int up;
  final List<double> history;

  @override
  Widget build(BuildContext context) => TunneloGlass(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
    radius: 24,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Сейчас загружается',
          style: TextStyle(color: TunneloColors.muted, fontSize: 14),
        ),
        const SizedBox(height: 6),
        Text(
          down.speed(),
          style: const TextStyle(
            color: TunneloColors.seaDeep,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'отдача ${up.speed()}',
          style: const TextStyle(color: TunneloColors.muted, fontSize: 14),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 72,
          child: CustomPaint(
            painter: _Sparkline(history),
            size: Size.infinite,
          ),
        ),
      ],
    ),
  );
}

/// График скорости. Рисуем сами: ради одной линии тянуть библиотеку графиков
/// незачем, а своя рисуется ровно в нашей палитре.
class _Sparkline extends CustomPainter {
  const _Sparkline(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final peak = values.reduce(math.max);
    if (peak <= 0) return;

    final step = size.width / (values.length - 1);
    final line = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * step;
      final y = size.height - (values[i] / peak) * size.height;
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x405FE0B8), Color(0x005FE0B8)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = TunneloColors.sea
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Sparkline old) => old.values != values;
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: TunneloColors.seaDeep,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: TunneloColors.muted, fontSize: 13),
      ),
    ],
  );
}
