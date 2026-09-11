import 'package:flutter/material.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';

/// Строка аккаунта в карточке на главной.
///
/// Без аккаунта — одна кнопка «Войти по почте»: отдельной регистрации нет,
/// аккаунт появляется при первом входе по коду из письма. С аккаунтом —
/// почта и «Выйти». Провайдеров не знает, данные приходят снаружи: так её
/// можно проверить тестом без всего приложения.
class TunneloAccountRow extends StatelessWidget {
  const TunneloAccountRow({
    super.key,
    required this.email,
    required this.onLogin,
    required this.onLogout,
  });

  final String? email;
  final VoidCallback onLogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final email = this.email;
    if (email == null) {
      return InkWell(
        onTap: onLogin,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Row(
            children: [
              Icon(Icons.login_rounded, size: 19, color: TunneloColors.sea),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Войти по почте',
                      style: TextStyle(color: TunneloColors.sea, fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Чтобы подписка не пропала вместе с устройством',
                      style: TextStyle(color: TunneloColors.muted, fontSize: 12.5, height: 1.3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: TunneloColors.muted),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 2),
      child: Row(
        children: [
          const Icon(Icons.alternate_email_rounded, size: 19, color: TunneloColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              email,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: TunneloColors.seaDeep, fontSize: 14.5),
            ),
          ),
          TextButton(
            onPressed: onLogout,
            style: TextButton.styleFrom(
              foregroundColor: TunneloColors.muted,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}
