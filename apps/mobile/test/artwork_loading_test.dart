import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/posters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const film = Film(
  'whisklet:42',
  'Image',
  '电影',
  '',
  0,
  posterUrl: 'https://example.com/poster.jpg',
);

Future<Image> mount(WidgetTester t, {Film value = film}) async {
  await t.pumpWidget(
    MaterialApp(
      home: Center(child: FilmArtwork(value, width: 108, height: 140)),
    ),
  );
  await t.pumpAndSettle();
  return t.widget<Image>(find.byType(Image));
}

void main() {
  testWidgets(
    'first frame uses a static loading placeholder then shows the image',
    (t) async {
      final image = await mount(t), context = t.element(find.byType(Image));
      expect(image.frameBuilder, isNotNull);
      const child = SizedBox();
      expect(
        image.frameBuilder!(context, child, null, false).key,
        const Key('artwork-loading'),
      );
      expect(
        identical(image.frameBuilder!(context, child, 0, false), child),
        isTrue,
      );
      expect(
        identical(image.frameBuilder!(context, child, null, true), child),
        isTrue,
      );
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('temporary errors retry once and then expose manual recovery', (
    t,
  ) async {
    var image = await mount(t);
    final error = NetworkImageLoadException(
      statusCode: 503,
      uri: Uri.parse(film.posterUrl!),
    );
    final waiting = image.errorBuilder!(
      t.element(find.byType(Image)),
      error,
      null,
    );
    expect(waiting.key, const Key('artwork-loading'));
    await t.pump(const Duration(milliseconds: 600));
    await t.pumpAndSettle();
    image = t.widget<Image>(find.byType(Image));
    expect(image.key, const ValueKey(1));
    expect(
      image.errorBuilder!(t.element(find.byType(Image)), error, null).key,
      const Key('artwork-failed'),
    );
    await t.pump(const Duration(seconds: 2));
    expect(t.widget<Image>(find.byType(Image)).key, const ValueKey(1));
    await t.tap(find.byTooltip('重试封面'));
    await t.pumpAndSettle();
    expect(t.widget<Image>(find.byType(Image)).key, const ValueKey(2));
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'permanent HTTP errors fail visibly without automatic request loops',
    (t) async {
      final image = await mount(t), context = t.element(find.byType(Image));
      final error = NetworkImageLoadException(
        statusCode: 404,
        uri: Uri.parse(film.posterUrl!),
      );
      expect(
        image.errorBuilder!(context, error, null).key,
        const Key('artwork-failed'),
      );
      await t.pump(const Duration(seconds: 2));
      expect(t.widget<Image>(find.byType(Image)).key, const ValueKey(0));
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('a pending retry cannot reopen a replaced or disposed cover', (
    t,
  ) async {
    final image = await mount(t);
    image.errorBuilder!(
      t.element(find.byType(Image)),
      StateError('temporary'),
      null,
    );
    await mount(
      t,
      value: const Film(
        'whisklet:43',
        'Other',
        '电影',
        '',
        0,
        posterUrl: 'https://example.com/other.jpg',
      ),
    );
    await t.pump(const Duration(seconds: 1));
    expect(t.widget<Image>(find.byType(Image)).key, const ValueKey(0));
    final next = t.widget<Image>(find.byType(Image));
    next.errorBuilder!(
      t.element(find.byType(Image)),
      StateError('temporary'),
      null,
    );
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
  });
}
