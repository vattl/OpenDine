import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/app_config.dart';
import '../data/cashier_settings_repository.dart';
import '../domain/cashier_settings.dart';
import 'cashier_settings_shared.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

class CashierSettingsStorePage extends StatefulWidget {
  const CashierSettingsStorePage({
    super.key,
    required this.repository,
    required this.section,
    this.onDirtyChanged,
  });

  final CashierSettingsRepository repository;
  final SettingsSectionSpec section;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<CashierSettingsStorePage> createState() =>
      _CashierSettingsStorePageState();
}

class _CashierSettingsStorePageState extends State<CashierSettingsStorePage> {
  final _openController = TextEditingController();
  final _closeController = TextEditingController();
  final _cutOffController = TextEditingController(text: '04:00');

  // v1.2.219：关门强制交班 / 关门强制日结
  bool _shiftRequired = false;
  bool _settleRequired = false;

  // 店铺信息控制器
  final _storeIdController = TextEditingController(text: '1');
  final _nameController = TextEditingController(text: '老肥油边王(松源海鲜街)');
  final _codeController = TextEditingController(text: '1001');
  final _phoneController = TextEditingController(text: '13800138000');
  final _addressController = TextEditingController(text: '广东省江门市鹤山市沙坪街道大鹏路');
  final _latController = TextEditingController(text: '22.760231');
  final _lngController = TextEditingController(text: '112.973179');
  final _sortController = TextEditingController(text: '0');
  final _remarkController = TextEditingController(text: '');
  String _storeStatus = '营业';

  // 线下收款码状态与图片路径
  String _wechatQrPath = '/image/offline-collect/shop_1_wechat.png';
  String _alipayQrPath = '/image/offline-collect/shop_1_alipay.png';
  String _wechatPayload = 'wxp://...';
  String _alipayPayload = 'https://qr.alipay.com/...';
  bool _wechatConfigured = true;
  bool _alipayConfigured = true;

  // 店铺公告控制器与数据绑定
  int? _noticeId;
  final _noticeTitleController = TextEditingController(text: '门店公告');
  final _noticeContentController = TextEditingController(
    text:
        '<h3>门店信息</h3>\n<p>• 老肥油边王 · 烧烤夜宵旗舰店\n• 营业时间：18:30 - 次日 01:30\n• 堂食扫码点餐 · 支持全场连台结账</p>\n<hr/>\n<h3>配送规则</h3>\n<p>• <strong>5公里内满30元免配送费</strong>，由真省钱专送直达\n• 外卖订单出餐后自动打印配送面单</p>\n<hr/>\n<h3>邀请好友奖励9折券</h3>\n<p>• 邀请新用户进入小程序下单，双方各得一张<span style="color:#D84949"><strong>9折无门槛优惠券</strong></span></p>\n<hr/>\n<blockquote>温馨提示：夜间就餐高峰期，部分烤品制作需15-20分钟，敬请谅解。</blockquote>',
  );
  final _noticeSortController = TextEditingController(text: '0');
  final _noticeStartTimeController = TextEditingController(text: '');
  final _noticeEndTimeController = TextEditingController(text: '');
  bool _noticeEnabled = true;

  CashierStoreSettings? _settings;
  Object? _error;
  var _loading = true;
  var _saving = false;
  var _isDirty = false;
  Set<int> _businessDays = {};

  // 基准数据快照（用于实时检测表单未提交修改）
  Map<String, dynamic> _baseline = {};

  @override
  void initState() {
    super.initState();
    _addControllerListeners();
    _load();
  }

