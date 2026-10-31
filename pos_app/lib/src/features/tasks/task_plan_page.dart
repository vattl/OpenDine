import 'package:flutter/material.dart';

class TaskPlanPage extends StatelessWidget {
  const TaskPlanPage({super.key});

  static const tasks = [
    (
      'P0 架构基线',
      '独立 Flutter 工程、app/core/features 分层、Shell、登录认证、权限过滤、门店切换、真实 Repository。',
    ),
    (
      'P1 用户运营',
      '用户运营：契约、筛选、金额排序、积分/余额/消费/邀请/券数与权限入口。',
    ),
    ('P2 收银订单', '订单列表、详情找零字段、点餐台、桌台状态、接单、结账、退菜、补打、kds_order_status。'),
    ('P3 商品财务', '分类、菜品、套餐、单位、优惠券、库存成本、日结、充值流水、经营看板、数据分析。'),
    ('P4 KDS 外卖实时', 'KDS 配置、厨显客户端、/ws/kds、/ws/menu、外卖配送、真省钱履约、骑手追踪。'),
  ];

  static const standards = [
    'flutter analyze 无错误，flutter test 全部通过。',
    'B 端接口声明权限码、门店头策略和分页策略；白名单接口不带门店头。',
    '分页请求 pageSize <= 100，空值参数不提交。',
    '用户字段缺失时 invite_registered_count 和 available_coupon_count 显示 0。',
    '金额口径统一为 sett_amount - discount_amount + service_fee - refund_amount - pay_amount_gift。',
    '订单 todayCount、找零字段、KDS 状态可解析；退菜只作用 line_status=normal 明细；补打不改接单状态。',
    '菜品库存读写 t_dish_shop 门店维度；上下架与售罄互不误改。',
    'KDS 设备端使用 X-Kds-Device-Token，并校验 screen_tag 与设备 token 绑定。',
    'WebSocket 断线后通过增量接口补齐状态；外卖退款与配送取消展示责任提示。',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Panel(
            title: '任务目标',
            children: [
              for (final task in tasks)
                ListTile(
                  leading: const Icon(Icons.radio_button_checked, size: 18),
                  title: Text(task.$1),
                  subtitle: Text(task.$2),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _Panel(
            title: '验收标准',
            children: [
              for (var i = 0; i < standards.length; i++)
                ListTile(
                  leading: CircleAvatar(radius: 13, child: Text('${i + 1}')),
                  title: Text(standards[i]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}
