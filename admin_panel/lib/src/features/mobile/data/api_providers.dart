import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/http_transport.dart';
import '../../orders/data/order_repository.dart';
import '../../orders/data/real_order_repository.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/data/real_pos_repository.dart';
import '../../reports/data/report_repository.dart';
import '../../tables/data/real_table_repository.dart';
import '../../tables/data/table_repository.dart';
import 'announcement_repository.dart';
import 'app_version_repository.dart';
import 'auth_state.dart';
import 'cart_storage.dart';
import 'dashboard_repository.dart';
import 'pending_order_worker.dart';
import 'push_service.dart';

final httpTransportProvider = Provider<HttpTransport>(
  (ref) => createHttpTransport(),
);

final apiClientProvider = Provider<AdminApiClient>((ref) {
  final auth = ref.watch(authProvider);
  return AdminApiClient(
    baseUrl: auth.baseUrl,
    transport: ref.watch(httpTransportProvider),
    token: auth.token,
    shopId: auth.currentShopId,
  );
});

final tableRepositoryProvider = Provider<TableRepository>(
  (ref) => RealTableRepository(ref.watch(apiClientProvider)),
);

final posRepositoryProvider = Provider<PosRepository>(
  (ref) => RealPosRepository(ref.watch(apiClientProvider)),
);

final posBalanceCheckoutProvider = Provider<PosBalanceCheckoutRepository>(
  (ref) => RealPosRepository(ref.watch(apiClientProvider)),
);

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => RealOrderRepository(ref.watch(apiClientProvider)),
);

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(apiClientProvider)),
);

final dashboardRepositoryProvider = Provider<MobileDashboardRepository>(
  (ref) => MobileDashboardRepository(ref.watch(apiClientProvider)),
);

final announcementRepositoryProvider = Provider<AnnouncementRepository>((ref) {
  if (kUseMockAnnouncement) return const MockAnnouncementRepository();
  return RealAnnouncementRepository(ref.watch(apiClientProvider));
});

final pushServiceProvider = Provider<PushService>((ref) {
  if (kUseMockPush) return const MockPushService();
  final isIos = defaultTargetPlatform == TargetPlatform.iOS;
  final service = RealPushService(
    platform: isIos ? 'ios' : 'android',
    channel: isIos ? 'apns' : 'fcm',
  );
  // 每次重建时绑定最新 client（含当前 token + 选店后的 X-Shop-Id）。
  service.bindClient(ref.watch(apiClientProvider));
  return service;
});

final appVersionRepositoryProvider = Provider<AppVersionRepository>(
  (ref) => AppVersionRepository(ref.watch(apiClientProvider)),
);

final cartStorageProvider = Provider<CartStorage>((ref) => CartStorage());

final pendingOrderWorkerProvider = Provider<PendingOrderWorker>((ref) {
  final worker = PendingOrderWorker(ref.watch(cartStorageProvider));
  ref.onDispose(worker.stop);
  return worker;
});
