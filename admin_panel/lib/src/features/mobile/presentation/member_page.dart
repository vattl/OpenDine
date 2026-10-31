import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../data/api_providers.dart';
import '../design/mobile_colors.dart';
import '../design/mobile_components.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';

/// 会员查询与充值（PRD F10，权限 user:view，路由侧已守卫）。
///
/// 手机号查询会员画像（余额/积分/消费行为），查看消费记录与充值流水，
/// 支持余额充值（本金 ≥ 50 元，可选赠送，二次确认）。
class MemberPage extends ConsumerStatefulWidget {
  const MemberPage({super.key});

  @override
  ConsumerState<MemberPage> createState() => _MemberPageState();
}

class _MemberPageState extends ConsumerState<MemberPage> {
  final _phoneController = TextEditingController();
  Map<String, Object?>? _profile;
  List<Map<String, Object?>> _consumption = const [];
  List<Map<String, Object?>> _rechargeList = const [];
  bool _searched = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String get _phone => _phoneController.text.trim();

  Future<void> _search() async {
    final phone = _phone;
    if (phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入会员手机号')));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final client = ref.read(apiClientProvider);
      final profileData = await client.get(
        memberProfileEndpoint,
        query: {'phone': phone},
      );
      final consumption = await client.get(
        memberConsumptionEndpoint,
        query: {'phone': phone, 'limit': 20},
      );
      final recharge = await client.get(
        memberRechargeListEndpoint,
        query: {'phone': phone, 'allShops': true},
      );
      if (mounted) {
        setState(() {
          final pmap = profileData is Map
              ? profileData.cast<String, Object?>()
              : const <String, Object?>{};
          final user = pmap['profile'] is Map
              ? (pmap['profile'] as Map).cast<String, Object?>()['user']
              : pmap['user'];
          _profile = user is Map ? user.cast<String, Object?>() : null;
          _consumption = objectList(consumption);
          _rechargeList = objectList(recharge);
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _profile = null;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _recharge() async {
    final phone = _phone;
    if (_profile == null || phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先查询会员')));
      return;
    }
    final amountController = TextEditingController();
    final giftController = TextEditingController();
    final amount = await showModalBottomSheet<double?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MobileMetrics.radiusSheet)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(MobileMetrics.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '为会员 $_phone 充值',
                style: MobileTypography.sectionTitle,
              ),
              const SizedBox(height: MobileMetrics.spaceSm),
              Text(
                '手机号已在上一页查询确认。本金单笔不低于 50 元。',
                style: context.bodySecondaryStyle,
              ),
              const SizedBox(height: MobileMetrics.spaceMd),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '充值本金（元，≥50）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: MobileMetrics.spaceMd),
              TextField(
                controller: giftController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '赠送金额（元，可选）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: MobileMetrics.spaceLg),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(MobileMetrics.buttonHeightCta),
                ),
                onPressed: () => Navigator.of(
                  sheetContext,
                ).pop(double.tryParse(amountController.text.trim())),
                child: const Text('下一步：确认充值'),
              ),
            ],
          ),
        ),
      ),
    );
    if (amount == null || amount < 50) {
      if (amount != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('充值本金不得低于 50 元')));
      }
      return;
    }
    final gift = double.tryParse(giftController.text.trim()) ?? 0;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('充值确认'),
        content: Text(
          '确认向会员 $_phone 充值\n本金 ¥${amount.toStringAsFixed(2)}'
          '${gift > 0 ? ' + 赠送 ¥${gift.toStringAsFixed(2)}' : ''}？\n'
          '充值将即时到账并写入充值记录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认充值'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final client = ref.read(apiClientProvider);
      await client.post(
        memberRechargeCreateEndpoint,
        body: {
          'phone': phone,
          'amount': amount,
          if (gift > 0) 'gift_amount': gift,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('充值成功')));
        _search();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('充值失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('会员中心')),
      body: Column(
        children: [
          Padding(
            padding: MobileMetrics.pagePadding.copyWith(bottom: MobileMetrics.spaceSm),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: '输入会员手机号',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: MobileMetrics.spaceMd),
                FilledButton(onPressed: _loading ? null : _search, child: const Text('查询')),
              ],
            ),
          ),
          Expanded(
            child: _buildBody(context),
          ),
        ],
      ),
      bottomNavigationBar: _profile == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(MobileMetrics.spaceLg),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(MobileMetrics.buttonHeightCta),
                  ),
                  onPressed: _recharge,
                  icon: const Icon(Icons.add_card_outlined),
                  label: const Text('余额充值'),
                ),
              ),
            ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const LoadingSkeleton(height: 220);
    if (!_searched) {
      return const EmptyState(message: '输入手机号查询会员信息');
    }
    if (_error != null) {
      return ErrorState(message: '查询失败：$_error', onRetry: _search);
    }
    if (_profile == null) {
      return const EmptyState(message: '未找到该手机号对应的会员');
    }
    return ListView(
      padding: MobileMetrics.pagePadding.copyWith(top: MobileMetrics.spaceLg),
      children: [
        _profileCard(context),
        const SizedBox(height: MobileMetrics.cardGap),
        const Text('消费与充值', style: MobileTypography.sectionTitle),
        const SizedBox(height: MobileMetrics.spaceSm),
        _buildRecords(context),
      ],
    );
  }

  Widget _profileCard(BuildContext context) {
    final p = _profile!;
    String s(Object? v) => v == null ? '' : '$v';
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final name = s(p['name'] ?? p['nickname'] ?? '会员');
    final phone = s(p['phone']);
    final points = s(p['points']);
    final balance = d(p['balance']);
    return Card(
      child: Padding(
        padding: MobileMetrics.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: context.palette.brandSoft,
                  child: Text(
                    name.isEmpty ? '会' : name.characters.first,
                    style: TextStyle(
                      color: context.palette.brandInk,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: MobileMetrics.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: MobileTypography.sectionTitle),
                      const SizedBox(height: MobileMetrics.spaceXs),
                      Text(
                        _maskPhone(phone),
                        style: context.captionStyle,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AmountText(
                      balance,
                      style: MobileTypography.displayAmount.copyWith(
                        color: context.palette.brandInk,
                        fontSize: 24,
                      ),
                    ),
                    const Text('余额（元）', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            if (points.isNotEmpty) ...[
              const SizedBox(height: MobileMetrics.spaceMd),
              const Divider(height: 1),
              const SizedBox(height: MobileMetrics.spaceMd),
              Text('积分：$points', style: MobileTypography.body),
            ],
          ],
        ),
      ),
    );
  }

  static String _maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}****${digits.substring(7)}';
    }
    if (phone.length <= 4) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 2)}';
  }

  Widget _buildRecords(BuildContext context) {
    if (_consumption.isEmpty && _rechargeList.isEmpty) {
      return const EmptyState(message: '暂无消费与充值记录');
    }
    return Card(
      child: Column(
        children: [
          if (_consumption.isNotEmpty) ...[
            for (final row in _consumption) _consumptionRow(context, row),
            const Divider(height: 1),
          ],
          if (_rechargeList.isNotEmpty)
            for (final row in _rechargeList) _rechargeRow(context, row),
        ],
      ),
    );
  }

  Widget _consumptionRow(BuildContext context, Map<String, Object?> row) {
    String s(Object? v) => v == null ? '' : '$v';
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final amount = d(row['payAmount'] ?? row['amount'] ?? row['totalAmount']);
    final time = s(row['payTime'] ?? row['pay_time'] ?? row['orderTime'] ?? '');
    return ListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: const Text('消费'),
      subtitle: Text(time, style: context.captionStyle),
      trailing: AmountText(amount, style: MobileTypography.itemTitle),
    );
  }

  Widget _rechargeRow(BuildContext context, Map<String, Object?> row) {
    String s(Object? v) => v == null ? '' : '$v';
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final amount = d(row['amount'] ?? row['rechargeAmount']);
    final gift = d(row['giftAmount'] ?? row['gift_amount']);
    final time = s(row['createdAt'] ?? row['created_at'] ?? '');
    final label = gift > 0 ? '充值 + 赠送' : '充值';
    return ListTile(
      leading: const Icon(Icons.add_card_outlined),
      title: Text(label),
      subtitle: Text(time, style: context.captionStyle),
      trailing: AmountText(amount + gift, style: MobileTypography.itemTitle),
    );
  }
}
