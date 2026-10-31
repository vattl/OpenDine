import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class CashierKdsCertPaths {
  const CashierKdsCertPaths({
    required this.caCertPath,
    required this.caKeyPath,
    required this.serverCertPath,
    required this.serverKeyPath,
  });

  final String caCertPath;
  final String caKeyPath;
  final String serverCertPath;
  final String serverKeyPath;
}

/// 局域网 TLS 自签名 PKI 证书自动生成器。
///
/// 具备零配置就地签发能力：
/// 1. 自动生成 5 年期的门店根 CA (`ca.crt` + `ca.key`)；
/// 2. 自动检测网卡私网 IP 与回环地址，为服务端生成带完整 IP/DNS SAN 扩展的服务端证书 (`server.crt` + `server.key`)；
/// 3. 输出 UTF-8 无 BOM 的标准 PEM 文件，可直接被 BoringSSL (dart:io SecurityContext) 加载。
class CashierKdsCertGenerator {
  static const String caCertFileName = 'ca.crt';
  static const String caKeyFileName = 'ca.key';
  static const String serverCertFileName = 'server.crt';
  static const String serverKeyFileName = 'server.key';

  static bool certificatesExist(Directory certsDirectory) {
    final caCert = File(p.join(certsDirectory.path, caCertFileName));
    final serverCert = File(p.join(certsDirectory.path, serverCertFileName));
    final serverKey = File(p.join(certsDirectory.path, serverKeyFileName));
    return caCert.existsSync() &&
        serverCert.existsSync() &&
        serverKey.existsSync();
  }

  /// 确保指定目录中存在可用的 PKI 证书。如果已存在且未指定 [force]，直接返回。
  static Future<CashierKdsCertPaths> ensureCertificates({
    required Directory certsDirectory,
    List<String> ipAddresses = const ['127.0.0.1'],
    List<String> dnsNames = const ['localhost', 'lan-cashier.local'],
    bool force = false,
  }) async {
    if (!force && certificatesExist(certsDirectory)) {
      return CashierKdsCertPaths(
        caCertPath: p.join(certsDirectory.path, caCertFileName),
        caKeyPath: p.join(certsDirectory.path, caKeyFileName),
        serverCertPath: p.join(certsDirectory.path, serverCertFileName),
        serverKeyPath: p.join(certsDirectory.path, serverKeyFileName),
      );
    }
    return generate(
      certsDirectory: certsDirectory,
      ipAddresses: ipAddresses,
      dnsNames: dnsNames,
      force: force,
    );
  }

  /// 在指定目录下生成全新的证书。
  static Future<CashierKdsCertPaths> generate({
    required Directory certsDirectory,
    List<String> ipAddresses = const ['127.0.0.1'],
    List<String> dnsNames = const ['localhost', 'lan-cashier.local'],
    bool force = false,
  }) async {
    if (!certsDirectory.existsSync()) {
      certsDirectory.createSync(recursive: true);
    }

    final effectiveIps = <String>{'127.0.0.1', ...ipAddresses}.toList();
    final effectiveDns = <String>{'localhost', ...dnsNames}.toList();

    if (Platform.isWindows) {
      await _generateWindowsPowerShell(
        certsDir: certsDirectory,
        ips: effectiveIps,
        dnsNames: effectiveDns,
      );
    } else if (Platform.isAndroid) {
      await _generateAndroid(
        certsDir: certsDirectory,
        ips: effectiveIps,
        dnsNames: effectiveDns,
      );
    } else {
      await _generateOpenssl(
        certsDir: certsDirectory,
        ips: effectiveIps,
        dnsNames: effectiveDns,
      );
    }

    final caCert = File(p.join(certsDirectory.path, caCertFileName));
    final caKey = File(p.join(certsDirectory.path, caKeyFileName));
    final serverCert = File(p.join(certsDirectory.path, serverCertFileName));
    final serverKey = File(p.join(certsDirectory.path, serverKeyFileName));

    if (!serverCert.existsSync() || !serverKey.existsSync()) {
      throw FileSystemException(
        'TLS 证书生成失败：输出文件未就绪',
        certsDirectory.path,
      );
    }

    return CashierKdsCertPaths(
      caCertPath: caCert.path,
      caKeyPath: caKey.path,
      serverCertPath: serverCert.path,
      serverKeyPath: serverKey.path,
    );
  }

