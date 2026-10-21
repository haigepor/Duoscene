import 'package:flutter/material.dart';

import 'components.dart';
import 'tokens.dart';

/// 装饰图不参与语义；按实际显示尺寸解码，避免小插图常驻整张原图。
class DSIllustration extends StatelessWidget {
  const DSIllustration(
    this.name, {
    super.key,
    this.width = 80,
    this.height = 72,
  });
  final String name;
  final double width, height;
  @override
  Widget build(BuildContext context) {
    final pixels = width * MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = [
      128,
      256,
      384,
      512,
      768,
    ].firstWhere((size) => size >= pixels, orElse: () => 768);
    return RepaintBoundary(
      child: Opacity(
        opacity: Theme.of(context).brightness == Brightness.dark ? .9 : .72,
        child: Image.asset(
          '${DS.media}$name.webp',
          width: width,
          height: height,
          fit: BoxFit.contain,
          cacheWidth: decodeWidth,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

class DSIntro extends StatelessWidget {
  const DSIntro(
    this.title,
    this.description, {
    super.key,
    required this.artwork,
  });
  final String title, description, artwork;
  @override
  Widget build(BuildContext context) => Panel(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: DS.section),
              const SizedBox(height: DS.space8),
              Text(description, style: DS.smallFor(context)),
            ],
          ),
        ),
        const SizedBox(width: DS.space12),
        DSIllustration(artwork),
      ],
    ),
  );
}
