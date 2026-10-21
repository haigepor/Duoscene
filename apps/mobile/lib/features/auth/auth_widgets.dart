import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/illustrations.dart';
import '../../design/tokens.dart';

/// 认证页共享开放式表单骨架；键盘与大字体下保持自然滚动，不锁定图片高度。
class AuthBody extends StatelessWidget {
  const AuthBody({super.key, required this.children, this.filmstrip = false});
  final List<Widget> children;
  final bool filmstrip;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showArt =
              filmstrip &&
              constraints.maxHeight >= 640 &&
              MediaQuery.viewInsetsOf(context).bottom == 0 &&
              MediaQuery.textScalerOf(context).scale(DS.bodySize) < 20;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (showArt)
                Positioned(
                  bottom: -DS.space16,
                  left: -DS.space24 * 2,
                  right: -DS.space24 * 2,
                  child: IgnorePointer(
                    // 设计稿是延伸到画面外的背景胶片，放大裁切并降低存在感。
                    child: Opacity(
                      opacity: .65,
                      child: DSIllustration(
                        'auth-filmstrip-glass',
                        width: constraints.maxWidth + DS.space24 * 4,
                        height: DS.space32 * 6,
                      ),
                    ),
                  ),
                ),
              ListView(
                key: const Key('auth-scroll'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  DS.space24,
                  DS.space8,
                  DS.space24,
                  DS.space24,
                ),
                children: children,
              ),
            ],
          );
        },
      ),
    ),
  );
}

class AuthIntro extends StatelessWidget {
  const AuthIntro(
    this.title,
    this.description, {
    super.key,
    required this.artwork,
  });
  final String title, description, artwork;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.textScalerOf(context).scale(DS.bodySize) > 20;
    return Padding(
      padding: const EdgeInsets.only(bottom: DS.space16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 112),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DS.heading.copyWith(
                      fontSize: DS.sectionSize + DS.space4,
                    ),
                  ),
                  const SizedBox(height: DS.space8),
                  Text(description, style: DS.smallFor(context)),
                ],
              ),
            ),
            const SizedBox(width: DS.space8),
            DSIllustration(
              artwork,
              width: compact ? 72 : 96,
              height: compact ? 72 : 96,
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration authInputDecoration(
  BuildContext context,
  String hint,
  String icon, {
  Widget? suffix,
}) => InputDecoration(
  hintText: hint,
  hintStyle: DS.body.copyWith(color: DSPalette.of(context).muted),
  counterText: '',
  prefixIcon: Center(
    widthFactor: 1,
    heightFactor: 1,
    child: DSIcon(
      icon,
      size: DS.navigationIcon,
      color: DSPalette.of(context).muted,
    ),
  ),
  prefixIconConstraints: const BoxConstraints(
    minWidth: DS.touchTarget,
    minHeight: DS.inputHeight,
  ),
  suffixIcon: suffix,
  suffixIconConstraints: const BoxConstraints(
    minWidth: DS.touchTarget,
    minHeight: DS.touchTarget,
  ),
  errorStyle: DS.small.copyWith(color: Theme.of(context).colorScheme.error),
  errorMaxLines: 3,
);

class AuthHint extends StatelessWidget {
  const AuthHint(this.message, {super.key, this.icon = 'info'});
  final String message, icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: DS.space16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: DS.space2),
          child: DSIcon(
            icon,
            size: DS.iconSmall,
            color: DSPalette.of(context).primary,
          ),
        ),
        const SizedBox(width: DS.space8),
        Expanded(child: Text(message, style: DS.smallFor(context))),
      ],
    ),
  );
}

class AuthLink extends StatelessWidget {
  const AuthLink(this.label, this.onPressed, {super.key, this.prefix});
  final String label;
  final String? prefix;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Center(
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.center,
      children: [
        if (prefix != null) Text(prefix!, style: DS.smallFor(context)),
        TextButton(onPressed: onPressed, child: Text(label)),
      ],
    ),
  );
}
