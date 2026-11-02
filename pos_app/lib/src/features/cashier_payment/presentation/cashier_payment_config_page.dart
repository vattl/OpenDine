import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/admin_api_client.dart';
import '../../cashier_shell/presentation/cashier_components.dart';
import '../../pos/presentation/pos_auth_dialog.dart';
import '../../pos/presentation/pos_notice_dialog.dart';
import '../data/cashier_payment_repository.dart';
import '../domain/cashier_payment_config.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';
import 'cashier_routing_rule_dialog.dart';
import 'cashier_routing_simulator_dialog.dart';

class CashierPaymentConfigPage extends StatefulWidget {
  const CashierPaymentConfigPage({
    super.key,
    required this.repository,
    this.permissions = const {},
    this.canEdit,
    this.onDirtyChanged,
  });

  final CashierPaymentRepository repository;
  final Set<String> permissions;
  final bool? canEdit;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<CashierPaymentConfigPage> createState() =>
      _CashierPaymentConfigPageState();
}

class _CashierPaymentConfigPageState extends State<CashierPaymentConfigPage> {
  CashierPaymentCapabilities? _capabilities;
  final Map<PaymentChannel, PaymentMerchantCollection> _merchants = {};
  bool _loading = true;
  bool _savingCapabilities = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<Object>([
        widget.repository.loadCapabilities(),
        widget.repository.loadMerchants(PaymentChannel.wechat),
        widget.repository.loadMerchants(PaymentChannel.alipay),
      ]);
      if (!mounted) return;
      setState(() {
        _capabilities = values[0] as CashierPaymentCapabilities;
        _merchants[PaymentChannel.wechat] =
            values[1] as PaymentMerchantCollection;
        _merchants[PaymentChannel.alipay] =
            values[2] as PaymentMerchantCollection;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _reloadMerchants(PaymentChannel channel) async {
    final value = await widget.repository.loadMerchants(channel);
    if (mounted) setState(() => _merchants[channel] = value);
  }

  Future<void> _saveCapabilities() async {
    final value = _capabilities;
    if (value == null || _savingCapabilities) return;
    final blocked = _unavailableAttempts(value);
    if (blocked.isNotEmpty) {
      await _showMessage(
        '以下渠道暂不可开启：\n${blocked.join('\n')}',
        error: true,
      );
      return;
    }
    setState(() => _savingCapabilities = true);
    try {
      final saved = await widget.repository.saveCapabilities(value);
      if (!mounted) return;
      setState(() {
        _capabilities = saved;
        _savingCapabilities = false;
      });
      await _showMessage('支付能力已保存');
      widget.onDirtyChanged?.call(false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingCapabilities = false);
      await _showMessage(_message(error), error: true);
    }
  }

  /// D015 本地预检：已开启的渠道若 available=false，保存前拦截并给出后端原因。
  List<String> _unavailableAttempts(CashierPaymentCapabilities value) {
    final blocked = <String>[];
    void check(PaymentTerminalCapabilities terminal, String terminalLabel) {
      final channels = <String, bool>{
        'wechat': terminal.wechat,
        'alipay': terminal.alipay,
        'balance': terminal.balance,
        'combined': terminal.combined,
        'wechat_qr': terminal.wechatQr,
        'alipay_qr': terminal.alipayQr,
      };
      for (final entry in channels.entries) {
        if (!entry.value) continue;
        final state = terminal.stateOf(entry.key);
        if (state != null && !state.available) {
          blocked.add(
            '$terminalLabel·${entry.key}${state.hint.isEmpty ? '' : '：${state.hint}'}',
          );
        }
      }
    }

    check(value.cashier, '收银端');
    check(value.miniProgram, '小程序端');
    return blocked;
  }

  Future<void> _addMerchant(PaymentChannel channel) async {
    final existingKeys = (_merchants[channel]?.owned ?? [])
        .map((m) => m.merchantKey)
        .toSet();
    final defaultKey = existingKeys.contains('default')
        ? (existingKeys.contains('small_amount') ? 'custom' : 'small_amount')
        : 'default';

    try {
      final form = await widget.repository.loadEditForm(
        channel,
        merchantKey: defaultKey == 'custom' ? 'merchant_custom' : defaultKey,
      );
      if (!mounted) return;
      final changed = await _showMerchantForm(
        form,
        existingMerchantKeys: existingKeys.toList(),
      );
      if (changed == true) {
        await _reloadMerchants(channel);
        if (mounted) {
          await _showMessage('商户配置已保存并立即生效');
        }
      }
    } catch (error) {
      if (mounted) await _showMessage(_message(error), error: true);
    }
  }

  Future<void> _editMerchant(PaymentMerchant merchant) async {
    if (merchant.readOnly || merchant.id == null) return;
    try {
      final form = await widget.repository.loadMerchant(merchant.id!);
      if (!mounted) return;
      final changed = await _showMerchantForm(form);
      if (changed == true) {
        await _reloadMerchants(merchant.channel);
        if (mounted) {
          await _showMessage('商户配置已保存并立即生效');
        }
      }
    } catch (error) {
      if (mounted) await _showMessage(_message(error), error: true);
    }
  }

  Future<bool?> _showMerchantForm(
    PaymentMerchantForm form, {
    List<String> existingMerchantKeys = const [],
  }) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => MerchantFormDialog(
      repository: widget.repository,
      initialValue: form,
      existingMerchantKeys: existingMerchantKeys,
    ),
  );

  Future<void> _deleteMerchant(PaymentMerchant merchant) async {
    if (merchant.readOnly || merchant.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteMerchantDialog(merchant: merchant),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await widget.repository.deleteMerchant(merchant.id!);
      if (!result.deleted) {
        throw const FormatException('服务端未确认删除');
      }
      await _reloadMerchants(merchant.channel);
    } catch (error) {
      if (mounted) await _showMessage(_message(error), error: true);
    }
  }

  Future<void> _showMessage(String message, {bool error = false}) {
    return showPosNotice(
      context,
      title: error ? '支付配置操作失败' : '支付配置已更新',
      message: message,
      tone: error ? PosNoticeTone.error : PosNoticeTone.success,
    );
  }

  bool get _canEditPaymentConfig {
    if (widget.canEdit != null) return widget.canEdit!;
    return widget.permissions.contains('payment:config:write') ||
        widget.permissions.contains('payment:manage') ||
        widget.permissions.contains('payment:config') ||
        widget.permissions.contains('admin:manage') ||
        widget.permissions.contains('shop:manage');
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.cashier.canvas,
    child: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _PageError(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const _PageHeading(),
                  const SizedBox(height: 20),
                  _CapabilitiesCard(
                    value: _capabilities!,
                    saving: _savingCapabilities,
                    onChanged: (value) {
                      setState(() => _capabilities = value);
                      widget.onDirtyChanged?.call(true);
                    },
                    onSave: _saveCapabilities,
                  ),
                  if (_canEditPaymentConfig) ...[
                    const SizedBox(height: 20),
                    for (final channel in PaymentChannel.values) ...[
                      _MerchantSection(
                        channel: channel,
                        value:
                            _merchants[channel] ??
                            const PaymentMerchantCollection(),
                        onAdd: () => _addMerchant(channel),
                        onEdit: _editMerchant,
                        onDelete: _deleteMerchant,
                      ),
                      const SizedBox(height: 20),
                    ],
                    _PaymentRoutingRulesCard(
                      key: const Key('cashier-routing-rules-card'),
                      repository: widget.repository,
                      merchants: _merchants,
                    ),
                    const SizedBox(height: 20),
                    _NotifyUrlsCard(repository: widget.repository),
                    const SizedBox(height: 20),
                    _PrivateKeyToolsCard(repository: widget.repository),
                  ],
                ],
              ),
            ),
    ),
  );
}

class _PageHeading extends StatelessWidget {
  const _PageHeading();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('支付配置', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(
        '分别管理收银端、小程序端支付能力与本店商户凭证',
        style: TextStyle(color: context.cashier.inkMuted, fontSize: 17),
      ),
    ],
  );
}

