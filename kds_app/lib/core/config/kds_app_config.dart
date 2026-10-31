/// KDS App 全局配置
abstract final class KdsAppConfig {
  static const appVersion = 'V1.0.1';
  static const defaultApiBase = '';
  static const defaultCloudApiBase = String.fromEnvironment(
    'KDS_CLOUD_API_BASE',
    defaultValue: 'http://localhost:8080',
  );
  static const lanApiBaseExample = 'https://192.168.x.x:17026';
  static const cloudApiBaseExample = 'https://api.yourdomain.com';
}
