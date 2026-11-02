import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/dashboard_report.dart';

class ReportRepository {
  const ReportRepository(this.client);

  final AdminApiClient client;

  Future<DashboardReport> loadDashboard({required int shopId}) async {
    final data = await client.copyWith(shopId: shopId).get(dashboardEndpoint);
    final map = data is Map
        ? data.cast<String, Object?>()
        : <String, Object?>{};
    return DashboardReport.fromJson(map);
  }
}