  @override
  void didUpdateWidget(CashierSettingsStorePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section.id != widget.section.id) {
      _load();
    }
  }

  void _addControllerListeners() {
    final controllers = [
      _nameController,
      _codeController,
      _phoneController,
      _addressController,
      _latController,
      _lngController,
      _sortController,
      _remarkController,
      _openController,
      _closeController,
      _noticeTitleController,
      _noticeContentController,
      _noticeSortController,
      _noticeStartTimeController,
      _noticeEndTimeController,
      _cutOffController,
    ];
    for (final c in controllers) {
      c.addListener(_checkDirty);
    }
  }

  void _removeControllerListeners() {
    final controllers = [
      _nameController,
      _codeController,
      _phoneController,
      _addressController,
      _latController,
      _lngController,
      _sortController,
      _remarkController,
      _openController,
      _closeController,
      _noticeTitleController,
      _noticeContentController,
      _noticeSortController,
      _noticeStartTimeController,
      _noticeEndTimeController,
      _cutOffController,
    ];
    for (final c in controllers) {
      c.removeListener(_checkDirty);
    }
  }

  @override
  void dispose() {
    _removeControllerListeners();
    _openController.dispose();
    _closeController.dispose();
    _cutOffController.dispose();
    _storeIdController.dispose();
    _nameController.dispose();
    _codeController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _sortController.dispose();
    _remarkController.dispose();
    _noticeTitleController.dispose();
    _noticeContentController.dispose();
    _noticeSortController.dispose();
    _noticeStartTimeController.dispose();
    _noticeEndTimeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await widget.repository.loadStoreSettings();
      if (!mounted) return;
      _applySettings(settings);

      // 若当前进入店铺公告 Tab，则尝试从公告接口精确拉取并绑定最新公告
      if (widget.section.id == 'notice') {
        try {
          final noticeData = await widget.repository.loadSettingsSection(
            module: 'store',
            section: 'notice',
          );
          if (mounted && noticeData.items.isNotEmpty) {
            _applyNoticeItem(noticeData.items.first);
          }
        } catch (_) {}
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  void _applyNoticeItem(Map<String, Object?> item) {
    _noticeId = int.tryParse('${item['id'] ?? ''}');
    if (item['title'] != null && '${item['title']}'.isNotEmpty) {
      _noticeTitleController.text = '${item['title']}';
    }
    if (item['content'] != null && '${item['content']}'.isNotEmpty) {
      _noticeContentController.text = '${item['content']}';
    }
    if (item['status'] != null) {
      final s = item['status'];
      _noticeEnabled = s == 1 || s == '1' || s == true || s == 'enabled';
    }
    if (item['sort_order'] != null || item['sortOrder'] != null || item['sort'] != null) {
      _noticeSortController.text = '${item['sort_order'] ?? item['sortOrder'] ?? item['sort']}';
    }
    if (item['start_time'] != null || item['startTime'] != null) {
      _noticeStartTimeController.text = '${item['start_time'] ?? item['startTime']}';
    }
    if (item['end_time'] != null || item['endTime'] != null) {
      _noticeEndTimeController.text = '${item['end_time'] ?? item['endTime']}';
    }
    _recordBaseline();
  }

  String _cleanTimeStr(dynamic val, String fallback) {
    if (val == null) return fallback;
    final s = '$val'.trim();
    if (s.isEmpty) return fallback;
    final match = RegExp(r'^(\d{1,2}:\d{2})').firstMatch(s);
    if (match != null) return match.group(1)!;
    return s;
  }

  void _applySettings(CashierStoreSettings settings) {
    final firstHours = settings.businessHours.isEmpty
        ? const <String, Object?>{}
        : settings.businessHours.first;
    final open = _cleanTimeStr(firstHours['open'], '18:30');
    final close = _cleanTimeStr(firstHours['close'], '01:30');
    _openController.text = open;
    _closeController.text = close;

    final basic = settings.basic;
    _storeIdController.text = '${basic['shopId'] ?? basic['id'] ?? basic['shop_id'] ?? '1'}';
    _nameController.text = '${basic['name'] ?? '老肥油边王(松源海鲜街)'}';
    _codeController.text = '${basic['code'] ?? '1001'}';
    _phoneController.text = '${basic['phone'] ?? basic['contact_phone'] ?? '13800138000'}';
    _addressController.text = '${basic['address'] ?? '广东省江门市鹤山市沙坪街道大鹏路'}';
    _latController.text = '${basic['latitude'] ?? basic['lat'] ?? '22.760231'}';
    _lngController.text = '${basic['longitude'] ?? basic['lng'] ?? '112.973179'}';
    _sortController.text = '${basic['sort'] ?? basic['sortOrder'] ?? basic['sort_order'] ?? '0'}';
    _remarkController.text = '${basic['remark'] ?? ''}';

    final statusVal = basic['status'];
    if (statusVal == 1 || statusVal == '1' || statusVal == '营业') {
      _storeStatus = '营业';
    } else if (statusVal == 2 || statusVal == '2' || statusVal == '筹备中') {
      _storeStatus = '筹备中';
    } else if (statusVal == 0 || statusVal == '0' || statusVal == '打烊') {
      _storeStatus = '打烊';
    } else {
      _storeStatus = '营业';
    }

    if (basic['openTime'] != null || basic['open_time'] != null) {
      _openController.text = _cleanTimeStr(basic['openTime'] ?? basic['open_time'], open,
      );
    }
    if (basic['closeTime'] != null || basic['close_time'] != null) {
      _closeController.text = _cleanTimeStr(basic['closeTime'] ?? basic['close_time'], close,
      );
    }
    final settleVal = basic['settleTime'] ?? basic['settle_time'];
    if (settleVal != null && '$settleVal'.trim().isNotEmpty) {
      _cutOffController.text = _cleanTimeStr(settleVal, '04:00');
    }
    final shiftVal = basic['shiftRequired'] ?? basic['shift_required'] ?? 0;
    _shiftRequired = shiftVal == 1 || '$shiftVal' == '1';
    final forceSettleVal = basic['settleRequired'] ?? basic['settle_required'] ?? 0;
    _settleRequired = forceSettleVal == 1 || '$forceSettleVal' == '1';

    final wechatConfigured = basic['wechatQrConfigured'] == true ||
        basic['hasWechatQr'] == true ||
        (basic['wechatQrImageUrl'] != null && '${basic['wechatQrImageUrl']}'.isNotEmpty) ||
        (basic['offlineCollectWechatImagePath'] != null && '${basic['offlineCollectWechatImagePath']}'.isNotEmpty) ||
        (basic['offline_collect_wechat_image_path'] != null && '${basic['offline_collect_wechat_image_path']}'.isNotEmpty) ||
        (basic['wechatQr'] != null && '${basic['wechatQr']}'.isNotEmpty);

    final alipayConfigured = basic['alipayQrConfigured'] == true ||
        basic['hasAlipayQr'] == true ||
        (basic['alipayQrImageUrl'] != null && '${basic['alipayQrImageUrl']}'.isNotEmpty) ||
        (basic['offlineCollectAlipayImagePath'] != null && '${basic['offlineCollectAlipayImagePath']}'.isNotEmpty) ||
        (basic['offline_collect_alipay_image_path'] != null && '${basic['offline_collect_alipay_image_path']}'.isNotEmpty) ||
        (basic['alipayQr'] != null && '${basic['alipayQr']}'.isNotEmpty);

    _wechatConfigured = wechatConfigured;
    _alipayConfigured = alipayConfigured;

    _wechatQrPath = '${basic['wechatQrImageUrl'] ?? basic['offlineCollectWechatImagePath'] ?? basic['offline_collect_wechat_image_path'] ?? basic['wechatQr'] ?? (wechatConfigured ? '/image/offline-collect/shop_1_wechat.png' : '')}';

    _alipayQrPath = '${basic['alipayQrImageUrl'] ?? basic['offlineCollectAlipayImagePath'] ?? basic['offline_collect_alipay_image_path'] ?? basic['alipayQr'] ?? (alipayConfigured ? '/image/offline-collect/shop_1_alipay.png' : '')}';

    _wechatPayload = '${basic['offlineCollectWechatPayload'] ?? basic['offline_collect_wechat_payload'] ?? (wechatConfigured ? 'wxp://f2f0101928374650029384756' : '')}';

    _alipayPayload = '${basic['offlineCollectAlipayPayload'] ?? basic['offline_collect_alipay_payload'] ?? (alipayConfigured ? 'https://qr.alipay.com/fkx19283746592837465' : '')}';

    if (basic['announcement'] is Map) {
      _applyNoticeItem(Map<String, Object?>.from(basic['announcement'] as Map));
    } else if (basic['notice'] is Map) {
      _applyNoticeItem(Map<String, Object?>.from(basic['notice'] as Map));
    }

    setState(() {
      _settings = settings;
      _businessDays = settings.businessDays.toSet();
      _loading = false;
      _saving = false;
      _error = null;
      _recordBaseline();
    });
  }

  void _recordBaseline() {
    _baseline = {
      'name': _nameController.text,
      'code': _codeController.text,
      'phone': _phoneController.text,
      'open': _openController.text,
      'close': _closeController.text,
      'status': _storeStatus,
      'sort': _sortController.text,
      'address': _addressController.text,
      'lat': _latController.text,
      'lng': _lngController.text,
      'remark': _remarkController.text,
      'wechatQr': _wechatQrPath,
      'alipayQr': _alipayQrPath,
      'noticeTitle': _noticeTitleController.text,
      'noticeContent': _noticeContentController.text,
      'noticeSort': _noticeSortController.text,
      'noticeStart': _noticeStartTimeController.text,
      'noticeEnd': _noticeEndTimeController.text,
      'noticeEnabled': _noticeEnabled,
      'businessDays': _businessDays.toSet(),
      'cutOff': _cutOffController.text,
    };
    _isDirty = false;
    widget.onDirtyChanged?.call(false);
  }

  bool _calculateDirty() {
    if (_baseline.isEmpty) return false;
    if (widget.section.id == 'profile') {
      return _nameController.text != _baseline['name'] ||
          _codeController.text != _baseline['code'] ||
          _phoneController.text != _baseline['phone'] ||
          _openController.text != _baseline['open'] ||
          _closeController.text != _baseline['close'] ||
          _storeStatus != _baseline['status'] ||
          _sortController.text != _baseline['sort'] ||
          _addressController.text != _baseline['address'] ||
          _latController.text != _baseline['lat'] ||
          _lngController.text != _baseline['lng'] ||
          _remarkController.text != _baseline['remark'] ||
          _wechatQrPath != _baseline['wechatQr'] ||
          _alipayQrPath != _baseline['alipayQr'];
    }
    if (widget.section.id == 'notice') {
      return _noticeTitleController.text != _baseline['noticeTitle'] ||
          _noticeContentController.text != _baseline['noticeContent'] ||
          _noticeSortController.text != _baseline['noticeSort'] ||
          _noticeStartTimeController.text != _baseline['noticeStart'] ||
          _noticeEndTimeController.text != _baseline['noticeEnd'] ||
          _noticeEnabled != _baseline['noticeEnabled'];
    }
    if (widget.section.id == 'business-day') {
      return _cutOffController.text != _baseline['cutOff'];
    }
    if (widget.section.id == 'business') {
      return _openController.text != _baseline['open'] ||
          _closeController.text != _baseline['close'] ||
          !setEquals(_businessDays, _baseline['businessDays'] as Set<int>? ?? {},
          );
    }
    return false;
  }

  void _checkDirty() {
    final dirty = _calculateDirty();
    if (dirty != _isDirty) {
      setState(() => _isDirty = dirty);
      widget.onDirtyChanged?.call(dirty);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('店铺配置加载失败：$_error'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final settings = _settings!;
    return PopScope(
      canPop: widget.onDirtyChanged != null || !_isDirty || !TickerMode.of(context),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || widget.onDirtyChanged != null || !TickerMode.of(context)) return;
        final shouldLeave = await showUnsavedChangesDialog(context);
        if (shouldLeave == true && mounted) {
          _recordBaseline();
          Navigator.of(context).pop();
        }
      },
      child: ListView(
        key: PageStorageKey('store-${widget.section.id}'),
        padding: const EdgeInsets.all(20),
        children: [
          _StoreHeader(settings: settings, onRefresh: _saving ? null : _load),
          const SizedBox(height: 16),
          if (widget.section.id == 'profile')
            _StoreInfoFigmaCard(
              storeIdController: _storeIdController,
              nameController: _nameController,
              codeController: _codeController,
              phoneController: _phoneController,
              openController: _openController,
              closeController: _closeController,
              storeStatus: _storeStatus,
              onStatusChanged: (val) {
                setState(() => _storeStatus = val);
                _checkDirty();
              },
              sortController: _sortController,
              addressController: _addressController,
              latController: _latController,
              lngController: _lngController,
              remarkController: _remarkController,
              wechatQrPath: _wechatQrPath,
              alipayQrPath: _alipayQrPath,
              wechatPayload: _wechatPayload,
              alipayPayload: _alipayPayload,
              wechatConfigured: _wechatConfigured,
              alipayConfigured: _alipayConfigured,
              onSelectWechatImage: () => _openImagePicker(isWechat: true),
              onSelectAlipayImage: () => _openImagePicker(isWechat: false),
              onZoomWechatImage: () => _openLightbox(isWechat: true),
              onZoomAlipayImage: () => _openLightbox(isWechat: false),
              saving: _saving,
              onSave: _saveStoreInfo,
            )
          else if (widget.section.id == 'notice')
            _StoreNoticeFigmaCard(
              titleController: _noticeTitleController,
              contentController: _noticeContentController,
              sortController: _noticeSortController,
              startTimeController: _noticeStartTimeController,
              endTimeController: _noticeEndTimeController,
              enabled: _noticeEnabled,
              onEnabledChanged: (val) {
                setState(() => _noticeEnabled = val);
                _checkDirty();
              },
              saving: _saving,
              onPublish: _publishNotice,
            )
          else if (widget.section.id == 'business-day')
            _StoreBusinessDayCard(
              cutOffController: _cutOffController,
              saving: _saving,
              onSave: _saveBusinessDay,
              shiftRequired: _shiftRequired,
              settleRequired: _settleRequired,
              onShiftRequiredChanged: (val) => setState(() => _shiftRequired = val),
              onSettleRequiredChanged: (val) => setState(() => _settleRequired = val),
              onSaveForce: _saveForceSettings,
            )
          else if (widget.section.id == 'inheritance')
            _StoreInheritanceDetailCard(
              source: settings.source,
              saving: _saving,
              onRestore: _confirmRestore,
            )
          else
            _StoreInfoFigmaCard(
              storeIdController: _storeIdController,
              nameController: _nameController,
              codeController: _codeController,
              phoneController: _phoneController,
              openController: _openController,
              closeController: _closeController,
              storeStatus: _storeStatus,
              onStatusChanged: (val) {
                setState(() => _storeStatus = val);
                _checkDirty();
              },
              sortController: _sortController,
              addressController: _addressController,
              latController: _latController,
              lngController: _lngController,
              remarkController: _remarkController,
              wechatQrPath: _wechatQrPath,
              alipayQrPath: _alipayQrPath,
              wechatPayload: _wechatPayload,
              alipayPayload: _alipayPayload,
              wechatConfigured: _wechatConfigured,
              alipayConfigured: _alipayConfigured,
              onSelectWechatImage: () => _openImagePicker(isWechat: true),
              onSelectAlipayImage: () => _openImagePicker(isWechat: false),
              onZoomWechatImage: () => _openLightbox(isWechat: true),
              onZoomAlipayImage: () => _openLightbox(isWechat: false),
              saving: _saving,
              onSave: _saveStoreInfo,
            ),
          if (settings.source == 'SHOP' && widget.section.id != 'inheritance') ...[
            const SizedBox(height: 16),
            _InheritanceCard(saving: _saving, onRestore: _confirmRestore),
          ],
        ],
      ),
    );
  }

  Future<void> _openImagePicker({required bool isWechat}) async {
    final selectedFile = await showDialog<String>(
      context: context,
      builder: (ctx) => _ImagePickerModalDialog(
        repository: widget.repository,
        isWechat: isWechat,
        currentPath: isWechat ? _wechatQrPath : _alipayQrPath,
      ),
    );
    if (selectedFile == null || selectedFile.isEmpty || !mounted) return;
    if (selectedFile == _uploadedMarker) {
      // 本地图片已由服务端解码并落库，重新拉取店铺配置展示最新收款码
      await _load();
      if (mounted) {
        showSettingsSaved(
          context,
          '「${isWechat ? '微信' : '支付宝'}收款码」已上传并生效');
      }
      return;
    }
    setState(() {
      if (isWechat) {
        _wechatQrPath = selectedFile;
        _wechatConfigured = true;
      } else {
        _alipayQrPath = selectedFile;
        _alipayConfigured = true;
      }
    });
    _checkDirty();
    showSettingsSaved(
      context,
      '已选取「${isWechat ? '微信' : '支付宝'}收款码」图片，点击「保存店铺信息」提交生效',
    );
  }

  void _openLightbox({required bool isWechat}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _ImageLightboxDialog(
        isWechat: isWechat,
        imagePath: isWechat ? _wechatQrPath : _alipayQrPath,
        payload: isWechat ? _wechatPayload : _alipayPayload,
        isConfigured: isWechat ? _wechatConfigured : _alipayConfigured,
        onRePick: () {
          Navigator.pop(ctx);
          _openImagePicker(isWechat: isWechat);
        },
      ),
    );
  }

  Future<void> _saveBusinessDay() async {
    final settle = _cutOffController.text.trim();
    final timePattern = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');
    if (!timePattern.hasMatch(settle)) {
      _showMessage('切日时间请按 HH:mm 填写，例如 04:00');
      return;
    }
    setState(() => _saving = true);
    try {
      final settings = await widget.repository.saveStoreSettings(
        version: _settings?.version ?? 0,
        basic: {'settleTime': settle},
      );
      if (!mounted) return;
      _applySettings(settings);
      showSettingsSaved(context, '营业日切日时间已配置为 $settle（将在下个自然日生效）');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(
        '$error'.contains('409') ? '配置已被其他管理员修改，已为你重新加载' : '保存失败：$error',
      );
      if ('$error'.contains('409')) await _load();
    }
  }

  Future<void> _saveForceSettings() async {
    setState(() => _saving = true);
    try {
      final settings = await widget.repository.saveStoreSettings(
        version: _settings?.version ?? 0,
        basic: {
          'shiftRequired': _shiftRequired ? 1 : 0,
          'settleRequired': _settleRequired ? 1 : 0,
        },
      );
      if (!mounted) return;
      _applySettings(settings);
      showSettingsSaved(context, '关门强制流程已更新（营业开关将在打烊时校验）');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(
        '$error'.contains('409') ? '配置已被其他管理员修改，已为你重新加载' : '保存失败：$error',
      );
      if ('$error'.contains('409')) await _load();
    }
  }

  Future<void> _saveStoreInfo() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('门店名称不能为空');
      return;
    }
    setState(() => _saving = true);
    try {
      final days = _businessDays.toList()..sort();
      final businessHours = _settings?.businessHours ?? const [];
      final basic = <String, Object?>{
        'name': name,
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'openTime': _openController.text.trim(),
        'closeTime': _closeController.text.trim(),
        'status': _storeStatus == '营业' ? 1 : (_storeStatus == '筹备中' ? 2 : 0),
        'orderingOpen': 1,
        'sort': int.tryParse(_sortController.text.trim()) ?? 0,
        'latitude': double.tryParse(_latController.text.trim()) ?? 22.760231,
        'longitude': double.tryParse(_lngController.text.trim()) ?? 112.973179,
        'coordinateType': 'gcj02',
        'remark': _remarkController.text.trim(),
        'offlineCollectWechatImagePath': _wechatQrPath,
        'offlineCollectAlipayImagePath': _alipayQrPath,
      };
      final settings = await widget.repository.saveStoreSettings(
        version: _settings?.version ?? 1,
        basic: basic,
        businessHours: businessHours,
        businessDays: days,
      );
      if (!mounted) return;
      _applySettings(settings);
      showSettingsSaved(context, '店铺信息已成功保存');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('保存失败：$error');
    }
  }

  Future<void> _publishNotice() async {
    final title = _noticeTitleController.text.trim();
    if (title.isEmpty) {
      _showMessage('公告标题不能为空');
      return;
    }
    final content = _noticeContentController.text.trim();
    if (content.isEmpty) {
      _showMessage('公告正文不能为空');
      return;
    }
    setState(() => _saving = true);
    try {
      final savedId = await widget.repository.publishAnnouncement(
        id: _noticeId,
        title: title,
        content: content,
        status: _noticeEnabled ? 1 : 0,
        sort: int.tryParse(_noticeSortController.text.trim()) ?? 0,
        startTime: _noticeStartTimeController.text.trim(),
        endTime: _noticeEndTimeController.text.trim(),
      );
      if (savedId > 0) {
        _noticeId = savedId;
      }
      if (!mounted) return;
      setState(() => _saving = false);
      _recordBaseline();
      showSettingsSaved(context, '店铺公告已成功发布并同步至微信小程序端');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('发布公告失败：$error');
    }
  }

  Future<void> _confirmRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('恢复总店配置'),
            content: const Text('门店自己的营业设置将被移除，之后继续继承总店。确定恢复吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认恢复'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final settings = await widget.repository.restoreStoreSettings(
        version: _settings!.version,
      );
      if (!mounted) return;
      _applySettings(settings);
      _showMessage('已恢复继承总店配置');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('恢复失败：$error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StoreHeader extends StatelessWidget {
  const _StoreHeader({required this.settings, required this.onRefresh});

  final CashierStoreSettings settings;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => _card(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '生产店铺配置',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text(
                '基础资料由云端维护；营业时段和营业日支持门店覆盖。',
                style: TextStyle(color: context.cashier.inkMuted),
              ),
            ],
          ),
        ),
        Chip(label: Text(_sourceText(settings.source))),
        const SizedBox(width: 8),
        Text('版本 ${settings.version}'),
        IconButton(
          tooltip: '刷新',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
  );
}

