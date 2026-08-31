import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';

class AppTheme {
  AppTheme(this.mode, this.fontFamily);
  final AppThemeMode mode;
  final String fontFamily;

  /// Схемы Material You с устройства намеренно игнорируются: у продукта
  /// своя палитра, и она должна выглядеть одинаково на всех телефонах.
  ///
  /// Светлая мятная гамма: спокойный фон, белые карточки, зелёный —
  /// основной, коралловый — действие.
  ThemeData lightTheme(ColorScheme? lightColorScheme) => _tunneloTheme();

  ThemeData darkTheme(ColorScheme? darkColorScheme) => _tunneloTheme();

  ThemeData _tunneloTheme() {
    final scheme = ColorScheme.fromSeed(seedColor: TunneloColors.sea).copyWith(
      primary: TunneloColors.sea,
      onPrimary: Colors.white,
      secondary: TunneloColors.coral,
      onSecondary: Colors.white,
      surface: TunneloColors.mist,
      onSurface: TunneloColors.text,
      surfaceContainer: TunneloColors.card,
      surfaceContainerHigh: TunneloColors.card,
      surfaceContainerHighest: TunneloColors.card,
      outline: TunneloColors.line,
      outlineVariant: TunneloColors.line,
      error: TunneloColors.alert,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: TunneloColors.mist,
      fontFamily: fontFamily,
      appBarTheme: const AppBarTheme(
        backgroundColor: TunneloColors.mist,
        foregroundColor: TunneloColors.seaDeep,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: TunneloColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: TunneloColors.card,
        indicatorColor: TunneloColors.sea.withValues(alpha: 0.14),
        elevation: 0,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: TunneloColors.sea,
        textColor: TunneloColors.text,
      ),
      dividerColor: TunneloColors.line,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.tunnelo},
    );
  }

  CupertinoThemeData cupertinoThemeData(bool sysDark, ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
    final bool isDark = switch (mode) {
      AppThemeMode.system => sysDark,
      AppThemeMode.light => false,
      AppThemeMode.dark => true,
      AppThemeMode.black => true,
    };
    final def = CupertinoThemeData(brightness: isDark ? Brightness.dark : Brightness.light);
    // final def = CupertinoThemeData(brightness: Brightness.dark);

    // return def;
    final defaultMaterialTheme = isDark ? darkTheme(darkColorScheme) : lightTheme(lightColorScheme);
    return MaterialBasedCupertinoThemeData(
      materialTheme: defaultMaterialTheme.copyWith(
        cupertinoOverrideTheme: def.copyWith(
          textTheme: CupertinoTextThemeData(
            textStyle: def.textTheme.textStyle.copyWith(fontFamily: fontFamily),
            actionTextStyle: def.textTheme.actionTextStyle.copyWith(fontFamily: fontFamily),
            navActionTextStyle: def.textTheme.navActionTextStyle.copyWith(fontFamily: fontFamily),
            navTitleTextStyle: def.textTheme.navTitleTextStyle.copyWith(fontFamily: fontFamily),
            navLargeTitleTextStyle: def.textTheme.navLargeTitleTextStyle.copyWith(fontFamily: fontFamily),
            pickerTextStyle: def.textTheme.pickerTextStyle.copyWith(fontFamily: fontFamily),
            dateTimePickerTextStyle: def.textTheme.dateTimePickerTextStyle.copyWith(fontFamily: fontFamily),
            tabLabelTextStyle: def.textTheme.tabLabelTextStyle.copyWith(fontFamily: fontFamily),
          ).copyWith(),
          barBackgroundColor: def.barBackgroundColor,
          scaffoldBackgroundColor: def.scaffoldBackgroundColor,
        ),
      ),
    );
  }
}
