import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_service.dart';

/// Periodická kontrola outboxu/fotek a automatický sync (FE-06).
class SyncRetryScheduler {
  SyncRetryScheduler(this._syncService);

  final SyncService _syncService;
  Timer? _timer;
  bool _running = false;

  static const tickInterval = Duration(seconds: 15);

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(tickInterval, (_) => tick());
    tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> tick() async {
    if (_running) return;
    _running = true;
    try {
      await _syncService.syncAll(force: false);
    } finally {
      _running = false;
    }
  }

  void dispose() => stop();
}

final syncRetrySchedulerProvider = Provider<SyncRetryScheduler>((ref) {
  final scheduler = SyncRetryScheduler(ref.read(syncServiceProvider));
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
