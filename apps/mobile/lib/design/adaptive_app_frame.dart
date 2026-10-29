import 'package:flutter/material.dart';

import 'bottom_navigation.dart';
import 'components.dart';
import 'window_layout.dart';

class AdaptiveAppFrame extends StatelessWidget {
  const AdaptiveAppFrame({
    super.key,
    required this.index,
    required this.onSelect,
    required this.child,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = WindowLayout.isWide(context);
    return Scaffold(
      extendBody: !wide,
      body: Forest(
        child: SafeArea(
          bottom: false,
          // 两个槽位始终存在，旋转时内容不会从 Row 移入另一棵子树。
          child: Row(
            children: [
              SizedBox(
                width: wide ? WindowLayout.railWidth : 0,
                child: wide
                    ? Center(
                        child: DuosceneNavigation(
                          key: const Key('tablet-navigation'),
                          index: index,
                          onSelect: onSelect,
                          notifyReselection: true,
                          vertical: true,
                        ),
                      )
                    : null,
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : DuosceneNavigation(
              index: index,
              onSelect: onSelect,
              notifyReselection: true,
            ),
    );
  }
}
