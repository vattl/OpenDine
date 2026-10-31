import 'package:flutter/material.dart';
import '../../api_debug/presentation/api_debug_console_page.dart';

import '../../../core/admin_api_client.dart';
import '../../auth/data/access_approval_repository.dart';
import '../../kds_local/runtime/cashier_kds_runtime.dart';
import '../../cashier_payment/data/cashier_payment_repository.dart';
import '../../cashier_payment/presentation/cashier_payment_config_page.dart';
import '../data/cashier_settings_repository.dart';
import 'cashier_settings_access_page.dart';
import 'cashier_settings_delivery_page.dart';
import 'cashier_settings_inventory_page.dart';
import 'cashier_settings_marketing_page.dart';
import 'cashier_settings_coupon_page.dart';
import 'cashier_settings_report_page.dart';
import 'cashier_settings_log_page.dart';
import 'cashier_settings_kds_page.dart';
import 'cashier_settings_notification_page.dart';
import 'cashier_settings_printer_page.dart';
import 'cashier_settings_prototype_pages.dart';
import 'cashier_settings_shared.dart';
import 'cashier_settings_store_page.dart';
import 'cashier_settings_version_page.dart';
import '../../receivable_management/presentation/receivable_management_page.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

class SettingsDetailPage extends StatefulWidget {
  const SettingsDetailPage({
    super.key,
    required this.repository,
    required this.paymentRepository,
    required this.destination,
    required this.storeName,
    required this.onBack,
    this.client,
    this.permissions = const {},
    this.currentShopId,
    this.onPasswordChanged,
    this.kdsRuntime,
    this.showBack = true,
  });
  final CashierSettingsRepository repository;
  final CashierPaymentRepository paymentRepository;
  final SettingsDestination destination;
  final String storeName;
  final VoidCallback onBack;

  /// 接口调试目的地所需的客户端与权限（原「更多」页迁移而来）。
  final AdminApiClient? client;
  final Set<String> permissions;
  final int? currentShopId;
  final VoidCallback? onPasswordChanged;
  final CashierKdsRuntime? kdsRuntime;
  final bool showBack;

  @override
  State<SettingsDetailPage> createState() => SettingsDetailPageState();
}

class SettingsDetailPageState extends State<SettingsDetailPage> {
  var _selectedSection = 0;
  var _isPageDirty = false;

  Future<bool>? _leaveDecision;

  Future<bool> confirmLeave() {
    return _leaveDecision ??= _confirmLeave().whenComplete(
      () => _leaveDecision = null,
    );
  }

  Future<bool> _confirmLeave() async {
    if (!_isPageDirty) return true;
    final leave = await showUnsavedChangesDialog(context);
      if (!mounted || leave != true) return false;
      _isPageDirty = false;
    return true;
  }

  Future<void> requestBack() async {
    if (await confirmLeave() && mounted) widget.onBack();
  }

  Future<void> _selectSection(int value) async {
    if (value == _selectedSection) return;
    if (!await confirmLeave() || !mounted) return;
    setState(() => _selectedSection = value);
  }