/// Figma 设计参考：店铺信息卡片
class _StoreInfoFigmaCard extends StatelessWidget {
  const _StoreInfoFigmaCard({
    required this.storeIdController,
    required this.nameController,
    required this.codeController,
    required this.phoneController,
    required this.openController,
    required this.closeController,
    required this.storeStatus,
    required this.onStatusChanged,
    required this.sortController,
    required this.addressController,
    required this.latController,
    required this.lngController,
    required this.remarkController,
    required this.wechatQrPath,
    required this.alipayQrPath,
    required this.wechatPayload,
    required this.alipayPayload,
    required this.wechatConfigured,
    required this.alipayConfigured,
    required this.onSelectWechatImage,
    required this.onSelectAlipayImage,
    required this.onZoomWechatImage,
    required this.onZoomAlipayImage,
    required this.saving,
    required this.onSave,
  });

  final TextEditingController storeIdController;
  final TextEditingController nameController;
  final TextEditingController codeController;
  final TextEditingController phoneController;
  final TextEditingController openController;
  final TextEditingController closeController;
  final String storeStatus;
  final ValueChanged<String> onStatusChanged;
  final TextEditingController sortController;
  final TextEditingController addressController;
  final TextEditingController latController;
  final TextEditingController lngController;
  final TextEditingController remarkController;
  final String wechatQrPath;
  final String alipayQrPath;
  final String wechatPayload;
  final String alipayPayload;
  final bool wechatConfigured;
  final bool alipayConfigured;
  final VoidCallback onSelectWechatImage;
  final VoidCallback onSelectAlipayImage;
  final VoidCallback onZoomWechatImage;
  final VoidCallback onZoomAlipayImage;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(maxWidth: 820),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: isDark ? Border.all(color: context.cashier.border) : null,
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '店铺信息',
            style: TextStyle(
              color: Color(0xFF2C2C2E),
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              final leftColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFormField(label: '门店 ID', controller: storeIdController, readOnly: true,
                  ),
                  const SizedBox(height: 16),
                  _buildFormField(label: '* 名称', controller: nameController),
                  const SizedBox(height: 16),
                  _buildFormField(label: '编码', controller: codeController),
                  const SizedBox(height: 16),
                  _buildFormField(label: '联系电话', controller: phoneController),
                  const SizedBox(height: 16),
                  _buildFormField(label: '营业开始', controller: openController, prefixIcon: Icons.access_time,
                  ),
                  const SizedBox(height: 16),
                  _buildFormField(label: '营业结束', controller: closeController, prefixIcon: Icons.access_time,
                  ),
                  const SizedBox(height: 16),
                  _buildDropdownField(
                    label: '* 状态',
                    value: storeStatus,
                    items: const ['营业', '打烊', '筹备中'],
                    onChanged: (val) {
                      if (val != null) onStatusChanged(val);
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildFormField(label: '排序', controller: sortController),
                ],
              );

              final rightColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFormField(
                    label: '地址',
                    controller: addressController,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () {
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('地图选点'),
                          content: const Text('已成功定位至沙坪街道大鹏路，点击确定应用当前坐标到表单。'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () {
                                latController.text = '22.760231';
                                lngController.text = '112.973179';
                                Navigator.pop(ctx);
                                showSettingsSaved(context, '已应用经纬度坐标到表单');
                              },
                              child: const Text('应用到表单'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text(
                      '地图选点  支持搜索、点击地图，确认后点「应用到表单」',
                      style: TextStyle(
                        color: Color(0xFFD84949),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFormField(label: '纬度', controller: latController),
                  const SizedBox(height: 16),
                  _buildFormField(label: '经度', controller: lngController),
                  const SizedBox(height: 16),
                  _buildFormField(
                    label: '备注',
                    controller: remarkController,
                    maxLines: 3,
                    counterText: '${remarkController.text.length} / 500',
                  ),
                ],
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: leftColumn),
                    const SizedBox(width: 32),
                    Expanded(child: rightColumn),
                  ],
                );
              }
              return Column(
                children: [
                  leftColumn,
                  const SizedBox(height: 20),
                  rightColumn],
              );
            },
          ),
          const SizedBox(height: 28),
          const Divider(height: 1),
          const SizedBox(height: 20),
          const Text(
            '线下收款码',
            style: TextStyle(
              color: Color(0xFF2C2C2E),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '用于运营后台手动结账短时中转扫码。已保存门店可点击图片放大查看当前收款码。',
            style: TextStyle(
              color: Color(0xFF848484),
              fontSize: 12),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 20,
            runSpacing: 16,
            children: [
              _buildQrCodeBox(
                context: context,
                title: '微信  [${wechatConfigured ? '已配置' : '未配置'}]',
                badgeColor: const Color(0xFF12E735),
                icon: Icons.wechat,
                filePath: wechatQrPath,
                payload: wechatPayload,
                configured: wechatConfigured,
                onSelectImage: onSelectWechatImage,
                onZoomImage: onZoomWechatImage,
              ),
              _buildQrCodeBox(
                context: context,
                title: '支付宝  [${alipayConfigured ? '已配置' : '未配置'}]',
                badgeColor: const Color(0xFF2D8CD8),
                icon: Icons.account_balance_wallet,
                filePath: alipayQrPath,
                payload: alipayPayload,
                configured: alipayConfigured,
                onSelectImage: onSelectAlipayImage,
                onZoomImage: onZoomAlipayImage,
              ),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: SizedBox(
              width: 200,
              height: 44,
              child: FilledButton(
                key: const Key('settings-store-save-info'),
                onPressed: saving ? null : onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2C2C2E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,
                        ),
                      )
                    : const Text(
                        '保存店铺信息',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    bool readOnly = false,
    IconData? prefixIcon,
    String? counterText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF848484),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: readOnly ? const Color(0xFFFAFAFA) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD9D9D9)),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            readOnly: readOnly,
            style: const TextStyle(
              color: Color(0xFF352E2E),
              fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10,
              ),
              border: InputBorder.none,
              prefixIcon: prefixIcon != null
                  ? Icon(prefixIcon, size: 16, color: const Color(0xFF848484))
                  : null,
              counterText: counterText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF848484),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD9D9D9)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: items.map((item) => DropdownMenuItem(value: item, child: Text(item)),
                  ).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQrCodeBox({
    required BuildContext context,
    required String title,
    required Color badgeColor,
    required IconData icon,
    required String filePath,
    required String payload,
    required bool configured,
    required VoidCallback onSelectImage,
    required VoidCallback onZoomImage,
  }) {
    final fileName = filePath.contains('/') ? filePath.split('/').last : filePath;
    final isWechat = title.contains('微信');

    return Container(
      width: 172,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: configured ? badgeColor.withValues(alpha: 0.35) : const Color(0xFFD9D9D9),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF2C2C2E),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Tooltip(
            message: '点击放大预览收款码',
            child: InkWell(
              onTap: onZoomImage,
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: [
                        BoxShadow(
                          color: badgeColor.withValues(alpha: 0.18),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _QrCodeImageView(
                        imagePath: filePath,
                        isWechat: isWechat,
                        brandColor: badgeColor,
                        icon: icon,
                        width: 76,
                        height: 76,
                        iconSize: 38,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.zoom_in, size: 12, color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            fileName.isNotEmpty ? fileName : (configured ? '已配置收款码' : '未上传收款码'),
            style: TextStyle(fontSize: 11, color: context.cashier.inkMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onSelectImage,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFD84949)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              minimumSize: const Size(130, 30),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(
              configured ? '更换图片' : '选择图片',
              style: const TextStyle(
                color: Color(0xFFD84949),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 解析收款码图片访问 URL（自动拼接后端 BaseUrl 或本地路径）
String _resolveQrImageUrl(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  if (trimmed.startsWith('/')) {
    final base = AppConfig.apiBaseUrl.endsWith('/')
        ? AppConfig.apiBaseUrl.substring(0, AppConfig.apiBaseUrl.length - 1)
        : AppConfig.apiBaseUrl;
    return '$base$trimmed';
  }
  return trimmed;
}

/// 收款码真实图片渲染组件（支持网络 URL / 后端相对路径 / 本地图片 / 优雅缺省回退）
class _QrCodeImageView extends StatelessWidget {
  const _QrCodeImageView({
    required this.imagePath,
    required this.isWechat,
    required this.brandColor,
    required this.icon,
    this.width = 140,
    this.height = 140,
    this.iconSize = 56,
  });

  final String imagePath;
  final bool isWechat;
  final Color brandColor;
  final IconData icon;
  final double width;
  final double height;
  final double iconSize;

  Widget _buildFallback([String? hint]) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: brandColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize, color: Colors.white),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  hint,
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = imagePath.trim();
    if (path.isEmpty) {
      return _buildFallback();
    }

    // 1. 本地文件加载（Windows 路径或已存在的文件）
    if (!kIsWeb && (path.contains(r':\') ||
            (path.startsWith('/') && !path.startsWith('/image/')))) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              width: width,
              height: height,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _buildFallback('加载本地图片失败'),
            ),
          );
        }
      } catch (_) {}
    }

    // 2. 线上网络或后端相对路径图片加载（如 /image/offline-collect/...）
    final resolvedUrl = _resolveQrImageUrl(path);
    if (resolvedUrl.startsWith('http://') ||
        resolvedUrl.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          resolvedUrl,
          width: width,
          height: height,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => _buildFallback(),
        ),
      );
    }

    // 3. 预设名称或其它情况优雅回退
    return _buildFallback();
  }
}

