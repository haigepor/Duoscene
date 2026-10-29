import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/posters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const remoteFilm = Film(
  'whisklet:42',
  'Decode sample',
  '电影',
  '',
  0,
  posterUrl: 'https://example.com/poster.jpg?version=2',
);

Future<ResizeImage> artwork(
  WidgetTester t,
  double width,
  double dpr, {
  int? explicit,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(devicePixelRatio: dpr),
        child: Center(
          child: SizedBox(
            width: width,
            height: width / .66,
            child: FilmArtwork(remoteFilm, cacheWidth: explicit),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return t.widget<Image>(find.byType(Image)).image as ResizeImage;
}

void main() {
  for (final sample in [
    (64.0, 1.0, 64),
    (96.0, 2.0, 192),
    (108.0, 3.0, 324),
    (240.0, 3.0, 480),
  ]) {
    testWidgets(
      'remote artwork decodes layout ${sample.$1} at DPR ${sample.$2}',
      (t) async {
        final resized = await artwork(t, sample.$1, sample.$2);
        expect(resized.width, sample.$3);
        expect(resized.height, isNull);
        expect(resized.allowUpscaling, isFalse);
        expect(
          (resized.imageProvider as NetworkImage).url,
          remoteFilm.posterUrl,
        );
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('explicit decode hint retains its existing contract', (t) async {
    expect((await artwork(t, 64, 3, explicit: 192)).width, 192);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('layout changes produce a matching decode cache key', (t) async {
    final original = await artwork(t, 108, 3);
    final same = await artwork(t, 108, 3);
    final smaller = await artwork(t, 54, 3);
    expect(
      await original.obtainKey(ImageConfiguration.empty),
      await same.obtainKey(ImageConfiguration.empty),
    );
    expect(
      await smaller.obtainKey(ImageConfiguration.empty),
      isNot(await original.obtainKey(ImageConfiguration.empty)),
    );
    expect(smaller.width, 162);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('unbounded artwork keeps a finite decode fallback', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: FilmArtwork(remoteFilm, height: 90),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      (t.widget<Image>(find.byType(Image)).image as ResizeImage).width,
      480,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
