import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kds_app/core/config/api_base_util.dart';
import 'package:kds_app/core/config/kds_app_config.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:kds_app/core/device/kds_device_code_resolver.dart';
import 'package:kds_app/core/layout/kds_display_scope.dart';
import 'package:kds_app/core/theme/kds_theme.dart';
import 'package:kds_app/features/auth/session_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _apiBaseCtrl = TextEditingController(text: '');
  final _cloudApiBaseCtrl =
      TextEditingController(text: platformDefaultCloudApiBase());
  static const _connectionMode = KdsConnectionMode.cloudFirst;
  final _shopIdCtrl = TextEditingController(text: '1');
  final _kdsPinCtrl = TextEditingController(text: '123456');
  final _deviceCodeCtrl = TextEditingController();
  final _deviceNameCtrl = TextEditingController();
  final _pairingCodeCtrl = TextEditingController();
  bool _obscurePin = true;
  final _deviceCodeResolver = KdsDeviceCodeResolver();
  final Set<KdsWorkflow> _workflows = {
    KdsWorkflow.prep,
    KdsWorkflow.cook,
    KdsWorkflow.serve,
  };

  bool _deviceCodeLoading = true;
  String? _deviceCodeHint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapForm());
  }

  Future<void> _bootstrapForm() async {
    final session = ref.read(sessionProvider);
    final storage = ref.read(sessionProvider.notifier).storageOrNull;
    if (session.apiBase.isNotEmpty) _apiBaseCtrl.text = session.apiBase;
    if (session.cloudApiBase.isNotEmpty) {
      _cloudApiBaseCtrl.text = session.cloudApiBase;
    }
    final rememberedShopId =
        session.device?.shopId ?? storage?.getLastShopId();
    if (rememberedShopId != null && rememberedShopId > 0) {
      _shopIdCtrl.text = rememberedShopId.toString();
    }
    final rememberedWorkflows = session.device?.workflows.isNotEmpty == true
        ? session.device!.workflows
        : (storage
                ?.getLastWorkflows()
                ?.map(KdsWorkflow.fromValue)
                .whereType<KdsWorkflow>()
                .toList() ??
            const []);
    if (rememberedWorkflows.isNotEmpty) {
      _workflows
        ..clear()
        ..addAll(rememberedWorkflows);
    }
    final rememberedDeviceName =
        session.device?.deviceName ?? storage?.getLastDeviceName();
    if (rememberedDeviceName != null && rememberedDeviceName.isNotEmpty) {
      _deviceNameCtrl.text = rememberedDeviceName;
    }
    await _resolveDeviceCode(sessionDeviceCode: session.device?.deviceCode);
  }

  Future<void> _resolveDeviceCode(
      {String? sessionDeviceCode, bool force = false}) async {
    if (!mounted) return;

    setState(() => _deviceCodeLoading = true);
    final resolved = await _deviceCodeResolver.resolve(
      sessionDeviceCode: sessionDeviceCode,
    );
    if (!mounted) return;

    setState(() {
      _deviceCodeLoading = false;
      _deviceCodeCtrl.text = resolved.code;
      _deviceCodeHint = resolved.hasCode ? resolved.originLabel : null;
    });
  }

  @override
  void dispose() {
    _apiBaseCtrl.dispose();
    _cloudApiBaseCtrl.dispose();
    _shopIdCtrl.dispose();
    _kdsPinCtrl.dispose();
    _deviceCodeCtrl.dispose();
    _deviceNameCtrl.dispose();
    _pairingCodeCtrl.dispose();
    super.dispose();
  }

  void _copyDeviceCode() {
    final code = _deviceCodeCtrl.text.trim();
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制设备码 $code，请在收银端【设置 - KDS设置 - 设备管理】中绑定此设备'),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _submit({
    KdsActiveChannel initialChannel = KdsActiveChannel.cloud,
  }) async {
    final rawShopId = _shopIdCtrl.text.trim();
    final shopId = int.tryParse(rawShopId);
    if (shopId == null || shopId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入正确的门店编号（如：1）')),
      );
      return;
    }
    final kdsPin = _kdsPinCtrl.text.trim();
    if (kdsPin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 6 位 KDS 登录 PIN 码（默认 123456）')),
      );
      return;
    }

    final cloudBase = _cloudApiBaseCtrl.text.trim().isEmpty
        ? platformDefaultCloudApiBase()
        : _cloudApiBaseCtrl.text.trim();
    final storedLan = ref.read(sessionProvider).apiBase.trim();
    final lanBase = isPrivateLanApiBase(storedLan) ? storedLan : '';

    if (cloudBase.isEmpty || !isValidApiBase(cloudBase)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('云端 API 地址无效，请检查高级设置中的云端地址')),
      );
      return;
    }

    if (_deviceCodeCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在识别本机设备码，请稍候…')),
      );
      return;
    }
    if (_workflows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个工作流程')),
      );
      return;
    }

    final ok = await ref.read(sessionProvider.notifier).login(
          deviceCode: _deviceCodeCtrl.text.trim(),
          screenTag: KdsScreenTag.workflowBoard,
          shopId: shopId,
          kdsPin: kdsPin,
          workflows: _workflows.toList(),
          deviceName:
              _deviceNameCtrl.text.isEmpty ? null : _deviceNameCtrl.text.trim(),
          pairingCode: _pairingCodeCtrl.text.trim().isEmpty
              ? null
              : _pairingCodeCtrl.text.trim().toUpperCase(),
          apiBase: lanBase,
          cloudApiBase: cloudBase,
          mode: _connectionMode,
          initialChannel: initialChannel,
        );

    if (!mounted) return;
    if (ok) {
      context.go('/');
    } else {
      final session = ref.read(sessionProvider);
      if (initialChannel == KdsActiveChannel.cloud &&
          session.lanLoginSuggested) {
        final useLan = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('云端响应异常'),
            content: const Text(
              '云端延迟过高或无响应。是否通过收银端局域网代理转发登录请求？\n\n'
              '登录凭据仍由 KDS 原样提交、由云端校验；进入看板后不会自动切换连接通道。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('暂不切换'),
              ),
              FilledButton.icon(
                key: const ValueKey('login-switch-to-lan'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.lan_outlined),
                label: const Text('使用局域网代理'),
              ),
            ],
          ),
        );
        if (useLan == true && mounted) {
          await _submit(initialChannel: KdsActiveChannel.lan);
        }
        return;
      }
      if (session.error != null && session.error!.contains('设备未绑定')) {
        _showUnboundDialog(_deviceCodeCtrl.text.trim());
      }
    }
  }

  void _showUnboundDialog(String code) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFFFFA726)),
            SizedBox(width: 8),
            Text('设备未在收银端绑定'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('当前设备尚未在收银端登记，请前往收银端完成绑定：'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: KdsColors.segmentBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      code,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: '复制设备码',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('设备码已复制')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '操作路径：收银端【设置】➔【KDS 设置】➔【设备管理】➔【添加/绑定设备】输入上方设备码即可。',
              style: TextStyle(color: KdsColors.textMuted, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.cleaning_services_outlined, size: 16),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _clearAllCache();
            },
            label: const Text('清除旧缓存'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('设备码已复制')),
              );
            },
            child: const Text('复制并关闭'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_outlined, color: Color(0xFFFFA726)),
            SizedBox(width: 8),
            Text('清除本地缓存并重置'),
          ],
        ),
        content: const Text(
          '此操作将彻底清除本机保存的所有旧登录凭据、离线看板快照、待同步队列和硬件缓存，'
          '并将设备重置为全新初始状态。\n\n确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(sessionProvider.notifier).clearAllCache();

    if (!mounted) return;
    setState(() {
      _shopIdCtrl.text = '1';
      _kdsPinCtrl.text = '123456';
      _workflows.clear();
      _workflows.add(KdsWorkflow.cook);
      _deviceNameCtrl.clear();
      _pairingCodeCtrl.clear();
      _apiBaseCtrl.clear();
      _cloudApiBaseCtrl.text = platformDefaultCloudApiBase();
    });
    await _resolveDeviceCode(force: true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已清除所有本地缓存与历史凭据，请重新输入 6 位 PIN 码登录'),
        backgroundColor: Color(0xFF0CB960),
        duration: Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final display = context.kdsDisplay;

    return Scaffold(
      backgroundColor: KdsColors.shellBg,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(display.dp(24)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: display.loginFormMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('老肥餐饮系统',
                    style: KdsTypography.brandTitle,
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'KDS 厨显登录',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '${display.formFactorLabel} · ${display.resolutionLabel}',
                  style:
                      const TextStyle(color: KdsColors.textMuted, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  '选择当前工作区负责流程 · 可多选',
                  style: TextStyle(color: KdsColors.textMuted),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: display.dp(28)),
                _field(
                  '门店编号 (Shop ID)',
                  _shopIdCtrl,
                  hint: '请输入门店编号，例如：1',
                  keyboard: TextInputType.number,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _kdsPinCtrl,
                    obscureText: _obscurePin,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration('6位后厨登录 PIN 码').copyWith(
                      hintText: '默认 123456，可在收银端查看/修改',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePin ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePin = !_obscurePin),
                      ),
                    ),
                  ),
                ),
                InputDecorator(
                  decoration: _inputDecoration('工作流程（可多选）'),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final workflow in KdsWorkflow.values)
                        FilterChip(
                          label: Text(workflow.label),
                          selected: _workflows.contains(workflow),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _workflows.add(workflow);
                              } else {
                                _workflows.remove(workflow);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _field('设备/档口名称（可选）', _deviceNameCtrl, hint: '如：烧烤档 / 凉菜档 / 出餐台'),
                const SizedBox(height: 4),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    tilePadding: EdgeInsets.zero,
                    title: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune, size: 16, color: KdsColors.textMuted),
                        SizedBox(width: 6),
                        Text(
                          '高级网络与硬件设置 (选填)',
                          style: TextStyle(fontSize: 13, color: KdsColors.textMuted),
                        ),
                      ],
                    ),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                          leading: Icon(Icons.cloud_done_outlined),
                          title: Text('云端直连优先 · 可选局域网'),
                          subtitle: Text('系统默认直连云端；局域网地址可在登录后进入【设置】配置'),
                        ),
                      ),
                      _field(
                        '云端服务地址 (主通道)',
                        _cloudApiBaseCtrl,
                        hint: KdsAppConfig.cloudApiBaseExample,
                      ),
                      _deviceCodeField(),
                      _field(
                        '一次性配对码',
                        _pairingCodeCtrl,
                        hint: '如已使用 PIN 码登录则无需填写',
                      ),
                    ],
                  ),
                ),
                if (session.error != null) ...[
                  const SizedBox(height: 12),
                  Text(session.error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ],
                SizedBox(height: display.dp(24)),
                FilledButton(
                  onPressed: session.loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: Size.fromHeight(display.minTouchTarget),
                  ),
                  child: Text(session.loading ? '登录中…' : '登录'),
                ),
                const SizedBox(height: 14),
                Center(
                  child: TextButton.icon(
                    key: const ValueKey('login-clear-cache-btn'),
                    onPressed: session.loading ? null : _clearAllCache,
                    icon: const Icon(Icons.cleaning_services_outlined, size: 16, color: KdsColors.textMuted),
                    label: const Text(
                      '清除本地缓存并重置设备',
                      style: TextStyle(color: KdsColors.textMuted, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _deviceCodeField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _deviceCodeCtrl,
            readOnly: true, // 锁定禁止人工修改
            enableInteractiveSelection: true,
            decoration: _inputDecoration('本机硬件设备码（系统自动生成，不可篡改）').copyWith(
              hintText: 'KDS-XXXXXXXX',
              suffixIcon: _deviceCodeLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '复制设备码',
                          onPressed: _copyDeviceCode,
                          icon: const Icon(Icons.copy, size: 20),
                        ),
                        IconButton(
                          tooltip: '重新识别硬件',
                          onPressed: () => _resolveDeviceCode(force: true),
                          icon: const Icon(Icons.refresh, size: 20),
                        ),
                      ],
                    ),
            ),
          ),
          if (_deviceCodeHint != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: KdsColors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$_deviceCodeHint · 硬件唯一绑定',
                    style: const TextStyle(
                        color: KdsColors.textMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    TextInputType? keyboard,
    ValueChanged<String>? onChanged,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        onChanged: onChanged,
        obscureText: obscure,
        enableSuggestions: !obscure,
        autocorrect: !obscure,
        decoration: _inputDecoration(label).copyWith(hintText: hint),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: KdsColors.textSecondary),
      filled: true,
      fillColor: KdsColors.segmentBg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
