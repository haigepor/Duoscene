import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'catalog.dart';
import 'posters.dart';

/// 片源只提供竖版海报时，将海报和信息并排，避免用超宽 cover 裁去主体。
class TabletFeatureCard extends StatelessWidget {
  const TabletFeatureCard({
    super.key,
    required this.film,
    required this.onDetail,
    required this.onPlay,
  });
  final Film film;
  final VoidCallback onDetail, onPlay;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Material(
        key: const Key('tablet-feature-card'),
        color: DSPalette.of(context).panel,
        borderRadius: BorderRadius.circular(DS.panelRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onDetail,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AspectRatio(
                  key: const Key('tablet-feature-cover'),
                  aspectRatio: .75,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(DS.radiusSmall),
                    child: FilmArtwork(
                      film,
                      asset: film.image,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('精选', style: DS.smallFor(context)),
                      const SizedBox(height: 8),
                      Text(
                        film.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DS.section,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        homeMetadata(film),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DS.smallFor(context),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: onPlay,
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('选择视频'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