class _CapabilitiesCard extends StatelessWidget {
  const _CapabilitiesCard({
    required this.value,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  final CashierPaymentCapabilities value;
  final bool saving;
  final ValueChanged<CashierPaymentCapabilities> onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => CashierCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '支付能力',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
            ),
            if (value.inheritsGlobal)
              const CashierStatusBadge(
                label: '继承全店配置',
                variant: CashierStatusBadgeVariant.info,
              ),
            const SizedBox(width: 12),
            CashierActionButton(
              label: '保存开关',
              onPressed: onSave,
              busy: saving,
              minimumWidth: 138,
              height: 52,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          '收银端与小程序端的支付开关相互独立，请分别配置。',
          style: TextStyle(color: Color(0xFF667085)),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final children = [
              _TerminalPanel(
                title: '收银端',
                terminal: value.cashier,
                showAlipay: true,
                showCombined: true,
                showQrGroup: true,
                onChanged: (terminal) =>
                    onChanged(value.copyWith(cashier: terminal)),
              ),
              _TerminalPanel(
                title: '微信小程序端',
                terminal: value.miniProgram,
                showAlipay: true,
                showCombined: false,
                showQrGroup: false,
                footer: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    initialValue: value.disabledMessage,
                    decoration: const InputDecoration(
                      labelText: '线上支付关闭提示（C 端展示）',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (message) =>
                        onChanged(value.copyWith(disabledMessage: message)),
                  ),
                ),
                onChanged: (terminal) =>
                    onChanged(value.copyWith(miniProgram: terminal)),
              ),
            ];
            if (constraints.maxWidth < 860) {
              return Column(
                children: [
                  children.first,
                  const SizedBox(height: 16),
                  children.last,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children.first),
                const SizedBox(width: 16),
                Expanded(child: children.last),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _TerminalPanel extends StatelessWidget {
  const _TerminalPanel({
    required this.title,
    required this.terminal,
    required this.showAlipay,
    required this.showCombined,
    required this.showQrGroup,
    required this.onChanged,
    this.footer,
  });

  final String title;
  final PaymentTerminalCapabilities terminal;
  final bool showAlipay;
  final bool showCombined;
  final bool showQrGroup;
  final ValueChanged<PaymentTerminalCapabilities> onChanged;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.cashier.row,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.cashier.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CapabilitySwitch(
            title: title,
            subtitle: '终端总开关',
            value: terminal.enabled,
            onChanged: (value) => onChanged(terminal.copyWith(enabled: value)),
          ),
          const _GroupLabel('线上支付'),
          _ChannelTile(
            icon: Icons.chat_bubble_outline,
            iconColor: const Color(0xFF07C160),
            label: '微信',
            value: terminal.wechat,
            disabled: !(terminal.stateOf('wechat')?.available ?? true),
            hint: terminal.stateOf('wechat')?.hint ?? terminal.wechatReadyHint,
            onChanged: (value) => onChanged(terminal.copyWith(wechat: value)),
          ),
          if (showAlipay)
            _ChannelTile(
              icon: Icons.account_balance_wallet_outlined,
              iconColor: const Color(0xFF1677FF),
              label: '支付宝',
              value: terminal.alipay,
              disabled: !(terminal.stateOf('alipay')?.available ?? true),
              hint: terminal.stateOf('alipay')?.hint ?? '',
              onChanged: (value) => onChanged(terminal.copyWith(alipay: value)),
            ),
          _ChannelTile(
            icon: Icons.account_balance_outlined,
            iconColor: const Color(0xFF7B61FF),
            label: '余额',
            value: terminal.balance,
            disabled: !(terminal.stateOf('balance')?.available ?? true),
            hint: terminal.stateOf('balance')?.hint ?? '',
            onChanged: (value) => onChanged(terminal.copyWith(balance: value)),
          ),
          if (showCombined)
            _ChannelTile(
              icon: Icons.compare_arrows,
              iconColor: const Color(0xFFFA8C16),
              label: '组合支付',
              subtitle: '需至少两个基础渠道生效',
              value: terminal.combined,
              disabled: !(terminal.stateOf('combined')?.available ?? true),
              hint: terminal.stateOf('combined')?.hint ?? '',
              onChanged: (value) =>
                  onChanged(terminal.copyWith(combined: value)),
            ),
          if (showQrGroup) ...[
            const _GroupLabel('线下收款码'),
            _ChannelTile(
              icon: Icons.qr_code_2,
              iconColor: const Color(0xFF07C160),
              label: '微信收款码',
              subtitle: '线下个人码收款',
              value: terminal.wechatQr,
              disabled: !(terminal.stateOf('wechat_qr')?.available ?? true),
              hint: terminal.stateOf('wechat_qr')?.hint ?? '',
              onChanged: (value) =>
                  onChanged(terminal.copyWith(wechatQr: value)),
            ),
            _ChannelTile(
              icon: Icons.qr_code_2,
              iconColor: const Color(0xFF1677FF),
              label: '支付宝收款码',
              subtitle: '线下个人码收款',
              value: terminal.alipayQr,
              disabled: !(terminal.stateOf('alipay_qr')?.available ?? true),
              hint: terminal.stateOf('alipay_qr')?.hint ?? '',
              onChanged: (value) =>
                  onChanged(terminal.copyWith(alipayQr: value)),
            ),
          ],
          if (footer != null) footer!,
        ],
      ),
    ),
  );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.cashier.inkMuted,
      ),
    ),
  );
}

class _CapabilitySwitch extends StatelessWidget {
  const _CapabilitySwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      title,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
    ),
    subtitle: Text(subtitle),
    value: value,
    onChanged: onChanged,
  );
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle = '',
    this.disabled = false,
    this.hint = '',
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String subtitle;
  final bool disabled;
  final String hint;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    secondary: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: iconColor),
    ),
    title: Text(label, style: const TextStyle(fontSize: 17)),
    subtitle: hint.isNotEmpty
        ? Text(
            hint,
            style: const TextStyle(fontSize: 12, color: Color(0xFFB54708)),
          )
        : subtitle.isEmpty
        ? null
        : Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: context.cashier.inkMuted,
            ),
          ),
    value: value,
    onChanged: disabled ? null : onChanged,
  );
}

class _MerchantSection extends StatelessWidget {
  const _MerchantSection({
    required this.channel,
    required this.value,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final PaymentChannel channel;
  final PaymentMerchantCollection value;
  final VoidCallback onAdd;
  final ValueChanged<PaymentMerchant> onEdit;
  final ValueChanged<PaymentMerchant> onDelete;

  @override
  Widget build(BuildContext context) {
    final all = [...value.owned, ...value.inheritedTemplates];
    final defaults = all
        .where((merchant) => merchant.merchantKey == 'default')
        .toList();
    final defaultMerchant = defaults.isEmpty ? null : defaults.first;
    return CashierCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${channel.label}商户',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                CashierActionButton(
                  key: Key('cashier-merchant-add-${channel.code}'),
                  label: '新增商户',
                  icon: Icons.add,
                  onPressed: onAdd,
                  minimumWidth: 142,
                  height: 52,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                CashierStatusBadge(
                  label: '本店 ${value.owned.length} 条',
                  variant: CashierStatusBadgeVariant.neutral,
                ),
                if (value.inheritedTemplates.isNotEmpty)
                  CashierStatusBadge(
                    label: '继承全店 ${value.inheritedTemplates.length} 条',
                    variant: CashierStatusBadgeVariant.info,
                  ),
                if (defaultMerchant != null)
                  CashierStatusBadge(
                    label: defaultMerchant.payReady
                        ? 'default 支付就绪'
                        : 'default 未就绪',
                    variant: defaultMerchant.payReady
                        ? CashierStatusBadgeVariant.success
                        : CashierStatusBadgeVariant.warning,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (all.isEmpty)
            Padding(
              padding: const EdgeInsets.all(42),
              child: Text(
                '暂无商户配置',
                style: TextStyle(
                  color: context.cashier.inkMuted,
                  fontSize: 18,
                ),
              ),
            )
          else
            for (var index = 0; index < all.length; index++) ...[
              _MerchantRow(
                merchant: all[index],
                onEdit: () => onEdit(all[index]),
                onDelete: () => onDelete(all[index]),
              ),
              if (index != all.length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _MerchantRow extends StatelessWidget {
  const _MerchantRow({
    required this.merchant,
    required this.onEdit,
    required this.onDelete,
  });

  final PaymentMerchant merchant;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: merchant.channel == PaymentChannel.wechat
                ? const Color(0xffe8f8ef)
                : const Color(0xffeaf4ff),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            merchant.channel == PaymentChannel.wechat
                ? Icons.chat_bubble_outline
                : Icons.account_balance_wallet_outlined,
            color: context.cashier.ink,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    merchant.merchantKey.isEmpty
                        ? '未命名商户'
                        : merchant.merchantKey,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  CashierStatusBadge(
                    label: merchant.enabled ? '已启用' : '已停用',
                    variant: merchant.enabled
                        ? CashierStatusBadgeVariant.success
                        : CashierStatusBadgeVariant.neutral,
                  ),
                  if (merchant.readOnly)
                    const CashierStatusBadge(
                      label: '全店模板 · 只读',
                      variant: CashierStatusBadgeVariant.info,
                    ),
                  if (merchant.payReady)
                    const CashierStatusBadge(
                      label: '支付就绪',
                      variant: CashierStatusBadgeVariant.success,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (merchant.mchId.isNotEmpty) '商户号 ${merchant.mchId}',
                  if (merchant.appId.isNotEmpty) 'AppID ${merchant.appId}',
                  if (merchant.hasApiV3Key) 'APIv3 已配置',
                  if (merchant.hasApiV2Key) 'APIv2 已配置',
                  if (merchant.hasClientCertP12) 'P12 客户端证书已就绪',
                  if (merchant.hasPrivateKey) '私钥已就绪',
                  if (merchant.hasAlipayAppCert) '应用公钥证书已就绪',
                  if (merchant.hasAlipayPublicCert) '支付宝公钥证书已就绪',
                  if (merchant.hasAlipayRootCert) '根证书已就绪',
                ].join('  ·  '),
                style: TextStyle(
                  color: context.cashier.inkMuted,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        if (!merchant.readOnly) ...[
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('编辑'),
          ),
          if (merchant.enabled) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              key: merchant.id == null
                  ? null
                  : Key('cashier-payment-merchant-delete-${merchant.id}'),
              onPressed: onDelete,
              style: TextButton.styleFrom(
                foregroundColor: context.cashier.danger,
              ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除'),
            ),
          ],
        ],
      ],
    ),
  );
}

class _MerchantKeyDialog extends StatefulWidget {
  const _MerchantKeyDialog({required this.channel});

  final PaymentChannel channel;

  @override
  State<_MerchantKeyDialog> createState() => _MerchantKeyDialogState();
}

class _MerchantKeyDialogState extends State<_MerchantKeyDialog> {
  final _controller = TextEditingController(text: 'default');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CashierDialogFrame(
    title: '新增${widget.channel.label}商户',
    width: 660,
    height: 350,
    onClose: () => Navigator.pop(context),
    body: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: '商户实例键',
        helperText: '例如 default 或 small_amount',
        border: OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      CashierActionButton(
        label: '取消',
        variant: CashierActionButtonVariant.secondary,
        minimumWidth: 110,
        height: 52,
        onPressed: () => Navigator.pop(context),
      ),
      CashierActionButton(
        label: '继续',
        minimumWidth: 110,
        height: 52,
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
      ),
    ],
  );
}

/// 校验 PEM 私钥格式：排斥公钥与证书，确保包含 BEGIN PRIVATE KEY / BEGIN RSA PRIVATE KEY。
String? validatePemContent(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    return '私钥内容不能为空';
  }
  if (trimmed.contains('BEGIN CERTIFICATE') ||
      trimmed.contains('BEGIN PUBLIC KEY')) {
    return '检测到证书或公钥内容，请上传包含 BEGIN PRIVATE KEY 的商户私钥文件 (apiclient_key.pem)';
  }
  if (!trimmed.contains('PRIVATE KEY')) {
    return '私钥格式无效，必须包含 -----BEGIN PRIVATE KEY----- 或 -----BEGIN RSA PRIVATE KEY-----';
  }
  return null;
}

/// 微信支付平台公钥或 X.509 平台证书格式校验结果。
class PublicCertificateValidationResult {
  const PublicCertificateValidationResult({
    required this.materialType,
    this.error,
  });