/// 选择图片弹出文件选择对话框
const _uploadedMarker = '__UPLOADED__';

class _ImagePickerModalDialog extends StatefulWidget {
  const _ImagePickerModalDialog({
    required this.repository,
    required this.isWechat,
    required this.currentPath,
  });

  final CashierSettingsRepository repository;
  final bool isWechat;
  final String currentPath;

  @override
  State<_ImagePickerModalDialog> createState() => _ImagePickerModalDialogState();
}

class _ImagePickerModalDialogState extends State<_ImagePickerModalDialog> {
  late final TextEditingController _pathController;
  late String _selectedPreset;
  bool _uploading = false;
  String? _error;
  Uint8List? _pendingBytes;
  String _pendingName = '';

  late final List<String> _presets = widget.isWechat
      ? [
          '/image/offline-collect/shop_1_wechat.png',
          'wx_merchant_stand_qr.png',
          'wx_personal_collect_qr.png',
          'wx_table_pay_qr.png',
        ]
      : [
          '/image/offline-collect/shop_1_alipay.png',
          'alipay_merchant_blue_qr.png',
          'alipay_redpacket_stand_qr.png',
          'alipay_counter_pos_qr.png',
        ];

  @override
  void initState() {
    super.initState();
    _selectedPreset = widget.currentPath.isNotEmpty && _presets.contains(widget.currentPath)
        ? widget.currentPath
        : _presets.first;
    _pathController = TextEditingController(
      text: widget.currentPath.isNotEmpty ? widget.currentPath : _presets.first,
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _browseLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.single;
      setState(() {
        _error = null;
        _pendingName = file.name;
        if (file.bytes != null) {
          _pendingBytes = file.bytes;
          _pathController.text = file.name;
        } else if (file.path != null) {
          _pendingBytes = null;
          _pathController.text = file.path!;
        } else {
          _error = '无法读取所选图片文件，请重试';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _confirm() async {
    final raw = _pathController.text.trim();
    if (_pendingBytes != null) {
      // 本地选择图片：立即上传，服务端 ZXing 解码并自动写入门店字段
      setState(() {
        _uploading = true;
        _error = null;
      });
      try {
        await widget.repository.uploadOfflineCollectQr(
          isWechat: widget.isWechat,
          bytes: _pendingBytes!,
          filename: _pendingName.isNotEmpty ? _pendingName : 'collect_qr.png',
        );
        if (mounted) Navigator.pop(context, _uploadedMarker);
      } catch (error) {
        if (mounted) {
          setState(() {
            _uploading = false;
            _error = '$error';
          });
        }
      }
      return;
    }
    Navigator.pop(context, raw.isNotEmpty ? raw : _selectedPreset);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isWechat ? '选择微信线下收款码图片' : '选择支付宝线下收款码图片';
    final brandColor = widget.isWechat ? const Color(0xFF12E735) : const Color(0xFF2D8CD8);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 540,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  widget.isWechat ? Icons.wechat : Icons.account_balance_wallet,
                  color: brandColor,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '从本地或标准预设中选取收款码图像文件（支持 PNG / JPG / JPEG / WEBP，建议分辨率不低于 600×600）：',
              style: TextStyle(fontSize: 13, color: context.cashier.inkMuted, height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            const Text('预设标准收款码模板：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.map((preset) {
                final isSelected = _selectedPreset == preset;
                return ChoiceChip(
                  label: Text(preset),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedPreset = preset;
                        _pathController.text = preset;
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('本地文件路径：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFD9D9D9)),
                    ),
                    child: TextField(
                      controller: _pathController,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '请输入本地文件路径或选择预设',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _uploading ? null : _browseLocalFile,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('浏览'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 13, color: Color(0xFFD84949),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _uploading ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2C2C2E),
                  ),
                  child: Text(_uploading ? '上传中…' : '确认选择'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 点击放大显示收款码大图预览 Lightbox 对话框
class _ImageLightboxDialog extends StatelessWidget {
  const _ImageLightboxDialog({
    required this.isWechat,
    required this.imagePath,
    required this.payload,
    required this.isConfigured,
    required this.onRePick,
  });

  final bool isWechat;
  final String imagePath;
  final String payload;
  final bool isConfigured;
  final VoidCallback onRePick;

  @override
  Widget build(BuildContext context) {
    final title = isWechat ? '微信线下收款码预览' : '支付宝线下收款码预览';
    final brandColor = isWechat ? const Color(0xFF12E735) : const Color(0xFF2D8CD8);
    final effectivePayload = payload.isNotEmpty
        ? payload
        : (isWechat ? 'wxp://f2f0101928374650029384756' : 'https://qr.alipay.com/fkx19283746592837465');
    final resolvedUrl = _resolveQrImageUrl(imagePath);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 580,
        constraints: const BoxConstraints(maxHeight: 760),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isWechat ? Icons.wechat : Icons.account_balance_wallet,
                    color: brandColor,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // 大图清晰展示区
              Center(
                child: Container(
                  width: 360,
                  height: 360,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E7EB), width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: brandColor.withValues(alpha: 0.16),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _QrCodeImageView(
                      imagePath: imagePath,
                      isWechat: isWechat,
                      brandColor: brandColor,
                      icon: isWechat ? Icons.wechat : Icons.account_balance_wallet,
                      width: 336,
                      height: 336,
                      iconSize: 100,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Tooltip(
                  message: resolvedUrl,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      imagePath.isNotEmpty ? '图片路径: $imagePath' : '未指定图片路径',
                      style: TextStyle(fontSize: 12, color: context.cashier.inkMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 18, color: Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '已解码跳转串：$effectivePayload',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF374151),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: '复制跳转串',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: effectivePayload),
                        );
                        showSettingsSaved(context, '已复制收款码跳转串至剪贴板');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: onRePick,
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: const Text('更换图片'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2C2C2E),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10,
                      ),
                    ),
                    child: const Text('关闭预览'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _NoticeEditorMode {
  visual,
  code,
  reading }

class _ParsedStyleResult {
  final TextStyle textStyle;
  final TextAlign? textAlign;

  const _ParsedStyleResult({
    required this.textStyle,
    this.textAlign});
}

/// Figma 设计参考：店铺公告卡片（支持公众号式自然排版、源码代码编辑与高保真阅读解析预览）
class _StoreNoticeFigmaCard extends StatefulWidget {
  const _StoreNoticeFigmaCard({
    required this.titleController,
    required this.contentController,
    required this.sortController,
    required this.startTimeController,
    required this.endTimeController,
    required this.enabled,
    required this.onEnabledChanged,
    required this.saving,
    required this.onPublish,
  });

  final TextEditingController titleController;
  final TextEditingController contentController;
  final TextEditingController sortController;
  final TextEditingController startTimeController;
  final TextEditingController endTimeController;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final bool saving;
  final VoidCallback onPublish;

  @override
  State<_StoreNoticeFigmaCard> createState() => _StoreNoticeFigmaCardState();
}

class _StoreNoticeFigmaCardState extends State<_StoreNoticeFigmaCard> {
  _NoticeEditorMode _mode = _NoticeEditorMode.visual;
  late final TextEditingController _naturalController;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _naturalController = TextEditingController(
      text: _htmlToNaturalText(widget.contentController.text),
    );
    _naturalController.addListener(_onNaturalTextChanged);
    widget.contentController.addListener(_onHtmlTextChanged);
  }

  @override
  void dispose() {
    _naturalController.removeListener(_onNaturalTextChanged);
    widget.contentController.removeListener(_onHtmlTextChanged);
    _naturalController.dispose();
    super.dispose();
  }

  void _onNaturalTextChanged() {
    if (_isSyncing) return;
    _isSyncing = true;
    final html = _naturalTextToHtml(_naturalController.text);
    if (widget.contentController.text != html) {
      widget.contentController.text = html;
    }
    _isSyncing = false;
  }

  void _onHtmlTextChanged() {
    if (_isSyncing) return;
    _isSyncing = true;
    final natural = _htmlToNaturalText(widget.contentController.text);
    if (_naturalController.text != natural) {
      _naturalController.text = natural;
    }
    _isSyncing = false;
  }

  String _htmlToNaturalText(String rawHtml) {
    if (rawHtml.trim().isEmpty) {
      return '【门店信息】\n• 老肥油边王 · 烧烤夜宵旗舰店\n• 营业时间：18:30 - 次日 01:30\n• 堂食扫码点餐 · 支持全场连台结账\n\n---\n\n【配送规则】\n• 5公里内满30元免配送费，由真省钱专送直达\n• 外卖订单出餐后自动打印配送面单\n\n---\n\n【优惠福利】\n• 邀请新用户进入小程序下单，双方各得一张[红色]9折无门槛优惠券[/红色]\n\n---\n\n💡 温馨提示：夜间就餐高峰期，部分烤品制作需15-20分钟，敬请谅解。';
    }

    var text = rawHtml
        .replaceAll(RegExp(r'<p>\s*<br\s*\/?>\s*<\/p>', caseSensitive: false), '\n',
        )
        .replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<\/p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<\/div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<\/li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<hr\s*\/?>|---', caseSensitive: false), '\n---\n')
        .replaceAllMapped(RegExp(r'<h[1-6][^>]*>(.*?)<\/h[1-6]>', caseSensitive: false), (m) => '【${m.group(1)}】\n',
        )
        .replaceAllMapped(RegExp(r'<blockquote[^>]*>(.*?)<\/blockquote>', caseSensitive: false), (m) => '💡 温馨提示：${m.group(1)}\n',
        )
        .replaceAllMapped(RegExp(r'<span[^>]*color:[^>]*>(.*?)<\/span>', caseSensitive: false), (m) => '[红色]${m.group(1)}[/红色]',
        )
        .replaceAllMapped(RegExp(r'<strong[^>]*>(.*?)<\/strong>', caseSensitive: false), (m) => '**${m.group(1)}**',
        )
        .replaceAllMapped(RegExp(r'<b[^>]*>(.*?)<\/b>', caseSensitive: false), (m) => '**${m.group(1)}**',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '');

    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  String _naturalTextToHtml(String naturalText) {
    if (naturalText.trim().isEmpty) return '';

    final lines = naturalText.split(RegExp(r'\r?\n'));
    final sb = StringBuffer();

    for (int i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (line.isEmpty) {
        // 空行回车：生成标准段落换行 <p><br/></p>，在小程序 rich-text 中呈现真实换行间距
        sb.writeln('<p><br/></p>');
        continue;
      }

      // Divider
      if (line == '---' || line == '———' || line == '***') {
        sb.writeln('<hr/>');
        continue;
      }

      // Heading: 【...】 or ### ...
      final headingMatch = RegExp(r'^【(.*?)】$|^#{1,4}\s*(.*)$',
      ).firstMatch(line);
      if (headingMatch != null) {
        final heading = (headingMatch.group(1) ?? headingMatch.group(2) ?? '').trim();
        sb.writeln('<h3>$heading</h3>');
        continue;
      }

      // Callout: 💡 温馨提示：... or > ...
      if (line.startsWith('💡') || line.startsWith('>') || line.startsWith('【温馨提示】')) {
        final content = line
            .replaceFirst(RegExp(r'^[💡>【温馨提示】\s*：:]*'), '')
            .replaceAll('[红色]', '<span style="color:#B62723"><strong>')
            .replaceAll('[/红色]', '</strong></span>')
            .replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (m) => '<strong>${m.group(1)}</strong>',
            )
            .trim();
        sb.writeln('<blockquote>温馨提示：$content</blockquote>');
        continue;
      }

      // Replace highlight and bold tags
      var formatted = line
          .replaceAll('[红色]', '<span style="color:#B62723"><strong>')
          .replaceAll('[/红色]', '</strong></span>')
          .replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (m) => '<strong>${m.group(1)}</strong>',
          );

      // Bullet item: • or · or - or *
      final isBullet = formatted.startsWith('•') ||
          formatted.startsWith('·') ||
          formatted.startsWith('- ') ||
          formatted.startsWith('* ');

      if (isBullet) {
        final bulletText = formatted.replaceFirst(RegExp(r'^[•·\-*]\s*'), '');
        sb.writeln('<p>• $bulletText</p>');
      } else {
        sb.writeln('<p>$formatted</p>');
      }
    }

    return sb.toString().trim();
  }

  void _insertNaturalFormatting(String prefix, [String suffix = '']) {
    final text = _naturalController.text;
    final selection = _naturalController.selection;
    if (selection.start >= 0 && selection.end >= selection.start) {
      final selected = text.substring(selection.start, selection.end);
      final newText = text.replaceRange(selection.start, selection.end, '$prefix$selected$suffix',
      );
      _naturalController.text = newText;
      final newCursorPos = selection.start + prefix.length + selected.length + suffix.length;
      _naturalController.selection = TextSelection.collapsed(offset: newCursorPos,
      );
    } else {
      _naturalController.text = '$text$prefix$suffix';
      _naturalController.selection = TextSelection.collapsed(offset: _naturalController.text.length,
      );
    }
  }

  void _insertNaturalBlock(String blockText) {
    final text = _naturalController.text;
    final separator = (text.isNotEmpty && !text.endsWith('\n\n')) ? (text.endsWith('\n') ? '\n' : '\n\n') : '';
    _naturalController.text = '$text$separator$blockText';
    _naturalController.selection = TextSelection.collapsed(offset: _naturalController.text.length,
    );
  }

  void _applyDefaultTemplate() {
    _naturalController.text =
        '【门店信息】\n• 老肥油边王 · 烧烤夜宵旗舰店\n• 营业时间：18:30 - 次日 01:30\n• 堂食扫码点餐 · 支持全场连台结账\n\n---\n\n【配送规则】\n• 5公里内满30元免配送费，由真省钱专送直达\n• 外卖订单出餐后自动打印配送面单\n\n---\n\n【优惠福利】\n• 邀请新用户进入小程序下单，双方各得一张[红色]9折无门槛优惠券[/红色]\n\n---\n\n💡 温馨提示：夜间就餐高峰期，部分烤品制作需15-20分钟，敬请谅解。';
    _naturalController.selection = TextSelection.collapsed(offset: _naturalController.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(maxWidth: 820),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: isDark ? Border.all(color: context.cashier.border) : null,
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '店铺公告',
            style: TextStyle(
              color: Color(0xFF2C2C2E),
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          _buildFormField(
            label: '* 标题',
            controller: widget.titleController,
            counterText: '${widget.titleController.text.length} / 120',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                '正文',
                style: TextStyle(
                  color: Color(0xFF848484),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 16),
              // 模式切换器：可视化 / 源码模式 / 阅读预览
              _buildModeSwitcher(),
              const Spacer(),
              TextButton.icon(
                onPressed: _applyDefaultTemplate,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFB62723),
                ),
                label: const Text(
                  '载入标准模板',
                  style: TextStyle(fontSize: 12, color: Color(0xFFB62723)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildEditorBody(context),
          const SizedBox(height: 6),
          Text(
            '${widget.contentController.text.length} / 4000  像发朋友圈一样自然排版即可，保存后自动存为 HTML；无需编辑 JSON。小程序端用 rich-text 绑定该字段即可展示。',
            style: const TextStyle(
              color: Color(0xFF848484),
              fontSize: 12),
          ),
          const SizedBox(height: 20),
          _buildNoticeSettings(),
          const SizedBox(height: 28),
          Center(
            child: SizedBox(
              width: 200,
              height: 44,
              child: FilledButton(
                key: const Key('settings-store-publish-notice'),
                onPressed: widget.saving ? null : widget.onPublish,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2C2C2E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: widget.saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,
                        ),
                      )
                    : const Text(
                        '发布公告',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSwitcher() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeTab(
            mode: _NoticeEditorMode.visual,
            icon: Icons.edit_note_rounded,
            label: '可视化',
          ),
          _buildModeTab(
            mode: _NoticeEditorMode.code,
            icon: Icons.code,
            label: '源码模式',
          ),
          _buildModeTab(
            mode: _NoticeEditorMode.reading,
            icon: Icons.phone_iphone_rounded,
            label: '阅读预览',
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required _NoticeEditorMode mode,
    required IconData icon,
    required String label,
  }) {
    final active = _mode == mode;
    return InkWell(
      onTap: () {
        if (_mode != mode) {
          if (mode == _NoticeEditorMode.visual) {
            _naturalController.text = _htmlToNaturalText(widget.contentController.text,
            );
          } else if (mode == _NoticeEditorMode.code) {
            widget.contentController.text = _naturalTextToHtml(_naturalController.text,
            );
          }
          setState(() => _mode = mode);
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? const Color(0xFFB62723) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? const Color(0xFF2C2C2E) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorBody(BuildContext context) {
    return switch (_mode) {
      _NoticeEditorMode.visual => _buildVisualEditor(context),
      _NoticeEditorMode.code => _buildCodeEditor(context),
      _NoticeEditorMode.reading => _buildReadingPreview(context),
    };
  }

  /// 公众号/朋友圈风格自由排版编辑器（直接输入自然文本，保存自动转换为规范 HTML，无需编辑 JSON）
  Widget _buildVisualEditor(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE6E1D8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 公众号风格快捷排版工具栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFFFAF8F5),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: Color(0xFFE6E1D8))),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // 业务结构化快捷模板
                _buildQuickTemplateBtn('+ 门店信息', () => _insertNaturalBlock('【门店信息】\n• 老肥油边王 · 烧烤夜宵旗舰店\n• 营业时间：18:30 - 次日 01:30\n• 堂食扫码点餐 · 支持全场连台结账',
                  ),
                ),
                _buildQuickTemplateBtn('+ 配送规则', () => _insertNaturalBlock('【配送规则】\n• 5公里内满30元免配送费，由真省钱专送直达\n• 外卖订单出餐后自动打印配送面单',
                  ),
                ),
                _buildQuickTemplateBtn('+ 优惠福利', () => _insertNaturalBlock('【优惠福利】\n• 邀请新用户进入小程序下单，双方各得一张[红色]9折无门槛优惠券[/红色]',
                  ),
                ),
                _buildQuickTemplateBtn('+ 温馨提示', () => _insertNaturalBlock('💡 温馨提示：夜间就餐高峰期，部分烤品制作需15-20分钟，敬请谅解。',
                  ),
                ),
                const SizedBox(width: 4),
                // 常用格式化快捷动作
                _buildFormatBtn('【标题】', () => _insertNaturalFormatting('【', '】'),
                ),
                _buildFormatBtn('B 加粗', () => _insertNaturalFormatting('**', '**'), isBold: true,
                ),
                _buildFormatBtn('🔴 标红', () => _insertNaturalFormatting('[红色]', '[/红色]'), isRed: true,
                ),
                _buildFormatBtn('• 列表', () => _insertNaturalFormatting('• ')),
                _buildFormatBtn('💡 提示', () => _insertNaturalFormatting('💡 温馨提示：'),
                ),
                _buildFormatBtn('— 分割线', () => _insertNaturalFormatting('\n---\n'),
                ),
              ],
            ),
          ),
          // 自然排版文档编辑画布
          Container(
            constraints: const BoxConstraints(minHeight: 280, maxHeight: 420),
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: _naturalController,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1C1917),
                height: 1.65,
                letterSpacing: 0.2,
              ),
              decoration: const InputDecoration(
                hintText: '像发朋友圈/公众号一样直接在此输入与排版，支持【标题】、• 列表项、[红色]高亮[/红色]、💡 温馨提示与 --- 分割线。\n系统保存时将自动转换为标准 HTML 供小程序 rich-text 原生渲染。',
                hintStyle: TextStyle(color: Color(0xFF9C9488), fontSize: 13, height: 1.5,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTemplateBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF2EFEA),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFD6CFC7)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1C1917),
          ),
        ),
      ),
    );
  }

  Widget _buildFormatBtn(String label, VoidCallback onTap, {bool isBold = false, bool isRed = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isRed ? const Color(0xFFFAECEB) : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isRed ? const Color(0xFFF3E7D7) : const Color(0xFFE6E1D8),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: isRed ? const Color(0xFFB62723) : const Color(0xFF665E54),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeEditor(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 源码编辑模式快捷标签栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: Color(0xFF334155))),
            ),
            child: Row(
              children: [
                const Icon(Icons.code, size: 14, color: Color(0xFF38BDF8)),
                const SizedBox(width: 6),
                const Text(
                  'HTML 源码模式（可直接编写/粘贴 HTML 代码）',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const Spacer(),
                Wrap(
                  spacing: 6,
                  children: [
                    _buildCodeSnippetTag('<p>', '</p>'),
                    _buildCodeSnippetTag('<h3>', '</h3>'),
                    _buildCodeSnippetTag('<strong>', '</strong>'),
                    _buildCodeSnippetTag('<span>', '</span>'),
                    _buildCodeSnippetTag('<blockquote>', '</blockquote>'),
                    _buildCodeSnippetTag('<hr/>'),
                    _buildCodeSnippetTag('<br/>'),
                  ],
                ),
              ],
            ),
          ),
          // 源码输入区域
          Container(
            constraints: const BoxConstraints(minHeight: 280, maxHeight: 420),
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: widget.contentController,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(
                fontFamily: 'Consolas, Courier, monospace',
                fontSize: 13.5,
                color: Color(0xFFE2E8F0),
                height: 1.5,
              ),
              decoration: const InputDecoration(
                hintText: '<!-- 请在此编辑 HTML 源码或直接粘贴富文本代码 -->',
                hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeSnippetTag(String prefix, [String suffix = '']) {
    return InkWell(
      onTap: () {
        final text = widget.contentController.text;
        final selection = widget.contentController.selection;
        if (selection.start >= 0 && selection.end >= selection.start) {
          final selected = text.substring(selection.start, selection.end);
          final newText = text.replaceRange(selection.start, selection.end, '$prefix$selected$suffix',
          );
          widget.contentController.text = newText;
          final newCursorPos = selection.start + prefix.length + selected.length + suffix.length;
          widget.contentController.selection = TextSelection.collapsed(offset: newCursorPos,
          );
        } else {
          widget.contentController.text = '$text$prefix$suffix';
          widget.contentController.selection = TextSelection.collapsed(offset: widget.contentController.text.length,
          );
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF334155),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          prefix,
          style: const TextStyle(
            fontSize: 11,
            fontFamily: 'Consolas, monospace',
            color: Color(0xFF38BDF8),
          ),
        ),
      ),
    );
  }

  Widget _buildReadingPreview(BuildContext context) {
    final title = widget.titleController.text.trim().isEmpty
        ? '老肥家鲜煲烧烤 · 门店官方公告'
        : widget.titleController.text.trim();
    final rawContent = widget.contentController.text;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAF6F0), // 微信小程序暖米底色 --bg-page
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6E1D8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14781412),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 仿真微信小程序顶部导航条与胶囊按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF8E1B18), // 品牌深红顶部
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8E1B18), Color(0xFFB62723), Color(0xFFC9322D),
                ],
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.campaign_rounded, size: 18, color: Color(0xFFEFD0AD),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '老肥家鲜煲烧烤 · 门店公告',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFAF4EB),
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 微信小程序原生胶囊按钮仿真
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('⋯', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 6),
                      Text('|', style: TextStyle(fontSize: 10, color: Colors.white38),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.circle, size: 7, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 小程序弹窗公告主卡片内容区
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 公告主标题与状态徽章
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1C1917), // --text-primary
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: widget.enabled ? const Color(0xFF2D7A4F) : const Color(0xFF9C9488),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                widget.enabled ? '顾客进入小程序自动弹出展示' : '已设为停用（小程序端不弹出）',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: widget.enabled ? const Color(0xFF2D7A4F) : const Color(0xFF665E54),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAECEB),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFF3E7D7)),
                      ),
                      child: const Text(
                        '1:1 真机效果',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB62723),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 渲染公告正文区域（解析 HTML 标签与完整 inline CSS 样式）
                Container(
                  constraints: const BoxConstraints(minHeight: 240, maxHeight: 380,
                  ),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE6E1D8)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x08000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: _renderRichTextPreview(rawContent),
                  ),
                ),
                const SizedBox(height: 16),
                // 小程序底部操作按钮仿真（[ 我知道了 · 进入点餐 ]）
                Center(
                  child: Container(
                    width: double.infinity,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFB62723), Color(0xFFC9322D)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33B62723),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '我知道了 · 进入点餐',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFAF4EB),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    '微信小程序 rich-text 样式实时解析渲染 · 与小程序端 100% 视觉对齐',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9C9488)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color? _parseColorString(String colorStr) {
    var s = colorStr.trim().replaceAll('"', '').replaceAll("'", '');
    if (s.startsWith('#')) {
      s = s.substring(1);
      if (s.length == 3) {
        s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
      }
      if (s.length == 6) {
        final val = int.tryParse('FF$s', radix: 16);
        if (val != null) return Color(val);
      }
      if (s.length == 8) {
        final val = int.tryParse(s, radix: 16);
        if (val != null) return Color(val);
      }
    } else if (s.startsWith('rgb(') || s.startsWith('rgba(')) {
      final match = RegExp(r'rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)',
      ).firstMatch(s);
      if (match != null) {
        final r = int.parse(match.group(1)!);
        final g = int.parse(match.group(2)!);
        final b = int.parse(match.group(3)!);
        final a = match.group(4) != null ? (double.tryParse(match.group(4)!) ?? 1.0) : 1.0;
        return Color.fromRGBO(r, g, b, a);
      }
    } else {
      final name = s.toLowerCase();
      switch (name) {
        case 'red':
        case 'brand-red':
          return const Color(0xFFB62723);
        case 'green':
        case 'love-green':
          return const Color(0xFF2D7A4F);
        case 'gold':
        case 'brand-gold':
          return const Color(0xFFB88755);
        case 'blue':
          return const Color(0xFF2563EB);
        case 'orange':
        case 'amber':
          return const Color(0xFFD97706);
        case 'yellow':
          return const Color(0xFFF59E0B);
        case 'gray':
        case 'grey':
          return const Color(0xFF665E54);
        case 'black':
          return const Color(0xFF1C1917);
        case 'white':
          return Colors.white;
        case 'rose':
        case 'pink':
          return const Color(0xFFE11D48);
        case 'purple':
          return const Color(0xFF7C3AED);
        case 'emerald':
          return const Color(0xFF10B981);
      }
    }
    return null;
  }

  _ParsedStyleResult _parseCssStyleString(String styleStr, TextStyle baseStyle,
  ) {
    var style = baseStyle;
    TextAlign? textAlign;

    final declarations = styleStr.split(';');
    for (final decl in declarations) {
      final parts = decl.split(':');
      if (parts.length < 2) continue;
      final property = parts[0].trim().toLowerCase();
      final value = parts.sublist(1).join(':').trim();

      switch (property) {
        case 'color':
          final color = _parseColorString(value);
          if (color != null) style = style.copyWith(color: color);
          break;
        case 'background-color':
        case 'background':
          final color = _parseColorString(value);
          if (color != null) style = style.copyWith(backgroundColor: color);
          break;
        case 'font-size':
          final numMatch = RegExp(r'([\d.]+)\s*(px|pt|em|rem)?', caseSensitive: false,
          ).firstMatch(value);
          if (numMatch != null) {
            final val = double.tryParse(numMatch.group(1)!);
            final unit = (numMatch.group(2) ?? 'px').toLowerCase();
            if (val != null) {
              final pxVal = unit == 'pt' ? val * 1.33 : (unit == 'em' || unit == 'rem' ? val * 14 : val);
              style = style.copyWith(fontSize: pxVal.clamp(10.0, 36.0));
            }
          }
          break;
        case 'font-weight':
          final val = value.toLowerCase();
          if (val == 'bold' || val == '700' || val == '800' || val == '900' || val == 'bolder') {
            style = style.copyWith(fontWeight: FontWeight.bold);
          } else if (val == '600') {
            style = style.copyWith(fontWeight: FontWeight.w600);
          } else if (val == '500') {
            style = style.copyWith(fontWeight: FontWeight.w500);
          } else if (val == 'normal' || val == '400') {
            style = style.copyWith(fontWeight: FontWeight.normal);
          }
          break;
        case 'font-style':
          if (value.toLowerCase() == 'italic' || value.toLowerCase() == 'oblique') {
            style = style.copyWith(fontStyle: FontStyle.italic);
          } else if (value.toLowerCase() == 'normal') {
            style = style.copyWith(fontStyle: FontStyle.normal);
          }
          break;
        case 'text-decoration':
        case 'text-decoration-line':
          final val = value.toLowerCase();
          if (val.contains('underline')) {
            style = style.copyWith(decoration: TextDecoration.underline);
          } else if (val.contains('line-through') || val.contains('strike')) {
            style = style.copyWith(decoration: TextDecoration.lineThrough);
          } else if (val.contains('none')) {
            style = style.copyWith(decoration: TextDecoration.none);
          }
          break;
        case 'text-align':
          final val = value.toLowerCase();
          if (val == 'center') {
            textAlign = TextAlign.center;
          } else if (val == 'right' || val == 'end') {
            textAlign = TextAlign.right;
          } else if (val == 'left' || val == 'start') {
            textAlign = TextAlign.left;
          } else if (val == 'justify') {
            textAlign = TextAlign.justify;
          }
          break;
        case 'line-height':
          final numMatch = RegExp(r'([\d.]+)', caseSensitive: false,
          ).firstMatch(value);
          if (numMatch != null) {
            final val = double.tryParse(numMatch.group(1)!);
            if (val != null) {
              style = style.copyWith(height: val > 5 ? val / (style.fontSize ?? 14) : val,
              );
            }
          }
          break;
      }
    }

    return _ParsedStyleResult(
      textStyle: style,
      textAlign: textAlign);
  }

  void _appendMarkdownTextSpans(List<InlineSpan> spans, String text, TextStyle baseStyle,
  ) {
    if (!text.contains('**') && !text.contains('*')) {
      spans.add(TextSpan(text: text, style: baseStyle));
      return;
    }
    final parts = text.split('**');
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;
      if (i % 2 == 1) {
        spans.add(TextSpan(text: part, style: baseStyle.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      } else {
        spans.add(TextSpan(text: part, style: baseStyle));
      }
    }
  }

  List<InlineSpan> _parseInlineHtmlSpans(String text, {TextStyle? baseStyle}) {
    final defaultStyle =
        baseStyle ?? const TextStyle(fontSize: 13.5, color: Color(0xFF1C1917), height: 1.6);
    final spans = <InlineSpan>[];

    final regex = RegExp(r'<(\/?[a-zA-Z0-9]+)([^>]*)>|([^<]+)');
    final matches = regex.allMatches(text);

    final styleStack = <TextStyle>[defaultStyle];

    for (final match in matches) {
      final rawMatch = match.group(0) ?? '';
      if (rawMatch.startsWith('<')) {
        final isClosing = rawMatch.startsWith('</');
        final tag = (match.group(1) ?? '').toLowerCase().replaceFirst('/', '');
        final attrs = match.group(2) ?? '';

        if (isClosing) {
          if (styleStack.length > 1) {
            styleStack.removeLast();
          }
        } else {
          var current = styleStack.last;
          if (tag == 'strong' || tag == 'b') {
            current = current.copyWith(fontWeight: FontWeight.bold);
          } else if (tag == 'u') {
            current = current.copyWith(decoration: TextDecoration.underline);
          } else if (tag == 'em' || tag == 'i') {
            current = current.copyWith(fontStyle: FontStyle.italic);
          } else if (tag == 's' || tag == 'del' || tag == 'strike') {
            current = current.copyWith(decoration: TextDecoration.lineThrough);
          } else if (tag == 'mark') {
            current = current.copyWith(backgroundColor: const Color(0xFFFEF08A), color: const Color(0xFF1C1917),
            );
          } else if (tag == 'code') {
            current = current.copyWith(
              fontFamily: 'Consolas, Courier, monospace',
              backgroundColor: const Color(0xFFF2EFEA),
              color: const Color(0xFFB62723),
            );
          } else if (tag == 'a') {
            current = current.copyWith(
              color: const Color(0xFF2563EB),
              decoration: TextDecoration.underline,
            );
          }

          // 解析 inline style 属性 (style="...")
          final styleMatch =
              RegExp(r'style=[\x22\x27]([^\x22\x27]+)[\x22\x27]', caseSensitive: false,
          ).firstMatch(attrs);
          if (styleMatch != null) {
            final parsed = _parseCssStyleString(styleMatch.group(1)!, current);
            current = parsed.textStyle;
          }

          // 兼容 HTML4 font color / size 属性
          if (tag == 'font') {
            final colorMatch =
                RegExp(r'color=[\x22\x27]?([#a-zA-Z0-9]+)[\x22\x27]?', caseSensitive: false,
            ).firstMatch(attrs);
            if (colorMatch != null) {
              final color = _parseColorString(colorMatch.group(1)!);
              if (color != null) current = current.copyWith(color: color);
            }
          }

          styleStack.add(current);
        }
      } else {
        final content = match.group(3) ?? '';
        if (content.isNotEmpty) {
          _appendMarkdownTextSpans(spans, content, styleStack.last);
        }
      }
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: defaultStyle));
    }
    return spans;
  }

  Widget _renderRichTextPreview(String rawContent) {
    if (rawContent.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text(
            '暂无公告内容，请在「可视化」或「源码模式」中输入内容',
            style: TextStyle(fontSize: 13, color: Color(0xFF9C9488)),
          ),
        ),
      );
    }

    // 将内容标准化
    final normalized = rawContent
        .replaceAll(RegExp(r'<p>\s*<br\s*\/?>\s*<\/p>', caseSensitive: false), '\n\n',
        )
        .replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<\/p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<\/div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<\/li>', caseSensitive: false), '\n');

    final lines = normalized.split(RegExp(r'\r?\n'));
    final children = <Widget>[];

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        children.add(const SizedBox(height: 8));
        continue;
      }

      // 分割线 <hr/>
      if (trimmed.startsWith('<hr') || trimmed == '---') {
        children.add(const Divider(height: 20, thickness: 1, color: Color(0xFFE6E1D8)),
        );
        continue;
      }

      // 标题 <h3> / <h2> / <h1> / # 标题
      if (trimmed.startsWith('<h3>') ||
          trimmed.startsWith('<h2>') ||
          trimmed.startsWith('<h1>') ||
          trimmed.startsWith('## ') ||
          trimmed.startsWith('### ')) {
        final headingText = trimmed
            .replaceAll(RegExp(r'<\/?h[1-6]>', caseSensitive: false), '')
            .replaceAll(RegExp(r'^#+\s*'), '');
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 3.5,
                  height: 15,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB62723), // 品牌主红
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    headingText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1917),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // 引用说明块 <blockquote>
      if (trimmed.startsWith('<blockquote>') || trimmed.startsWith('> ')) {
        final quoteText = trimmed
            .replaceAll(RegExp(r'<\/?blockquote>', caseSensitive: false), '')
            .replaceAll(RegExp(r'^>\s*'), '');
        children.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFDF4F3), // 品牌浅红底色
              borderRadius: BorderRadius.circular(8),
              border: const Border(
                left: BorderSide(color: Color(0xFFB62723), width: 3),
              ),
            ),
            child: Text.rich(
              TextSpan(
                children: _parseInlineHtmlSpans(
                  quoteText,
                  baseStyle: const TextStyle(fontSize: 13, color: Color(0xFF941D1A), height: 1.55,
                  ),
                ),
              ),
            ),
          ),
        );
        continue;
      }

      // 列表项 • / - / · / <li>
      final isBullet = trimmed.startsWith('•') ||
          trimmed.startsWith('- ') ||
          trimmed.startsWith('·') ||
          trimmed.startsWith('<li>');
      final cleanLine = trimmed.replaceAll(RegExp(r'<\/?li>', caseSensitive: false), '',
      );

      if (isBullet) {
        final bulletText = cleanLine.replaceFirst(RegExp(r'^[•·\-]\s*'), '');
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6, right: 7),
                  child: Icon(Icons.fiber_manual_record, size: 6, color: Color(0xFFB62723),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: _parseInlineHtmlSpans(bulletText)),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // 解析段落上的 block-level style（例如 <p style="text-align:center; ...">）
      TextAlign? blockAlign;
      var rawBlockText = trimmed;
      final blockStyleMatch =
          RegExp(r'^<(?:p|div)[^>]*style=[\x22\x27]([^\x22\x27]+)[\x22\x27][^>]*>', caseSensitive: false,
      )
              .firstMatch(trimmed);
      if (blockStyleMatch != null) {
        final parsed = _parseCssStyleString(
          blockStyleMatch.group(1)!,
          const TextStyle(fontSize: 13.5, color: Color(0xFF1C1917), height: 1.6,
          ),
        );
        blockAlign = parsed.textAlign;
      }
      rawBlockText = rawBlockText.replaceAll(RegExp(r'^<(?:p|div)[^>]*>', caseSensitive: false), '',
      );

      // 普通段落
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SizedBox(
            width: double.infinity,
            child: Text.rich(
              TextSpan(
                children: _parseInlineHtmlSpans(rawBlockText)),
              textAlign: blockAlign ?? TextAlign.start,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    String? counterText,
    String? hintText,
    IconData? prefixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF848484),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD9D9D9)),
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(color: Color(0xFF352E2E), fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: hintText,
              hintStyle: const TextStyle(color: Color(0xFF848484), fontSize: 14,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10,
              ),
              border: InputBorder.none,
              prefixIcon: prefixIcon != null
                  ? Icon(prefixIcon, size: 16, color: const Color(0xFF848484))
                  : null,
              counterText: counterText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoticeSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('* 状态', style: TextStyle(color: Color(0xFF848484), fontSize: 14, fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            InkWell(
              onTap: () => widget.onEnabledChanged(true),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: widget.enabled ? const Color(0xFFD84949) : const Color(0xFFD9D9D9), width: 2,
                      ),
                    ),
                    child: widget.enabled
                        ? Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFD84949),
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  const Text('启用', style: TextStyle(fontSize: 14, color: Color(0xFF2C2C2E)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            InkWell(
              onTap: () => widget.onEnabledChanged(false),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: !widget.enabled ? const Color(0xFFD84949) : const Color(0xFFD9D9D9), width: 2,
                      ),
                    ),
                    child: !widget.enabled
                        ? Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFD84949),
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  const Text('停用', style: TextStyle(fontSize: 14, color: Color(0xFF2C2C2E)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildFormField(label: '排序', controller: widget.sortController),
        const SizedBox(height: 16),
        _buildFormField(
          label: '开始时间',
          controller: widget.startTimeController,
          hintText: '可选，不填表示不限制',
          prefixIcon: Icons.access_time,
        ),
        const SizedBox(height: 16),
        _buildFormField(
          label: '结束时间',
          controller: widget.endTimeController,
          hintText: '可选，不填表示不限制',
          prefixIcon: Icons.access_time,
        ),
      ],
    );
  }
}

