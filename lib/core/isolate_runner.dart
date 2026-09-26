import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;

import 'errors.dart';

/// Task contract: receives a [PfJobContext], reports progress, checks
/// [PfJobContext.isCancelled] between steps, returns a sendable result.
typedef PfTask<R> = Future<R> Function(PfJobContext ctx);

final class PfJobContext {
  PfJobContext(this._progressPort, ReceivePort cancelPort) {
    cancelPort.listen((message) {
      if (message == 'cancel') _cancelled = true;
    });
  }

  final SendPort _progressPort;
  bool _cancelled = false;

  /// Cooperative cancellation flag — long jobs check between steps and
  /// return promptly when true. The caller sweeps any leftover temps.
  bool get isCancelled => _cancelled;

  /// Report progress (0.0 → 1.0) with an optional label.
  void report(double fraction, [String? label]) {
    _progressPort.send(_Progress(fraction, label));
  }
}

sealed class JobEvent<R> {
  const JobEvent();
}

final class JobProgress<R> extends JobEvent<R> {
  const JobProgress(this.fraction, this.label);
  final double fraction;
  final String? label;
}

final class JobDone<R> extends JobEvent<R> {
  const JobDone(this.result);
  final R result;
}

final class JobFailed<R> extends JobEvent<R> {
  const JobFailed(this.error);
  final PureError error;
}

/// Handle for a running job: event stream, completion future, cancel.
final class JobHandle<R> {
  JobHandle._(this.events, this.future, this._kill);

  final Stream<JobEvent<R>> events;
  final Future<R> future;
  final void Function() _kill;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _kill();
  }

  bool get isCancelled => _cancelled;
}

final class _Msg {
  _Msg(this.progressPort, this.task, this.isolateToken);
  final SendPort progressPort;
  final PfTask<dynamic> task;

  /// Platform-channel token so tasks may use plugins (pdfx rendering) inside
  /// the job isolate. Null in environments without a token (unit tests).
  final RootIsolateToken? isolateToken;
}

final class _Progress {
  _Progress(this.fraction, this.label);
  final double fraction;
  final String? label;
}

final class _Done {
  _Done(this.result);
  final Object result;
}

/// Runs [task] inside its own isolate with progress, cooperative cancel and a
/// hard timeout. A native crash or infinite loop in the task can never freeze
/// the app — the isolate is killed and a typed error is surfaced.
JobHandle<R> runJob<R>({
  required PfTask<R> task,
  Duration timeout = const Duration(minutes: 5),
}) {
  final controller = StreamController<JobEvent<R>>.broadcast();
  final completer = Completer<R>();
  late final JobHandle<R> handle;
  Isolate? isolate;
  Timer? timeoutTimer;
  ReceivePort? cancelPort;
  ReceivePort? progressPort;

  void fail(PureError error) {
    if (!completer.isCompleted) {
      completer.completeError(error);
      if (!controller.isClosed) controller.add(JobFailed<R>(error));
    }
    if (!controller.isClosed) controller.close();
    timeoutTimer?.cancel();
    cancelPort?.close();
    progressPort?.close();
  }

  void kill() {
    isolate?.kill(priority: Isolate.immediate);
    fail(const JobCancelled());
  }

  handle = JobHandle<R>._(controller.stream, completer.future, kill);

  void complete(Object result) {
    if (!completer.isCompleted) {
      completer.complete(result as R);
      if (!controller.isClosed) controller.add(JobDone<R>(result as R));
      if (!controller.isClosed) controller.close();
    }
    timeoutTimer?.cancel();
    cancelPort?.close();
    progressPort?.close();
  }

  final port = ReceivePort();
  progressPort = port;
  port.listen((message) {
    switch (message) {
      case _Progress(:final fraction, :final label):
        controller.add(JobProgress<R>(fraction, label));
      case _Done(:final result):
        complete(result);
      case final PureError error:
        fail(error);
      case final SendPort workerCancel:
        // First message from the worker: its cancel-signal port.
        final cp = ReceivePort();
        cp.listen((m) {
          if (m == 'cancel') {
            // Grace period for the worker to observe the flag and clean up;
            // then a hard kill guarantees the app can never hang on a job.
            Future.delayed(const Duration(milliseconds: 500), kill);
          }
        });
        cancelPort = cp;
        workerCancel.send(cp.sendPort);
      case _:
        fail(const UnknownFailure('Unknown job message'));
    }
  });

  Isolate.spawn<_Msg>(
    _entry,
    _Msg(port.sendPort, task as PfTask<dynamic>, RootIsolateToken.instance),
  ).then((spawned) {
    isolate = spawned;
    timeoutTimer = Timer(timeout, () {
      spawned.kill(priority: Isolate.immediate);
      fail(const JobTimedOut());
    });
  }).catchError((Object e) {
    fail(e is PureError ? e : UnknownFailure(e.toString()));
  });

  return handle;
}

Future<void> _entry(_Msg msg) async {
  // Platform channels (pdfx page rendering etc.) work in this isolate only
  // after the host isolate's token is registered here.
  final token = msg.isolateToken;
  if (token != null) BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final cancelReceive = ReceivePort();
  msg.progressPort.send(cancelReceive.sendPort);
  final ctx = PfJobContext(msg.progressPort, cancelReceive);
  try {
    final result = await msg.task(ctx);
    msg.progressPort.send(_Done(result as Object));
  } on PureError catch (e) {
    msg.progressPort.send(e);
  } catch (e) {
    msg.progressPort.send(UnknownFailure(e.toString()));
  }
}