  final String materialType;
  final String? error;

  bool get isValid => error == null;
}

/// 校验微信支付平台公钥或平台证书格式：排斥私钥，识别 PUBLIC KEY 与 CERTIFICATE。
PublicCertificateValidationResult validatePublicCertificateContent(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    return const PublicCertificateValidationResult(
      materialType: '',
      error: '公钥证书内容不能为空',
    );
  }
  if (trimmed.contains('BEGIN PRIVATE KEY') ||
      trimmed.contains('BEGIN RSA PRIVATE KEY')) {
    return const PublicCertificateValidationResult(
      materialType: '',
      error: '检测到私钥内容，此处仅允许上传微信支付平台公钥或 X.509 平台证书',
    );
  }
  if (trimmed.contains('BEGIN PUBLIC KEY') && trimmed.contains('END PUBLIC KEY')) {
    return const PublicCertificateValidationResult(
      materialType: 'PUBLIC_KEY',
    );
  }
  if (trimmed.contains('BEGIN CERTIFICATE') && trimmed.contains('END CERTIFICATE')) {
    return const PublicCertificateValidationResult(
      materialType: 'CERTIFICATE',
    );
  }
  return const PublicCertificateValidationResult(
    materialType: '',
    error: '文件不是有效的微信支付平台公钥或 X.509 平台证书（需包含 BEGIN PUBLIC KEY 或 BEGIN CERTIFICATE）',
  );
}

class _PastePrivateKeyDialog extends StatefulWidget {
  const _PastePrivateKeyDialog();

  @override
  State<_PastePrivateKeyDialog> createState() => _PastePrivateKeyDialogState();
}

class _PastePrivateKeyDialogState extends State<_PastePrivateKeyDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _controller.text.trim();
    final error = validatePemContent(text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => CashierDialogFrame(
    title: '粘贴微信 PEM 私钥内容',
    width: 660,
    height: 480,
    onClose: () => Navigator.pop(context),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '请将商户平台下载的 apiclient_key.pem 文本全部粘贴在下方（必须包含完整的 BEGIN/END PRIVATE KEY）：',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('cashier-merchant-paste-pk-input'),
          controller: _controller,
          maxLines: 8,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            hintText: '-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            key: const Key('cashier-merchant-paste-pk-error'),
            style: const TextStyle(color: Color(0xFFB42318), fontSize: 13),
          ),
        ],
      ],
    ),
    actions: [
      CashierActionButton(
        label: '取消',
        variant: CashierActionButtonVariant.secondary,
        minimumWidth: 110,
        height: 52,
        onPressed: () => Navigator.pop(context),
      ),
      CashierActionButton(
        key: const Key('cashier-merchant-paste-pk-confirm-btn'),
        label: '校验并应用',
        minimumWidth: 140,
        height: 52,
        onPressed: _confirm,
      ),
    ],
  );
}

class MerchantFormDialog extends StatefulWidget {
  const MerchantFormDialog({
    super.key,
    required this.repository,
    required this.initialValue,
    this.existingMerchantKeys = const [],
    this.pickFileOverride,
    this.pickCertFileOverride,
    this.pickP12FileOverride,
    this.pickAlipayCertOverride,
  });

  final CashierPaymentRepository repository;
  final PaymentMerchantForm initialValue;
  final List<String> existingMerchantKeys;
  final Future<PlatformFile?> Function()? pickFileOverride;
  final Future<PlatformFile?> Function()? pickCertFileOverride;
  final Future<PlatformFile?> Function()? pickP12FileOverride;
  final Future<PlatformFile?> Function(String type)? pickAlipayCertOverride;

  @override
  State<MerchantFormDialog> createState() => _MerchantFormDialogState();
}

