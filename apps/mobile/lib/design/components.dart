import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'tokens.dart';
import 'scroll_chrome.dart';
import 'window_layout.dart';

/// 业务弹层显式恢复语义前景色，避免继承播放器的白色媒体文字。
Future<T?> showDSSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool showDragHandle = true,
  Color? backgroundColor,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  backgroundColor: backgroundColor ?? DSPalette.of(context).panel,
  showDragHandle: showDragHandle,
  sheetAnimationStyle: AnimationStyle(
    duration: DSMotion.duration(context, DSMotion.navigation),
    reverseDuration: DSMotion.duration(context),
  ),
  builder: (context) => DefaultTextStyle(
    style: DS.body.copyWith(color: DSPalette.of(context).ink),
    child: IconTheme(
      data: IconThemeData(color: DSPalette.of(context).ink, size: DS.iconSize),
      child: builder(context),
    ),
  ),
);

class DSSheetContent extends StatelessWidget {
  const DSSheetContent({
    super.key,
    required this.title,
    required this.children,
    required this.closeLabel,
    this.subtitle,
  });
  final String title, closeLabel;
  final String? subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .88,
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          DS.pageInset,
          0,
          DS.pageInset,
          DS.space16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: DS.section)),
                IconTap('x', closeLabel, () => Navigator.pop(context)),
              ],
            ),
            if (subtitle != null) ...[
              Text(subtitle!, style: DS.smallFor(context)),
              const SizedBox(height: DS.space16),
            ],
            ...children,
          ],
        ),
      ),
    ),
  );
}

class DSIcon extends StatelessWidget {
  const DSIcon(this.name, {super.key, this.size = DS.iconSize, this.color});
  final String name;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/design/icons/$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(
      color ?? IconTheme.of(context).color ?? DSPalette.of(context).ink,
      BlendMode.srcIn,
    ),
  );
}

