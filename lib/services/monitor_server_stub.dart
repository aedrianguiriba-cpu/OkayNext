import 'monitor_client.dart';
export 'monitor_client.dart';

/// Browser build: the monitor server only exists in the desktop app.
class MonitorServer {
  MonitorServer._();
  static final MonitorServer instance = MonitorServer._();

  bool get running => false;
  bool enabled = false;
  String? error;
  int port = 8090;
  Stream<void> get changes => const Stream<void>.empty();
  List<MonitorClient> get clients => const [];

  Future<void> init() async {}
  Future<void> setEnabled(bool value) async {}
  Future<bool> start() async => false;
  Future<void> stop() async {}
}