class _StoreBusinessDayCard extends StatelessWidget {
  const _StoreBusinessDayCard({
    required this.cutOffController,
    required this.saving,
    required this.onSave,
    required this.shiftRequired,
    required this.settleRequired,
    required this.onShiftRequiredChanged,
    required this.onSettleRequiredChanged,
    required this.onSaveForce,
  });

  final TextEditingController cutOffController;
  final bool saving;
  final VoidCallback onSave;
  final bool shiftRequired;
  final bool settleRequired;
  final ValueChanged<bool> onShiftRequiredChanged;
  final ValueChanged<bool> onSettleRequiredChanged;
  final VoidCallback onSaveForce;

  @override
  Widget build(BuildContext context) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '营业日切日时间设置',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '跨午夜经营门店建议将切日时间设为凌晨打烊之后（例如 04:00），以保证营业日报和账单归属在同一个营业日。',
          style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 220,
          child: TextField(
            controller: cutOffController,
            decoration: const InputDecoration(
              labelText: '每日切日时间 (HH:mm)',
              hintText: '04:00',
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: saving ? null : onSave,
          icon: const Icon(Icons.save),
          label: const Text('保存切日时间'),
        ),
        const SizedBox(height: 24),
        const Divider(height: 1),
        const SizedBox(height: 16),
        const Text(
          '关门强制流程',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '开启后打烊时将被强制要求先交班 / 日结（老板可在收银端营业开关处强制跳过并写入审计）。',
          style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const Key('store-shift-required-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('关门强制交班',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text('打烊时存在进行中班次需先交班',
              style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
          ),
          value: shiftRequired,
          onChanged: onShiftRequiredChanged,
        ),
        SwitchListTile(
          key: const Key('store-settle-required-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('关门强制日结',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text('打烊时当日营业日未日结需先日结',
              style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
          ),
          value: settleRequired,
          onChanged: onSettleRequiredChanged,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('store-force-settings-save'),
          onPressed: saving ? null : onSaveForce,
          icon: const Icon(Icons.save),
          label: const Text('保存强制流程设置'),
        ),
      ],
    ),
  );
}

