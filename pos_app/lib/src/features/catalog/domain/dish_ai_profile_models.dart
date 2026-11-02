import 'dart:convert';

List<String> _parseStringList(Object? value) {
  if (value == null) return const [];
  if (value is List) {
    return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        }
      } catch (_) {}
    }
    return trimmed.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

bool _parseBool(Object? value, {bool defaultValue = false}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value == 1;
  final str = value.toString().trim().toLowerCase();
  if (str == 'true' || str == '1') return true;
  if (str == 'false' || str == '0') return false;
  return defaultValue;
}

double? _parseDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim());
}

int? _parseInt(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim());
}

/// 菜品 AI 食材风味与健康画像实体
class DishFoodProfile {
  const DishFoodProfile({
    this.id,
    required this.storeId,
    required this.dishId,
    this.nonSpicyAvailable = true,
    this.spiceOptions = const [],
    this.verifiedAllergens = const [],
    this.isSuitableFitness = false,
    this.caloriesKcal,
    this.proteinG,
    this.fatG,
    this.edibleWeightG,
    this.ingredients,
    this.seasonings,
  });

  final int? id;
  final int storeId;
  final int dishId;
  final bool nonSpicyAvailable;
  final List<String> spiceOptions;
  final List<String> verifiedAllergens;
  final bool isSuitableFitness;
  final double? caloriesKcal;
  final double? proteinG;
  final double? fatG;
  final double? edibleWeightG;
  final String? ingredients;
  final String? seasonings;

  factory DishFoodProfile.fromJson(Map<String, dynamic> json) {
    return DishFoodProfile(
      id: _parseInt(json['id']),
      storeId: _parseInt(json['store_id'] ?? json['storeId']) ?? 0,
      dishId: _parseInt(json['dish_id'] ?? json['dishId']) ?? 0,
      nonSpicyAvailable: _parseBool(
        json['non_spicy_available'] ?? json['nonSpicyAvailable'],
        defaultValue: true,
      ),
      spiceOptions: _parseStringList(json['spice_options'] ?? json['spiceOptions']),
      verifiedAllergens: _parseStringList(json['verified_allergens'] ?? json['verifiedAllergens']),
      isSuitableFitness: _parseBool(
        json['is_suitable_fitness'] ?? json['isSuitableFitness'],
        defaultValue: false,
      ),
      caloriesKcal: _parseDouble(json['calories_kcal'] ?? json['caloriesKcal']),
      proteinG: _parseDouble(json['protein_g'] ?? json['proteinG']),
      fatG: _parseDouble(json['fat_g'] ?? json['fatG']),
      edibleWeightG: _parseDouble(json['edible_weight_g'] ?? json['edibleWeightG']),
      ingredients: json['ingredients']?.toString(),
      seasonings: json['seasonings']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'store_id': storeId,
      'dish_id': dishId,
      'non_spicy_available': nonSpicyAvailable ? 1 : 0,
      'spice_options': spiceOptions,
      'verified_allergens': verifiedAllergens,
      'is_suitable_fitness': isSuitableFitness ? 1 : 0,
      if (caloriesKcal != null) 'calories_kcal': caloriesKcal,
      if (proteinG != null) 'protein_g': proteinG,
      if (fatG != null) 'fat_g': fatG,
      if (edibleWeightG != null) 'edible_weight_g': edibleWeightG,
      if (ingredients != null) 'ingredients': ingredients,
      if (seasonings != null) 'seasonings': seasonings,
    };
  }

  DishFoodProfile copyWith({
    int? id,
    int? storeId,
    int? dishId,
    bool? nonSpicyAvailable,
    List<String>? spiceOptions,
    List<String>? verifiedAllergens,
    bool? isSuitableFitness,
    double? caloriesKcal,
    double? proteinG,
    double? fatG,
    double? edibleWeightG,
    String? ingredients,
    String? seasonings,
  }) {
    return DishFoodProfile(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      dishId: dishId ?? this.dishId,
      nonSpicyAvailable: nonSpicyAvailable ?? this.nonSpicyAvailable,
      spiceOptions: spiceOptions ?? this.spiceOptions,
      verifiedAllergens: verifiedAllergens ?? this.verifiedAllergens,
      isSuitableFitness: isSuitableFitness ?? this.isSuitableFitness,
      caloriesKcal: caloriesKcal ?? this.caloriesKcal,
      proteinG: proteinG ?? this.proteinG,
      fatG: fatG ?? this.fatG,
      edibleWeightG: edibleWeightG ?? this.edibleWeightG,
      ingredients: ingredients ?? this.ingredients,
      seasonings: seasonings ?? this.seasonings,
    );
  }
}

