import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/core/app_state.dart';
import 'package:admin_panel_flutter/src/features/catalog/data/dish_ai_profile_repository.dart';
import 'package:admin_panel_flutter/src/features/catalog/domain/dish_ai_profile_models.dart';
import 'package:admin_panel_flutter/src/features/catalog/presentation/dish_ai_profiles_page.dart';

class MockDishAiProfileRepository implements DishAiProfileRepository {
  List<DishWithProfileVO> mockDishes = [
    const DishWithProfileVO(
      dishId: 101,
      dishName: '招牌老肥油边串',
      categoryId: 1,
      categoryName: '经典烤肉',
      price: 12.0,
      hasProfile: true,
      profile: DishFoodProfile(
        storeId: 1,
        dishId: 101,
        nonSpicyAvailable: true,
        spiceOptions: ['不辣', '微辣', '中辣'],
        verifiedAllergens: ['PEANUT'],
        isSuitableFitness: false,
        caloriesKcal: 320.0,
        proteinG: 28.0,
        fatG: 8.5,
        edibleWeightG: 200.0,
      ),
    ),
    const DishWithProfileVO(
      dishId: 102,
      dishName: '蜜汁烤鸡翅',
      categoryId: 1,
      categoryName: '经典烤肉',
      price: 16.0,
      hasProfile: true,
      profile: DishFoodProfile(
        storeId: 1,
        dishId: 102,
        nonSpicyAvailable: false,
        spiceOptions: ['微辣', '特辣'],
        verifiedAllergens: ['SOY'],
        isSuitableFitness: true,
        caloriesKcal: 250.0,
        proteinG: 32.0,
        fatG: 5.0,
        edibleWeightG: 180.0,
      ),
    ),
    const DishWithProfileVO(
      dishId: 103,
      dishName: '锡纸金针菇',
      categoryId: 2,
      categoryName: '锡纸素菜',
      price: 15.0,
      hasProfile: false,
      profile: null,
    ),
  ];

  bool autoInitCalled = false;
  DishFoodProfileInput? lastSavedInput;
  List<DishFoodProfileInput>? lastBatchInputs;

  @override
  Future<List<DishWithProfileVO>> fetchDishProfiles({
    required int storeId,
    int? categoryId,
    bool? configuredOnly,
  }) async {
    return mockDishes;
  }

  @override
  Future<DishFoodProfile?> fetchSingleProfile({
    required int storeId,
    required int dishId,
  }) async {
    final d = mockDishes.firstWhere((e) => e.dishId == dishId);
    return d.profile;
  }

  @override
  Future<DishFoodProfile> saveDishProfile({
    required int storeId,
    required int dishId,
    required DishFoodProfileInput input,
  }) async {
    lastSavedInput = input;
    final saved = DishFoodProfile(
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
    );
    final idx = mockDishes.indexWhere((e) => e.dishId == dishId);
    if (idx != -1) {
      mockDishes[idx] = mockDishes[idx].copyWith(
        hasProfile: true,
        profile: saved,
      );
    }
    return saved;
  }

  @override
  Future<int> batchSaveDishProfiles({
    required int storeId,
    required List<DishFoodProfileInput> inputs,
  }) async {
    lastBatchInputs = inputs;
    return inputs.length;
  }

  @override
  Future<int> autoInitDishProfiles({
    required int storeId,
  }) async {
    autoInitCalled = true;
    return 1;
  }
}

void main() {
  late MockDishAiProfileRepository repository;
  late AppState appState;

  setUp(() {
    repository = MockDishAiProfileRepository();
    appState = AppState();
    appState.currentShopId = 1;
  });

  Widget buildTestableWidget() {
    return MaterialApp(
      home: DishAiProfilesPage(
        appState: appState,
        repository: repository,
        initialShopId: 1,
      ),
    );
  }

  testWidgets('DishAiProfilesPage renders header, filters and data table', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    expect(find.text('菜品 AI 配餐画像管理'), findsOneWidget);
    expect(find.byKey(const ValueKey('btn-auto-init')), findsOneWidget);
    expect(find.byKey(const ValueKey('btn-batch-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('btn-save-all')), findsOneWidget);

    expect(find.text('已配置 2'), findsOneWidget);
    expect(find.text('未配置 1'), findsOneWidget);

    expect(find.text('招牌老肥油边串'), findsOneWidget);
    expect(find.text('蜜汁烤鸡翅'), findsOneWidget);
    expect(find.text('锡纸金针菇'), findsOneWidget);

    expect(find.text('可免辣'), findsOneWidget);
    expect(find.text('不可免辣'), findsOneWidget);
    expect(find.text('★ 健身友好'), findsOneWidget);
  });

  testWidgets('Search query filters dish list', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('input-search')), '鸡翅');
    await tester.pumpAndSettle();

    expect(find.text('蜜汁烤鸡翅'), findsOneWidget);
    expect(find.text('招牌老肥油边串'), findsNothing);
    expect(find.text('锡纸金针菇'), findsNothing);
  });

  testWidgets('Auto-init triggers confirmation dialog and repository call', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('btn-auto-init')));
    await tester.pumpAndSettle();

    expect(find.text('一键智能初始化画像'), findsOneWidget);
    await tester.tap(find.text('确定开始'));
    await tester.pumpAndSettle();

    expect(repository.autoInitCalled, isTrue);
    expect(find.textContaining('智能初始化成功'), findsOneWidget);
  });

  testWidgets('Open edit drawer, toggle switch, and save single dish profile', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('btn-edit-101')));
    await tester.pumpAndSettle();

    expect(find.textContaining('菜品画像编辑 — 招牌老肥油边串'), findsOneWidget);
    expect(find.text('后厨是否支持免辣制作'), findsOneWidget);
    expect(find.text('可用辣度选项 (多选)'), findsOneWidget);
    expect(find.text('核验过敏原'), findsOneWidget);
    expect(find.text('健身控重优选'), findsOneWidget);
    expect(find.text('营养成分卡片'), findsOneWidget);

    // Toggle non-spicy switch off and verify warning box appears
    await tester.tap(find.byKey(const ValueKey('switch-non-spicy')));
    await tester.pumpAndSettle();
    expect(find.textContaining('若关闭此项，AI 求解器在遇到不吃辣顾客时，绝对不会推荐该菜品！'), findsOneWidget);

    // Click save
    await tester.tap(find.byKey(const ValueKey('btn-save-drawer')));
    await tester.pumpAndSettle();

    expect(repository.lastSavedInput, isNotNull);
    expect(repository.lastSavedInput!.nonSpicyAvailable, isFalse);
    expect(find.textContaining('画像已成功保存'), findsOneWidget);
  });

  testWidgets('Batch edit dialog updates selected dishes', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('btn-batch-edit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('批量编辑画像'), findsOneWidget);
    await tester.tap(find.text('应用到选定菜品'));
    await tester.pumpAndSettle();

    expect(repository.lastBatchInputs, isNotNull);
    expect(find.textContaining('已成功批量更新'), findsOneWidget);
  });
}