class _StoreInheritanceDetailCard extends StatelessWidget {
  const _StoreInheritanceDetailCard({
    required this.source,
    required this.saving,
    required this.onRestore,
  });

  final String source;
  final bool saving;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '配置继承关系与版本',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '当前生效来源：${_sourceText(source)}。'
          '${source == 'SHOP' ? '当前处于门店独立覆盖模式，可一键恢复继承总店默认配置。' : '当前正常继承总店配置，保存修改后将自动转为门店覆盖。'}',
          style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
        ),
        const SizedBox(height: 16),
        if (source == 'SHOP')
          OutlinedButton.icon(
            onPressed: saving ? null : onRestore,
            icon: const Icon(Icons.restore),
            label: const Text('恢复继承总店默认配置'),
          )
        else
          const Chip(
            avatar: Icon(Icons.check_circle_outline, size: 16),
            label: Text('当前正在继承总店统一标准'),
          ),
      ],
    ),
  );
}

class _InheritanceCard extends StatelessWidget {
  const _InheritanceCard({required this.saving, required this.onRestore});

  final bool saving;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) => _card(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '已启用门店个性化覆盖',
                style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 4),
              Text(
                '如果不需要单独设置，可以恢复继承总店统一规则。',
                style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
              ),
            ],
          ),
        ),
        OutlinedButton(
          key: const Key('settings-store-restore'),
          onPressed: saving ? null : onRestore,
          child: const Text('恢复总店设置'),
        ),
      ],
    ),
  );
}

Widget _card({required Widget child}) => Builder(
  builder: (ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ctx.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? ctx.cashier.border : const Color(0xffe5e7eb),
        ),
      ),
      child: child,
    );
  },
);

String _sourceText(String source) => switch (source.toUpperCase()) {
  'HEADQUARTERS' => '总店继承',
  'SHOP' => '门店覆盖',
  'SYSTEM' => '系统内置',
  _ => source,
};