class _MerchantFormDialogState extends State<MerchantFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  late final TextEditingController _customKeyController;
  late String _selectedKeyType;
  late bool _enabled;
  bool _busy = false;
  String? _error;

  Uint8List? _pendingPemBytes;
  String? _pendingPemName;
  String? _pendingPemText;
  bool _showAdvancedKeyRef = false;

  Uint8List? _pendingCertBytes;
  String? _pendingCertName;
  String? _pendingCertMaterialType;
  bool _showAdvancedPubKeyRef = false;

  Uint8List? _pendingP12Bytes;
  String? _pendingP12Name;
  bool _showAdvancedP12Ref = false;

  Uint8List? _pendingAlipayAppCertBytes;
  String? _pendingAlipayAppCertName;
  Uint8List? _pendingAlipayPublicCertBytes;
  String? _pendingAlipayPublicCertName;
  Uint8List? _pendingAlipayRootCertBytes;
  String? _pendingAlipayRootCertName;
  bool _showAdvancedAlipayRef = false;

  @override
  void initState() {
    super.initState();
    final value = widget.initialValue;
    _enabled = value.enabled;

    if (!value.exists) {
      final key = value.merchantKey;
      if (key == 'default' || key == 'small_amount') {
        _selectedKeyType = key;
        _customKeyController = TextEditingController();
      } else if (key.isNotEmpty) {
        _selectedKeyType = 'custom';
        _customKeyController = TextEditingController(text: key);
      } else {
        _selectedKeyType = 'default';
        _customKeyController = TextEditingController();
      }
    } else {
      _selectedKeyType = value.merchantKey;
      _customKeyController = TextEditingController();
    }

    _fields = {
      'appId': TextEditingController(text: value.appId),
      'mchId': TextEditingController(text: value.mchId),
      'notifyUrl': TextEditingController(text: value.notifyUrl),
      'refundNotifyUrl': TextEditingController(text: value.refundNotifyUrl),
      'apiV3Key': TextEditingController(),
      'apiV2Key': TextEditingController(),
      'privateKeyRef': TextEditingController(text: value.privateKeyRef),
      'clientCertP12Ref': TextEditingController(text: value.clientCertP12Ref),
      'platformPubKeyId': TextEditingController(text: value.platformPubKeyId),
      'platformPubKeyRef': TextEditingController(text: value.platformPubKeyRef),
      'serialNo': TextEditingController(text: value.serialNo),
      'alipayAppCertRef': TextEditingController(text: value.alipayAppCertRef),
      'alipayPublicCertRef': TextEditingController(text: value.alipayPublicCertRef),
      'alipayRootCertRef': TextEditingController(text: value.alipayRootCertRef),
      'routingRuleJson': TextEditingController(text: value.routingRuleJson),
      'sortOrder': TextEditingController(
        text: value.sortOrder > 0 ? '${value.sortOrder}' : '',
      ),
      'remark': TextEditingController(text: value.remark),
    };
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _customKeyController.dispose();
    super.dispose();
  }

  bool get _hasReadyPrivateKey =>
      _pendingPemBytes != null ||
      (_pendingPemText != null && _pendingPemText!.isNotEmpty) ||
      _fields['privateKeyRef']!.text.trim().isNotEmpty ||
      widget.initialValue.hasPrivateKey;

  bool get _hasReadyClientCertP12 =>
      _pendingP12Bytes != null ||
      (_fields['clientCertP12Ref']!.text.trim().isNotEmpty &&
          !_fields['clientCertP12Ref']!.text.startsWith('已选文件:') &&
          !_fields['clientCertP12Ref']!.text.startsWith('待上传：')) ||
      widget.initialValue.hasClientCertP12;

  bool get _hasReadyAlipayAppCert =>
      _pendingAlipayAppCertBytes != null ||
      (_fields['alipayAppCertRef']!.text.trim().isNotEmpty &&
          !_fields['alipayAppCertRef']!.text.startsWith('已选文件:')) ||
      widget.initialValue.hasAlipayAppCert;

  bool get _hasReadyAlipayPublicCert =>
      _pendingAlipayPublicCertBytes != null ||
      (_fields['alipayPublicCertRef']!.text.trim().isNotEmpty &&
          !_fields['alipayPublicCertRef']!.text.startsWith('已选文件:')) ||
      widget.initialValue.hasAlipayPublicCert;

  bool get _hasReadyAlipayRootCert =>
      _pendingAlipayRootCertBytes != null ||
      (_fields['alipayRootCertRef']!.text.trim().isNotEmpty &&
          !_fields['alipayRootCertRef']!.text.startsWith('已选文件:')) ||
      widget.initialValue.hasAlipayRootCert;

  Future<void> _pickPrivateKeyFile() async {
    try {
      PlatformFile? file;
      if (widget.pickFileOverride != null) {
        file = await widget.pickFileOverride!();
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pem', 'key', 'txt'],
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          file = result.files.single;
        }
      }
      if (file == null || !mounted) return;

      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        final ioFile = File(file.path!);
        if (await ioFile.exists()) {
          bytes = await ioFile.readAsBytes();
        }
      }
      if (bytes == null || bytes.isEmpty) {
        setState(() => _error = '无法读取所选私钥文件内容');
        return;
      }

      final content = utf8.decode(bytes, allowMalformed: true);
      final error = validatePemContent(content);
      if (error != null) {
        setState(() => _error = error);
        return;
      }

      setState(() {
        _pendingPemBytes = bytes;
        _pendingPemName = file!.name;
        _pendingPemText = null;
        _fields['privateKeyRef']!.text = '已选文件: ${file.name}（保存时自动上传）';
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '选择私钥文件失败: $e');
    }
  }

  Future<void> _pastePrivateKeyContent() async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _PastePrivateKeyDialog(),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() {
      _pendingPemText = text.trim();
      _pendingPemBytes = Uint8List.fromList(utf8.encode(text.trim()));
      _pendingPemName = '手动粘贴私钥 (${text.trim().length} 字符)';
      _fields['privateKeyRef']!.text = '已粘贴私钥文本（保存时自动上传）';
      _error = null;
    });
  }

  Future<void> _pickPublicCertificateFile() async {
    try {
      PlatformFile? file;
      if (widget.pickCertFileOverride != null) {
        file = await widget.pickCertFileOverride!();
      } else if (widget.pickFileOverride != null) {
        file = await widget.pickFileOverride!();
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pem', 'cer', 'crt', 'key', 'txt'],
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          file = result.files.single;
        }
      }
      if (file == null || !mounted) return;

      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        final ioFile = File(file.path!);
        if (await ioFile.exists()) {
          bytes = await ioFile.readAsBytes();
        }
      }
      if (bytes == null || bytes.isEmpty) {
        setState(() => _error = '无法读取所选公钥证书文件内容');
        return;
      }

      final content = utf8.decode(bytes, allowMalformed: true);
      final validation = validatePublicCertificateContent(content);
      if (!validation.isValid) {
        setState(() => _error = validation.error);
        return;
      }

      setState(() {
        _pendingCertBytes = bytes;
        _pendingCertName = file!.name;
        _pendingCertMaterialType = validation.materialType;
        _fields['platformPubKeyRef']!.text = '已选文件: ${file.name}（保存时自动上传）';
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '选择公钥证书文件失败: $e');
    }
  }

  Future<void> _pickClientCertP12File() async {
    try {
      PlatformFile? file;
      if (widget.pickP12FileOverride != null) {
        file = await widget.pickP12FileOverride!();
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['p12', 'pfx'],
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          file = result.files.single;
        }
      }
      if (file == null || !mounted) return;

      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        final ioFile = File(file.path!);
        if (await ioFile.exists()) {
          bytes = await ioFile.readAsBytes();
        }
      }
      if (bytes == null || bytes.isEmpty) {
        setState(() => _error = '无法读取所选客户端证书文件内容');
        return;
      }

      final validationError = validateClientCertP12Bytes(bytes);
      if (validationError != null) {
        setState(() => _error = validationError);
        return;
      }

      setState(() {
        _pendingP12Bytes = bytes;
        _pendingP12Name = file!.name;
        _fields['clientCertP12Ref']!.text = '已选文件: ${file.name}（保存时自动上传）';
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '选择客户端证书失败: $e');
    }
  }

  Future<void> _pickAlipayCertFile(String type) async {
    try {
      PlatformFile? file;
      if (widget.pickAlipayCertOverride != null) {
        file = await widget.pickAlipayCertOverride!(type);
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['crt', 'cer', 'pem', 'txt'],
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          file = result.files.single;
        }
      }
      if (file == null || !mounted) return;

      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        final ioFile = File(file.path!);
        if (await ioFile.exists()) {
          bytes = await ioFile.readAsBytes();
        }
      }
      if (bytes == null || bytes.isEmpty) {
        setState(() => _error = '无法读取所选证书文件内容');
        return;
      }

      setState(() {
        if (type == 'ALIPAY_APP_CERT') {
          _pendingAlipayAppCertBytes = bytes;
          _pendingAlipayAppCertName = file!.name;
          _fields['alipayAppCertRef']!.text = '已选文件: ${file.name}（保存时自动上传）';
        } else if (type == 'ALIPAY_PUBLIC_CERT') {
          _pendingAlipayPublicCertBytes = bytes;
          _pendingAlipayPublicCertName = file!.name;
          _fields['alipayPublicCertRef']!.text = '已选文件: ${file.name}（保存时自动上传）';
        } else if (type == 'ALIPAY_ROOT_CERT') {
          _pendingAlipayRootCertBytes = bytes;
          _pendingAlipayRootCertName = file!.name;
          _fields['alipayRootCertRef']!.text = '已选文件: ${file.name}（保存时自动上传）';
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '选择证书文件失败: $e');
    }
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final targetKey = widget.initialValue.exists
        ? widget.initialValue.merchantKey
        : (_selectedKeyType == 'custom'
            ? _customKeyController.text.trim()
            : _selectedKeyType);

    if (targetKey.isEmpty) {
      setState(() {
        _busy = false;
        _error = '请输入或选择商户实例键';
      });
      return;
    }

    try {
      String privateKeyRef = _text('privateKeyRef');
      if (privateKeyRef.startsWith('已选文件:') ||
          privateKeyRef.startsWith('已粘贴私钥')) {
        privateKeyRef = '';
      }

      // 如果选取了本地私钥或粘贴了私钥文本，先自动上传
      if (_pendingPemBytes != null ||
          (_pendingPemText != null && _pendingPemText!.isNotEmpty)) {
        final bytes = _pendingPemBytes ?? utf8.encode(_pendingPemText!);
        final filename =
            _pendingPemName != null && _pendingPemName!.endsWith('.pem')
                ? _pendingPemName!
                : 'merchant-$targetKey.pem';
        final uploadResult = await widget.repository.uploadWechatPrivateKey(
          pemBytes: bytes,
          filename: filename,
          merchantKey: targetKey,
        );
        privateKeyRef = uploadResult.privateKeyRef;
      }

      String clientCertP12Ref = _text('clientCertP12Ref');
      if (clientCertP12Ref.startsWith('已选文件:') ||
          clientCertP12Ref.startsWith('待上传：')) {
        clientCertP12Ref = '';
      }

      // 如果选取了本地 PKCS12 客户端证书，先自动上传
      if (_pendingP12Bytes != null && _pendingP12Bytes!.isNotEmpty) {
        final filename = _pendingP12Name != null &&
                (_pendingP12Name!.endsWith('.p12') ||
                    _pendingP12Name!.endsWith('.pfx'))
            ? _pendingP12Name!
            : 'wechat-$targetKey-apiclient-cert.p12';
        final uploadResult = await widget.repository.uploadCertificate(
          bytes: _pendingP12Bytes!,
          filename: filename,
          merchantKey: targetKey,
          type: 'CLIENT_CERT_P12',
        );
        clientCertP12Ref = uploadResult.fileRef;
        _fields['clientCertP12Ref']!.text = clientCertP12Ref;
      }

      String platformPubKeyRef = _text('platformPubKeyRef');
      if (platformPubKeyRef.startsWith('已选文件:') ||
          platformPubKeyRef.startsWith('待上传：')) {
        platformPubKeyRef = '';
      }

      // 如果选取了本地公钥证书，先自动上传
      if (_pendingCertBytes != null && _pendingCertBytes!.isNotEmpty) {
        final filename = _pendingCertName != null &&
                (_pendingCertName!.endsWith('.pem') ||
                 _pendingCertName!.endsWith('.cer') ||
                 _pendingCertName!.endsWith('.crt'))
            ? _pendingCertName!
            : 'wechat-$targetKey-platform-public.pem';
        final uploadResult = await widget.repository.uploadWechatPlatformPublicKey(
          pemBytes: _pendingCertBytes!,
          filename: filename,
          merchantKey: targetKey,
        );
        platformPubKeyRef = uploadResult.platformPubKeyRef;
        _fields['platformPubKeyRef']!.text = platformPubKeyRef;
      }

      String alipayAppCertRef = _text('alipayAppCertRef');
      if (alipayAppCertRef.startsWith('已选文件:')) alipayAppCertRef = '';
      if (_pendingAlipayAppCertBytes != null &&
          _pendingAlipayAppCertBytes!.isNotEmpty) {
        final filename =
            _pendingAlipayAppCertName ?? 'appCertPublicKey_$targetKey.crt';
        final res = await widget.repository.uploadCertificate(
          bytes: _pendingAlipayAppCertBytes!,
          filename: filename,
          merchantKey: targetKey,
          type: 'ALIPAY_APP_CERT',
        );
        alipayAppCertRef = res.fileRef;
        _fields['alipayAppCertRef']!.text = alipayAppCertRef;
      }

      String alipayPublicCertRef = _text('alipayPublicCertRef');
      if (alipayPublicCertRef.startsWith('已选文件:')) alipayPublicCertRef = '';
      if (_pendingAlipayPublicCertBytes != null &&
          _pendingAlipayPublicCertBytes!.isNotEmpty) {
        final filename =
            _pendingAlipayPublicCertName ?? 'alipayCertPublicKey_RSA2.crt';
        final res = await widget.repository.uploadCertificate(
          bytes: _pendingAlipayPublicCertBytes!,
          filename: filename,
          merchantKey: targetKey,
          type: 'ALIPAY_PUBLIC_CERT',
        );
        alipayPublicCertRef = res.fileRef;
        _fields['alipayPublicCertRef']!.text = alipayPublicCertRef;
      }

      String alipayRootCertRef = _text('alipayRootCertRef');
      if (alipayRootCertRef.startsWith('已选文件:')) alipayRootCertRef = '';
      if (_pendingAlipayRootCertBytes != null &&
          _pendingAlipayRootCertBytes!.isNotEmpty) {
        final filename =
            _pendingAlipayRootCertName ?? 'alipayRootCert.crt';
        final res = await widget.repository.uploadCertificate(
          bytes: _pendingAlipayRootCertBytes!,
          filename: filename,
          merchantKey: targetKey,
          type: 'ALIPAY_ROOT_CERT',
        );
        alipayRootCertRef = res.fileRef;
        _fields['alipayRootCertRef']!.text = alipayRootCertRef;
      }

      final initial = widget.initialValue;
      final sortOrderParsed =
          int.tryParse(_text('sortOrder')) ?? initial.sortOrder;
      final form = initial.copyWith(
        merchantKey: targetKey,
        enabled: _enabled,
        appId: _text('appId'),
        mchId: _text('mchId'),
        notifyUrl: _text('notifyUrl'),
        refundNotifyUrl: _text('refundNotifyUrl'),
        apiV3Key: _text('apiV3Key'),
        apiV2Key: _text('apiV2Key'),
        privateKeyRef: privateKeyRef,
        clientCertP12Ref: clientCertP12Ref,
        platformPubKeyId: _text('platformPubKeyId'),
        platformPubKeyRef: platformPubKeyRef,
        serialNo: _text('serialNo'),
        alipayAppCertRef: alipayAppCertRef,
        alipayPublicCertRef: alipayPublicCertRef,
        alipayRootCertRef: alipayRootCertRef,
        routingRuleJson: _text('routingRuleJson'),
        sortOrder: sortOrderParsed,
        remark: _text('remark'),
      );

      await widget.repository.saveMerchant(form);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _message(error);
      });
    }
  }

  String _text(String key) => _fields[key]!.text.trim();

  Widget _buildKeySelector() {
    final value = widget.initialValue;
    if (value.exists) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              value.merchantKey,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (value.hasApiV3Key)
              const CashierStatusBadge(
                label: 'APIv3 密钥已配置',
                variant: CashierStatusBadgeVariant.success,
              ),
            if (value.hasApiV2Key)
              const CashierStatusBadge(
                label: 'APIv2 密钥已配置',
                variant: CashierStatusBadgeVariant.success,
              ),
            if (value.hasClientCertP12)
              const CashierStatusBadge(
                label: 'P12 客户端证书已配置',
                variant: CashierStatusBadgeVariant.success,
              ),
            if (value.hasPrivateKey)
              const CashierStatusBadge(
                label: '私钥已配置',
                variant: CashierStatusBadgeVariant.success,
              ),
            if (value.hasAlipayAppCert)
              const CashierStatusBadge(
                label: '应用公钥证书已配置',
                variant: CashierStatusBadgeVariant.success,
              ),
            if (value.hasAlipayPublicCert)
              const CashierStatusBadge(
                label: '支付宝公钥已配置',
                variant: CashierStatusBadgeVariant.success,
              ),
            if (value.hasAlipayRootCert)
              const CashierStatusBadge(
                label: '支付宝根证书已配置',
                variant: CashierStatusBadgeVariant.success,
              ),
            if (value.payReady)
              const CashierStatusBadge(
                label: '支付就绪',
                variant: CashierStatusBadgeVariant.success,
              ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              const Text(
                '商户实例键 (merchantKey)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildKeyChip('default', 'default (默认主商户)'),
                  _buildKeyChip('small_amount', 'small_amount (小额专区)'),
                  _buildKeyChip('custom', '自定义键名...'),
                ],
              ),
            ],
          ),
          if (_selectedKeyType == 'custom') ...[
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('cashier-merchant-custom-key-input'),
              controller: _customKeyController,
              decoration: const InputDecoration(
                labelText: '自定义商户键',
                hintText: '例如 custom_pos 或 takeaway_mch',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? '请输入自定义商户键' : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKeyChip(String type, String label) {
    final active = _selectedKeyType == type;
    return ChoiceChip(
      key: Key('cashier-merchant-chip-$type'),
      label: Text(label),
      selected: active,
      selectedColor: const Color(0xFF0F172A),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: active ? Colors.white : const Color(0xFF475569),
      ),
      side: BorderSide(
        color: active ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedKeyType = type);
        }
      },
    );
  }

  Widget _buildPrivateKeyCard() {
    final hasPk = _hasReadyPrivateKey;
    final isWechat = widget.initialValue.channel == PaymentChannel.wechat;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.vpn_key_outlined, size: 18, color: Color(0xFF166534)),
              const SizedBox(width: 8),
              Text(
                isWechat
                    ? '商户私钥 (apiclient_key.pem) 直传'
                    : '应用私钥 (app_private_key.pem) 直传',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF166534),
                ),
              ),
              const Spacer(),
              Container(
                key: const Key('cashier-merchant-pk-status'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: hasPk ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasPk ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasPk ? const Color(0xFF22C55E) : const Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasPk ? '私钥已就绪' : '未配置私钥',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: hasPk ? const Color(0xFF15803D) : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                key: const Key('cashier-merchant-pick-pk-btn'),
                onPressed: _busy ? null : _pickPrivateKeyFile,
                icon: const Icon(Icons.folder_open, size: 16),
                label: Text(isWechat ? '选择私钥文件 (.pem)' : '选择应用私钥 (.pem)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('cashier-merchant-paste-pk-btn'),
                onPressed: _busy ? null : _pastePrivateKeyContent,
                icon: const Icon(Icons.paste_outlined, size: 16),
                label: const Text('粘贴私钥内容'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF166534),
                  side: const BorderSide(color: Color(0xFF86EFAC), width: 1.5),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              if (_pendingPemName != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_pendingPemName (已通过本地 BEGIN PRIVATE KEY 校验)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: Color(0xFF15803D),
                    ),
                  ),
                )
              else if (_fields['privateKeyRef']!.text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '已配置引用: ${_fields['privateKeyRef']!.text}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: Color(0xFF15803D),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isWechat
                ? '★ 微信支付 V3 请求签名必须项。直接选取商户平台下载的 apiclient_key.pem 即可，保存商户时系统自动无感上传并配置，保存立即生效！'
                : '★ 支付宝应用签名必须项。直接选取开放平台生成的应用私钥 PEM 文件，保存商户时系统自动无感上传配置。',
            style: const TextStyle(fontSize: 12, color: Color(0xFF15803D), height: 1.4),
          ),
          const SizedBox(height: 8),
          InkWell(
            key: const Key('cashier-merchant-pk-toggle-advanced'),
            onTap: () => setState(() => _showAdvancedKeyRef = !_showAdvancedKeyRef),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showAdvancedKeyRef ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16,
                    color: const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showAdvancedKeyRef ? '收起高级设置' : '高级设置：手动指定服务器私钥路径',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showAdvancedKeyRef) ...[
            const SizedBox(height: 8),
            _field('privateKeyRef', '商户私钥文件引用 / 服务器绝对路径'),
          ],
        ],
      ),
    );
  }

  Widget _buildClientCertP12Card() {
    final hasCert = _hasReadyClientCertP12;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF5FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8B4FE), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.security_outlined, size: 18, color: Color(0xFF6B21A8)),
              const SizedBox(width: 8),
              const Text(
                '客户端双向认证证书 (apiclient_cert.p12) 直传',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6B21A8),
                ),
              ),
              const Spacer(),
              Container(
                key: const Key('cashier-merchant-p12-status'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: hasCert ? const Color(0xFFF3E8FF) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasCert ? const Color(0xFFD8B4FE) : const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasCert ? const Color(0xFF9333EA) : const Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasCert ? '客户端证书已就绪' : '未配置客户端证书',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: hasCert ? const Color(0xFF7E22CE) : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                key: const Key('cashier-merchant-pick-p12-btn'),
                onPressed: _busy ? null : _pickClientCertP12File,
                icon: const Icon(Icons.file_present_outlined, size: 16),
                label: const Text('选择客户端证书 (.p12/.pfx)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9333EA),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              if (_pendingP12Name != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_pendingP12Name (PKCS12 校验通过 · 保存时自动上传)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: Color(0xFF7E22CE),
                    ),
                  ),
                )
              else if (_fields['clientCertP12Ref']!.text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '已配置引用: ${_fields['clientCertP12Ref']!.text}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: Color(0xFF7E22CE),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '★ 付款码 (Micropay) 刷卡支付与商户退款必须项。直接选取商户平台下载的 apiclient_cert.p12 二进制证书，保存商户时系统自动无感上传配置。',
            style: TextStyle(fontSize: 12, color: Color(0xFF7E22CE), height: 1.4),
          ),
          const SizedBox(height: 8),
          InkWell(
            key: const Key('cashier-merchant-p12-toggle-advanced'),
            onTap: () => setState(() => _showAdvancedP12Ref = !_showAdvancedP12Ref),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showAdvancedP12Ref ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16,
                    color: const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showAdvancedP12Ref ? '收起高级设置' : '高级设置：手动指定服务器证书路径',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showAdvancedP12Ref) ...[
            const SizedBox(height: 8),
            _field('clientCertP12Ref', '客户端证书文件引用 / 服务器绝对路径'),
          ],
        ],
      ),
    );
  }

  Widget _buildPublicCertificateCard() {
    final hasCert = _pendingCertBytes != null ||
        (_fields['platformPubKeyRef']!.text.trim().isNotEmpty &&
            !_fields['platformPubKeyRef']!.text.startsWith('已选文件:') &&
            !_fields['platformPubKeyRef']!.text.startsWith('待上传：')) ||
        widget.initialValue.platformPubKeyRef.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBAE6FD), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, size: 20, color: Color(0xFF0369A1)),
              const SizedBox(width: 8),
              const Text(
                '微信支付平台公钥证书',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0C4A6E),
                ),
              ),
              const Spacer(),
              Container(
                key: const Key('cashier-merchant-cert-status-badge'),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: hasCert ? Colors.white : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: hasCert ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasCert ? const Color(0xFF22C55E) : const Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasCert ? '公钥证书已就绪' : '待选择文件',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: hasCert ? const Color(0xFF15803D) : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                key: const Key('cashier-merchant-pick-cert-btn'),
                onPressed: _busy ? null : _pickPublicCertificateFile,
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: const Text('选择公钥证书'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0369A1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              if (_pendingCertName != null)
                Container(
                  key: const Key('cashier-merchant-cert-file-info'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_pendingCertName · ${_pendingCertMaterialType == 'CERTIFICATE' ? 'CERTIFICATE' : 'PUBLIC KEY'} 校验通过 · 保存时上传',
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Color(0xFF0369A1),
                    ),
                  ),
                )
              else if (_fields['platformPubKeyRef']!.text.isNotEmpty)
                Container(
                  key: const Key('cashier-merchant-cert-file-info'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '已配置引用: ${_fields['platformPubKeyRef']!.text}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Color(0xFF0369A1),
                    ),
                  ),
                )
              else
                Container(
                  key: const Key('cashier-merchant-cert-file-info'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '支持 .pem / .cer / .crt；PUBLIC KEY 或 CERTIFICATE',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 540;
              final pubIdWidget = _field(
                'platformPubKeyId',
                '微信支付平台公钥 ID',
                hint: '微信支付提供的 PUB_KEY_ID_...',
              );
              final previewRefText = _pendingCertName != null
                  ? '待上传：保存后自动回填服务器引用'
                  : (_fields['platformPubKeyRef']!.text.isEmpty
                      ? '保存时自动生成'
                      : _fields['platformPubKeyRef']!.text);
              final refPreviewWidget = Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  key: const Key('cashier-merchant-pubkey-ref-preview'),
                  readOnly: true,
                  controller: TextEditingController(text: previewRefText),
                  decoration: const InputDecoration(
                    labelText: '服务器引用',
                    hintText: '上传成功后自动回填，无需手工输入路径',
                    border: OutlineInputBorder(),
                    isDense: true,
                    enabled: false,
                  ),
                ),
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: pubIdWidget),
                    const SizedBox(width: 12),
                    Expanded(child: refPreviewWidget),
                  ],
                );
              }
              return Column(
                children: [
                  pubIdWidget,
                  refPreviewWidget,
                ],
              );
            },
          ),
          const Text(
            '用于验证微信支付回调签名。选择文件后先识别格式，点击保存时安全上传并立即应用。',
            style: TextStyle(fontSize: 12, color: Color(0xFF0369A1), height: 1.4),
          ),
          const SizedBox(height: 8),
          InkWell(
            key: const Key('cashier-merchant-cert-toggle-advanced'),
            onTap: () => setState(() => _showAdvancedPubKeyRef = !_showAdvancedPubKeyRef),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showAdvancedPubKeyRef ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16,
                    color: const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showAdvancedPubKeyRef ? '收起高级设置' : '高级设置：手动指定服务器公钥引用',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showAdvancedPubKeyRef) ...[
            const SizedBox(height: 8),
            _field('platformPubKeyRef', '微信支付平台公钥引用 / 服务器绝对路径'),
          ],
        ],
      ),
    );
  }

  Widget _buildAlipayCertificatesCard() {
    final allThreeReady = _hasReadyAlipayAppCert &&
        _hasReadyAlipayPublicCert &&
        _hasReadyAlipayRootCert;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, size: 20, color: Color(0xFF166534)),
              const SizedBox(width: 8),
              const Text(
                '支付宝公钥证书三件套',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF166534),
                ),
              ),
              const Spacer(),
              Container(
                key: const Key('cashier-merchant-alipay-cert-status'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: allThreeReady ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: allThreeReady ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: allThreeReady ? const Color(0xFF22C55E) : const Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      allThreeReady ? '公钥证书三件套已就绪' : '待配置证书文件',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: allThreeReady ? const Color(0xFF15803D) : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCertRow(
            label: '应用公钥证书 (appCertPublicKey_*.crt)',
            btnKey: 'cashier-merchant-pick-alipay-app-cert-btn',
            type: 'ALIPAY_APP_CERT',
            fieldKey: 'alipayAppCertRef',
            pendingName: _pendingAlipayAppCertName,
            isReady: _hasReadyAlipayAppCert,
          ),
          const SizedBox(height: 8),
          _buildCertRow(
            label: '支付宝公钥证书 (alipayCertPublicKey_RSA2.crt)',
            btnKey: 'cashier-merchant-pick-alipay-public-cert-btn',
            type: 'ALIPAY_PUBLIC_CERT',
            fieldKey: 'alipayPublicCertRef',
            pendingName: _pendingAlipayPublicCertName,
            isReady: _hasReadyAlipayPublicCert,
          ),
          const SizedBox(height: 8),
          _buildCertRow(
            label: '支付宝根证书 (alipayRootCert.crt)',
            btnKey: 'cashier-merchant-pick-alipay-root-cert-btn',
            type: 'ALIPAY_ROOT_CERT',
            fieldKey: 'alipayRootCertRef',
            pendingName: _pendingAlipayRootCertName,
            isReady: _hasReadyAlipayRootCert,
          ),
          const SizedBox(height: 10),
          const Text(
            '★ 支付宝开放平台公钥证书模式必须项。包含三个 CRT 证书，保存商户时系统自动无感上传配置。',
            style: TextStyle(fontSize: 12, color: Color(0xFF15803D), height: 1.4),
          ),
          const SizedBox(height: 8),
          InkWell(
            key: const Key('cashier-merchant-alipay-cert-toggle-advanced'),
            onTap: () => setState(() => _showAdvancedAlipayRef = !_showAdvancedAlipayRef),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showAdvancedAlipayRef ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16,
                    color: const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showAdvancedAlipayRef ? '收起高级设置' : '高级设置：手动指定服务器证书路径',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showAdvancedAlipayRef) ...[
            const SizedBox(height: 8),
            _field('alipayAppCertRef', '应用公钥证书引用 / 服务器路径'),
            _field('alipayPublicCertRef', '支付宝公钥证书引用 / 服务器路径'),
            _field('alipayRootCertRef', '支付宝根证书引用 / 服务器路径'),
          ],
        ],
      ),
    );
  }

  Widget _buildCertRow({
    required String label,
    required String btnKey,
    required String type,
    required String fieldKey,
    required String? pendingName,
    required bool isReady,
  }) => Wrap(
    spacing: 12,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ElevatedButton.icon(
        key: Key(btnKey),
        onPressed: _busy ? null : () => _pickAlipayCertFile(type),
        icon: const Icon(Icons.file_upload_outlined, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: isReady ? const Color(0xFF16A34A) : const Color(0xFF0F766E),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
      if (pendingName != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$pendingName (待上传)',
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: Color(0xFF15803D),
            ),
          ),
        )
      else if (_fields[fieldKey]!.text.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '已配置: ${_fields[fieldKey]!.text}',
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: Color(0xFF15803D),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final value = widget.initialValue;
    final wechat = value.channel == PaymentChannel.wechat;
    return CashierDialogFrame(
      title: value.exists
          ? '编辑${value.channel.label}商户'
          : '新增${value.channel.label}商户',
      width: 900,
      height: 780,
      busy: _busy,
      onClose: () => Navigator.pop(context, false),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildKeySelector(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用此商户'),
                value: _enabled,
                onChanged: _busy
                    ? null
                    : (next) => setState(() => _enabled = next),
              ),
              _field(
                'appId',
                wechat ? 'AppID (小程序/公众号)' : 'AppID (支付宝应用)',
                hint: wechat ? '与商户号绑定的微信 AppID' : '支付宝开放平台应用 AppID',
              ),
              if (wechat)
                _field('mchId', '商户号 (mch_id)', hint: '微信支付分配的 10 位商户号'),
              if (wechat) ...[
                _field(
                  'apiV3Key',
                  'APIv3 密钥 (微信统一下单与通知解密)',
                  obscureText: true,
                  helper: value.hasApiV3Key
                      ? '已配置，留空表示不修改；新密钥必须为 32 位'
                      : '必须填写 32 位密钥',
                  validator: (text) => validateApiV3Key(
                    text ?? '',
                    hasExistingKey: value.hasApiV3Key,
                  ),
                ),
                _field(
                  'apiV2Key',
                  'APIv2 密钥 (付款码支付与退款)',
                  obscureText: true,
                  helper: value.hasApiV2Key
                      ? '已配置，留空表示不修改；用于付款码 Micropay 与退款双向鉴权'
                      : '留空表示暂不配置；如需付款码 Micropay 支付与退款请填写 32 位密钥',
                  validator: (text) => validateApiV2Key(
                    text ?? '',
                    hasExistingKey: value.hasApiV2Key,
                  ),
                ),
                _field('serialNo', '商户 API 证书序列号', hint: '40 位大写十六进制字符串'),
                _buildPrivateKeyCard(),
                _buildClientCertP12Card(),
                _buildPublicCertificateCard(),
              ] else ...[
                _buildPrivateKeyCard(),
                _buildAlipayCertificatesCard(),
              ],
              _field(
                'notifyUrl',
                '支付回调地址',
                hint: value.notifyUrlSuggestions['payment'],
                keyboardType: TextInputType.url,
              ),
              _field(
                'refundNotifyUrl',
                '退款回调地址',
                hint: value.notifyUrlSuggestions['refund'],
                keyboardType: TextInputType.url,
              ),
              _field(
                'sortOrder',
                '排序权重 (数字越大越优先)',
                hint: '默认 0',
                keyboardType: TextInputType.number,
              ),
              _field('remark', '备注', maxLines: 2),
              if (value.missingFields.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '支付就绪仍缺少：${value.missingFields.join('、')}',
                    style: TextStyle(color: context.cashier.warning),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    key: const Key('cashier-merchant-form-error'),
                    style: TextStyle(color: context.cashier.danger),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        CashierActionButton(
          label: '取消',
          variant: CashierActionButtonVariant.secondary,
          minimumWidth: 110,
          height: 52,
          onPressed: _busy ? null : () => Navigator.pop(context, false),
        ),
        CashierActionButton(
          key: const Key('cashier-merchant-form-save-btn'),
          label: '保存商户并立即生效',
          minimumWidth: 180,
          height: 52,
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }

  Widget _field(
    String key,
    String label, {
    String? hint,
    String? helper,
    bool obscureText = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: Key('cashier-merchant-field-$key'),
      controller: _fields[key],
      enabled: !_busy,
      obscureText: obscureText,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

class _DeleteMerchantDialog extends StatelessWidget {
  const _DeleteMerchantDialog({required this.merchant});

  final PaymentMerchant merchant;

  @override
  Widget build(BuildContext context) => CashierDialogFrame(
    title: '删除商户配置',
    width: 660,
    height: 360,
    onClose: () => Navigator.pop(context, false),
    body: Text(
      '确定删除商户“${merchant.merchantKey}”吗？接口会执行软删除并停用该配置，审计记录仍会保留，相关支付能力可能被服务端自动关闭。',
      style: const TextStyle(fontSize: 18, height: 1.6),
    ),
    actions: [
      CashierActionButton(
        label: '取消',
        variant: CashierActionButtonVariant.secondary,
        minimumWidth: 110,
        height: 52,
        onPressed: () => Navigator.pop(context, false),
      ),
      CashierActionButton(
        key: const Key('cashier-payment-merchant-delete-confirm'),
        label: '确认删除',
        variant: CashierActionButtonVariant.danger,
        minimumWidth: 140,
        height: 52,
        onPressed: () => Navigator.pop(context, true),
      ),
    ],
  );
}

class _PageError extends StatelessWidget {
  const _PageError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 64,
            color: context.cashier.inkMuted,
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          CashierActionButton(
            label: '重新加载',
            onPressed: onRetry,
            minimumWidth: 150,
          ),
        ],
      ),
    ),
  );
}

String _message(Object error) {
  if (error is ApiException) return error.message;
  if (error is FormatException) return error.message;
  return error.toString().replaceFirst(RegExp(r'^Exception: '), '');
}

/// 支付回调 URL 模板（M-F，只读展示）。
class _NotifyUrlsCard extends StatefulWidget {
  const _NotifyUrlsCard({required this.repository});

  final CashierPaymentRepository repository;

  @override
  State<_NotifyUrlsCard> createState() => _NotifyUrlsCardState();
}

class _NotifyUrlsCardState extends State<_NotifyUrlsCard> {
  PaymentNotifyUrls? _urls;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final urls = await widget.repository.loadNotifyUrls();
      if (!mounted) return;
      setState(() => _urls = urls);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    }
  }

  @override
  Widget build(BuildContext context) => CashierCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                '支付回调地址模板',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
            ),
            CashierStatusBadge(
              label: '只读',
              variant: CashierStatusBadgeVariant.info,
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          '用于微信/支付宝支付与退款结果通知的回调地址，按门店环境自动生成，配置在服务端统一维护。',
          style: TextStyle(color: Color(0xFF667085)),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  '加载失败：$_error',
                  style: const TextStyle(color: Color(0xFFB42318)),
                ),
              ),
              TextButton(onPressed: _load, child: const Text('重试')),
            ],
          )
        else if (_urls == null)
          const Center(child: CircularProgressIndicator())
        else if (_urls!.isEmpty)
          const Text('暂无回调地址模板', style: TextStyle(color: Color(0xFF667085)))
        else ...[
          _NotifyUrlRow(
            label: '微信支付通知',
            value: _urls!.wechatPayNotify,
          ),
          const SizedBox(height: 8),
          _NotifyUrlRow(
            label: '微信退款通知',
            value: _urls!.wechatRefundNotify,
          ),
          const SizedBox(height: 8),
          _NotifyUrlRow(
            label: '支付宝支付通知',
            value: _urls!.alipayPayNotify,
          ),
        ],
      ],
    ),
  );
}

