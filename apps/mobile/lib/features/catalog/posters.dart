import 'package:flutter/material.dart';

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
  Future<void> retry(ImageProvider provider, String? url) async {
    await provider.evict();
    if (mounted && widget.film.posterUrl == url)
      setState(() => retryGeneration++);
  }

  @override
  Widget build(BuildContext context) {
    final film = widget.film;
    final width = widget.width, height = widget.height;
    final cacheWidth = widget.cacheWidth;
    final excludeFromSemantics = widget.excludeFromSemantics;
    ImageProvider? recovery;
    Widget fallback(BuildContext context, Object error, StackTrace? stack) =>
        SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: DSPalette.of(context).panel,
            child: Center(
              child: recovery == null
                  ? const Icon(Icons.movie_outlined)
                  : IconButton(
                      tooltip: '重试封面',
                      onPressed: () => retry(recovery!, film.posterUrl),
                      icon: const Icon(Icons.movie_outlined),
                    ),
            ),
          ),
        );
    if (film.remote) {
      final request = ArtworkRequest.parse(film.posterUrl);
      if (request == null)
        return fallback(context, StateError('No poster'), null);
      recovery = ResizeImage.resizeIfNeeded(
        cacheWidth ?? 480,
        null,
        request.headers.isNotEmpty
            ? ArtworkImage(request)
            : NetworkImage(request.uri.toString(), headers: request.headers),
      );
      return Image(
        key: ValueKey(retryGeneration),
        image: recovery,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: fallback,
        excludeFromSemantics: excludeFromSemantics,
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
                  cacheWidth: 480,
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
                ? const TextStyle(
                    fontSize: 12,
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
                .copyWith(fontSize: editorial ? 10 : null),
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
                      fontSize: DS.posterTitleSize,
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