  @override
  Widget build(BuildContext context) {
    final sections = widget.destination.sections;
    // The workspace retains inactive tabs using Offstage + TickerMode.
    final active = TickerMode.of(context);
    return PopScope(
      canPop: !active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && active) requestBack();
      },
      child: Column(
    children: [
      Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: context.cashier.surface,
          border: Border(
            bottom: BorderSide(
              color: context.cashier.border)),
        ),
        child: Row(
              children: [
                if (widget.showBack)
                  IconButton(
                      key: const Key('settings-back'),
                    tooltip: '返回',
                    onPressed: requestBack,
                      icon: const Icon(Icons.arrow_back, size: 20),
                  ),
                Expanded(
                          child: Text(
                            widget.destination.label,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                Text(
                  '当前门店',
                              style: TextStyle(
                                fontSize: 12,
                    color: context.cashier.inkMuted,
                              ),
                            ),
                          ],
                        ),
                ),
          _SettingsTopNavigation(
                  sections: sections,
                  selectedIndex: _selectedSection,
                  onSelected: _selectSection,
                ),
                const Divider(height: 1),
                Expanded(child: KeyedSubtree(
              key: ValueKey(
                '${widget.destination.name}-${widget.currentShopId}-${sections[_selectedSection].id}',
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: _sectionBody(sections[_selectedSection]),
            ),
              ),
        ),
      ),
    ],
  ),
    );
  }

  Widget _sectionBody(SettingsSectionSpec section) {
    if (widget.destination == SettingsDestination.store) {
      return CashierSettingsStorePage(
        key: ValueKey('store-section-${section.id}'),
        repository: widget.repository,
        section: section,
        onDirtyChanged: (dirty) => _isPageDirty = dirty,
      );
    }
    if (widget.destination == SettingsDestination.printer) {
      return CashierSettingsPrinterPage(
        repository: widget.repository,
        section: section,
        onDirtyChanged: (dirty) => _isPageDirty = dirty,
      );
    }
    if (widget.destination == SettingsDestination.payment) {
      return CashierPaymentConfigPage(
        repository: widget.paymentRepository,
        permissions: widget.permissions,
        onDirtyChanged: (dirty) => _isPageDirty = dirty,
      );
    }
    if (widget.destination == SettingsDestination.employee) {
      return CashierSettingsAccessEvaluatePage(
        repository: widget.repository,
        section: section,
        approvalRepository: widget.client == null
            ? null
            : AccessApprovalRepository(widget.client!),
      );
    }
    if (widget.destination == SettingsDestination.marketing) {
      return CashierSettingsMarketingPage(
        key: ValueKey('marketing-section-${section.id}'),
        repository: widget.repository,
        client: widget.client,
        section: section,
        permissions: widget.permissions,
        onDirtyChanged: (dirty) => _isPageDirty = dirty,
      );
    }
    if (widget.destination == SettingsDestination.coupon) {
      return CashierSettingsCouponPage(
        key: ValueKey('coupon-section-${section.id}'),
        repository: widget.repository,
        client: widget.client,
        section: section,
      );
    }
    if (widget.destination == SettingsDestination.delivery) {
      return CashierSettingsDeliveryPage(
        key: ValueKey('delivery-section-${section.id}'),
        repository: widget.repository,
        section: section,
        onDirtyChanged: (dirty) => _isPageDirty = dirty,
      );
    }
    if (widget.destination == SettingsDestination.kds) {
      return CashierSettingsKdsPage(
        repository: widget.repository,
        section: section,
        client: widget.client,
        currentShopId: widget.currentShopId,
        kdsRuntime: widget.kdsRuntime,
        canManageKds:
            widget.permissions.contains('kds:config') ||
            widget.permissions.contains('admin:manage'),
      );
    }
    if (widget.destination == SettingsDestination.inventory) {
      return CashierSettingsInventoryPage(
        key: ValueKey('inventory-section-${section.id}'),
        repository: widget.repository,
        client: widget.client,
        section: section,
        permissions: widget.permissions,
      );
    }
    if (widget.destination == SettingsDestination.report) {
      return CashierSettingsReportPage(
        key: ValueKey('report-section-${section.id}'),
        client: widget.client,
        section: section,
        storeName: widget.storeName,
        currentShopId: widget.currentShopId,
      );
    }
    if (widget.destination == SettingsDestination.log) {
      return CashierSettingsLogPage(
        key: ValueKey('log-section-${section.id}'),
        client: widget.client,
        section: section,
        storeName: widget.storeName,
        currentShopId: widget.currentShopId,
        permissions: widget.permissions,
      );
    }
    if (widget.destination == SettingsDestination.version) {
      return CashierSettingsVersionPage(
        key: ValueKey('version-section-${section.id}'),
        client: widget.client,
        section: section,
        permissions: widget.permissions,
        currentShopId: widget.currentShopId,
      );
    }
    if (widget.destination == SettingsDestination.receivable) {
      return ReceivableManagementPage(
        key: ValueKey('receivable-section-${section.id}'),
        client: widget.client,
        permissions: widget.permissions,
        currentShopId: widget.currentShopId,
        section: section.id,
        onBack: widget.onBack,
      );
    }
    if (widget.destination == SettingsDestination.notification) {
      return CashierSettingsNotificationPage(
        key: ValueKey('notification-section-${section.id}'),
        repository: widget.repository,
        section: section,
        client: widget.client,
        currentShopId: widget.currentShopId,
        onDirtyChanged: (dirty) => _isPageDirty = dirty,
      );
    }
    if (widget.destination == SettingsDestination.apiConsole) {
      return ApiDebugConsolePage();
    }
    return SettingsReadOnlySection(
      repository: widget.repository,
      destination: widget.destination,
      section: section,
    );
  }
}

class _SettingsTopNavigation extends StatelessWidget {
  const _SettingsTopNavigation({
    required this.sections,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<SettingsSectionSpec> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.cashier.surface,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (var index = 0; index < sections.length; index++) ...[
            _SettingsNavigationItem(
              section: sections[index],
              selected: index == selectedIndex,
              onTap: () => onSelected(index),
              compact: true,
            ),
            if (index != sections.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    ),
  );
}

class _SettingsNavigationItem extends StatelessWidget {
  const _SettingsNavigationItem({
    required this.section,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final SettingsSectionSpec section;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final itemBg = selected
        ? (isDark ? context.cashier.selectedBackground : context.cashier.ink)
        : Colors.transparent;
    final itemFg = selected
        ? (isDark ? context.cashier.selected : Colors.white)
        : context.cashier.ink;
    final iconColor = selected
        ? (isDark ? context.cashier.selected : Colors.white)
        : context.cashier.inkMuted;

    return Material(
      color: itemBg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: Key('settings-section-${section.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 12),
          child: Row(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Icon(
                section.icon,
                size: 20,
                color: iconColor),
              const SizedBox(width: 10),
              Text(
                section.label,
                style: TextStyle(
                  color: itemFg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}