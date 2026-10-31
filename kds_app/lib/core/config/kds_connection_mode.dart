/// KDS 连接模式定义
enum KdsConnectionMode {
  /// 云端优先（默认）：直连云端；传输故障与恢复均提示用户确认后再切换。
  cloudFirst('cloud_first', '云端优先 (手动确认切换)'),

  /// 历史兼容值。新会话和历史持久化值都会迁移到 [cloudFirst]，UI 不再暴露。
  @Deprecated('Use cloudFirst')

  /// 旧版局域网优先：仅保留用于兼容旧测试与显式配置。
  lanFirst('lan_first', '局域网优先 (自动容灾)'),

  /// 纯云端直连：直接通过外网连接云端后端服务，适用于无本地收银主机的纯前厅/档口场景
  cloudDirect('cloud_direct', '云端直连 (纯外网)'),

  /// 纯局域网：仅连接本地收银机，绝不外发云端，适用于网络封闭或强安全内网场景
  lanOnly('lan_only', '纯局域网');

  const KdsConnectionMode(this.value, this.label);

  final String value;
  final String label;

  static KdsConnectionMode fromValue(String? v) {
    // 生产架构固定为云端权威、云端优先、LAN 代理容灾。旧值只用于
    // 兼容底层传输测试，任何持久化配置都不能恢复为另一种业务策略。
    return KdsConnectionMode.cloudFirst;
  }
}

/// 当前实际生效的工作通道（运行期探活只建议，用户确认后才改变）
enum KdsActiveChannel {
  lan('lan', '局域网收银机'),
  cloud('cloud', '云端服务');

  const KdsActiveChannel(this.value, this.label);

  final String value;
  final String label;
}