class _NotifyUrlRow extends StatelessWidget {
  const _NotifyUrlRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 130,
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      Expanded(
        child: SelectableText(
          value,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF344054),
            fontFamily: 'monospace',
          ),
        ),
      ),
    ],
  );
}

/// 微信 PEM 私钥上传与商户绑定工具（M-F）。
class _PrivateKeyToolsCard extends StatelessWidget {
  const _PrivateKeyToolsCard({required this.repository});

  final CashierPaymentRepository repository;

  Future<void> _uploadStandalone(BuildContext context) async {
    final uploaded = await showDialog<bool>(
      context: context,
      builder: (context) => _UploadPrivateKeyDialog(
        repository: repository,
        mode: _UploadPrivateKeyMode.standalone,
      ),
    );
    if (uploaded == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('私钥已上传，可在新增商户配置时引用返回的路径')),
      );
    }
  }

  Future<void> _bindMerchant(BuildContext context) async {
    final uploaded = await showDialog<bool>(
      context: context,
      builder: (context) => _UploadPrivateKeyDialog(
        repository: repository,
        mode: _UploadPrivateKeyMode.merchant,
      ),
    );
    if (uploaded == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('商户私钥已绑定并生效')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => CashierCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '微信商户私钥',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        const Text(
          '上传 PEM 私钥文件内容（BEGIN PRIVATE KEY / BEGIN RSA PRIVATE KEY）。私钥内容仅用于上传，数据库只保存服务端返回的文件路径。',
          style: TextStyle(color: Color(0xFF667085)),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            CashierActionButton(
              key: const Key('cashier-payment-upload-private-key'),
              label: '上传微信 PEM 私钥',
              icon: Icons.key_outlined,
              minimumWidth: 220,
              height: 52,
              onPressed: () => _uploadStandalone(context),
            ),
            const SizedBox(width: 12),
            CashierActionButton(
              key: const Key('cashier-payment-bind-merchant-key'),
              label: '绑定到指定商户',
              variant: CashierActionButtonVariant.secondary,
              minimumWidth: 180,
              height: 52,
              onPressed: () => _bindMerchant(context),
            ),
          ],
        ),
      ],
    ),
  );
}

