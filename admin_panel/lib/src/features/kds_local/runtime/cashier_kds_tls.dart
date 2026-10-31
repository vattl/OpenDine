import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'cashier_kds_cert_generator.dart';

class CashierKdsTlsConfiguration {
  const CashierKdsTlsConfiguration({
    required this.securityContext,
    required this.certificateSha256,
    this.certificatePath,
    this.privateKeyPath,
    this.caCertificatePath,
  });

  final SecurityContext securityContext;

  /// SHA-256 of the leaf certificate DER, shown only for deployment checks.
  final String certificateSha256;

  final String? certificatePath;
  final String? privateKeyPath;
  final String? caCertificatePath;

  /// 从指定证书与私钥文件加载 TLS 配置。
  static CashierKdsTlsConfiguration fromFiles({
    required File certificateFile,
    required File privateKeyFile,
    File? caCertificateFile,
    String? password,
  }) {
    if (!certificateFile.existsSync()) {
      throw FileSystemException('LAN KDS TLS 证书不存在', certificateFile.path);
    }
    if (!privateKeyFile.existsSync()) {
      throw FileSystemException('LAN KDS TLS 私钥不存在', privateKeyFile.path);
    }

    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChain(certificateFile.path)
      ..usePrivateKey(privateKeyFile.path, password: password);

    return CashierKdsTlsConfiguration(
      securityContext: context,
      certificateSha256: _certificateFingerprint(
        certificateFile.readAsStringSync(),
      ),
      certificatePath: certificateFile.path,
      privateKeyPath: privateKeyFile.path,
      caCertificatePath:
          caCertificateFile != null && caCertificateFile.existsSync()
              ? caCertificateFile.path
              : null,
    );
  }

  /// 从指定目录加载（期望存在 server.crt, server.key, ca.crt）。
  static CashierKdsTlsConfiguration fromDirectory(Directory certsDir) {
    final serverCert = File(p.join(certsDir.path, CashierKdsCertGenerator.serverCertFileName));
    final serverKey = File(p.join(certsDir.path, CashierKdsCertGenerator.serverKeyFileName));
    final caCert = File(p.join(certsDir.path, CashierKdsCertGenerator.caCertFileName));
    return fromFiles(
      certificateFile: serverCert,
      privateKeyFile: serverKey,
      caCertificateFile: caCert,
    );
  }

  /// 优先从环境变量加载；若未配置则检查持久化目录，必要时自动签发新证书，实现零配置即开即用。
  static Future<CashierKdsTlsConfiguration?> resolve({
    required Directory applicationDataRoot,
    Map<String, String>? environment,
    List<String> lanIps = const ['127.0.0.1'],
    bool autoGenerateIfMissing = true,
  }) async {
    final env = environment ?? Platform.environment;
    final envConfig = fromEnvironment(env);
    if (envConfig != null) {
      return envConfig;
    }

    final certsDir = Directory(p.join(applicationDataRoot.path, 'certs'));
    final serverCert = File(p.join(certsDir.path, CashierKdsCertGenerator.serverCertFileName));
    final serverKey = File(p.join(certsDir.path, CashierKdsCertGenerator.serverKeyFileName));
    final caCert = File(p.join(certsDir.path, CashierKdsCertGenerator.caCertFileName));

    if (serverCert.existsSync() && serverKey.existsSync()) {
      try {
        return fromFiles(
          certificateFile: serverCert,
          privateKeyFile: serverKey,
          caCertificateFile: caCert.existsSync() ? caCert : null,
        );
      } catch (_) {
        // 如果文件已损坏且允许自动生成，则在下方重新签发覆盖
      }
    }

    if (autoGenerateIfMissing) {
      try {
        await CashierKdsCertGenerator.generate(
          certsDirectory: certsDir,
          ipAddresses: lanIps,
          dnsNames: const ['localhost', 'lan-cashier.local'],
          force: true,
        );
        return fromDirectory(certsDir);
      } catch (error) {
        // 自动签发受系统环境限制失败时，上抛供启动诊断捕获
        rethrow;
      }
    }

    return null;
  }

  static CashierKdsTlsConfiguration? fromEnvironment(
    Map<String, String> environment,
  ) {
    final certificatePath =
        environment['CASHIER_KDS_TLS_CERT_PATH']?.trim() ?? '';
    final privateKeyPath =
        environment['CASHIER_KDS_TLS_KEY_PATH']?.trim() ?? '';
    if (certificatePath.isEmpty && privateKeyPath.isEmpty) return null;
    if (certificatePath.isEmpty || privateKeyPath.isEmpty) {
      throw const FormatException(
        'CASHIER_KDS_TLS_CERT_PATH 与 CASHIER_KDS_TLS_KEY_PATH 必须同时配置',
      );
    }

    final certificate = File(certificatePath);
    final privateKey = File(privateKeyPath);
    if (!certificate.existsSync()) {
      throw FileSystemException('LAN KDS TLS 证书不存在', certificatePath);
    }
    if (!privateKey.existsSync()) {
      throw FileSystemException('LAN KDS TLS 私钥不存在', privateKeyPath);
    }

    final caPath = environment['CASHIER_KDS_TLS_CA_PATH']?.trim();
    final caFile = caPath != null && caPath.isNotEmpty ? File(caPath) : null;

    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChain(certificatePath)
      ..usePrivateKey(
        privateKeyPath,
        password: environment['CASHIER_KDS_TLS_KEY_PASSWORD'],
      );
    return CashierKdsTlsConfiguration(
      securityContext: context,
      certificateSha256: _certificateFingerprint(
        certificate.readAsStringSync(),
      ),
      certificatePath: certificatePath,
      privateKeyPath: privateKeyPath,
      caCertificatePath: caFile != null && caFile.existsSync() ? caFile.path : null,
    );
  }

  static String _certificateFingerprint(String pem) {
    final match = RegExp(
      r'-----BEGIN CERTIFICATE-----([\s\S]+?)-----END CERTIFICATE-----',
    ).firstMatch(pem);
    if (match == null) {
      throw const FormatException('LAN KDS TLS 证书不是有效 PEM 证书');
    }
    final encoded = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
    try {
      return sha256.convert(base64Decode(encoded)).toString().toUpperCase();
    } on FormatException {
      throw const FormatException('LAN KDS TLS 证书 PEM 内容无效');
    }
  }
}
