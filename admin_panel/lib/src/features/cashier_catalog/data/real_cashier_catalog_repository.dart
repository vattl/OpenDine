import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../../core/cashier_operation_audit.dart';
import '../domain/cashier_dish.dart';
import '../domain/combo_definition_models.dart';
import 'cashier_catalog_repository.dart';

class RealCashierCatalogRepository
    implements CashierCatalogRepository, CashierCatalogSortingRepository {
  const RealCashierCatalogRepository(this.client);

  final AdminApiClient client;

  @override
  Future<void> addCategory({required String name, required int sorting}) async {
    await client.post(
      categoryAddEndpoint,
      body: {'label': name.trim(), 'sorting': sorting},
    );
  }

  @override
  Future<void> deleteCategory(int id) async {
    await client.get(categoryDeleteEndpoint, query: {'id': '$id'});
  }

  @override
  Future<void> reorderCategory({
    required int id,
    required int targetIndex,
  }) async {
    await client.post(
      categorySortEndpoint,
      body: {'id': id, 'targetIndex': targetIndex},
    );
  }

  @override
  Future<void> reorderDish({
    required int id,
    required int targetIndex,
  }) async {
    await client.post(
      dishSortEndpoint,
      body: {'id': id, 'targetIndex': targetIndex},
    );
  }

  @override
  Future<List<CashierDishCategory>> loadCategories() async {
    final data = await client.get(categoryListAllEndpoint);
    final rows = _categoryRows(data);
    return rows.map(CashierDishCategory.fromJson).toList(growable: false)
      ..sort((a, b) => a.sorting.compareTo(b.sorting));
  }

  @override
  Future<CashierDishPage> loadDishes({
    required int pageNum,
    required int pageSize,
    required String query,
  }) async {
    final data = await client.post(
      dishListEndpoint,
      body: {'pageNum': pageNum, 'pageSize': pageSize, 'query': query.trim()},
    );
    final items = objectList(
      data,
    ).map(CashierDish.fromJson).toList(growable: false);
    return CashierDishPage(items: items, total: totalFrom(data, items.length));
  }

  @override
  Future<void> updateSoldOut({
    required CashierDish dish,
    required bool soldOut,
  }) async {
    await client.post(
      dishUpdateSaleStatusEndpoint,
      body: {'id': dish.id, 'sold_out': soldOut ? 1 : 0},
    );
    CashierOperationAuditStore.instance.record(CashierOperationAuditDraft(
      module: 'dish',
      action: soldOut ? 'sold_out' : 'restore',
      result: 'success',
      targetType: 'dish',
      targetId: '${dish.id}',
      detail: {'name': dish.name},
    ));
  }

  @override
  Future<void> updateOnSale({
    required CashierDish dish,
    required bool onSale,
  }) async {
    await client.post(
      dishUpdateOnSaleEndpoint,
      body: {'id': dish.id, 'onsale': onSale},
    );
  }

  @override
  Future<void> saveDish(CashierDishInput input) async {
    await client.post(dishSaveEndpoint, body: input.toJson());
  }

  @override
  Future<void> deleteDish(int id) async {
    await client.get(dishDeleteEndpoint, query: {'id': '$id'});
  }

  @override
  Future<CashierDishPage> loadHqTemplateDishes({
    required int pageNum,
    required int pageSize,
    required String query,
  }) async {
    final data = await client.post(
      dishHqTemplateListEndpoint,
      body: {'pageNum': pageNum, 'pageSize': pageSize, 'query': query.trim()},
    );
    final items = objectList(
      data,
    ).map(CashierDish.fromJson).toList(growable: false);
    return CashierDishPage(items: items, total: totalFrom(data, items.length));
  }

  @override
  Future<Map<String, Object?>> importDishesFromHq(List<int> dishIds) async {
    final data = await client.post(
      dishImportFromHqEndpoint,
      body: {'dishIds': dishIds},
    );
    CashierOperationAuditStore.instance.record(CashierOperationAuditDraft(
      module: 'dish',
      action: 'import_hq',
      result: 'success',
      targetType: 'dish_batch',
      targetId: dishIds.join(','),
      detail: {'count': dishIds.length},
    ));
    if (data is Map<String, Object?>) return data;
    if (data is Map) return data.cast<String, Object?>();
    return const {};
  }

  @override
  Future<String> uploadDishImage({
    required List<int> bytes,
    required String filename,
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError('bytes must not be empty');
    }
    final extension = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : 'jpg';
    final mime = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };

    final response = await client.postMultipart(
      dishUploadImageEndpoint,
      files: {
        'file': (
          bytes: bytes,
          filename: filename,
          contentType: mime,
        ),
      },
    );
    final map = _object(response);
    final src = (map['src'] ?? map['url'] ?? map['imageName'] ?? '').toString();
    if (src.isEmpty) {
      throw const ApiException('上传失败：未获取到有效的图片路径');
    }
    return src;
  }

  @override
  Future<ComboDetailResponse> getComboDetail(int dishId) async {
    final response = await client.get(
      comboGetByDishIdEndpoint,
      query: {'dishId': '$dishId'},
    );
    final map = _object(response);
    return ComboDetailResponse.fromJson(map, fallbackDishId: dishId);
  }

  @override
  Future<void> saveCombo(ComboSaveRequest request) async {
    await client.post(
      comboSaveEndpoint,
      body: request.toJson(),
    );
    CashierOperationAuditStore.instance.record(CashierOperationAuditDraft(
      module: 'combo',
      action: 'save_combo',
      result: 'success',
      targetType: 'combo',
      targetId: '${request.dishId}',
      detail: {
        'comboType': request.comboType,
        'fixedCount': request.fixedItems.length,
        'groupCount': request.groups.length,
      },
    ));
  }
}

List<Map<String, Object?>> _categoryRows(Object? value) {
  if (value is List) return _maps(value);
  if (value is Map) {
    for (final key in const [
      'categoryList',
      'category_list',
      'list',
      'records',
    ]) {
      final nested = value[key];
      if (nested is List) return _maps(nested);
    }
  }
  return const [];
}

List<Map<String, Object?>> _maps(List<Object?> value) => value
    .whereType<Map>()
    .map((item) => item.cast<String, Object?>())
    .toList(growable: false);

Map<String, Object?> _object(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}
