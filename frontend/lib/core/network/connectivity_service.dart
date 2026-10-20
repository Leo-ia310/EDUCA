import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityProvider = StreamProvider<bool>((ref) {
  final connectivity=Connectivity();
  final controller=StreamController<bool>();
  var disposed=false,receivedEvent=false;
  void emit(List<ConnectivityResult> results) {
    if(!disposed) controller.add(results.any((result)=>result!=ConnectivityResult.none));
  }
  // Subscribe before taking the initial snapshot, so a change during startup
  // is not lost or overwritten by a stale check result.
  final subscription=connectivity.onConnectivityChanged.listen((results) {
    receivedEvent=true;emit(results);
  },onError:(Object error,StackTrace stack) {
    if(!disposed)controller.addError(error,stack);
  },);
  unawaited(() async {
    try { final initial=await connectivity.checkConnectivity();if(!receivedEvent)emit(initial); }
    catch(error,stack) { if(!disposed && !receivedEvent)controller.addError(error,stack); }
  }());
  ref.onDispose(() {disposed=true;unawaited(subscription.cancel());unawaited(controller.close());});
  return controller.stream.distinct();
});
