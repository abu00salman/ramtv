import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ramtv/playback_queue.dart';

void main() {
  test('rapid channel switches skip superseded work and serialize opens',
      () async {
    final queue = PlaybackQueue();
    final gate = Completer<void>();
    final calls = <String>[];
    final first = queue.run(queue.invalidate(), () async {
      calls.add('first');
      await gate.future;
    });
    await Future<void>.delayed(Duration.zero);
    final second =
        queue.run(queue.invalidate(), () async => calls.add('second'));
    final third = queue.run(queue.invalidate(), () async => calls.add('third'));
    gate.complete();
    await Future.wait([first, second, third]);
    expect(calls, ['first', 'third']);
  });

  test('failure does not prevent the next channel from opening', () async {
    final queue = PlaybackQueue();
    await expectLater(
      queue.run(queue.invalidate(), () async => throw StateError('offline')),
      throwsStateError,
    );
    var opened = false;
    await queue.run(queue.invalidate(), () async => opened = true);
    expect(opened, isTrue);
  });

  test('disposal waits for active work and invalidates queued requests',
      () async {
    final queue = PlaybackQueue();
    final gate = Completer<void>();
    final calls = <String>[];
    final active = queue.run(queue.invalidate(), () => gate.future);
    await Future<void>.delayed(Duration.zero);
    final pending =
        queue.run(queue.invalidate(), () async => calls.add('open'));
    final close = queue.close(() async => calls.add('dispose'));
    gate.complete();
    await Future.wait([active, pending, close]);
    expect(calls, ['dispose']);
  });

  test('reconnect delay doubles and remains bounded', () {
    expect(List.generate(6, (i) => reconnectDelay(i + 1).inSeconds),
        [1, 2, 4, 8, 16, 32]);
    expect(reconnectDelay(100), const Duration(seconds: 32));
  });
}
