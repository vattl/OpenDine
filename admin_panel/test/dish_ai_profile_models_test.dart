import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/features/catalog/domain/dish_ai_profile_models.dart';

void main() {
  group('DishFoodProfile Tests', () {
    test('fromJson & toJson normal serialization', () {
      final json = {
        'id': 101,
        'store_id': 1,
        'dish_id': 5001,
        'non_spicy_available': 1,
        'spice_options': ['不辣', '微辣', '中辣'],
        'verified_allergens': ['PEANUT', 'SEAFOOD'],
        'is_suitable_fitness': 1,
        'calories_kcal': 320.5,
        'protein_g': 28.0,
        'fat_g': 8.5,
        'edible_weight_g': 200.0,
        'ingredients': '老肥牛肉, 秘制酱料',
        'seasonings': '生抽, 孜然',
      };

      final profile = DishFoodProfile.fromJson(json);
      expect(profile.id, 101);
      expect(profile.storeId, 1);
      expect(profile.dishId, 5001);
      expect(profile.nonSpicyAvailable, isTrue);
      expect(profile.spiceOptions, ['不辣', '微辣', '中辣']);
      expect(profile.verifiedAllergens, ['PEANUT', 'SEAFOOD']);
      expect(profile.isSuitableFitness, isTrue);
      expect(profile.caloriesKcal, 320.5);
      expect(profile.proteinG, 28.0);
      expect(profile.fatG, 8.5);
      expect(profile.edibleWeightG, 200.0);

      final outJson = profile.toJson();
      expect(outJson['non_spicy_available'], 1);
      expect(outJson['is_suitable_fitness'], 1);
      expect(outJson['calories_kcal'], 320.5);
    });

    test('fromJson handles JSON string for spice_options and allergens', () {
      final json = {
        'store_id': 1,
        'dish_id': 5002,
        'non_spicy_available': 0,
        'spice_options': '["微辣", "特辣"]',
        'verified_allergens': '["GLUTEN", "SOY"]',
        'is_suitable_fitness': 0,
        'calories_kcal': '450',
      };

      final profile = DishFoodProfile.fromJson(json);
      expect(profile.nonSpicyAvailable, isFalse);
      expect(profile.spiceOptions, ['微辣', '特辣']);
      expect(profile.verifiedAllergens, ['GLUTEN', 'SOY']);
      expect(profile.isSuitableFitness, isFalse);
      expect(profile.caloriesKcal, 450.0);
    });

    test('fromJson handles comma-separated string for spice_options', () {
      final json = {
        'storeId': 1,
        'dishId': 5003,
        'nonSpicyAvailable': true,
        'spiceOptions': '不辣, 微辣',
        'verifiedAllergens': 'EGG',
      };

      final profile = DishFoodProfile.fromJson(json);
      expect(profile.nonSpicyAvailable, isTrue);
      expect(profile.spiceOptions, ['不辣', '微辣']);
      expect(profile.verifiedAllergens, ['EGG']);
    });
  });

  group('DishWithProfileVO Tests', () {
    test('fromJson correctly parses dish with nested profile', () {
      final json = {
        'dish_id': 1001,
        'dish_name': '招牌老肥油边串',
        'category_id': 2,
        'category_name': '经典烤肉',
        'price': 12.0,
        'price_fen': 1200,
        'onsale': 1,
        'sold_out': 0,
        'has_profile': true,
        'profile': {
          'store_id': 1,
          'dish_id': 1001,
          'non_spicy_available': 1,
          'spice_options': ['不辣', '微辣'],
          'verified_allergens': [],
          'is_suitable_fitness': 0,
          'calories_kcal': 280,
        },
      };

      final vo = DishWithProfileVO.fromJson(json);
      expect(vo.dishId, 1001);
      expect(vo.dishName, '招牌老肥油边串');
      expect(vo.categoryName, '经典烤肉');
      expect(vo.price, 12.0);
      expect(vo.priceFen, 1200);
      expect(vo.hasProfile, isTrue);
      expect(vo.profile, isNotNull);
      expect(vo.profile!.nonSpicyAvailable, isTrue);
      expect(vo.profile!.caloriesKcal, 280.0);
    });

    test('fromJson correctly parses dish without profile', () {
      final json = {
        'dish_id': 1002,
        'dish_name': '烤大虾',
        'category_id': 3,
        'category_name': '海鲜烧烤',
        'price': 18.0,
        'price_fen': 1800,
        'has_profile': false,
        'profile': null,
      };

      final vo = DishWithProfileVO.fromJson(json);
      expect(vo.dishId, 1002);
      expect(vo.hasProfile, isFalse);
      expect(vo.profile, isNull);
    });
  });

  group('DishFoodProfileInput Tests', () {
    test('toJson formats DTO correctly for backend', () {
      const input = DishFoodProfileInput(
        storeId: 1,
        dishId: 1001,
        nonSpicyAvailable: true,
        spiceOptions: ['不辣', '微辣'],
        verifiedAllergens: ['PEANUT'],
        isSuitableFitness: true,
        caloriesKcal: 350.0,
        proteinG: 30.0,
      );

      final json = input.toJson();
      expect(json['store_id'], 1);
      expect(json['dish_id'], 1001);
      expect(json['non_spicy_available'], 1);
      expect(json['spice_options'], ['不辣', '微辣']);
      expect(json['verified_allergens'], ['PEANUT']);
      expect(json['is_suitable_fitness'], 1);
      expect(json['calories_kcal'], 350.0);
      expect(json['protein_g'], 30.0);
    });
  });
}
