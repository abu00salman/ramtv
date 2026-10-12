/// Serializes native mutations and skips superseded queued requests.
class PlaybackQueue {
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  bool _closed = false;
  int invalidate() => ++_generation;
  bool isCurrent(int generation) => !_closed && generation == _generation;
  Future<void> run(int generation, Future<void> Function() operation) {
    final next = _tail.then((_) async {
      if (isCurrent(generation)) await operation();
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> close(Future<void> Function() dispose) {
    _closed = true;
    invalidate();
    return _tail.then((_) => dispose());
  }
}

Duration reconnectDelay(int attempt) =>
    Duration(seconds: 1 << (attempt.clamp(1, 6) - 1));