enum _UploadPrivateKeyMode { standalone, merchant }

class _UploadPrivateKeyDialog extends StatefulWidget {
  const _UploadPrivateKeyDialog({
    required this.repository,
    required this.mode,
  });

  final CashierPaymentRepository repository;
  final _UploadPrivateKeyMode mode;

  @override
  State<_UploadPrivateKeyDialog> createState() =>
      _UploadPrivateKeyDialogState();
}

class _UploadPrivateKeyDialogState extends State<_UploadPrivateKeyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pem = TextEditingController();
  final _merchantId = TextEditingController();
  var _merchantKey = 'default';
  var _busy = false;
  String? _resultRef;

  @override
  void dispose() {
    _pem.dispose();
    _merchantId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bytes = const Utf8Encoder().convert(_pem.text.trim());
    setState(() {
      _busy = true;
      _resultRef = null;
    });
    try {
      final filename = 'wechat-${widget.mode == _UploadPrivateKeyMode.merchant ? 'merchant-${_merchantId.text.trim()}' : _merchantKey}.pem';
      if (widget.mode == _UploadPrivateKeyMode.merchant) {
        final merchantId = int.tryParse(_merchantId.text.trim()) ?? 0;
        final form = await widget.repository.uploadMerchantPrivateKey(
          merchantId: merchantId,
          pemBytes: bytes,
          filename: filename,
        );
        if (!mounted) return;
        setState(() => _resultRef = form.privateKeyRef);
      } else {
        final result = await widget.repository.uploadWechatPrivateKey(
          pemBytes: bytes,
          filename: filename,
          merchantKey: _merchantKey,
        );
        if (!mounted) return;
        setState(() => _resultRef = result.privateKeyRef);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _resultRef = '上传失败：$_message(error)';
      });
    }
  }

  @override
  Widget build(BuildContext context) => CashierDialogFrame(
    title: widget.mode == _UploadPrivateKeyMode.merchant
        ? '绑定商户 PEM 私钥'
        : '上传微信 PEM 私钥',
    width: 680,
    height: 560,
    onClose: () => Navigator.pop(context, false),
    body: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.mode == _UploadPrivateKeyMode.merchant) ...[
            TextFormField(
              key: const Key('cashier-payment-bind-merchant-id'),
              controller: _merchantId,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '商户配置 ID',
                hintText: '输入商户配置的 id',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (int.tryParse(value?.trim() ?? '') ?? 0) <= 0
                      ? '请输入有效商户 ID'
                      : null,
            ),
            const SizedBox(height: 12),
          ] else ...[
            DropdownButtonFormField<String>(
              key: const Key('cashier-payment-upload-merchant-key'),
              initialValue: _merchantKey,
              decoration: const InputDecoration(
                labelText: '商户实例键',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'default', child: Text('default（主商户）')),
                DropdownMenuItem(
                  value: 'small_amount',
                  child: Text('small_amount（小金额商户）'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _merchantKey = value ?? 'default'),
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            key: const Key('cashier-payment-upload-pem'),
            controller: _pem,
            enabled: !_busy,
            maxLines: 10,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'PEM 私钥内容',
              hintText: '粘贴完整 PEM 文本，例如 -----BEGIN PRIVATE KEY----- …',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ||
                !value!.trim().contains('PRIVATE KEY')
                ? '请输入包含 BEGIN/END PRIVATE KEY 的 PEM 内容'
                : null,
          ),
          if (_resultRef != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '上传结果：$_resultRef',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF026AA2),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      CashierActionButton(
        label: '取消',
        variant: CashierActionButtonVariant.secondary,
        minimumWidth: 110,
        height: 52,
        onPressed: _busy ? null : () => Navigator.pop(context, false),
      ),
      CashierActionButton(
        key: const Key('cashier-payment-upload-submit'),
        label: '上传',
        busy: _busy,
        minimumWidth: 140,
        height: 52,
        onPressed: _submit,
      ),
    ],
  );
}

