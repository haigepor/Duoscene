import 'package:duoscene/core/performance_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'frame statistics retain long tails and do not label them dropped frames',
    () {
      final samples = [1, 2, 3, 16667, 16668, 100000];
      expect(frameStatistics(samples), {
        'count': 6,
        'p50Us': 3,
        'p95Us': 100000,
        'p99Us': 100000,
        'maxUs': 100000,
        'above16667Us': 2,
      });
      expect(samples.first, 1);
      expect(frameStatistics([]), {'count': 0});
    },
  );
}
