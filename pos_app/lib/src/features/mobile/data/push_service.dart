import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';

/// 推送通道。后端 v1.2.172 已提供设备注册/解绑/偏好接口。
/// 真机 APNs/FCM 接入前，设备 token 由占位实现生成（placeholder），
/// 接口调用已走真实后端，便于联调设备注册链路。
///
/// 生命周期（对齐后端调用指南 §2/§4）：
/// 登录成功 + 选定门店后 → register()；
/// 系统 token 刷新 / 切换账号 / 切换门店后 → 重新 register()（后端按 token 迁移归属）；
/// 登出 → 先 unregister() 成功，再清除本地 JWT。
const kUseMockPush = bool.fromEnvironment('MOCK_PUSH', defaultValue: false);

class PushMessage {
  const PushMessage({
    required this.id,
    required this.title,
    required this.body,
    this.deeplink,
  });

  final String id;
  final String title;
  final String body;
  final String? deeplink;
}

abstract class PushService {
  /// 登录 + 选店后调用；token 刷新/账号/门店切换后重新调用。
  Future<String?> register();

  /// 登出时调用；仅解绑当前账号名下 token，不要求 X-Shop-Id。
  Future<void> unregister();

  /// 保存通知偏好（types 为空 = 当前门店关闭全部业务通知）。
  Future<void> savePreference(List<String> types);

  /// 前台收到推送的回调流。
  Stream<PushMessage> get onMessage;
}

class RealPushService implements PushService {
  RealPushService({required this.platform, this.channel = 'fcm'});

  /// 'android' | 'ios'
  final String platform;

  /// iOS 必须 'apns'；Android: 'fcm' | 'huawei' | 'xiaomi' | 'oppo' | 'vivo'
  final String channel;

  String? _deviceToken;
  String _appVersion = '';
  String _deviceModel = '';

  /// 真机接入后由 firebase_messaging / APNs 回调赋值。
  void updateDeviceToken(String token, {String appVersion = '', String deviceModel = ''}) {
    _deviceToken = token;
    _appVersion = appVersion;
    _deviceModel = deviceModel;
  }

  String get _token {
    // TODO(真机): 替换为真实厂商 token。占位 token 保证后端注册链路可联调
    // （后端同一 token 幂等迁移，不会重复建记录）。
    return _deviceToken ?? 'placeholder-$platform';
  }

  @override
  Future<String?> register() async {
    final token = _token;
    // 每次调用都用最新 client（调用方负责传入当前选店后的 client）。
    final activeClient = _client;
    if (activeClient == null) {
      throw StateError('PushService 未绑定 AdminApiClient，请先登录并选定门店');
    }
    await activeClient.post(
      pushDeviceRegisterEndpoint,
      body: {
        'deviceToken': token,
        'platform': platform,
        'channel': channel,
        if (_appVersion.isNotEmpty) 'appVersion': _appVersion,
        if (_deviceModel.isNotEmpty) 'deviceModel': _deviceModel,
      },
    );
    _deviceToken = token;
    return token;
  }

  @override
  Future<void> unregister() async {
    final token = _deviceToken;
    final activeClient = _client;
    if (token == null || activeClient == null) return;
    await activeClient.post(
      pushDeviceUnregisterEndpoint,
      body: {'deviceToken': token},
    );
    _deviceToken = null;
  }

  @override
  Future<void> savePreference(List<String> types) async {
    final activeClient = _client;
    if (activeClient == null) return;
    await activeClient.post(pushPreferenceEndpoint, body: {'types': types});
  }

  @override
  Stream<PushMessage> get onMessage => const Stream.empty();

  // client 由 provider 在每次 register/unregister/savePreference 前注入最新值。
  AdminApiClient? _client;
  void bindClient(AdminApiClient client) => _client = client;
}

class MockPushService implements PushService {
  const MockPushService();

  @override
  Future<String?> register() async => 'mock-device-token';

  @override
  Future<void> unregister() async {}

  @override
  Future<void> savePreference(List<String> types) async {}

  @override
  Stream<PushMessage> get onMessage => const Stream.empty();
}
