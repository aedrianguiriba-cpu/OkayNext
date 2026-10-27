// Desktop: real network lookups. Web: stubs (a browser can't and needn't).
export 'lan_address.dart';
export 'lan_info_stub.dart' if (dart.library.io) 'lan_info_io.dart';