/// 菜品及其 AI 画像视图对象 (DishWithProfileVO)
class DishWithProfileVO {
  const DishWithProfileVO({
    required this.dishId,
    required this.dishName,
    this.categoryId,
    this.categoryName,
    this.price = 0.0,
    this.priceFen,
    this.onsale = true,
    this.soldOut = false,
    this.hasProfile = false,
    this.imageUrl,
    this.profile,
  });

  final int dishId;
  final String dishName;
  final int? categoryId;
  final String? categoryName;
  final double price;
  final int? priceFen;
  final bool onsale;
  final bool soldOut;
  final bool hasProfile;
  final String? imageUrl;
  final DishFoodProfile? profile;

  factory DishWithProfileVO.fromJson(Map<String, dynamic> json) {
    final dishId = _parseInt(json['dish_id'] ?? json['dishId'] ?? json['id']) ?? 0;
    final rawProfile = json['profile'];
    DishFoodProfile? profile;
    if (rawProfile is Map<String, dynamic>) {
      profile = DishFoodProfile.fromJson(rawProfile);
    } else if (rawProfile is Map) {
      profile = DishFoodProfile.fromJson(rawProfile.cast<String, dynamic>());
    }

    final hasProfile = _parseBool(json['has_profile'] ?? json['hasProfile']) || profile != null;

    final priceFen = _parseInt(json['price_fen'] ?? json['priceFen']);
    double price = _parseDouble(json['price']) ?? 0.0;
    if (price == 0.0 && priceFen != null && priceFen > 0) {
      price = priceFen / 100.0;
    }

    return DishWithProfileVO(
      dishId: dishId,
      dishName: json['dish_name'] ?? json['dishName'] ?? json['name'] ?? '',
      categoryId: _parseInt(json['category_id'] ?? json['categoryId']),
      categoryName: json['category_name']?.toString() ?? json['categoryName']?.toString(),
      price: price,
      priceFen: priceFen ?? (price * 100).toInt(),
      onsale: _parseBool(json['onsale'], defaultValue: true),
      soldOut: _parseBool(json['sold_out'] ?? json['soldOut'], defaultValue: false),
      hasProfile: hasProfile,
      imageUrl: json['image_url']?.toString() ?? json['imageUrl']?.toString() ?? json['image']?.toString(),
      profile: profile,
    );
  }

  DishWithProfileVO copyWith({
    int? dishId,
    String? dishName,
    int? categoryId,
    String? categoryName,
    double? price,
    int? priceFen,
    bool? onsale,
    bool? soldOut,
    bool? hasProfile,
    String? imageUrl,
    DishFoodProfile? profile,
  }) {
    return DishWithProfileVO(
      dishId: dishId ?? this.dishId,
      dishName: dishName ?? this.dishName,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      price: price ?? this.price,
      priceFen: priceFen ?? this.priceFen,
      onsale: onsale ?? this.onsale,
      soldOut: soldOut ?? this.soldOut,
      hasProfile: hasProfile ?? this.hasProfile,
      imageUrl: imageUrl ?? this.imageUrl,
      profile: profile ?? this.profile,
    );
  }
}

/// 菜品 AI 画像提交载荷 DTO
class DishFoodProfileInput {
  const DishFoodProfileInput({
    required this.storeId,
    required this.dishId,
    this.nonSpicyAvailable = true,
    this.spiceOptions = const [],
    this.verifiedAllergens = const [],
    this.isSuitableFitness = false,
    this.caloriesKcal,
    this.proteinG,
    this.fatG,
    this.edibleWeightG,
    this.ingredients,
    this.seasonings,
  });

  final int storeId;
  final int dishId;
  final bool nonSpicyAvailable;
  final List<String> spiceOptions;
  final List<String> verifiedAllergens;
  final bool isSuitableFitness;
  final double? caloriesKcal;
  final double? proteinG;
  final double? fatG;
  final double? edibleWeightG;
  final String? ingredients;
  final String? seasonings;

  Map<String, dynamic> toJson() {
    return {
      'store_id': storeId,
      'dish_id': dishId,
      'non_spicy_available': nonSpicyAvailable ? 1 : 0,
      'spice_options': spiceOptions,
      'verified_allergens': verifiedAllergens,
      'is_suitable_fitness': isSuitableFitness ? 1 : 0,
      if (caloriesKcal != null) 'calories_kcal': caloriesKcal,
      if (proteinG != null) 'protein_g': proteinG,
      if (fatG != null) 'fat_g': fatG,
      if (edibleWeightG != null) 'edible_weight_g': edibleWeightG,
      if (ingredients != null) 'ingredients': ingredients,
      if (seasonings != null) 'seasonings': seasonings,
    };
  }
}
