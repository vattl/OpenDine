package com.laofei.cashier

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x509.BasicConstraints
import org.bouncycastle.asn1.x509.ExtendedKeyUsage
import org.bouncycastle.asn1.x509.Extension
import org.bouncycastle.asn1.x509.GeneralName
import org.bouncycastle.asn1.x509.GeneralNames
import org.bouncycastle.asn1.x509.KeyPurposeId
import org.bouncycastle.asn1.x509.KeyUsage
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import org.bouncycastle.util.io.pem.PemObject
import org.bouncycastle.util.io.pem.PemWriter
import java.io.File
import java.io.StringWriter
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.SecureRandom
import java.util.Date

class MainActivity : FlutterActivity() {
    private val channelName = "com.laofei.cashier/kds_cert"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "generateCerts") {
                val certsDir = call.argument<String>("certsDir")
                val ipAddresses = call.argument<List<String>>("ipAddresses") ?: listOf("127.0.0.1")
                val dnsNames = call.argument<List<String>>("dnsNames") ?: listOf("localhost", "lan-cashier.local")

                if (certsDir == null) {
                    result.error("INVALID_ARGUMENT", "certsDir must not be null", null)
                    return@setMethodCallHandler
                }

                try {
                    val dir = File(certsDir)
                    if (!dir.exists()) {
                        dir.mkdirs()
                    }

                    // 1. Generate RSA 2048 keypair for Root CA
                    val kpg = KeyPairGenerator.getInstance("RSA")
                    kpg.initialize(2048, SecureRandom())
                    val caKeyPair = kpg.generateKeyPair()

                    // 2. Generate Root CA cert (5 years)
                    val now = System.currentTimeMillis()
                    val caNotBefore = Date(now - 86400000L) // 1 day before to prevent clock skew
                    val caNotAfter = Date(now + 5L * 365 * 86400000L) // 5 years
                    val caSerial = BigInteger(64, SecureRandom())
                    val caSubject = X500Name("CN=LaoFei Cashier Root CA, O=LaoFei POS, C=CN")

                    val caBuilder = JcaX509v3CertificateBuilder(
                        caSubject,
                        caSerial,
                        caNotBefore,
                        caNotAfter,
                        caSubject,
                        caKeyPair.public
                    )
                    caBuilder.addExtension(Extension.basicConstraints, true, BasicConstraints(true))
                    caBuilder.addExtension(
                        Extension.keyUsage,
                        true,
                        KeyUsage(KeyUsage.keyCertSign or KeyUsage.cRLSign)
                    )

                    val signer = JcaContentSignerBuilder("SHA256withRSA").build(caKeyPair.private)
                    val caCertHolder = caBuilder.build(signer)
                    val caCert = JcaX509CertificateConverter().getCertificate(caCertHolder)

                    // 3. Generate RSA 2048 keypair for Server
                    val serverKeyPair = kpg.generateKeyPair()

                    // 4. Generate Server cert (2 years) signed by Root CA
                    val serverNotBefore = Date(now - 86400000L)
                    val serverNotAfter = Date(now + 2L * 365 * 86400000L) // 2 years
                    val serverSerial = BigInteger(64, SecureRandom())
                    val serverSubject = X500Name("CN=LaoFei Cashier LAN Server, O=LaoFei POS, C=CN")

                    val serverBuilder = JcaX509v3CertificateBuilder(
                        caSubject,
                        serverSerial,
                        serverNotBefore,
                        serverNotAfter,
                        serverSubject,
                        serverKeyPair.public
                    )
                    serverBuilder.addExtension(Extension.basicConstraints, false, BasicConstraints(false))
                    serverBuilder.addExtension(
                        Extension.keyUsage,
                        true,
                        KeyUsage(KeyUsage.digitalSignature or KeyUsage.keyEncipherment)
                    )
                    serverBuilder.addExtension(
                        Extension.extendedKeyUsage,
                        false,
                        ExtendedKeyUsage(KeyPurposeId.id_kp_serverAuth)
                    )

                    // Build SAN list
                    val generalNamesList = mutableListOf<GeneralName>()
                    for (dns in dnsNames) {
                        generalNamesList.add(GeneralName(GeneralName.dNSName, dns))
                    }
                    for (ip in ipAddresses) {
                        generalNamesList.add(GeneralName(GeneralName.iPAddress, ip))
                    }
                    val san = GeneralNames(generalNamesList.toTypedArray())
                    serverBuilder.addExtension(Extension.subjectAlternativeName, false, san)

                    val serverCertHolder = serverBuilder.build(signer)
                    val serverCert = JcaX509CertificateConverter().getCertificate(serverCertHolder)

                    // Helper to export PEM string
                    fun toPem(type: String, content: ByteArray): String {
                        val sw = StringWriter()
                        val pw = PemWriter(sw)
                        pw.writeObject(PemObject(type, content))
                        pw.flush()
                        return sw.toString()
                    }

                    val caCertPem = toPem("CERTIFICATE", caCert.encoded)
                    val caKeyPem = toPem("PRIVATE KEY", caKeyPair.private.encoded)
                    val serverKeyPem = toPem("PRIVATE KEY", serverKeyPair.private.encoded)
                    val serverCertPem = toPem("CERTIFICATE", serverCert.encoded)

                    // Write ca.crt, ca.key, server.key, server.crt (leaf + CA)
                    File(dir, "ca.crt").writeText(caCertPem, Charsets.UTF_8)
                    File(dir, "ca.key").writeText(caKeyPem, Charsets.UTF_8)
                    File(dir, "server.key").writeText(serverKeyPem, Charsets.UTF_8)
                    File(dir, "server.crt").writeText("$serverCertPem\n$caCertPem", Charsets.UTF_8)

                    result.success(true)
                } catch (e: Exception) {
                    result.error("CERT_GEN_ERROR", e.message, e.stackTraceToString())
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
