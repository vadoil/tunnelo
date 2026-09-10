import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Знакомство при первом запуске.
///
/// Главная его задача — третий экран. Android показывает окно «приложение
/// хочет отслеживать сетевой трафик», и без объяснения это выглядит как
/// просьба разрешить слежку. Люди закрывают приложение прямо там. Поэтому
/// мы сами рассказываем, что это за окно, до того как система его покажет.
class TunneloWelcomePage extends HookConsumerWidget {
  const TunneloWelcomePage({super.key});

  static const _steps = [
    _Step(
      image: 'assets/images/fox/lantern.png',
      title: 'Интернет без границ',
      text: 'YouTube, ChatGPT, Spotify и другие зарубежные сервисы '
          'открываются как обычно. '
          'Настраивать ничего не нужно — приложение уже готово к работе.',
    ),
    _Step(
      image: 'assets/images/fox/sitting.png',
      title: 'Российские сайты — напрямую',
      text: 'Госуслуги, банки, Ozon и Wildberries идут мимо туннеля. '
          'Они работают быстро и не считают вас иностранцем.',
    ),
    _Step(
      image: 'assets/images/fox/waving.png',
      title: 'Одно разрешение',
      text: 'Android сейчас спросит разрешение на подключение VPN и напишет '
          'про отслеживание трафика. Так система предупреждает про любой VPN — '
          'иначе туннель просто не поднять. Мы не смотрим, что вы открываете, '
          'и не храним историю.',
      action: 'Понятно, начнём',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = useState(0);
    final controller = usePageController();
    final step = _steps[page.value];
    final last = page.value == _steps.length - 1;

    return TunneloBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _finish(context, ref),
                  style: TextButton.styleFrom(foregroundColor: TunneloColors.muted),
                  child: Text(last ? '' : 'Пропустить'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: controller,
                  itemCount: _steps.length,
                  onPageChanged: (i) => page.value = i,
                  itemBuilder: (context, i) => _StepView(step: _steps[i]),
                ),
              ),
              _Dots(count: _steps.length, active: page.value),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: FilledButton(
                  onPressed: () {
                    if (last) {
                      _finish(context, ref);
                    } else {
                      controller.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: last ? TunneloColors.coral : TunneloColors.sea,
                    foregroundColor: last ? Colors.white : TunneloColors.mistDeep,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(step.action ?? 'Дальше'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _finish(BuildContext context, WidgetRef ref) {
    ref.read(Preferences.introCompleted.notifier).update(true);
    context.go('/home');
  }
}

class _Step {
  const _Step({
    required this.image,
    required this.title,
    required this.text,
    this.action,
  });

  final String image;
  final String title;
  final String text;

  /// Своя надпись на кнопке. У последнего шага она другая.
  final String? action;
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(step.image, height: 220, fit: BoxFit.contain),
        const SizedBox(height: 32),
        Text(
          step.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: TunneloColors.text,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          step.text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: TunneloColors.muted,
            fontSize: 15,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: i == active ? 22 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: i == active ? TunneloColors.sea : TunneloColors.line,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
    ],
  );
}
