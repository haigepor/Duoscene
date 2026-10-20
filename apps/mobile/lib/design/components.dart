import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'tokens.dart';
import 'scroll_chrome.dart';

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
  const Brand({super.key, this.size = 24});
  final double size;
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
            SizedBox(width: size * .22),
            CustomPaint(
              size: Size(size * .92, size * .65),
              painter: _Rings(DSPalette.of(context).primary),
            ),
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

class Forest extends StatelessWidget {
  const Forest({super.key, required this.child, this.hero = false});
  final Widget child;
  final bool hero;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: DSPalette.of(context).bg),
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (DSPalette.of(context).forest)
          Positioned.fill(
            child: Opacity(
              opacity: hero ? .85 : .5,
              child: Image.asset(
                '${DS.media}forest-atmosphere-v2.png',
                fit: BoxFit.cover,
                cacheWidth: 1080,
                excludeFromSemantics: true,
              ),
            ),
          ),
        if (DSPalette.of(context).forest)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: hero
                      ? [
                          Colors.transparent,
                          DSPalette.of(context).bg.withValues(alpha: .75),
                          DSPalette.of(context).bg,
                        ]
                      : [
                          DSPalette.of(context).bg.withValues(alpha: .4),
                          Colors.transparent,
                          DSPalette.of(context).bg.withValues(alpha: .8),
                        ],
                ),
              ),
            ),
          ),
        // 背景图之上的控件需要直接 Material 承载墨水反馈，避免被装饰层遮挡。
        Material(type: MaterialType.transparency, child: child),
      ],
    ),
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
      image: DSPalette.of(context).forest
          ? const DecorationImage(
              image: AssetImage('${DS.media}media-mountains-landscape.png'),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Color(0x77457669),
                BlendMode.srcATop,
              ),
            )
          : null,
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
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottom;
  final bool hero;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DSPalette.of(context).bg,
    body: Forest(
      hero: hero,
      child: SafeArea(
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
                  ),
                  Expanded(child: Text(title, style: DS.toolbar)),
                  ...?actions,
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
  });
  final String icon, title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Material(
    // 菜单也可独立出现在山景背景上，给墨水与列表背景提供直接的 Material。
    type: MaterialType.transparency,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      minVerticalPadding: 8,
      minTileHeight: DS.touchTarget,
      dense: true,
      minLeadingWidth: DS.navigationIcon,
      horizontalTitleGap: DS.space12,
      leading: DSIcon(icon, size: DS.navigationIcon),
      title: Text(title, style: DS.menuLabel),
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
    ),
    onPressed: onTap,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: DS.space2),
        DSIcon(
          'chevron-right',
          size: DS.chevronSize,
          color: DSPalette.of(context).primary,
        ),
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, required this.action});
  final String title;
  final Widget action;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(child: Text(title, style: DS.title)),
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
