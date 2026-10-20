import 'package:flutter/material.dart';

import 'components.dart';
import 'tokens.dart';

class DuosceneNavigation extends StatelessWidget {
  const DuosceneNavigation({
    super.key,
    required this.index,
    required this.onSelect,
  });
  final int index;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: DSPalette.of(context).bg,
      border: Border(
        top: BorderSide(color: DSPalette.of(context).line, width: .5),
      ),
    ),
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: index == i,
                label: ['观影', '短剧', '记录', '我的'][i],
                child: InkWell(
                  key: Key('tab-$i'),
                  onTap: () => onSelect(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: index == i ? 1 : 0),
                          duration: DSMotion.duration(context),
                          curve: DSMotion.curve,
                          builder: (context, value, _) => Transform.translate(
                            offset: Offset(0, -value * 2),
                            child: DSIcon(
                              [
                                'film-reel',
                                'clapperboard',
                                'notebook',
                                'user-round',
                              ][i],
                              size: 20,
                              color: Color.lerp(
                                DSPalette.of(context).muted,
                                DSPalette.of(context).primary,
                                value,
                              )!,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ['观影', '短剧', '记录', '我的'][i],
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.2,
                            color: index == i
                                ? DSPalette.of(context).primary
                                : DSPalette.of(context).muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
