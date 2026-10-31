import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/catalog_models.dart';
import 'catalog_repository.dart';

class RealCatalogRepository implements CatalogRepository {
  const RealCatalogRepository(this.client);

  final AdminApiClient client;

  @override
  Future<DishShopStock> loadDishStock({
    required int dishId,
    required int shopId,
  }) async {
    final data = await client
        .copyWith(shopId: shopId)
        .post(
          dishListEndpoint,
          body: {
            'pageNum': 1,
            'pageSize': 100,
            'id': dishId,
            'dish_id': dishId,
          },
        );
    final rows = objectList(data);
    final row = rows.firstWhere(
      (item) => _int(item['id'] ?? item['dish_id']) == dishId,
      orElse: () => rows.isEmpty ? <String, Object?>{} : rows.first,
    );
    if (row.isEmpty) {
      throw ApiException('接口未返回菜品 $dishId 的门店库存');
    }
    return DishShopStock.fromJson({
      ...row,
      'dish_id': row['dish_id'] ?? row['id'] ?? dishId,
      'shop_id': row['shop_id'] ?? shopId,
    });
  }

  @override
  Future<DishShopStock> updateOnSale({
    required DishShopStock stock,
    required bool onsale,
  }) async {
    await client
        .copyWith(shopId: stock.shopId)
        .post(
          dishUpdateOnSaleEndpoint,
          body: {'id': stock.dishId, 'dish_id': stock.dishId, 'onsale': onsale},
        );
    return stock.updateOnSale(onsale);
  }

  @override
  Future<DishShopStock> updateSoldOut({
    required DishShopStock stock,
    required bool soldOut,
  }) async {
    await client
        .copyWith(shopId: stock.shopId)
        .post(
          dishUpdateSaleStatusEndpoint,
          body: {
            'id': stock.dishId,
            'dish_id': stock.dishId,
            'sold_out': soldOut,
          },
        );
    return stock.updateSoldOut(soldOut);
  }
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
