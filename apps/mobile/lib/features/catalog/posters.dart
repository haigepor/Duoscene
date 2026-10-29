import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/window_layout.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import 'catalog.dart';
import 'artwork_request.dart';
import 'artwork_image.dart';

class FilmArtwork extends StatefulWidget {
  const FilmArtwork(
    this.film, {
    super.key,
    this.asset,
    this.width,
    this.height,
    this.cacheWidth,
    this.excludeFromSemantics = false,
  });
  final Film film;
  final String? asset;
  final double? width, height;
  final int? cacheWidth;
  final bool excludeFromSemantics;
  @override
  State<FilmArtwork> createState() => _FilmArtworkState();
}

class _FilmArtworkState extends State<FilmArtwork> {
  int retryGeneration = 0;
  int automaticRetries = 0;
  Timer? retryTimer;

  @override
  void didUpdateWidget(covariant FilmArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.film.posterUrl != widget.film.posterUrl ||
        oldWidget.film.id != widget.film.id) {
      retryTimer?.cancel();
      retryTimer = null;
      automaticRetries = retryGeneration = 0;
    }
  }

  @override
  void dispose() {
    retryTimer?.cancel();
    super.dispose();
  }

  Future<void> retry(ImageProvider provider, String? url) async {
    final generation = retryGeneration;
    final filmId = widget.film.id;
    await provider.evict();
    if (mounted &&
        widget.film.posterUrl == url &&
        widget.film.id == filmId &&
        generation == retryGeneration)
      setState(() => retryGeneration++);
  }

  bool scheduleRetry(ImageProvider provider, Film film, Object error) {
    // 瞬时连接/服务端/解码失败只自动重试一次；永久 4xx 不反复请求。
    if (error is NetworkImageLoadException &&
        error.statusCode >= 400 &&
        error.statusCode < 500 &&
        error.statusCode != 408 &&
        error.statusCode != 429)
      return false;
    if (automaticRetries != 0) return retryTimer != null;
    automaticRetries++;
    retryTimer = Timer(const Duration(milliseconds: 400), () {
      retryTimer = null;
      if (mounted &&
          widget.film.id == film.id &&
          widget.film.posterUrl == film.posterUrl) {
        unawaited(retry(provider, film.posterUrl));
      }
    });
    return true;
  }

  Widget placeholder(
    BuildContext context,
    String label, {
    bool loading = false,
    VoidCallback? onRetry,
  }) {
    final palette = DSPalette.of(context);
    return SizedBox(
      key: Key(loading ? 'artwork-loading' : 'artwork-failed'),
      width: widget.width,
      height: widget.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.panel, palette.tint.withValues(alpha: .32)],
          ),
        ),
        child: ExcludeSemantics(
          excluding: widget.excludeFromSemantics,
          child: Semantics(
            label: loading ? '封面加载中' : label,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onRetry != null)
                      IconButton(
                        tooltip: '重试封面',
                        onPressed: onRetry,
                        icon: Icon(Icons.refresh_rounded, color: palette.muted),
                      )
                    else
                      Icon(
                        loading
                            ? Icons.image_outlined
                            : Icons.hide_image_outlined,
                        size: 24,
                        color: palette.muted.withValues(alpha: .5),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(fontSize: 10, color: palette.muted),
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

  @override
  Widget build(BuildContext context) {
    final film = widget.film;
    final width = widget.width, height = widget.height;
    final cacheWidth = widget.cacheWidth;
    final excludeFromSemantics = widget.excludeFromSemantics;
    ImageProvider? recovery;
    Widget fallback(BuildContext context, Object error, StackTrace? stack) {
      if (recovery == null) return placeholder(context, '暂无封面');
      if (scheduleRetry(recovery!, film, error)) {
        return placeholder(context, '加载封面', loading: true);
      }
      return placeholder(
        context,
        '点按重试',
        onRetry: () => unawaited(retry(recovery!, film.posterUrl)),
      );
    }

    if (film.remote) {
      final request = ArtworkRequest.parse(film.posterUrl);
      if (request == null)
        return fallback(context, StateError('No poster'), null);
      return LayoutBuilder(
        builder: (context, constraints) {
          final logicalWidth =
              width ??
              (constraints.hasBoundedWidth ? constraints.maxWidth : null);
          // 对齐 Playra：按布局与 DPR 解码，单轴保持原图比例；沿用原 480px 上限。
          // 显式尺寸提示继续优先，宽度无界时保留原来的有限回退。
          final decodeWidth =
              cacheWidth ??
              (logicalWidth != null && logicalWidth.isFinite && logicalWidth > 0
                  ? (logicalWidth * MediaQuery.devicePixelRatioOf(context))
                        .ceil()
                        .clamp(1, 480)
                  : 480);
          recovery = ResizeImage.resizeIfNeeded(
            decodeWidth,
            null,
            request.headers.isNotEmpty
                ? ArtworkImage(request)
                : NetworkImage(
                    request.uri.toString(),
                    headers: request.headers,
                  ),
          );
          return Image(
            key: ValueKey(retryGeneration),
            image: recovery!,
            width: width,
            height: height,
            fit: BoxFit.cover,
            // 静态占位不为每张卡片启动脉冲或离屏淡入层；首帧到达即显示。
            frameBuilder: (context, child, frame, synchronous) =>
                frame != null || synchronous
                ? child
                : placeholder(context, '加载封面', loading: true),
            errorBuilder: fallback,
            excludeFromSemantics: excludeFromSemantics,
          );
        },
      );
    }
    return Image.asset(
      widget.asset ?? film.image,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      fit: BoxFit.cover,
      errorBuilder: fallback,
      excludeFromSemantics: excludeFromSemantics,
    );
  }
}

/// 只使用确认稿的插画裁片；片名、徽标和操作由组件绘制。
String homeArtwork(Film film, {bool landscape = false}) => switch (film.id) {
  'mountains' =>
    '${DS.media}home-v2-${landscape ? 'valley' : 'mountains'}.webp',
  'summer' => '${DS.media}home-v2-summer.webp',
  'stars' => '${DS.media}home-v2-stars.webp',
  'river' => '${DS.media}home-v2-river.webp',
  _ => film.image,
};

String homeMetadata(Film film) => film.remote
    ? film.meta
    : '${film.genre} · ${film.episodes == 1 ? '${film.minutes} 分钟' : '${film.episodes} 集'}';

class FilmPoster extends StatelessWidget {
  const FilmPoster(
    this.film, {
    super.key,
    this.onTap,
    this.selected,
    this.onSelect,
    this.showTitle = true,
    this.showMetadata = true,
    this.aspectRatio = .66,
    this.editorial = false,
  });
  final Film film;
  final VoidCallback? onTap, onSelect;
  final bool? selected;
  final bool showTitle, showMetadata;
  final double aspectRatio;
  final bool editorial;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onSelect ?? onTap,
    borderRadius: BorderRadius.circular(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: FilmArtwork(
                  film,
                  asset: editorial ? homeArtwork(film) : film.image,
                  cacheWidth: film.remote ? null : 480,
                ),
              ),
              if (!editorial)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(4, 30, 4, 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xDD06100F)],
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        film.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: DS.posterTitleSize,
                          fontFamily: 'DuosceneDisplay',
                          color: DSPalette.onMedia,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              if (selected != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: selected!
                          ? DSPalette.of(context).primary
                          : DSPalette.of(context).bg,
                      shape: BoxShape.circle,
                    ),
                    child: DSIcon(
                      selected! ? 'check' : 'bookmark',
                      size: 19,
                      color: selected!
                          ? DSPalette.of(context).bg
                          : DSPalette.of(context).ink,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (showTitle || showMetadata) SizedBox(height: editorial ? 8 : 6),
        if (showTitle)
          Text(
            film.title,
            style: editorial
                ? TextStyle(
                    fontSize: WindowLayout.isWide(context) ? 14 : 12,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  )
                : null,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (showMetadata) ...[
          SizedBox(height: editorial ? 4 : 3),
          Text(
            editorial ? homeMetadata(film) : film.meta,
            style: DS
                .smallFor(context)
                .copyWith(
                  fontSize: editorial
                      ? WindowLayout.isWide(context)
                            ? 12
                            : 10
                      : null,
                ),
            maxLines: editorial ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    ),
  );
}

class FilmHero extends StatelessWidget {
  const FilmHero(
    this.film, {
    super.key,
    this.height = 300,
    this.child,
    this.blendBackground = false,
  });
  final Film film;
  final double height;
  final Widget? child;
  final bool blendBackground;
  Widget _backdrop(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      FilmArtwork(
        film,
        asset: film.id == 'mountains'
            ? '${DS.media}media-mountains-landscape.png'
            : film.image,
        cacheWidth:
            (MediaQuery.sizeOf(context).width *
                    MediaQuery.devicePixelRatioOf(context))
                .ceil()
                .clamp(480, 1080),
      ),
      const DecoratedBox(
        decoration: const BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, .45, 1],
            colors: [
              const Color(0x180B1617),
              const Color(0x000B1617),
              DSPalette.media,
            ],
          ),
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      fit: StackFit.expand,
      children: [
        _backdrop(context),
        Positioned(
          left: 20,
          right: 20,
          bottom: 18,
          child:
              child ??
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    film.title,
                    style: const TextStyle(
                      color: DSPalette.onMedia,
                      fontSize: 28,
                      fontFamily: 'DuosceneDisplay',
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    film.remote
                        ? film.meta
                        : '${film.genre} · 2026 · ${film.meta}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
        ),
      ],
    ),
  );
}