class _PaymentRoutingRulesCard extends StatefulWidget {
  const _PaymentRoutingRulesCard({
    super.key,
    required this.repository,
    required this.merchants,
  });

  final CashierPaymentRepository repository;
  final Map<PaymentChannel, PaymentMerchantCollection> merchants;

  @override
  State<_PaymentRoutingRulesCard> createState() =>
      _PaymentRoutingRulesCardState();
}

class _PaymentRoutingRulesCardState extends State<_PaymentRoutingRulesCard> {
  PaymentChannel _activeChannel = PaymentChannel.wechat;
  bool _isAuthorized = false;
  bool _loading = true;
  String? _error;
  PaymentRoutingRuleCollection? _rules;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.repository.loadRoutingRules(_activeChannel);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _rules = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  Future<bool> _ensureAuthorized() async {
    if (_isAuthorized) return true;
    final auth = await showPosAuthDialog(
      context,
      title: '商户分流主管授权',
      reason: '修改商户分流路由规则涉及资金去向，请由店长或管理员输入账号密码进行二次授权。',
      warningMessage: '商户分流路由规则涉及收款资金去向，属于高危财务配置，请谨慎操作。',
      onVerify: (account, password) => widget.repository.verifyPassword(
        username: account,
        password: password,
      ),
    );
    if (auth != null) {
      if (mounted) setState(() => _isAuthorized = true);
      return true;
    }
    return false;
  }

