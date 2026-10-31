import 'package:flutter/material.dart';

import '../core/app_state.dart';

typedef ShellPageBuilder = Widget Function(BuildContext context);

class ShellPage {
  const ShellPage({
    required this.title,
    required this.icon,
    required this.requiredPermission,
    required this.builder,
    this.permissionOr,
  });

  final String title;
  final IconData icon;
  final String requiredPermission;
  final String? permissionOr;
  final ShellPageBuilder builder;
}

class ShellPageGroup {
  const ShellPageGroup({
    required this.title,
    required this.icon,
    required this.pages,
  });

  final String title;
  final IconData icon;
  final List<ShellPage> pages;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.appState, required this.groups});

  final AppState appState;
  final List<ShellPageGroup> groups;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool collapsed = false;

  bool _allowed(ShellPage page) {
    return widget.appState.hasPermission(page.requiredPermission) ||
        (page.permissionOr != null &&
            widget.appState.hasPermission(page.permissionOr!));
  }

  @override
  Widget build(BuildContext context) {
    final groups = [
      for (final group in widget.groups)
        ShellPageGroup(
          title: group.title,
          icon: group.icon,
          pages: group.pages.where(_allowed).toList(growable: false),
        ),
    ].where((group) => group.pages.isNotEmpty).toList(growable: false);
    final pages = [for (final group in groups) ...group.pages];
    if (pages.isEmpty) {
      return const Scaffold(body: Center(child: Text('当前账号没有可访问的后台页面')));
    }

    final selectedIndex = widget.appState.selectedIndex
        .clamp(0, pages.length - 1)
        .toInt();
    final selected = pages[selectedIndex];

    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: collapsed ? 72 : 240,
            child: _Sidebar(
              groups: groups,
              selected: selected,
              collapsed: collapsed,
              onSelected: (page) =>
                  widget.appState.selectPage(pages.indexOf(page)),
              onToggle: () => setState(() => collapsed = !collapsed),
              onLogout: widget.appState.logout,
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  appState: widget.appState,
                  title: selected.title,
                  onToggleSidebar: () => setState(() => collapsed = !collapsed),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: selected.builder(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.groups,
    required this.selected,
    required this.collapsed,
    required this.onSelected,
    required this.onToggle,
    required this.onLogout,
  });

  final List<ShellPageGroup> groups;
  final ShellPage selected;
  final bool collapsed;
  final ValueChanged<ShellPage> onSelected;
  final VoidCallback onToggle;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xffad1919),
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 76,
              child: Center(
                child: collapsed
                    ? const Text(
                        '收',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '运营后台',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '美团收银风格',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final group in groups)
                    if (collapsed)
                      for (final page in group.pages)
                        _MenuTile(
                          page: page,
                          selected: page == selected,
                          onTap: onSelected,
                        )
                    else
                      ExpansionTile(
                        initiallyExpanded: group.pages.contains(selected),
                        leading: Icon(group.icon, color: Colors.white),
                        title: Text(
                          group.title,
                          style: const TextStyle(color: Colors.white),
                        ),
                        iconColor: Colors.white,
                        collapsedIconColor: Colors.white,
                        children: [
                          for (final page in group.pages)
                            _MenuTile(
                              page: page,
                              selected: page == selected,
                              onTap: onSelected,
                            ),
                        ],
                      ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            _FooterButton(
              collapsed: collapsed,
              icon: collapsed
                  ? Icons.keyboard_double_arrow_right
                  : Icons.keyboard_double_arrow_left,
              label: collapsed ? '展开' : '收起',
              onTap: onToggle,
            ),
            _FooterButton(
              collapsed: collapsed,
              icon: Icons.logout,
              label: '退出登录',
              onTap: onLogout,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.page,
    required this.selected,
    required this.onTap,
  });

  final ShellPage page;
  final bool selected;
  final ValueChanged<ShellPage> onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: const Color(0xff6b0f0f),
      leading: Icon(page.icon, color: Colors.white),
      title: Text(page.title, style: const TextStyle(color: Colors.white)),
      onTap: () => onTap(page),
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.collapsed,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool collapsed;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Colors.white),
      title: collapsed
          ? null
          : Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.appState,
    required this.title,
    required this.onToggleSidebar,
  });

  final AppState appState;
  final String title;
  final VoidCallback onToggleSidebar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffe5e7eb))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '切换侧栏',
            onPressed: onToggleSidebar,
            icon: const Icon(Icons.menu_open),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(width: 8),
          if (appState.shops.isEmpty)
            const Chip(label: Text('未返回可访问门店'))
          else () {
            final uniqueShops = <int, ShopSummary>{};
            for (final s in appState.shops) {
              if (s.id > 0) uniqueShops.putIfAbsent(s.id, () => s);
            }
            if (uniqueShops.isEmpty) return const Chip(label: Text('未返回可访问门店'));
            final selectedId = uniqueShops.containsKey(appState.currentShopId)
                ? appState.currentShopId
                : uniqueShops.keys.first;
            return ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
              child: DropdownButtonFormField<int>(
                key: ValueKey(selectedId),
                initialValue: selectedId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '当前门店'),
                items: [
                  for (final shop in uniqueShops.values)
                    DropdownMenuItem(
                      value: shop.id,
                      child: Text(
                        '${shop.name}${shop.code.isEmpty ? '' : ' (${shop.code})'}',
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      appState.selectShop(id);
                    });
                  }
                },
              ),
            );
          }(),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xfffff1ed),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xffffdcd3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.account_circle,
                  size: 20,
                  color: Color(0xffed3d08),
                ),
                const SizedBox(width: 6),
                Text(
                  appState.currentDisplayName.isNotEmpty
                      ? appState.currentDisplayName
                      : (appState.currentRealName.isNotEmpty
                          ? appState.currentRealName
                          : (appState.currentActorName ?? '管理员')),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xff2d2d2f),
                  ),
                ),
                if (appState.currentJobTitle.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xffed3d08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      appState.currentJobTitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (appState.currentWorkNo.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    appState.currentWorkNo,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xff848484),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Chip(
            avatar: const Icon(Icons.verified_user_outlined, size: 18),
            label: Text(appState.scope),
          ),
        ],
      ),
    );
  }
}
