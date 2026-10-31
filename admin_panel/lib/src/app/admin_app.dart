import 'dart:async';

import 'package:flutter/material.dart';

import '../core/admin_api_client.dart';
import '../core/api_contract.dart';
import '../core/app_state.dart';
import '../core/http_transport.dart';
import '../core/terminal_device_service.dart';
import '../features/auth/data/access_approval_repository.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/catalog/data/dish_ai_profile_repository.dart';
import '../features/catalog/data/real_catalog_repository.dart';
import '../features/catalog/presentation/catalog_finance_page.dart';
import '../features/catalog/presentation/dish_ai_profiles_page.dart';
import '../features/common/presentation/api_module_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/kds_local/presentation/kds_devices_page.dart';
import '../features/orders/data/real_order_repository.dart';
import '../features/orders/presentation/order_console_page.dart';
import '../features/realtime/data/realtime_repository.dart';
import '../features/realtime/presentation/realtime_page.dart';
import '../features/reports/data/report_repository.dart';
import '../features/tables/data/real_table_repository.dart';
import '../features/tables/presentation/table_overview_page.dart';
import '../features/users/data/real_user_repository.dart';
import '../features/users/domain/user_query.dart';
import '../features/users/presentation/user_list_page.dart';
import '../features/users/presentation/employee_list_view.dart';
import '../features/receivable_management/presentation/receivable_management_page.dart';
import 'app_shell.dart';

class AdminPanelFlutterApp extends StatefulWidget {
  const AdminPanelFlutterApp({super.key, this.transport});

  final HttpTransport? transport;

  @override
  State<AdminPanelFlutterApp> createState() => _AdminPanelFlutterAppState();
}

class _AdminPanelFlutterAppState extends State<AdminPanelFlutterApp> {
  final AppState appState = AppState();
  late final HttpTransport transport =
      widget.transport ?? createHttpTransport();

  @override
  void initState() {
    super.initState();
    unawaited(TerminalDeviceService.instance.getOrInitializeTerminalId());
  }

