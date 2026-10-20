import 'dart:async';

import 'package:flutter/material.dart';

import '../design/components.dart';
import '../design/tokens.dart';
import 'api_client.dart';

String friendlyError(Object error) => error is ApiException
    ? '${error.message}${error.requestId == null ? '' : '\n参考编号：${error.requestId}'}'
    : '暂时无法完成操作，请稍后重试。';

class ErrorNotice extends StatefulWidget {
  const ErrorNotice(this.message, {super.key, this.floating = false});
  final String message;
  final bool floating;
  @override
  State<ErrorNotice> createState() => _ErrorNoticeState();
}

class _ErrorNoticeState extends State<ErrorNotice> {
  Timer? _timer;
  bool _visible = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _visible = true);
      _arm();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _arm();
  }

  @override
  void didUpdateWidget(covariant ErrorNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message != oldWidget.message ||
        widget.floating != oldWidget.floating) {
      _visible = true;
      _arm();
    }
  }

  void _arm() {
    _timer?.cancel();
    // 辅助导航下保留提示，避免用户尚未阅读就消失；行内错误也持续保留。
    if (_visible &&
        widget.floating &&
        !MediaQuery.accessibleNavigationOf(context)) {
      _timer = Timer(const Duration(seconds: 6), _dismiss);
    }
  }

  void _dismiss() {
    _timer?.cancel();
    if (mounted) setState(() => _visible = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: DSMotion.duration(context),
    switchInCurve: DSMotion.curve,
    switchOutCurve: DSMotion.curve,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -.12),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: _visible ? _bubble(context) : const SizedBox.shrink(),
  );

  void _showDetails() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('提示详情'),
        content: SingleChildScrollView(
          child: SelectableText(widget.message, style: DS.body),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context) {
    final separator = widget.message.indexOf('\n参考编号：');
    final summary = separator < 0
        ? widget.message
        : widget.message.substring(0, separator);
    return Semantics(
      key: ValueKey(widget.message),
      liveRegion: true,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 56),
        margin: widget.floating
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(vertical: DS.space12),
        padding: EdgeInsets.fromLTRB(
          DS.space4,
          widget.floating ? DS.space4 : DS.space12,
          DS.space4,
          widget.floating ? DS.space4 : DS.space12,
        ),
        decoration: BoxDecoration(
          color: DSPalette.of(context).noticeSurface,
          border: Border.all(color: DSPalette.of(context).noticeBorder),
          borderRadius: BorderRadius.circular(DS.radiusSheet),
          boxShadow: widget.floating
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: '查看错误详情',
              style: IconButton.styleFrom(
                minimumSize: const Size.square(DS.touchTarget),
              ),
              onPressed: _showDetails,
              icon: DSIcon(
                'circle-alert',
                size: DS.navigationIcon,
                color: DSPalette.of(context).noticeAccent,
              ),
            ),
            const SizedBox(width: DS.space4),
            Expanded(
              child: Text(
                summary,
                style: DS.body.copyWith(color: DSPalette.of(context).ink),
              ),
            ),
            if (widget.floating)
              IconButton(
                tooltip: '关闭提示',
                onPressed: _dismiss,
                icon: DSIcon(
                  'x',
                  size: DS.chevronSize,
                  color: DSPalette.of(context).muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: child,
    ),
  );
}
