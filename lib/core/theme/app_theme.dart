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
  ThemeData lightTheme(ColorScheme? lightColorScheme) {
    final scheme = ColorScheme.fromSeed(seedColor: TunneloColors.ringFar).copyWith(
      primary: TunneloColors.ringFar,
      secondary: TunneloColors.ringNear,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );
  }

  ThemeData darkTheme(ColorScheme? darkColorScheme) {
    final scheme = ColorScheme.fromSeed(seedColor: TunneloColors.ringFar, brightness: Brightness.dark).copyWith(
      primary: TunneloColors.ringNear,
      onPrimary: TunneloColors.abyss,
      secondary: TunneloColors.ringFar,
      surface: TunneloColors.abyss,
      onSurface: TunneloColors.core,
      surfaceContainer: TunneloColors.surface,
      surfaceContainerHigh: TunneloColors.surfaceHi,
      surfaceContainerHighest: TunneloColors.surfaceHi,
      outline: TunneloColors.surfaceHi,
      outlineVariant: TunneloColors.surfaceHi,
      error: TunneloColors.alert,
    );
    final background = mode.trueBlack ? Colors.black : TunneloColors.abyss;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: TunneloColors.core,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: TunneloColors.surface,
        indicatorColor: TunneloColors.ringFar.withValues(alpha: 0.28),
      ),
      dividerColor: TunneloColors.surfaceHi,
      fontFamily: fontFamily,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.dark},
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
