import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/dish_ai_profile_models.dart';

abstract class DishAiProfileRepository {
  Future<List<DishWithProfileVO>> fetchDishProfiles({
    required int storeId,
    int? categoryId,
    bool? configuredOnly,
  });

  Future<DishFoodProfile?> fetchSingleProfile({
    required int storeId,
    required int dishId,
  });

  Future<DishFoodProfile> saveDishProfile({
    required int storeId,
    required int dishId,
    required DishFoodProfileInput input,
  });

  Future<int> batchSaveDishProfiles({
    required int storeId,
    required List<DishFoodProfileInput> inputs,
  });

  Future<int> autoInitDishProfiles({
    required int storeId,
  });
}

class RealDishAiProfileRepository implements DishAiProfileRepository {
  const RealDishAiProfileRepository(this.client);

  final AdminApiClient client;

  @override
  Future<List<DishWithProfileVO>> fetchDishProfiles({
    required int storeId,
    int? categoryId,
    bool? configuredOnly,
  }) async {
    final endpoint = aiStoreDishProfilesEndpoint.withPathParams({
      'storeId': '$storeId',
    });

    final query = <String, Object?>{
      if (categoryId != null && categoryId > 0) 'categoryId': categoryId,
      if (configuredOnly != null) 'configuredOnly': configuredOnly,
    };

    final raw = await client.get(endpoint, query: query);
    final list = _extractList(raw);
    return list.map((item) => DishWithProfileVO.fromJson(item)).toList();
  }

  @override
  Future<DishFoodProfile?> fetchSingleProfile({
    required int storeId,
    required int dishId,
  }) async {
    final endpoint = aiSingleDishProfileEndpoint.withPathParams({
      'storeId': '$storeId',
      'dishId': '$dishId',
    });

    final raw = await client.get(endpoint);
    final map = _extractMap(raw);
    if (map.isEmpty) return null;
    return DishFoodProfile.fromJson(map);
  }

  @override
  Future<DishFoodProfile> saveDishProfile({
    required int storeId,
    required int dishId,
    required DishFoodProfileInput input,
  }) async {
    final endpoint = aiSaveDishProfileEndpoint.withPathParams({
      'storeId': '$storeId',
      'dishId': '$dishId',
    });

    final raw = await client.put(endpoint, body: input.toJson());
    final map = _extractMap(raw);
    if (map.isEmpty) {
      return DishFoodProfile(
        storeId: storeId,
        dishId: dishId,
        nonSpicyAvailable: input.nonSpicyAvailable,
        spiceOptions: input.spiceOptions,
        verifiedAllergens: input.verifiedAllergens,
        isSuitableFitness: input.isSuitableFitness,
        caloriesKcal: input.caloriesKcal,
        proteinG: input.proteinG,
        fatG: input.fatG,
        edibleWeightG: input.edibleWeightG,
        ingredients: input.ingredients,
        seasonings: input.seasonings,
      );
    }
    return DishFoodProfile.fromJson(map);
  }

  @override
  Future<int> batchSaveDishProfiles({
    required int storeId,
    required List<DishFoodProfileInput> inputs,
  }) async {
    final endpoint = aiBatchDishProfilesEndpoint.withPathParams({
      'storeId': '$storeId',
    });

    final raw = await client.post(
      endpoint,
      body: inputs.map((e) => e.toJson()).toList(),
    );

    if (raw is num) return raw.toInt();
    if (raw is Map) {
      final data = raw['data'] ?? raw['count'] ?? raw['updatedCount'];
      if (data is num) return data.toInt();
    }
    return inputs.length;
  }

  @override
  Future<int> autoInitDishProfiles({
    required int storeId,
  }) async {
    final endpoint = aiAutoInitDishProfilesEndpoint.withPathParams({
      'storeId': '$storeId',
    });

    final raw = await client.post(endpoint);
    final map = _extractMap(raw);
    final count = map['initialized_count'] ?? map['initializedCount'] ?? map['count'];
    if (count is num) return count.toInt();
    if (raw is num) return raw.toInt();
    return 0;
  }

  List<Map<String, dynamic>> _extractList(Object? raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    if (raw is Map) {
      final data = raw['data'];
      if (data is List) {
        return data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
    }
    return const [];
  }

  Map<String, dynamic> _extractMap(Object? raw) {
    if (raw == null) return const {};
    if (raw is Map) {
      if (raw.containsKey('data') && raw['data'] is Map) {
        return (raw['data'] as Map).cast<String, dynamic>();
      }
      return raw.cast<String, dynamic>();
    }
    return const {};
  }
}