  Future<void> _handleAddRule() async {
    if (!await _ensureAuthorized()) return;
    final available = widget.merchants[_activeChannel]?.owned ?? [];
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CashierRoutingRuleDialog(
        repository: widget.repository,
        channel: _activeChannel,
        availableMerchants: available,
      ),
    );
    if (changed == true) {
      await _loadRules();
    }
  }

  Future<void> _handleEditRule(PaymentRoutingRule rule) async {
    if (rule.readOnly) return;
    if (!await _ensureAuthorized()) return;
    final available = widget.merchants[_activeChannel]?.owned ?? [];
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CashierRoutingRuleDialog(
        repository: widget.repository,
        channel: _activeChannel,
        initialRule: rule,
        availableMerchants: available,
      ),
    );
    if (changed == true) {
      await _loadRules();
    }
  }

  Future<void> _handleDeleteRule(PaymentRoutingRule rule) async {
    if (rule.readOnly || rule.id == null) return;
    if (!await _ensureAuthorized()) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除分流规则'),
        content: Text('确定要删除分流规则「${rule.ruleName}」吗？删除后该规则将永久失效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      final ok = await widget.repository.deleteRoutingRule(rule.id!);
      if (ok) {
        await _loadRules();
      }
    } catch (e) {
      if (mounted) {
        showPosNotice(
          context,
          title: '删除失败',
          message: _message(e),
          tone: PosNoticeTone.error,
        );
      }
    }
  }

  Future<void> _handleToggle(PaymentRoutingRule rule, bool next) async {
    if (rule.readOnly || rule.id == null) return;
    if (!await _ensureAuthorized()) return;
    try {
      await widget.repository.saveRoutingRule(
        id: rule.id,
        data: {
          ...rule.toSaveJson(),
          'enabled': next,
        },
      );
      await _loadRules();
    } catch (e) {
      if (mounted) {
        showPosNotice(
          context,
          title: '操作失败',
          message: _message(e),
          tone: PosNoticeTone.error,
        );
      }
    }
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    if (!await _ensureAuthorized()) return;
    final rules = _rules?.rules;
    if (rules == null || rules.length <= 1) return;

    final mutable = List<PaymentRoutingRule>.from(rules);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = mutable.removeAt(oldIndex);
    mutable.insert(newIndex, item);

    final ruleIds = mutable.map((r) => r.id).whereType<int>().toList();
    try {
      await widget.repository.sortRoutingRules(_activeChannel, ruleIds);
      await _loadRules();
    } catch (e) {
      if (mounted) {
        showPosNotice(
          context,
          title: '排序更新失败',
          message: _message(e),
          tone: PosNoticeTone.error,
        );
      }
    }
  }

  void _handleOpenSimulator() {
    final available = widget.merchants[_activeChannel]?.owned ?? [];
    showDialog<void>(
      context: context,
      builder: (ctx) => CashierRoutingSimulatorDialog(
        repository: widget.repository,
        channel: _activeChannel,
        availableMerchants: available,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules?.rules ?? const [];
    final inherited = _rules?.inheritedTemplates ?? const [];

    return CashierCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题与操作区
          Row(
            children: [
              const Text(
                '商户分流路由规则',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 12),
              CashierStatusBadge(
                key: const Key('cashier-routing-lock-badge'),
                label: _isAuthorized ? '🟢 店长已授权 (免密操作中)' : '🔒 店长/老板专享功能',
                variant: _isAuthorized
                    ? CashierStatusBadgeVariant.success
                    : CashierStatusBadgeVariant.warning,
              ),
              const Spacer(),
              SegmentedButton<PaymentChannel>(
                key: const Key('cashier-routing-channel-tabs'),
                segments: const [
                  ButtonSegment(
                    value: PaymentChannel.wechat,
                    label: Text('微信支付'),
                  ),
                  ButtonSegment(
                    value: PaymentChannel.alipay,
                    label: Text('支付宝'),
                  ),
                ],
                selected: {_activeChannel},
                onSelectionChanged: (val) {
                  if (val.isNotEmpty && val.first != _activeChannel) {
                    setState(() => _activeChannel = val.first);
                    _loadRules();
                  }
                },
              ),
              const SizedBox(width: 10),
              CashierActionButton(
                key: const Key('cashier-routing-simulator-btn'),
                label: '🔍 模拟测算',
                variant: CashierActionButtonVariant.secondary,
                minimumWidth: 120,
                height: 44,
                onPressed: _handleOpenSimulator,
              ),
              const SizedBox(width: 8),
              CashierActionButton(
                key: const Key('cashier-routing-add-rule-btn'),
                label: '+ 新增规则',
                variant: CashierActionButtonVariant.primary,
                minimumWidth: 120,
                height: 44,
                onPressed: _handleAddRule,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '基于就餐方式、订单金额、菜品明细与营业时段等多条件组合判定，分流至指定商户号并保障资金安全。',
            style: TextStyle(color: Color(0xFF667085)),
          ),
          const SizedBox(height: 18),

          // 内容区
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadRules,
                    child: const Text('重试加载规则'),
                  ),
                ],
              ),
            )
          else if (rules.isEmpty && inherited.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.alt_route, size: 40, color: Color(0xFF94A3B8)),
                  const SizedBox(height: 10),
                  Text(
                    '当前${_activeChannel.label}暂未配置任何商户分流路由规则',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '所有付款订单将按默认主商户 (default) 进行收款',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _handleAddRule,
                    icon: const Icon(Icons.add),
                    label: const Text('新增第一条分流规则'),
                  ),
                ],
              ),
            )
          else ...[
            if (rules.isNotEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: rules.length,
                onReorder: _handleReorder,
                itemBuilder: (ctx, index) {
                  final rule = rules[index];
                  return _buildRuleCard(
                    key: ValueKey('rule-${rule.id}'),
                    rule: rule,
                    index: index,
                  );
                },
              ),

            // 继承的上级模板
            if (inherited.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Row(
                children: [
                  Icon(Icons.corporate_fare, size: 18, color: Color(0xFF64748B)),
                  SizedBox(width: 8),
                  Text(
                    '上级总店下发的分流规则模板（只读生效中）',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < inherited.length; i++)
                _buildRuleCard(
                  key: ValueKey('inherited-${inherited[i].id}'),
                  rule: inherited[i],
                  index: i,
                  isInherited: true,
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRuleCard({
    required Key key,
    required PaymentRoutingRule rule,
    required int index,
    bool isInherited = false,
  }) {
    final cond = rule.conditions;
    final keywords = cond?.goodsMatch?.goodsNameKeywords ?? [];
    final dining = cond?.diningTypes ?? [];
    final hasMin = cond?.minPaidYuan != null;
    final hasMax = cond?.maxPaidYuan != null;
    final hasTime = (cond?.timeRange?.startTime.isNotEmpty ?? false) ||
        (cond?.timeRange?.endTime.isNotEmpty ?? false);

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isInherited ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          // 拖拽手柄
          if (!isInherited)
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Icon(
                  Icons.drag_indicator,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Icon(
                Icons.lock_outline,
                color: Color(0xFF94A3B8),
                size: 20,
              ),
            ),
          const SizedBox(width: 8),

          // 优先级徽标
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isInherited
                  ? const Color(0xFFE2E8F0)
                  : const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '#${index + 1} (优先级 ${rule.priority})',
              style: TextStyle(
                color: isInherited
                    ? const Color(0xFF475569)
                    : const Color(0xFF0369A1),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 规则主体信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      rule.ruleName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 目标商户标签与就绪灯
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: rule.targetMerchantPayReady
                            ? const Color(0xFFECFDF5)
                            : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: rule.targetMerchantPayReady
                              ? const Color(0xFFA7F3D0)
                              : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: rule.targetMerchantPayReady
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '目标: ${rule.targetMerchantKey} · ${rule.targetMerchantPayReady ? "就绪" : "凭据未就绪(将自动降级)"}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: rule.targetMerchantPayReady
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 条件胶囊摘要
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildChip(
                      rule.matchMode == 'ALL' ? '全部满足 (AND)' : '任一满足 (OR)',
                      isPrimary: true,
                    ),
                    if (dining.isNotEmpty)
                      _buildChip('就餐: ${dining.join('/')}'),
                    if (hasMin || hasMax)
                      _buildChip(
                        '实付: ¥${cond?.minPaidYuan?.toStringAsFixed(2) ?? "0"} ~ ${cond?.maxPaidYuan != null ? "¥${cond!.maxPaidYuan!.toStringAsFixed(2)}" : "不限"}',
                      ),
                    if (keywords.isNotEmpty)
                      _buildChip('含菜品: ${keywords.join(', ')}'),
                    if (hasTime)
                      _buildChip(
                        '时段: ${cond?.timeRange?.startTime ?? "00:00"} ~ ${cond?.timeRange?.endTime ?? "24:00"}',
                      ),
                    if (rule.remark.isNotEmpty)
                      _buildChip('备注: ${rule.remark}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // 操作按钮区
          if (!isInherited) ...[
            Switch(
              key: Key('cashier-routing-switch-${rule.id}'),
              value: rule.enabled,
              onChanged: (val) => _handleToggle(rule, val),
            ),
            IconButton(
              key: Key('cashier-routing-edit-${rule.id}'),
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: '编辑规则',
              onPressed: () => _handleEditRule(rule),
            ),
            IconButton(
              key: Key('cashier-routing-delete-${rule.id}'),
              icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFDC2626)),
              tooltip: '删除规则',
              onPressed: () => _handleDeleteRule(rule),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '只读',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isPrimary ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isPrimary ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isPrimary ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
        ),
      ),
    );
  }
}

