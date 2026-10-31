import '../domain/migration_models.dart';

abstract class LedgerMigrationRepository {
  Future<BackfillReport> backfill({String? statDate, bool dryRun = false});

  Future<ShadowVerifyResult> shadowVerify({required String statDate});

  Future<CutoverStatus> getStatus();

  Future<Map<String, dynamic>> cutover({required String targetSource});
}
