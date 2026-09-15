import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/gen/translations.g.dart';

extension AppLocaleX on AppLocale {
  String get preferredFontFamily =>
      this == AppLocale.fa ? FontFamily.shabnam : (kIsWeb || !Platform.isWindows ? "" : FontFamily.emoji);

  String get localeName => switch (flutterLocale.toString()) {
    "ar" => "العربية",
    // Языки России и СНГ добавлены 16.09.2026: приложением пользуются не
    // только по-русски, а «Unknown» в списке выглядит как поломка.
    "az" => "Azərbaycan dili",
    "en" => "English",
    "hy" => "Հայերեն",
    "ka" => "ქართული",
    "kk" => "Қазақша",
    "ky" => "Кыргызча",
    "tg" => "Тоҷикӣ",
    "uz" => "Oʻzbekcha",
    "es" => "Español",
    "fa" => "فارسی",
    "fr" => "Français",
    "id" => "Bahasa Indonesia",
    "pt_BR" => "Português (Brasil)",
    "ru" => "Русский",
    "tr" => "Türkçe",
    "zh" || "zh_CN" => "中文 (中国)",
    "zh_TW" => "中文 (台湾)",
    _ => "Unknown",
  };
}
