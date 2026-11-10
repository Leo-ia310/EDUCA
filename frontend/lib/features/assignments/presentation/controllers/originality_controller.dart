import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/backend_api_client.dart';
import '../../data/originality_api.dart';
import '../../data/originality_report.dart';
import '../../data/originality_summary.dart';

final originalityApiProvider = Provider<OriginalityApi?>((ref) {
  final api = ref.watch(backendApiClientProvider);
  return api == null ? null : OriginalityApi(api);
});

// ---------------------------------------------------------------------------
// Resumen por actividad
// ---------------------------------------------------------------------------

/// Resumen de la actividad. Mientras haya análisis en cola/proceso se vuelve a
/// consultar con espera creciente (10 → 20 → 40 → 60 s); no usa Realtime.
class OriginalitySummaryController
    extends StateNotifier<AsyncValue<OriginalitySummary>> {
  OriginalitySummaryController(this._api, this._assignmentId)
      : super(const AsyncLoading()) {
    unawaited(load());
  }

  final OriginalityApi? _api;
  final String _assignmentId;
  Timer? _timer;
  bool _busy = false;
  int _delay = 10;

  Future<void> load() async {
    if (_busy) return;
    _timer?.cancel();
    final api = _api;
    if (api == null) {
      state =
          AsyncError(StateError('Sesión no disponible'), StackTrace.current);
      return;
    }
    _busy = true;
    try {
      final summary = await api.summary(_assignmentId);
      if (!mounted) return;
      state = AsyncData(summary);
      if (summary.working) {
        _timer = Timer(Duration(seconds: _delay), () => unawaited(load()));
        _delay = math.min(_delay * 2, 60);
      } else {
        _delay = 10;
      }
    } catch (e, st) {
      if (mounted) state = AsyncError(e, st);
    } finally {
      _busy = false;
    }
  }

  /// Vuelve a empezar con espera corta (tras guardar la plantilla o reintentar).
  Future<void> refresh() {
    _delay = 10;
    return load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final originalitySummaryProvider = StateNotifierProvider.autoDispose.family<
    OriginalitySummaryController, AsyncValue<OriginalitySummary>, String>(
  (ref, assignmentId) => OriginalitySummaryController(
    ref.watch(originalityApiProvider),
    assignmentId,
  ),
);

// ---------------------------------------------------------------------------
// Reporte de una entrega
// ---------------------------------------------------------------------------

class OriginalityReportState {
  const OriginalityReportState({
    this.report,
    this.busy = true,
    this.failed = false,
    this.denied = false,
    this.evidence = false,
  });
  final OriginalityReport? report;
  final bool busy;
  final bool failed;

  /// 401/403/404: se descarta la evidencia en memoria.
  final bool denied;

  /// El docente pidió ver fragmentos: las siguientes lecturas los incluyen.
  final bool evidence;

  OriginalityReportState copyWith({
    OriginalityReport? report,
    bool clearReport = false,
    bool? busy,
    bool? failed,
    bool? denied,
    bool? evidence,
  }) =>
      OriginalityReportState(
        report: clearReport ? null : report ?? this.report,
        busy: busy ?? this.busy,
        failed: failed ?? this.failed,
        denied: denied ?? this.denied,
        evidence: evidence ?? this.evidence,
      );
}

typedef OriginalityReportArgs = ({String assignmentId, String submissionId});

/// Reporte bajo demanda de una entrega. Sondea (5 → 60 s) solo mientras la
/// pantalla está abierta y el análisis sigue en curso. La evidencia solo se
/// pide cuando el docente la solicita.
class OriginalityReportController
    extends StateNotifier<OriginalityReportState> {
  OriginalityReportController(this._api, this._submissionId, this._onChanged)
      : super(const OriginalityReportState()) {
    unawaited(load());
  }

  final OriginalityApi? _api;
  final String _submissionId;
  final void Function() _onChanged;
  Timer? _timer;
  int _delay = 5;

  Future<void> load({bool retry = false}) async {
    final api = _api;
    if (api == null) {
      state = state.copyWith(busy: false, failed: true);
      return;
    }
    _timer?.cancel();
    state = state.copyWith(busy: true);
    try {
      final report = retry
          ? await api.retry(_submissionId)
          : await api.report(_submissionId, evidence: state.evidence);
      if (!mounted) return;
      final withEvidence = retry && state.evidence
          ? await api.report(_submissionId, evidence: true)
          : report;
      if (!mounted) return;
      state = state.copyWith(
        report: withEvidence,
        failed: false,
        denied: false,
      );
      if (retry) _onChanged();
    } catch (error) {
      if (!mounted) return;
      final denied = error is BackendApiException &&
          const [401, 403, 404].contains(error.statusCode);
      state = state.copyWith(
        failed: true,
        denied: denied,
        clearReport: denied,
        evidence: denied ? false : null,
      );
    } finally {
      if (mounted) {
        state = state.copyWith(busy: false);
        if (state.report?.working ?? false) {
          _timer = Timer(Duration(seconds: _delay), () => unawaited(load()));
          _delay = math.min(_delay * 2, 60);
        }
      }
    }
  }

  Future<void> showEvidence() {
    if (state.evidence) return Future.value();
    state = state.copyWith(evidence: true);
    return load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final originalityReportProvider = StateNotifierProvider.autoDispose.family<
    OriginalityReportController, OriginalityReportState, OriginalityReportArgs>(
  (ref, args) => OriginalityReportController(
    ref.watch(originalityApiProvider),
    args.submissionId,
    () => unawaited(
      ref
          .read(originalitySummaryProvider(args.assignmentId).notifier)
          .refresh(),
    ),
  ),
);

// ---------------------------------------------------------------------------
// Plantilla
// ---------------------------------------------------------------------------

final originalityTemplateProvider = FutureProvider.autoDispose
    .family<OriginalityTemplate, String>((ref, assignmentId) async {
  final api = ref.watch(originalityApiProvider);
  if (api == null) throw StateError('Sesión no disponible');
  return api.template(assignmentId);
});
