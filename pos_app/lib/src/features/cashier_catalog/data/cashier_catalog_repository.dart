import '../domain/cashier_dish.dart';
import '../domain/combo_definition_models.dart';

abstract interface class CashierCatalogRepository {
  Future<List<CashierDishCategory>> loadCategories();

  Future<void> addCategory({required String name, required int sorting});

  Future<void> deleteCategory(int id);

  Future<CashierDishPage> loadDishes({
    required int pageNum,
    required int pageSize,
    required String query,
  });

  Future<void> updateSoldOut({
    required CashierDish dish,
    required bool soldOut,
  });

  Future<void> updateOnSale({required CashierDish dish, required bool onSale});

  Future<void> saveDish(CashierDishInput input);

  /// 删除菜品（不可恢复）；成功后云端广播 dish_catalog_changed。
  Future<void> deleteDish(int id);

  /// 查询总部标准模板菜品列表（分页/搜索）
  Future<CashierDishPage> loadHqTemplateDishes({
    required int pageNum,
    required int pageSize,
    required String query,
  });

  /// 将总部菜品批量挂载导入到当前门店
  Future<Map<String, Object?>> importDishesFromHq(List<int> dishIds);

  /// 上传菜品图片（multipart），返回服务器相对可访问路径（如 /image/dish/uuid.png）
  Future<String> uploadDishImage({
    required List<int> bytes,
    required String filename,
  });

  /// 获取菜品结构化套餐详情（fixed items + groups）
  Future<ComboDetailResponse> getComboDetail(int dishId);

  /// 保存菜品结构化套餐定义
  Future<void> saveCombo(ComboSaveRequest request);
}

abstract interface class CashierCatalogSortingRepository {
  /// 拖拽更新类目排序（v1.2.283 契约）：[targetIndex] 为当前门店分类列表中的
  /// 1-based 目标显示位置（0 等价移到首位，越界由后端收敛到首/末位）。
  Future<void> reorderCategory({required int id, required int targetIndex});

  /// 拖拽更新菜品排序（v1.2.283 契约）：[targetIndex] 为当前门店、该菜品
  /// 生效分类内的 1-based 目标显示位置；仅重排生效分类内的 `t_dish_shop.sorting_override`。
  Future<void> reorderDish({required int id, required int targetIndex});
}

extension CashierCatalogPagination on CashierCatalogRepository {
  Future<List<CashierDish>> loadAllDishes({required String query}) async {
    const pageSize = 100;
    final normalizedQuery = query.trim();
    final dishes = <CashierDish>[];
    final seenIds = <int>{};

    for (var pageNum = 1; ; pageNum++) {
      final page = await loadDishes(
        pageNum: pageNum,
        pageSize: pageSize,
        query: normalizedQuery,
      );
      final previousCount = dishes.length;
      for (final dish in page.items) {
        if (seenIds.add(dish.id)) dishes.add(dish);
      }
      if (page.items.isEmpty ||
          dishes.length >= page.total ||
          page.items.length < pageSize ||
          dishes.length == previousCount) {
        return List.unmodifiable(dishes);
      }
    }
  }
}
