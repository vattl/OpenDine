library shop_core;

// Core
export 'src/core/admin_api_client.dart';
export 'src/core/api_contract.dart';
export 'src/core/api_debug_log.dart';
export 'src/core/app_config.dart';
export 'src/core/app_state.dart';
export 'src/core/display_mode.dart';
export 'src/core/formatters.dart';
export 'src/core/http_transport.dart';
export 'src/core/network_status_monitor.dart';
export 'src/core/responsive_design_viewport.dart';
export 'src/core/shop_summary.dart';

// Domain Models & Repositories
export 'src/shared/auth/domain/auth_models.dart';
export 'src/shared/auth/data/auth_repository.dart';
export 'src/shared/auth/data/cashier_account_storage.dart';

export 'src/shared/tables/domain/dining_table.dart';
export 'src/shared/tables/data/table_repository.dart';
export 'src/shared/tables/data/real_table_repository.dart';

export 'src/shared/orders/domain/admin_order.dart';
export 'src/shared/orders/domain/order_query.dart';
export 'src/shared/orders/data/order_repository.dart';
export 'src/shared/orders/data/real_order_repository.dart';

export 'src/shared/pos/domain/pos_models.dart';
export 'src/shared/pos/data/pos_repository.dart';
export 'src/shared/pos/data/real_pos_repository.dart';

export 'src/shared/cashier_member/domain/cashier_member.dart';
export 'src/shared/cashier_member/data/cashier_member_repository.dart';
export 'src/shared/cashier_member/data/real_cashier_member_repository.dart';

export 'src/shared/cashier_shift/domain/cashier_shift.dart';
export 'src/shared/cashier_shift/data/cashier_shift_repository.dart';
export 'src/shared/cashier_shift/data/real_cashier_shift_repository.dart';
export 'src/shared/reports/domain/dashboard_report.dart';
export 'src/shared/reports/data/report_repository.dart';

export 'src/shared/catalog/domain/catalog_models.dart';
export 'src/shared/catalog/data/catalog_repository.dart';
export 'src/shared/catalog/data/real_catalog_repository.dart';