  AdminApiClient _client() {
    return AdminApiClient(
      baseUrl: appState.baseUrl,
      transport: transport,
      token: appState.token,
      shopId: appState.currentShopId,
      terminalId: TerminalDeviceService.instance.currentTerminalId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xffad1919),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: '运营收银后台 Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xfff5f7fb),
        visualDensity: VisualDensity.compact,
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xffe5e7eb)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: AnimatedBuilder(
        animation: appState,
        builder: (context, _) {
          final client = _client();
          if (!appState.isAuthenticated) {
            return LoginPage(
              appState: appState,
              repository: AuthRepository(client),
            );
          }
          final reportRepository = ReportRepository(client);
          return AppShell(
            appState: appState,
            groups: _groups(client, reportRepository),
          );
        },
      ),
    );
  }

  List<ShellPageGroup> _groups(
    AdminApiClient client,
    ReportRepository reportRepository,
  ) {
    return [
      ShellPageGroup(
        title: '收银营业',
        icon: Icons.point_of_sale,
        pages: [
          ShellPage(
            title: '订单管理',
            icon: Icons.receipt_long_outlined,
            requiredPermission: 'order:view',
            builder: (_) => OrderConsolePage(
              key: ValueKey('orders-${appState.currentShopId}'),
              appState: appState,
              repository: RealOrderRepository(client),
              approvalRepository: AccessApprovalRepository(client),
            ),
          ),
          ShellPage(
            title: '点餐台',
            icon: Icons.shopping_cart_outlined,
            requiredPermission: 'order:operate',
            builder: (_) => TableOverviewPage(
              key: ValueKey('tables-${appState.currentShopId}'),
              repository: RealTableRepository(client),
              canManageTable: appState.hasPermission('table:manage'),
            ),
          ),
          _module(
            title: '桌台管理',
            icon: Icons.table_restaurant_outlined,
            permission: 'table:manage',
            description: '对齐旧工程 table/List.vue：桌台列表、状态、开台、并台、转台、清台。',
            client: client,
            actions: [
              const ApiModuleAction(label: '桌台列表', endpoint: tableListEndpoint),
              const ApiModuleAction(
                label: '新增桌台',
                endpoint: tableAddEndpoint,
                defaultBody: {'table_number': '', 'people_count': 4},
              ),
              const ApiModuleAction(
                label: '删除桌台',
                endpoint: tableDeleteEndpoint,
                defaultQuery: {'id': ''},
              ),
              const ApiModuleAction(
                label: '桌台出清',
                endpoint: tableOutEndpoint,
                defaultQuery: {'id': ''},
              ),
              const ApiModuleAction(
                label: '桌台状态',
                endpoint: tableStatusEndpoint,
              ),
            ],
          ),
          _module(
            title: '外卖配送',
            icon: Icons.delivery_dining_outlined,
            permission: 'order:view',
            description: '对齐旧工程 takeout/Index.vue：外卖配置、配送列表、履约状态、骑手轨迹、真省钱操作。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '配送列表',
                endpoint: takeoutDeliveryListEndpoint,
              ),
              const ApiModuleAction(
                label: '配送详情',
                endpoint: takeoutDeliveryDetailEndpoint,
                defaultQuery: {'id': ''},
              ),
              const ApiModuleAction(
                label: '骑手轨迹',
                endpoint: takeoutDeliveryTrackingEndpoint,
                defaultQuery: {'id': ''},
              ),
              const ApiModuleAction(
                label: '改配送状态',
                endpoint: takeoutDeliveryStatusEndpoint,
                defaultBody: {'id': 0, 'status': ''},
              ),
              const ApiModuleAction(
                label: '真省钱发配送',
                endpoint: takeoutZsqDispatchEndpoint,
                defaultBody: {'delivery_id': 0},
              ),
              const ApiModuleAction(
                label: '重新发配送',
                endpoint: takeoutZsqRedispatchEndpoint,
                defaultBody: {'delivery_id': 0},
              ),
              const ApiModuleAction(
                label: '同步配送',
                endpoint: takeoutZsqSyncEndpoint,
                defaultBody: {'delivery_id': 0},
              ),
              const ApiModuleAction(
                label: '外卖配置',
                endpoint: takeoutConfigEndpoint,
              ),
              const ApiModuleAction(
                label: '保存外卖配置',
                endpoint: takeoutConfigSaveEndpoint,
                defaultBody: {
                  'enabled': true,
                  'min_order_amount': 68,
                  'delivery_fee': 5,
                },
              ),
            ],
          ),
          ShellPage(
            title: '厨显 KDS',
            icon: Icons.monitor_outlined,
            requiredPermission: 'kds:config',
            builder: (_) => RealtimePage(
              key: ValueKey('realtime-${appState.currentShopId}'),
              appState: appState,
              repository: RealtimeRepository(client),
            ),
          ),
        ],
      ),
      ShellPageGroup(
        title: '商品菜单',
        icon: Icons.restaurant_menu_outlined,
        pages: [
          _module(
            title: '类目管理',
            icon: Icons.folder_outlined,
            permission: 'dish:manage',
            description: '对齐旧工程 category/List.vue：分类列表、新增、编辑、删除、排序。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '类目列表',
                endpoint: categoryListEndpoint,
              ),
              const ApiModuleAction(
                label: '全部类目',
                endpoint: categoryListAllEndpoint,
              ),
              const ApiModuleAction(
                label: '新增类目',
                endpoint: categoryAddEndpoint,
                defaultBody: {'name': '', 'sort': 0},
              ),
              const ApiModuleAction(
                label: '更新类目',
                endpoint: categoryUpdateEndpoint,
                defaultBody: {'id': 0, 'name': '', 'sort': 0},
              ),
              const ApiModuleAction(
                label: '删除类目',
                endpoint: categoryDeleteEndpoint,
                defaultQuery: {'id': ''},
              ),
              const ApiModuleAction(
                label: '类目排序',
                endpoint: categorySortEndpoint,
                defaultBody: {'ids': []},
              ),
            ],
          ),
          ShellPage(
            title: '菜品管理',
            icon: Icons.ramen_dining_outlined,
            requiredPermission: 'dish:manage',
            builder: (_) => CatalogFinancePage(
              key: ValueKey('catalog-${appState.currentShopId}'),
              appState: appState,
              repository: RealCatalogRepository(client),
              reportRepository: reportRepository,
            ),
          ),
          ShellPage(
            title: 'AI配餐画像',
            icon: Icons.auto_awesome_outlined,
            requiredPermission: 'dish:manage',
            builder: (_) => DishAiProfilesPage(
              key: ValueKey('ai-profiles-${appState.currentShopId}'),
              appState: appState,
              repository: RealDishAiProfileRepository(client),
            ),
          ),
          _module(
            title: '菜品维护',
            icon: Icons.edit_note_outlined,
            permission: 'dish:manage',
            description: '对齐 OpenAPI 菜品维护：分页、总部模板导入、保存、删除、排序、上下架与售罄。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '菜品分页',
                endpoint: dishListEndpoint,
                defaultBody: {'pageNum': 1, 'pageSize': 20},
              ),
              const ApiModuleAction(
                label: '总部模板',
                endpoint: dishHqTemplateListEndpoint,
                defaultBody: {'pageNum': 1, 'pageSize': 20},
              ),
              const ApiModuleAction(
                label: '导入总部菜',
                endpoint: dishImportFromHqEndpoint,
                defaultBody: {'dishIds': []},
              ),
              const ApiModuleAction(
                label: '保存菜品',
                endpoint: dishSaveEndpoint,
                defaultBody: {'name': '', 'category_id': 0, 'unitprice': 0},
              ),
              const ApiModuleAction(
                label: '删除菜品',
                endpoint: dishDeleteEndpoint,
                defaultQuery: {'id': ''},
              ),
              const ApiModuleAction(
                label: '菜品排序',
                endpoint: dishSortEndpoint,
                defaultBody: {'ids': []},
              ),
              const ApiModuleAction(
                label: '上下架',
                endpoint: dishUpdateOnSaleEndpoint,
                defaultBody: {'id': 0, 'onsale': true},
              ),
              const ApiModuleAction(
                label: '售罄状态',
                endpoint: dishUpdateSaleStatusEndpoint,
                defaultBody: {'id': 0, 'sold_out': false},
              ),
            ],
          ),
          _module(
            title: '套餐管理',
            icon: Icons.set_meal_outlined,
            permission: 'dish:manage',
            description: '对齐旧工程 combo/Index.vue：套餐定义、固定项、可选分组、价格计算。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '按菜品查套餐',
                endpoint: comboByDishEndpoint,
                defaultQuery: {'dishId': ''},
              ),
              const ApiModuleAction(
                label: '保存套餐',
                endpoint: comboSaveEndpoint,
                defaultBody: {
                  'dish_id': 0,
                  'definition': {'fixedItems': [], 'groups': []},
                },
              ),
            ],
          ),
          _module(
            title: '单位管理',
            icon: Icons.grid_view_outlined,
            permission: 'dish:manage',
            description: '对齐旧工程 unit/List.vue：单位列表、新增和维护。',
            client: client,
            actions: [
              const ApiModuleAction(label: '单位列表', endpoint: unitListEndpoint),
              const ApiModuleAction(
                label: '新增单位',
                endpoint: unitAddEndpoint,
                defaultBody: {'unit': ''},
              ),
            ],
          ),
        ],
      ),
      ShellPageGroup(
        title: '门店营销',
        icon: Icons.storefront_outlined,
        pages: [
          _module(
            title: '门店管理',
            icon: Icons.store_outlined,
            permission: 'shop:manage',
            permissionOr: 'announcement:manage',
            description: '对齐旧工程 shop/List.vue：门店列表、新增、编辑、编码、经纬度、营业时间。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '门店列表',
                endpoint: adminShopListEndpoint,
              ),
              const ApiModuleAction(
                label: '保存门店',
                endpoint: adminShopSaveEndpoint,
                defaultBody: {
                  'id': null,
                  'name': '',
                  'code': '',
                  'address': '',
                  'latitude': '',
                  'longitude': '',
                },
              ),
            ],
          ),
          _module(
            title: '轮播图',
            icon: Icons.image_outlined,
            permission: 'banner:manage',
            description: '对齐旧工程 activity/List.vue：轮播图、活动弹窗、门店适用范围。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '轮播列表',
                endpoint: activityListEndpoint,
              ),
              const ApiModuleAction(
                label: '新增轮播',
                endpoint: activityAddEndpoint,
                defaultBody: {'image': '', 'url': '', 'sort': 0},
              ),
              const ApiModuleAction(
                label: '公告列表',
                endpoint: announcementListEndpoint,
              ),
              const ApiModuleAction(
                label: '公告详情',
                endpoint: announcementGetEndpoint,
                defaultQuery: {'id': ''},
              ),
              const ApiModuleAction(
                label: '新增公告',
                endpoint: announcementAddEndpoint,
                defaultBody: {'title': '', 'content': '', 'enabled': true},
              ),
              const ApiModuleAction(
                label: '更新公告',
                endpoint: announcementUpdateEndpoint,
                defaultBody: {'id': 0, 'title': '', 'content': ''},
              ),
              const ApiModuleAction(
                label: '删除公告',
                endpoint: announcementDeleteEndpoint,
                defaultQuery: {'id': ''},
              ),
            ],
          ),
          _module(
            title: '优惠券',
            icon: Icons.confirmation_number_outlined,
            permission: 'coupon:manage',
            description: '对齐旧工程 coupon/List.vue：券模板、发券、批量发券、券码、用户券。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '优惠券列表',
                endpoint: couponListEndpoint,
              ),
              const ApiModuleAction(
                label: '优惠券详情',
                endpoint: couponGetEndpoint,
                defaultQuery: {'id': ''},
              ),
              const ApiModuleAction(
                label: '新增优惠券',
                endpoint: couponAddEndpoint,
                defaultBody: {'name': '', 'type': '', 'amount': 0},
              ),
              const ApiModuleAction(
                label: '更新优惠券',
                endpoint: couponUpdateEndpoint,
                defaultBody: {'id': 0, 'name': '', 'type': '', 'amount': 0},
              ),
              const ApiModuleAction(
                label: '删除优惠券',
                endpoint: couponDeleteEndpoint,
                defaultQuery: {'id': ''},
              ),
              const ApiModuleAction(
                label: '券码列表',
                endpoint: couponRedeemCodeListEndpoint,
              ),
              const ApiModuleAction(
                label: '生成券码',
                endpoint: couponRedeemCodeCreateEndpoint,
                defaultBody: {'coupon_id': 0, 'count': 1},
              ),
              const ApiModuleAction(
                label: '用户券列表',
                endpoint: couponUserCouponListEndpoint,
              ),
              const ApiModuleAction(
                label: '发用户券',
                endpoint: couponUserCouponGrantEndpoint,
                defaultBody: {'coupon_id': 0, 'openid': ''},
              ),
              const ApiModuleAction(
                label: '批量发券',
                endpoint: couponBatchSendEndpoint,
                defaultBody: {'coupon_id': 0, 'openids': []},
              ),
            ],
          ),
        ],
      ),
      ShellPageGroup(
        title: '数据财务',
        icon: Icons.analytics_outlined,
        pages: [
          _module(
            title: '日结对账',
            icon: Icons.fact_check_outlined,
            permission: 'daily:settle',
            description: '对齐旧工程 daily/Index.vue：日结提交、收入明细、渠道对账、毛利统计。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '日结汇总',
                endpoint: dailySummaryEndpoint,
              ),
              const ApiModuleAction(
                label: '执行日结',
                endpoint: dailySettleEndpoint,
                defaultBody: {'stat_date': ''},
              ),
              const ApiModuleAction(
                label: '收入明细',
                endpoint: dailyIncomeEndpoint,
              ),
              const ApiModuleAction(
                label: '渠道对账',
                endpoint: dailyByChannelEndpoint,
              ),
              const ApiModuleAction(
                label: '毛利统计',
                endpoint: dailyGrossProfitEndpoint,
              ),
            ],
          ),
          ShellPage(
            title: '数据分析',
            icon: Icons.query_stats_outlined,
            requiredPermission: 'statistics:view',
            builder: (_) => DashboardPage(
              key: ValueKey('dashboard-${appState.currentShopId}'),
              appState: appState,
              repository: reportRepository,
            ),
          ),
          _module(
            title: '智能备货',
            icon: Icons.trending_up_outlined,
            permission: 'material:manage',
            permissionOr: 'statistics:view',
            description: '对齐旧工程 stockPrep/Index.vue：BOM、配置、备货计划、预测结果、校验。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: 'BOM 列表',
                endpoint: stockPrepBomListEndpoint,
              ),
              const ApiModuleAction(
                label: '保存 BOM',
                endpoint: stockPrepBomSaveEndpoint,
                defaultBody: {'dish_id': 0, 'items': []},
              ),
              const ApiModuleAction(
                label: '备货配置',
                endpoint: stockPrepConfigEndpoint,
              ),
              const ApiModuleAction(
                label: '保存配置',
                endpoint: stockPrepConfigSaveEndpoint,
                defaultBody: {'enabled': true},
              ),
              const ApiModuleAction(
                label: '生成计划',
                endpoint: stockPrepPlanGenerateEndpoint,
                defaultBody: {'date': ''},
              ),
              const ApiModuleAction(
                label: '备货计划',
                endpoint: stockPrepPlanEndpoint,
              ),
            ],
          ),
          _module(
            title: '库存成本',
            icon: Icons.inventory_2_outlined,
            permission: 'material:manage',
            description: '对齐旧工程 material/List.vue：原材料、入库、出库、库存预警、成本报表。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '原材料列表',
                endpoint: materialListEndpoint,
              ),
              const ApiModuleAction(
                label: '保存原材料',
                endpoint: materialSaveEndpoint,
                defaultBody: {
                  'id': null,
                  'name': '',
                  'unit': '',
                  'safe_stock': 0,
                },
              ),
              const ApiModuleAction(
                label: '入库',
                endpoint: materialInboundEndpoint,
                defaultBody: {'material_id': 0, 'quantity': 0, 'unit_cost': 0},
              ),
              const ApiModuleAction(
                label: '出库',
                endpoint: materialOutboundEndpoint,
                defaultBody: {'material_id': 0, 'quantity': 0, 'reason': ''},
              ),
              const ApiModuleAction(
                label: '库存预警',
                endpoint: materialAlertEndpoint,
              ),
              const ApiModuleAction(
                label: '库存报表',
                endpoint: reportInventoryEndpoint,
              ),
            ],
          ),
          _module(
            title: '经营报表',
            icon: Icons.assessment_outlined,
            permission: 'report:view',
            permissionOr: 'statistics:view',
            description: '对齐 OpenAPI 数据报表：日报、周报、月报、菜品排行、收银员业绩、门店利润。',
            client: client,
            actions: [
              const ApiModuleAction(label: '日报', endpoint: reportDailyEndpoint),
              const ApiModuleAction(
                label: '周报',
                endpoint: reportWeeklyEndpoint,
              ),
              const ApiModuleAction(
                label: '月报',
                endpoint: reportMonthlyEndpoint,
              ),
              const ApiModuleAction(
                label: '菜品排行',
                endpoint: reportDishRankingEndpoint,
              ),
              const ApiModuleAction(
                label: '收银员业绩',
                endpoint: reportCashierPerformanceEndpoint,
              ),
              const ApiModuleAction(
                label: '门店利润',
                endpoint: reportShopProfitEndpoint,
              ),
              const ApiModuleAction(
                label: '充值流水',
                endpoint: memberRechargeEndpoint,
              ),
            ],
          ),
          _module(
            title: '分析洞察',
            icon: Icons.auto_graph_outlined,
            permission: 'statistics:view',
            description: '营业、趋势、菜品、顾客、会员与营销数据分析。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '营业分析',
                endpoint: analyticsBusinessEndpoint,
              ),
              const ApiModuleAction(
                label: '营业趋势',
                endpoint: analyticsBusinessTrendEndpoint,
              ),
              const ApiModuleAction(
                label: '菜品分析',
                endpoint: analyticsDishesEndpoint,
              ),
              const ApiModuleAction(
                label: '顾客分析',
                endpoint: analyticsCustomersEndpoint,
              ),
              const ApiModuleAction(
                label: '会员分析',
                endpoint: analyticsMembersEndpoint,
              ),
              const ApiModuleAction(
                label: '营销分析',
                endpoint: analyticsMarketingEndpoint,
              ),
            ],
          ),
        ],
      ),
      ShellPageGroup(
        title: '功能设置',
        icon: Icons.settings_outlined,
        pages: [
          _module(
            title: '开关与规则',
            icon: Icons.tune_outlined,
            permission: 'order:view',
            permissionOr: 'order:config',
            description: '对齐旧工程 settings/Index.vue：营业规则、邀请、外卖、真省钱自动 API。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '营业状态',
                endpoint: settingsBusinessEndpoint,
              ),
              const ApiModuleAction(
                label: '切换营业',
                endpoint: settingsChangeBusinessEndpoint,
                defaultBody: {'bus': '1'},
              ),
              const ApiModuleAction(
                label: '自动接单',
                endpoint: orderAutoAcceptGetEndpoint,
              ),
              const ApiModuleAction(
                label: '保存自动接单',
                endpoint: orderAutoAcceptSaveEndpoint,
                defaultBody: {'enabled': true},
              ),
              const ApiModuleAction(
                label: '外卖配置',
                endpoint: takeoutConfigEndpoint,
              ),
              const ApiModuleAction(
                label: '保存外卖配置',
                endpoint: takeoutConfigSaveEndpoint,
                defaultBody: {'enabled': true},
              ),
            ],
          ),
          _module(
            title: '支付方式',
            icon: Icons.credit_card_outlined,
            permission: 'payment:config:read',
            description: '对齐旧工程 payment/List.vue：支付方式、商户配置、私钥上传、线下收款码。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '支付能力',
                endpoint: paymentCapabilitiesEndpoint,
              ),
              const ApiModuleAction(
                label: '保存支付能力',
                endpoint: paymentCapabilitiesSaveEndpoint,
                defaultBody: {
                  'clients': {
                    'cashier': {
                      'enabled': true,
                      'channelStates': {
                        'wechat': {'enabled': true},
                        'alipay': {'enabled': true},
                        'balance': {'enabled': true},
                        'combined': {'enabled': false},
                        'wechat_qr': {'enabled': true},
                        'alipay_qr': {'enabled': false},
                      },
                    },
                    'miniProgram': {
                      'enabled': true,
                      'channelStates': {
                        'wechat': {'enabled': true},
                        'balance': {'enabled': true},
                        'alipay': {'enabled': false},
                      },
                    },
                  },
                },
              ),
              const ApiModuleAction(
                label: '夜间九折',
                endpoint: paymentNinefoldEndpoint,
              ),
              const ApiModuleAction(
                label: '保存九折',
                endpoint: paymentNinefoldSaveEndpoint,
                defaultBody: {'enabled': false},
              ),
              const ApiModuleAction(
                label: '支付商户',
                endpoint: paymentMerchantsEndpoint,
              ),
              const ApiModuleAction(
                label: '保存商户',
                endpoint: paymentMerchantSaveEndpoint,
                defaultBody: {'channel': 'wechat', 'enabled': true},
              ),
              const ApiModuleAction(
                label: '微信鉴权审计',
                endpoint: paymentWechatAuditEndpoint,
              ),
            ],
          ),
          ShellPage(
            title: '用户查询',
            icon: Icons.people_alt_outlined,
            requiredPermission: 'user:view',
            builder: (_) => UserListPage(
              key: ValueKey('users-${appState.currentShopId}'),
              appState: appState,
              repository: RealUserRepository(client),
              initialQuery: const UserQuery(pageNum: 1, pageSize: 20),
            ),
          ),
          ShellPage(
            title: '挂账管理',
            icon: Icons.account_balance_wallet_outlined,
            requiredPermission: 'receivable:view',
            permissionOr: 'admin:super',
            builder: (_) => ReceivableManagementPage(
              key: ValueKey('receivables-${appState.currentShopId}'),
              client: client,
              permissions: appState.permissions,
              currentShopId: appState.currentShopId,
            ),
          ),
          _module(
            title: '会员运营',
            icon: Icons.card_membership_outlined,
            permission: 'user:view',
            permissionOr: 'user:points',
            description: '对齐 OpenAPI 会员营销：资料、消费、充值、扣余额与充值流水。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '会员画像',
                endpoint: memberProfileEndpoint,
                defaultQuery: {'openid': ''},
              ),
              const ApiModuleAction(
                label: '消费记录',
                endpoint: memberConsumptionEndpoint,
                defaultQuery: {'openid': ''},
              ),
              const ApiModuleAction(
                label: '充值流水',
                endpoint: memberRechargeEndpoint,
              ),
              const ApiModuleAction(
                label: '后台充值',
                endpoint: memberRechargeCreateEndpoint,
                defaultBody: {'openid': '', 'amount': 50, 'gift_amount': 0},
              ),
              const ApiModuleAction(
                label: '扣减余额',
                endpoint: memberBalanceDeductEndpoint,
                defaultBody: {'openid': '', 'amount': 0, 'reason': ''},
              ),
            ],
          ),
          _module(
            title: '操作日志',
            icon: Icons.article_outlined,
            permission: 'log:view',
            description: '对齐旧工程 log/Operation.vue：关键操作、订单日志、外卖异常、KDS 操作日志。',
            client: client,
            actions: [
              const ApiModuleAction(
                label: '操作日志',
                endpoint: operationLogEndpoint,
              ),
              const ApiModuleAction(
                label: '订单日志',
                endpoint: orderLogEndpoint,
                defaultQuery: {'orderId': ''},
              ),
            ],
          ),
          ShellPage(
            title: '员工管理',
            icon: Icons.badge_outlined,
            requiredPermission: 'admin:manage',
            builder: (_) => EmployeeListView(
              key: ValueKey('employees-${appState.currentShopId}'),
              appState: appState,
              client: client,
            ),
          ),
          _module(
            title: '权限管理',
            icon: Icons.lock_outline,
            permission: 'admin:manage',
            description: '对齐旧工程 permission/Index.vue：管理员、角色、权限码、API 权限映射。',
            client: client,
            actions: [
              const ApiModuleAction(label: '角色列表', endpoint: rbacRolesEndpoint),
              const ApiModuleAction(
                label: '保存角色',
                endpoint: rbacRolesSaveEndpoint,
                defaultBody: {'roleCode': '', 'roleName': ''},
              ),
              const ApiModuleAction(
                label: '权限列表',
                endpoint: rbacPermissionsEndpoint,
              ),
              const ApiModuleAction(
                label: '保存权限',
                endpoint: rbacPermissionsSaveEndpoint,
                defaultBody: {'permissionCode': '', 'permissionName': ''},
              ),
              const ApiModuleAction(
                label: 'API 权限',
                endpoint: rbacApiPermissionsEndpoint,
              ),
              const ApiModuleAction(
                label: '保存 API 权限',
                endpoint: rbacApiPermissionsSaveEndpoint,
                defaultBody: {'pathPattern': '', 'permissionCode': ''},
              ),
              const ApiModuleAction(
                label: '管理员列表',
                endpoint: adminAdministratorListEndpoint,
              ),
              const ApiModuleAction(
                label: '创建管理员',
                endpoint: adminAdministratorCreateEndpoint,
                defaultBody: {'userName': '', 'password': ''},
              ),
            ],
          ),
          ShellPage(
            title: '设备管理',
            icon: Icons.devices_outlined,
            requiredPermission: 'kds:config',
            builder: (_) => KdsDevicesPage(
              key: ValueKey('kds-devices-${appState.currentShopId}'),
              appState: appState,
              client: client,
            ),
          ),
          _module(
            title: 'KDS 配置',
            icon: Icons.developer_board_outlined,
            permission: 'kds:config',
            description: '对齐 OpenAPI KDS Admin：档口、五屏初始化、绑屏、设备、门店模式与工单重推。',
            client: client,
            actions: [              const ApiModuleAction(
                label: 'KDS 配置',
                endpoint: kdsConfigEndpoint,
              ),
              const ApiModuleAction(
                label: '保存 KDS 配置',
                endpoint: kdsConfigSaveEndpoint,
                defaultBody: {'kds_mode': 'workflow'},
              ),
              const ApiModuleAction(
                label: '档口列表',
                endpoint: kdsStationListEndpoint,
              ),
              const ApiModuleAction(
                label: '保存档口',
                endpoint: kdsStationSaveEndpoint,
                defaultBody: {'name': '', 'screen': ''},
              ),
              const ApiModuleAction(
                label: '初始化五屏',
                endpoint: kdsStationInitFiveEndpoint,
              ),
              const ApiModuleAction(
                label: '设备列表',
                endpoint: kdsDeviceListEndpoint,
              ),
              const ApiModuleAction(
                label: '绑定设备',
                endpoint: kdsDeviceBindEndpoint,
                defaultBody: {'device_token': '', 'screen': ''},
              ),
              const ApiModuleAction(
                label: '绑屏列表',
                endpoint: kdsDishScreenListEndpoint,
              ),
              const ApiModuleAction(
                label: '保存绑屏',
                endpoint: kdsDishScreenBindEndpoint,
                defaultBody: {'dish_id': 0, 'screen': ''},
              ),
              const ApiModuleAction(
                label: '重推工单',
                endpoint: kdsTicketRepushEndpoint,
                defaultBody: {'order_no': ''},
              ),
            ],
          ),
        ],
      ),
    ];
  }

  ShellPage _module({
    required String title,
    required IconData icon,
    required String permission,
    required String description,
    required AdminApiClient client,
    required List<ApiModuleAction> actions,
    String? permissionOr,
  }) {
    return ShellPage(
      title: title,
      icon: icon,
      requiredPermission: permission,
      permissionOr: permissionOr,
      builder: (_) => ApiModulePage(
        key: ValueKey('$title-${appState.currentShopId}'),
        title: title,
        description: description,
        appState: appState,
        client: client,
        actions: actions,
      ),
    );
  }
}
