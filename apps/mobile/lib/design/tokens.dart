import 'package:flutter/material.dart';

import 'palette.dart';
export 'palette.dart';

abstract final class DS {
  static const media = 'assets/design/media/';
  // 字号使用逻辑像素；不随物理分辨率整体放大，系统 TextScaler 保持生效。
  static const bodySize = 14.0;
  static const captionSize = 12.0;
  static const labelSize = 12.0;
  static const itemTitleSize = 15.0;
  static const sectionSize = 16.0;
  static const pageTitleSize = 18.0;
  static const iconSize = 20.0;
  static const panelRadius = 14.0;
  static const panelPadding = 12.0;
  static const buttonHeight = 32.0;
  static const menuHeight = 44.0;
  // 导航视觉尺寸与触控尺寸分离，小图标仍保留完整的 48dp 点击区。
  static const navigationIcon = 18.0, chevronSize = 14.0;
  static const secondaryTitleSize = 16.0, secondarySectionSize = 14.0;
  static const carouselContentGap = 12.0;
  static const menuLabel = TextStyle(fontSize: 13, height: 1.4);
  static const secondarySection = TextStyle(
    fontSize: secondarySectionSize,
    height: 1.4,
    fontWeight: FontWeight.w600,
  );
  static const space2 = 2.0, space4 = 4.0, space8 = 8.0;
  static const space12 = 12.0, space16 = 16.0, space24 = 24.0, space32 = 32.0;
  static const pageInset = 16.0;
  static const toolbarHeight = 48.0;
  static const touchTarget = 48.0;
  static const inputHeight = 48.0;
  static const primaryButtonHeight = 48.0;
  static const radiusSmall = 8.0, radiusMedium = 12.0, radiusSheet = 20.0;
  static const iconSmall = 16.0;
  static const avatarSmall = 28.0, avatarMedium = 40.0, avatarLarge = 56.0;
  static const posterTitleSize = 28.0, heroTitleSize = 36.0;
  static const brandSize = 24.0, brandHeroSize = 40.0;
  static const displaySize = 24.0;
  static const body = TextStyle(fontSize: bodySize, height: 1.5);
  static const section = TextStyle(
    fontSize: sectionSize,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );
  static const title = TextStyle(
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w600,
  );
  static const label = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
  );
  static const toolbar = TextStyle(
    fontSize: secondaryTitleSize,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );
  static const heading = TextStyle(
    fontSize: pageTitleSize,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
  static const small = TextStyle(fontSize: captionSize, height: 1.5);
  static TextStyle smallFor(BuildContext context) =>
      small.copyWith(color: DSPalette.of(context).muted);
}

/// 动效表达层级与方向；跟随系统减少动画设置，不改变业务状态。
abstract final class DSMotion {
  static const fast = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 220);
  static const navigation = Duration(milliseconds: 280);
  static const curve = Curves.easeOutCubic;
  static Duration duration(BuildContext context, [Duration value = standard]) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}
