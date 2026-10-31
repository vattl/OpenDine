import 'takeout_dispatch_alert_source_base.dart';
import 'takeout_dispatch_alert_source_stub.dart'
    if (dart.library.io) 'takeout_dispatch_alert_source_io.dart'
    as platform;

export 'takeout_dispatch_alert_source_base.dart';

TakeoutDispatchAlertSource createTakeoutDispatchAlertSource(String baseUrl) =>
    platform.createTakeoutDispatchAlertSource(baseUrl);
