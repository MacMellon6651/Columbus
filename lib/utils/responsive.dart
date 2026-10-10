import 'package:flutter/material.dart';

class Responsive {
  final BuildContext context;
  late final Size screenSize;
  late final double screenWidth;
  late final double screenHeight;
  late final double shortestSide;
  late final double longestSide;
  late final Orientation orientation;
  late final bool isPhone;
  late final bool isTablet;
  late final bool isDesktop;

  Responsive(this.context) {
    screenSize = MediaQuery.of(context).size;
    screenWidth = screenSize.width;
    screenHeight = screenSize.height;
    shortestSide = screenSize.shortestSide;
    longestSide = screenSize.longestSide;
    orientation = MediaQuery.of(context).orientation;

    isPhone = shortestSide < 600;
    isTablet = shortestSide >= 600 && shortestSide < 900;
    isDesktop = shortestSide >= 900;
  }

  // Адаптивные отступы
  double get paddingHorizontal {
    if (isDesktop) return 40;
    if (isTablet) return 24;
    return 16;
  }

  double get paddingVertical {
    if (isDesktop) return 32;
    if (isTablet) return 20;
    return 12;
  }

  // Размер кнопок карты
  double get mapButtonSize {
    if (isDesktop) return 60;
    if (isTablet) return 56;
    return 52;
  }

  // Радиус закругления
  double get borderRadius {
    if (isDesktop) return 20;
    if (isTablet) return 18;
    return 16;
  }

  // Верхний отступ для поисковой строки
  double get topPadding {
    if (isDesktop) return 70;
    if (isTablet) return 60;
    return 50;
  }

  // Максимальная ширина контента (для десктопа)
  double get maxContentWidth {
    if (isDesktop) return 480;
    if (isTablet) return 420;
    return double.infinity;
  }

  // Ширина панели маршрута
  double get routePanelWidth {
    if (isDesktop) return 500;
    if (isTablet) return 420;
    return double.infinity;
  }

  // Высота панели настроек
  double get settingsPanelHeight {
    if (isDesktop) return 700;
    if (isTablet) return 600;
    return screenHeight * 0.8;
  }

  // Размер шрифта заголовков
  double get headingFontSize {
    if (isDesktop) return 32;
    if (isTablet) return 28;
    return 24;
  }
}