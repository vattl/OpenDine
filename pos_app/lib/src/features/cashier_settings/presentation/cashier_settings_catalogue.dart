import '../domain/cashier_settings.dart';
import 'cashier_settings_shared.dart';

/// Shared discoverability. Operations and the server still enforce permissions.
List<SettingsDestination> visibleSettingsDestinations(
  CashierSettingsOverview overview,
  Set<String> permissions,
) => [
  for (final destination in const [
    SettingsDestination.store,
    SettingsDestination.payment,
    SettingsDestination.receivable,
    SettingsDestination.delivery,
    SettingsDestination.marketing,
    SettingsDestination.coupon,
    SettingsDestination.inventory,
    SettingsDestination.employee,
    SettingsDestination.report,
    SettingsDestination.kds,
    SettingsDestination.printer,
    SettingsDestination.notification,
    SettingsDestination.log,
    SettingsDestination.version,
    SettingsDestination.apiConsole,
  ])
    if (switch (destination) {
      SettingsDestination.version => permissions.contains('admin:super'),
      SettingsDestination.receivable =>
        permissions.contains('receivable:view') ||
            permissions.contains('admin:manage') ||
            permissions.contains('admin:super'),
      SettingsDestination.kds ||
      SettingsDestination.delivery ||
      SettingsDestination.marketing => true,
      _ => overview.module(destination.backendModule)?.permitted != false,
    })
      destination,
];
