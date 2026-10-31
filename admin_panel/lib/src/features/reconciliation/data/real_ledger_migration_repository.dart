import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/migration_models.dart';
import 'ledger_migration_repository.dart';

class RealLedgerMigrationRepository implements LedgerMigrationRepository {
  const RealLedgerMigrationRepository(this.client);

  final AdminApiClient client;

  @override
  Future<BackfillReport> backfill({String? statDate, bool dryRun = false}) async {
    final body = <String, dynamic>{
      if (statDate != null && statDate.isNotEmpty) 'stat_date': statDate,
      'dry_run': dryRun,
    };
    final response = await client.post(
      migrationLedgerBackfillEndpoint,
      body: body,
    );
    final map = _map(response);
    return BackfillReport.fromJson(map);
  }

  @override
  Future<ShadowVerifyResult> shadowVerify({required String statDate}) async {
    final response = await client.get(
      migrationLedgerShadowVerifyEndpoint,
      query: {'stat_date': statDate},
    );
    final map = _map(response);
    return ShadowVerifyResult.fromJson(map);
  }

  @override
  Future<CutoverStatus> getStatus() async {
    final response = await client.get(migrationLedgerStatusEndpoint);
    final map = _map(response);
    return CutoverStatus.fromJson(map);
  }

  @override
  Future<Map<String, dynamic>> cutover({required String targetSource}) async {
    final response = await client.post(
      migrationLedgerCutoverEndpoint,
      body: {'read_source': targetSource},
    );
    return _map(response);
  }

  Map<String, dynamic> _map(dynamic response) {
    if (response is Map<String, dynamic>) {
      if (response['data'] is Map<String, dynamic>) {
        return Map<String, dynamic>.from(response['data'] as Map);
      }
      return response;
    }
    return <String, dynamic>{};
  }
}
