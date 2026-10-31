import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/formatters.dart';
import '../data/user_repository.dart';
import '../domain/admin_user.dart';
import '../domain/user_query.dart';

class UserListPage extends StatefulWidget {
  const UserListPage({
    super.key,
    required this.appState,
    required this.repository,
    required this.initialQuery,
  });

  final AppState appState;
  final UserRepository repository;
  final UserQuery initialQuery;

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  late UserQuery query = widget.initialQuery;
  final keywordController = TextEditingController();
  final phoneController = TextEditingController();
  final minController = TextEditingController();
  final maxController = TextEditingController();
  List<AdminUser> users = const [];
  int total = 0;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant UserListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState.currentShopId != widget.appState.currentShopId) {
      load();
    }
  }

  @override
  void dispose() {
    keywordController.dispose();
    phoneController.dispose();
    minController.dispose();
    maxController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final shopId = widget.appState.currentShopId;
    if (shopId == null) {
      setState(() => error = '当前账号没有可访问门店，无法查询用户列表');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await widget.repository.getUsers(query, shopId: shopId);
      if (!mounted) return;
      setState(() {
        users = page.users;
        total = page.total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void search() {
    final min = double.tryParse(minController.text.trim());
    final max = double.tryParse(maxController.text.trim());
    query = query.copyWith(
      pageNum: 1,
      query: keywordController.text,
      phone: phoneController.text,
      minAmount: min,
      maxAmount: max,
    );
    load();
  }

  void reset() {
    keywordController.clear();
    phoneController.clear();
    minController.clear();
    maxController.clear();
    query = const UserQuery(pageNum: 1, pageSize: 20);
    load();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Filters(
              keywordController: keywordController,
              phoneController: phoneController,
              minController: minController,
              maxController: maxController,
              query: query,
              onQueryChanged: (next) => setState(() => query = next),
              onSearch: search,
              onReset: reset,
              loading: loading,
            ),
            const SizedBox(height: 12),
            _Hint(total: total),
            const SizedBox(height: 12),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Expanded(
              child: loading && users.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _UserTable(users: users),
            ),
            const SizedBox(height: 12),
            _Pager(
              query: query,
              total: total,
              onChanged: (next) {
                setState(() => query = next);
                load();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.keywordController,
    required this.phoneController,
    required this.minController,
    required this.maxController,
    required this.query,
    required this.onQueryChanged,
    required this.onSearch,
    required this.onReset,
    required this.loading,
  });

  final TextEditingController keywordController;
  final TextEditingController phoneController;
  final TextEditingController minController;
  final TextEditingController maxController;
  final UserQuery query;
  final ValueChanged<UserQuery> onQueryChanged;
  final VoidCallback onSearch;
  final VoidCallback onReset;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 230,
          child: TextField(
            controller: keywordController,
            decoration: const InputDecoration(
              labelText: '关键字',
              prefixIcon: Icon(Icons.search),
              hintText: '昵称 / 手机号 / openid',
            ),
            onSubmitted: (_) => onSearch(),
          ),
        ),
        SizedBox(
          width: 160,
          child: TextField(
            controller: phoneController,
            decoration: const InputDecoration(labelText: '手机号'),
            onSubmitted: (_) => onSearch(),
          ),
        ),
        DropdownMenu<int?>(
          width: 132,
          label: const Text('用户类型'),
          initialSelection: query.userType,
          dropdownMenuEntries: const [
            DropdownMenuEntry(value: null, label: '全部'),
            DropdownMenuEntry(value: 0, label: '普通'),
            DropdownMenuEntry(value: 1, label: '会员'),
          ],
          onSelected: (value) =>
              onQueryChanged(query.copyWith(userType: value)),
        ),
        SizedBox(
          width: 120,
          child: TextField(
            controller: minController,
            decoration: const InputDecoration(labelText: '最低消费'),
            keyboardType: TextInputType.number,
          ),
        ),
        SizedBox(
          width: 120,
          child: TextField(
            controller: maxController,
            decoration: const InputDecoration(labelText: '最高消费'),
            keyboardType: TextInputType.number,
          ),
        ),
        DropdownMenu<String?>(
          width: 136,
          label: const Text('消费排序'),
          initialSelection: query.amountSort,
          dropdownMenuEntries: const [
            DropdownMenuEntry(value: null, label: '默认'),
            DropdownMenuEntry(value: 'desc', label: '高到低'),
            DropdownMenuEntry(value: 'asc', label: '低到高'),
          ],
          onSelected: (value) =>
              onQueryChanged(query.copyWith(amountSort: value)),
        ),
        FilledButton.icon(
          onPressed: loading ? null : onSearch,
          icon: const Icon(Icons.manage_search),
          label: const Text('查询'),
        ),
        OutlinedButton.icon(
          onPressed: loading ? null : onReset,
          icon: const Icon(Icons.refresh),
          label: const Text('重置'),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Text(
      '共 $total 条；消费金额按当前门店成功订单实付净额统计。新增字段：邀请注册数、可用券数。',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _UserTable extends StatefulWidget {
  const _UserTable({required this.users});

  final List<AdminUser> users;

  @override
  State<_UserTable> createState() => _UserTableState();
}

class _UserTableState extends State<_UserTable> {
  final horizontalController = ScrollController();

  @override
  void dispose() {
    horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.users.isEmpty) return const Center(child: Text('暂无数据'));
    return Scrollbar(
      controller: horizontalController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: horizontalController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1180,
          child: ListView(
            children: [
              const _HeaderRow(),
              for (final user in widget.users) _DataRow(user: user),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontWeight: FontWeight.w700,
      color: Color(0xff475569),
    );
    return Container(
      height: 42,
      color: const Color(0xfff8fafc),
      child: const Row(
        children: [
          _Cell('用户', width: 190, style: style),
          _Cell('openid', width: 180, style: style),
          _Cell('手机号', width: 128, style: style),
          _Cell('积分', width: 80, style: style, align: TextAlign.right),
          _Cell('余额', width: 100, style: style, align: TextAlign.right),
          _Cell('本店消费', width: 110, style: style, align: TextAlign.right),
          _Cell('邀请注册', width: 96, style: style, align: TextAlign.center),
          _Cell('可用券', width: 88, style: style, align: TextAlign.center),
          _Cell('类型', width: 88, style: style, align: TextAlign.center),
          _Cell('生日', width: 120, style: style),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xffe5e7eb))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 190,
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: CircleAvatar(
                child: Text(user.name.isEmpty ? '未' : user.name[0]),
              ),
              title: Text(user.name.isEmpty ? '未设置昵称' : user.name),
              subtitle: Text('ID ${user.id}'),
            ),
          ),
          _Cell(dash(user.openid), width: 180),
          _Cell(dash(user.phone), width: 128),
          _Cell('${user.points}', width: 80, align: TextAlign.right),
          _Cell(money(user.balance), width: 100, align: TextAlign.right),
          _Cell(money(user.consumeAmount), width: 110, align: TextAlign.right),
          _Cell(
            '${user.inviteRegisteredCount}',
            width: 96,
            align: TextAlign.center,
          ),
          _Cell(
            '${user.availableCouponCount}',
            width: 88,
            align: TextAlign.center,
          ),
          SizedBox(
            width: 88,
            child: Center(
              child: Chip(
                label: Text(user.isMember ? '会员' : '普通'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          _Cell(dash(user.birthday), width: 120),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(
    this.text, {
    required this.width,
    this.align = TextAlign.left,
    this.style,
  });

  final String text;
  final double width;
  final TextAlign align;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: style,
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.query,
    required this.total,
    required this.onChanged,
  });

  final UserQuery query;
  final int total;
  final ValueChanged<UserQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    final pageCount = total == 0
        ? 1
        : ((total + query.pageSize - 1) ~/ query.pageSize);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('第 ${query.pageNum} / $pageCount 页'),
        const SizedBox(width: 12),
        DropdownMenu<int>(
          width: 96,
          initialSelection: query.pageSize,
          dropdownMenuEntries: const [
            DropdownMenuEntry(value: 10, label: '10 条'),
            DropdownMenuEntry(value: 20, label: '20 条'),
            DropdownMenuEntry(value: 50, label: '50 条'),
            DropdownMenuEntry(value: 100, label: '100 条'),
          ],
          onSelected: (value) {
            if (value != null)
              onChanged(query.copyWith(pageNum: 1, pageSize: value));
          },
        ),
        IconButton(
          tooltip: '上一页',
          onPressed: query.pageNum <= 1
              ? null
              : () => onChanged(query.copyWith(pageNum: query.pageNum - 1)),
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: '下一页',
          onPressed: query.pageNum >= pageCount
              ? null
              : () => onChanged(query.copyWith(pageNum: query.pageNum + 1)),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