class IconTap extends StatelessWidget {
  const IconTap(this.icon, this.label, this.onTap, {super.key, this.color});
  final String icon, label;
  final VoidCallback? onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onTap,
    icon: DSIcon(icon, color: color),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.size = 24, this.ringsFirst = false});
  final double size;
  final bool ringsFirst;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Duoscene，两只相交圆环',
    child: ExcludeSemantics(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ringsFirst) ...[
              CustomPaint(
                size: Size(size * 1.3, size * .86),
                painter: _Rings(DSPalette.of(context).primary),
              ),
              SizedBox(width: size * .3),
            ],
            Text(
              'duoscene',
              style: TextStyle(
                fontFamily: 'DuosceneSerif',
                fontStyle: FontStyle.italic,
                fontSize: size,
                color: DSPalette.of(context).primary,
                letterSpacing: -.8,
              ),
            ),
            if (!ringsFirst) ...[
              SizedBox(width: size * .22),
              CustomPaint(
                size: Size(size * .92, size * .65),
                painter: _Rings(DSPalette.of(context).primary),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _Rings extends CustomPainter {
  _Rings(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final r = size.height * .47;
    canvas.drawCircle(Offset(r + 1, size.height / 2), r, p);
    canvas.drawCircle(Offset(size.width - r - 1, size.height / 2), r, p);
  }

  @override
  bool shouldRepaint(covariant _Rings oldDelegate) =>
      oldDelegate.color != color;
}

/// 保留旧背景组件名称供现有调用方使用，材质统一由蓝色主题 token 提供。
class Forest extends StatelessWidget {
  const Forest({super.key, required this.child, this.hero = false});
  final Widget child;
  final bool hero;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: DSPalette.of(context).bg,
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DS.panelPadding),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: DSPalette.of(context).panel,
      borderRadius: BorderRadius.circular(DS.panelRadius),
      border: Border.all(
        color: DSPalette.of(context).line.withValues(alpha: .7),
      ),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class MountainAvatar extends StatelessWidget {
  const MountainAvatar({super.key, this.initial = '知', this.size = 46});
  final String initial;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: DSPalette.of(context).primary.withValues(alpha: .65),
      ),
      color: DSPalette.of(context).tint,
    ),
    child: Text(
      initial,
      style: TextStyle(
        fontSize: size * .43,
        color: DSPalette.of(context).onTint,
      ),
    ),
  );
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.bottom,
    this.hero = false,
    this.centerTitle = false,
    this.maxContentWidth = WindowLayout.readingWidth,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottom;
  final bool hero;
  final bool centerTitle;
  final double maxContentWidth;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DSPalette.of(context).bg,
    body: Forest(
      hero: hero,
      child: SafeArea(
        child: ContentWidth(
          maxWidth: maxContentWidth,
          child: ScrollChrome(
            header: SizedBox(
              height: DS.toolbarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    IconTap(
                      'arrow-left',
                      '返回',
                      () => Navigator.maybePop(context),
                      // 外观页切换主题时，返回图标与页面前景色同步更新。
                      color: DSPalette.of(context).ink,
                    ),
                    Expanded(
                      child: Text(
                        title,
                        style: DS.toolbar.copyWith(
                          color: DSPalette.of(context).ink,
                        ),
                        textAlign: centerTitle
                            ? TextAlign.center
                            : TextAlign.start,
                      ),
                    ),
                    ...?actions,
                    if (centerTitle && actions == null)
                      const SizedBox(width: DS.touchTarget),
                  ],
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: DS.toolbarHeight),
              child: Column(
                children: [
                  Expanded(child: child),
                  if (bottom != null)
                    Padding(
                      padding: const EdgeInsets.all(DS.pageInset),
                      child: bottom!,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class MenuRow extends StatelessWidget {
  const MenuRow(
    this.icon,
    this.title, {
    super.key,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.compact = false,
  });
  final String icon, title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool compact;
  @override
  Widget build(BuildContext context) => Material(
    // 菜单独立承载交互反馈，与页面背景共用语义色。
    type: MaterialType.transparency,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      minVerticalPadding: compact ? DS.space4 : DS.space8,
      minTileHeight: DS.touchTarget,
      dense: true,
      minLeadingWidth: compact ? DS.iconSmall : DS.navigationIcon,
      horizontalTitleGap: compact ? DS.space8 : DS.space12,
      leading: DSIcon(icon, size: compact ? DS.iconSmall : DS.navigationIcon),
      title: Text(title, style: compact ? DS.label : DS.menuLabel),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: DS.smallFor(context)),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : DSIcon(
                  'chevron-right',
                  size: DS.chevronSize,
                  color: DSPalette.of(context).muted,
                )),
      onTap: onTap,
    ),
  );
}

/// 文案和 SVG 共用垂直中线，避免用字体箭头造成基线与字重差异。
class ArrowAction extends StatelessWidget {
  const ArrowAction(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      padding: const EdgeInsets.only(left: DS.space8),
      minimumSize: const Size(DS.touchTarget, DS.touchTarget),
      textStyle: DS.label,
      overlayColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
    ),
    onPressed: onTap,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: DS.space4),
        DSIcon(
          'arrow-right',
          size: DS.iconSmall,
          color: DSPalette.of(context).primary,
        ),
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.title, {
    super.key,
    required this.action,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final Widget action;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: subtitle == null
            ? Text(title, style: DS.title)
            : LayoutBuilder(
                builder: (context, constraints) {
                  final stacked =
                      MediaQuery.textScalerOf(context).scale(12) > 16;
                  final label = Text(title, style: DS.section);
                  final caption = Text(
                    subtitle!,
                    style: DS.smallFor(context).copyWith(height: 1.4),
                    maxLines: stacked ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  );
                  // 大字号独立成行，分类名不与副标题挤在一起。
                  return stacked
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label,
                            const SizedBox(height: DS.space4),
                            caption,
                          ],
                        )
                      : Row(
                          children: [
                            label,
                            const SizedBox(width: DS.space8),
                            Expanded(child: caption),
                          ],
                        );
                },
              ),
      ),
      const SizedBox(width: DS.space8),
      action,
    ],
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView(
    this.title,
    this.subtitle, {
    super.key,
    this.action,
    this.onTap,
    this.icon = 'bookmark',
  });
  final String title, subtitle, icon;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DSIcon(icon, size: 52, color: DSPalette.of(context).primary),
        const SizedBox(height: 20),
        Text(title, style: DS.section, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: TextStyle(color: DSPalette.of(context).muted, height: 1.7),
          textAlign: TextAlign.center,
        ),
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: FilledButton(onPressed: onTap, child: Text(action!)),
          ),
      ],
    ),
  );
}

void tell(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String action = '确认',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
Future<void> openPage(BuildContext context, Widget page) =>
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );

class PreviewLabel extends StatelessWidget {
  const PreviewLabel({super.key, this.text = '设计预览 · 虚构片目，无在线片源'});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: DSPalette.of(context).muted),
      textAlign: TextAlign.center,
    ),
  );
}
