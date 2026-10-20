import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import 'catalog.dart';

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
  });
  final Film film;
  final VoidCallback? onTap, onSelect;
  final bool? selected;
  final bool showTitle, showMetadata;
  final double aspectRatio;
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
                child: Image.asset(
                  film.image,
                  fit: BoxFit.cover,
                  cacheWidth: 480,
                ),
              ),
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
        if (showTitle || showMetadata) const SizedBox(height: 6),
        if (showTitle)
          Text(film.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (showMetadata) ...[
          const SizedBox(height: 3),
          Text(film.meta, style: DS.smallFor(context), maxLines: 2),
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
      Image.asset(
        film.id == 'mountains'
            ? '${DS.media}media-mountains-landscape.png'
            : film.image,
        fit: BoxFit.cover,
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
        // 仅淡出照片与遮罩，让底层森林透出；标题和按钮保持清晰可点击。
        if (blendBackground && DSPalette.of(context).forest)
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, .58, .82, 1],
              colors: [
                Colors.white,
                Colors.white,
                Color(0xAAFFFFFF),
                Colors.transparent,
              ],
            ).createShader(bounds),
            child: _backdrop(context),
          )
        else
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
                    '${film.genre} · 2026 · ${film.meta}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
        ),
      ],
    ),
  );
}
