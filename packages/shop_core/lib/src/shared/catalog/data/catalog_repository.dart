import '../domain/catalog_models.dart';

abstract class CatalogRepository {
  Future<DishShopStock> loadDishStock({
    required int dishId,
    required int shopId,
  });

  Future<DishShopStock> updateOnSale({
    required DishShopStock stock,
    required bool onsale,
  });

  Future<DishShopStock> updateSoldOut({
    required DishShopStock stock,
    required bool soldOut,
  });
}