  static Future<void> _generateWindowsPowerShell({
    required Directory certsDir,
    required List<String> ips,
    required List<String> dnsNames,
  }) async {
    final scriptFile = File(p.join(certsDir.path, 'generate_kds_certs.ps1'));
    scriptFile.writeAsStringSync(_windowsPowerShellScriptContent, flush: true);

    // 优先尝试 pwsh (PowerShell 7)，若未找到则回退系统内置 powershell.exe
    String executable = 'powershell';
    try {
      final probe = await Process.run('pwsh', ['-v']);
      if (probe.exitCode == 0) {
        executable = 'pwsh';
      }
    } catch (_) {
      executable = 'powershell';
    }

    final result = await Process.run(
      executable,
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptFile.path,
        '-OutputDir',
        certsDir.path,
        '-Ips',
        ips.join(','),
        '-DnsNames',
        dnsNames.join(','),
      ],
      runInShell: true,
    );

    // 清理临时脚本文件
    try {
      if (scriptFile.existsSync()) scriptFile.deleteSync();
    } catch (_) {}

    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        [scriptFile.path],
        '生成局域网 TLS 证书失败: ${result.stderr}\n${result.stdout}',
        result.exitCode,
      );
    }
  }

  static Future<void> _generateOpenssl({
    required Directory certsDir,
    required List<String> ips,
    required List<String> dnsNames,
  }) async {
    final caKeyPath = p.join(certsDir.path, caKeyFileName);
    final caCertPath = p.join(certsDir.path, caCertFileName);
    final serverKeyPath = p.join(certsDir.path, serverKeyFileName);
    final serverCertPath = p.join(certsDir.path, serverCertFileName);
    final serverCnfPath = p.join(certsDir.path, 'server.cnf');

    final sanIps = ips.asMap().entries.map((e) => 'IP.${e.key + 1} = ${e.value}').join('\n');
    final sanDns = dnsNames.asMap().entries.map((e) => 'DNS.${e.key + 1} = ${e.value}').join('\n');

    final cnfContent = """
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = LaoFei Cashier LAN Server
O = LaoFei POS
C = CN

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
$sanDns
$sanIps
""";
    File(serverCnfPath).writeAsStringSync(cnfContent);

    // 1. 生成 CA
    await Process.run('openssl', [
      'req',
      '-x509',
      '-nodes',
      '-newkey',
      'rsa:2048',
      '-keyout',
      caKeyPath,
      '-out',
      caCertPath,
      '-days',
      '1825',
      '-subj',
      '/CN=LaoFei Cashier Root CA/O=LaoFei POS/C=CN',
    ]);

    // 2. 生成 Server Key + CSR
    final csrPath = p.join(certsDir.path, 'server.csr');
    await Process.run('openssl', [
      'req',
      '-new',
      '-nodes',
      '-newkey',
      'rsa:2048',
      '-keyout',
      serverKeyPath,
      '-out',
      csrPath,
      '-config',
      serverCnfPath,
    ]);

    // 3. 签发 Server Cert
    final rawLeafCertPath = p.join(certsDir.path, 'leaf.crt');
    await Process.run('openssl', [
      'x509',
      '-req',
      '-in',
      csrPath,
      '-CA',
      caCertPath,
      '-CAkey',
      caKeyPath,
      '-CAcreateserial',
      '-out',
      rawLeafCertPath,
      '-days',
      '730',
      '-extensions',
      'v3_req',
      '-extfile',
      serverCnfPath,
    ]);

    // 4. 合成完整证书链
    final leafPem = File(rawLeafCertPath).readAsStringSync();
    final caPem = File(caCertPath).readAsStringSync();
    File(serverCertPath).writeAsStringSync('$leafPem\n$caPem');

    // 清理临时文件
    for (final tmp in [csrPath, rawLeafCertPath, serverCnfPath]) {
      try {
        final f = File(tmp);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  static const MethodChannel _androidChannel =
      MethodChannel('com.laofei.cashier/kds_cert');

  static Future<void> _generateAndroid({
    required Directory certsDir,
    required List<String> ips,
    required List<String> dnsNames,
  }) async {
    try {
      final success = await _androidChannel.invokeMethod<bool>(
        'generateCerts',
        {
          'certsDir': certsDir.path,
          'ipAddresses': ips,
          'dnsNames': dnsNames,
        },
      );
      if (success != true) {
        throw const FileSystemException('Android 原生 TLS 证书生成未返回成功');
      }
    } catch (e) {
      throw FileSystemException('Android 原生 TLS 证书生成异常: $e', certsDir.path);
    }
  }

  @visibleForTesting
  static Future<void> generateAndroidForTesting({
    required Directory certsDir,
    required List<String> ips,
    required List<String> dnsNames,
  }) => _generateAndroid(
    certsDir: certsDir,
    ips: ips,
    dnsNames: dnsNames,
  );

  static const String _windowsPowerShellScriptContent = r"""
param(
    [string]$OutputDir = ".",
    [string]$Ips = "127.0.0.1",
    [string]$DnsNames = "localhost"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$OutputDir = (Resolve-Path $OutputDir).Path

function Export-CertToPem($cert) {
    if ($cert.PSObject.Methods.Match('ExportCertificatePem').Count -gt 0) {
        return $cert.ExportCertificatePem()
    }
    $b64 = [Convert]::ToBase64String($cert.RawData, [Base64FormattingOptions]::InsertLineBreaks)
    return "-----BEGIN CERTIFICATE-----`r`n$b64`r`n-----END CERTIFICATE-----`r`n"
}

function Export-RsaKeyToPem($rsa) {
    if ($rsa.PSObject.Methods.Match('ExportPkcs8PrivateKeyPem').Count -gt 0) {
        return $rsa.ExportPkcs8PrivateKeyPem()
    }
    $keyBytes = $rsa.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
    $b64 = [Convert]::ToBase64String($keyBytes, [Base64FormattingOptions]::InsertLineBreaks)
    return "-----BEGIN PRIVATE KEY-----`r`n$b64`r`n-----END PRIVATE KEY-----`r`n"
}

function Write-Utf8NoBom($path, $text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $text, $enc)
}

# 1. Root CA (Valid 5 years)
$caRsa = [System.Security.Cryptography.RSA]::Create(2048)
$caSubject = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=LaoFei Cashier Root CA, O=LaoFei POS, C=CN")
$caReq = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
    $caSubject,
    $caRsa,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)

$caBasicConstraints = [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true, $true, 1, $true)
$caReq.CertificateExtensions.Add($caBasicConstraints)
$caUsage = [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
    [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign -bor [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::CrlSign -bor [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature,
    $true
)
$caReq.CertificateExtensions.Add($caUsage)

$notBefore = [DateTimeOffset]::UtcNow.AddDays(-1)
$notAfter = [DateTimeOffset]::UtcNow.AddYears(5)
$caCert = $caReq.CreateSelfSigned($notBefore, $notAfter)

$caCertPem = Export-CertToPem $caCert
$caKeyPem = Export-RsaKeyToPem $caRsa

Write-Utf8NoBom "$OutputDir/ca.crt" $caCertPem
Write-Utf8NoBom "$OutputDir/ca.key" $caKeyPem

# 2. Server Certificate (Valid 2 years, signed by CA)
$leafRsa = [System.Security.Cryptography.RSA]::Create(2048)
$leafSubject = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=LaoFei Cashier LAN Server, O=LaoFei POS, C=CN")
$leafReq = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
    $leafSubject,
    $leafRsa,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)

$leafUsage = [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
    [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment,
    $true
)
$leafReq.CertificateExtensions.Add($leafUsage)

$oids = [System.Security.Cryptography.OidCollection]::new()
$oids.Add([System.Security.Cryptography.Oid]::new("1.3.6.1.5.5.7.3.1"))
$eku = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids, $false)
$leafReq.CertificateExtensions.Add($eku)

$sanBuilder = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
$ipList = $Ips.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
foreach ($ip in $ipList) {
    try {
        $sanBuilder.AddIpAddress([System.Net.IPAddress]::Parse($ip))
    } catch {
        Write-Warning "Invalid IP address: $ip"
    }
}
$dnsList = $DnsNames.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
foreach ($dns in $dnsList) {
    try {
        $sanBuilder.AddDnsName($dns)
    } catch {
        Write-Warning "Invalid DNS name: $dns"
    }
}
$leafReq.CertificateExtensions.Add($sanBuilder.Build())

$serialBytes = [byte[]]::new(16)
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($serialBytes)
$serialBytes[0] = $serialBytes[0] -band 0x7F

$leafCert = $leafReq.Create(
    $caCert,
    $notBefore,
    [DateTimeOffset]::UtcNow.AddYears(2),
    $serialBytes
)

$leafCertPem = Export-CertToPem $leafCert
$fullChainPem = $leafCertPem + "`r`n" + $caCertPem
$leafKeyPem = Export-RsaKeyToPem $leafRsa

Write-Utf8NoBom "$OutputDir/server.crt" $fullChainPem
Write-Utf8NoBom "$OutputDir/server.key" $leafKeyPem
Write-Host "[CertGen] Certificates generated successfully at $OutputDir"
""";
}
