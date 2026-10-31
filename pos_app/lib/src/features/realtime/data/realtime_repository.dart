import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';

class RealtimeRepository {
  const RealtimeRepository(this.client);

  final AdminApiClient client;

  Future<Map<String, Object?>> loadKdsConfig({required int shopId}) async {
    final data = await client.copyWith(shopId: shopId).get(kdsConfigEndpoint);
    return data is Map ? data.cast<String, Object?>() : <String, Object?>{};
  }

  Future<Map<String, Object?>> saveKdsConfig({
    required int shopId,
    required Map<String, Object?> config,
  }) async {
    final data = await client
        .copyWith(shopId: shopId)
        .post(kdsConfigSaveEndpoint, body: config);
    return data is Map ? data.cast<String, Object?>() : <String, Object?>{};
  }

  Future<List<Map<String, Object?>>> loadTakeoutDeliveries({
    required int shopId,
  }) async {
    final data = await client
        .copyWith(shopId: shopId)
        .get(
          takeoutDeliveryListEndpoint,
          query: {'pageNum': 1, 'pageSize': 20},
        );
    return objectList(data);
  }
}
