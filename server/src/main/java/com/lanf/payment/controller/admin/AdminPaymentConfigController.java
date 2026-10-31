package com.lanf.payment.controller.admin;

import com.lanf.entity.R;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.payment.channel.wechat.WechatPayCredentialAudit;
import com.lanf.payment.config.PaymentConfigSync;
import com.lanf.payment.entity.PaymentCapabilityEntity;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import com.lanf.payment.service.PaymentCapabilityService;
import com.lanf.payment.service.PaymentMerchantConfigService;
import com.lanf.payment.service.PaymentMerchantPolicyService;
import com.lanf.payment.service.PaymentNinefoldService;
import com.lanf.payment.support.PaymentAdminShopScope;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.Map;

/**
 * 线上支付能力与商户配置（运营后台，按门店隔离）。
 */
@RestController
@RequestMapping("/admin/payment")
public class AdminPaymentConfigController {

    @Autowired
    private PaymentCapabilityService capabilityService;
    @Autowired
    private PaymentMerchantConfigService merchantConfigService;
    @Autowired
    private PaymentMerchantPolicyService merchantPolicyService;
    @Autowired
    private PaymentConfigSync paymentConfigSync;
    @Autowired
    private PaymentNinefoldService paymentNinefoldService;
    @Autowired
    private PaymentAdminShopScope shopScope;
    @Autowired
    private WechatMerchantKeyStore wechatMerchantKeyStore;

    @GetMapping("/ninefold")
    public R getNinefold(@RequestParam(required = false) Integer shopId) {
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId, holder);
        if (err != null) {
            return err;
        }
        return R.ok(paymentNinefoldService.toAdminMap(holder[0]));
    }

    @PutMapping("/ninefold")
    public R putNinefold(@RequestParam(required = false) Integer shopId,
                         @RequestBody Map<String, Object> body) {
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId, holder);
        if (err != null) {
            return err;
        }
        int sid = holder[0];
        R writeErr = shopScope.assertWritableShopId(sid);
        if (writeErr != null) {
            return writeErr;
        }
        try {
            paymentNinefoldService.upsert(sid, body);
            paymentConfigSync.reloadShop(sid);
            return R.ok(paymentNinefoldService.toAdminMap(sid));
        } catch (IllegalArgumentException | IllegalStateException e) {
            return R.error(e.getMessage());
        }
    }

    @GetMapping("/capabilities")
    public R getCapabilities(@RequestParam(required = false) Integer shopId) {
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId, holder);
        if (err != null) {
            return err;
        }
        return R.ok(capabilityService.toAdminMap(holder[0]));
    }

    @PutMapping("/capabilities")
    public R putCapabilities(@RequestParam(required = false) Integer shopId,
                             @RequestBody Map<String, Object> body) {
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId, holder);
        if (err != null) {
            return err;
        }
        int sid = holder[0];
        R writeErr = shopScope.assertWritableShopId(sid);
        if (writeErr != null) {
            return writeErr;
        }
        try {
            PaymentCapabilityEntity row = capabilityService.upsert(sid, body);
            paymentConfigSync.reloadShop(sid);
            return R.ok(capabilityService.toAdminMap(sid)).put("id", row.getId());
        } catch (IllegalArgumentException e) {
            return R.error(com.lanf.payment.PaymentErrorCodes.MERCHANT_NOT_CONFIGURED, e.getMessage());
        }
    }

    @GetMapping("/merchants")
    public R listMerchants(@RequestParam(required = false) Integer shopId,
                           @RequestParam(required = false, defaultValue = "wechat") String channel) {
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId, holder);
        if (err != null) {
            return err;
        }
        return R.ok(merchantConfigService.listForAdmin(holder[0], channel));
    }

    @GetMapping("/merchants/{id}")
    public R getMerchant(@PathVariable Long id) {
        PaymentMerchantConfigEntity row = merchantConfigService.getById(id);
        if (row == null) {
            return R.error("商户配置不存在");
        }
        R scopeErr = shopScope.assertMerchantReadable(row);
        if (scopeErr != null) {
            return scopeErr;
        }
        return R.ok(merchantConfigService.toAdminEditMap(row));
    }

    /**
     * 编辑表单：按门店+渠道+merchantKey 拉取本店配置；不存在则返回可填写的空白模板。
     */
    @GetMapping("/merchants/edit-form")
    public R getMerchantEditForm(@RequestParam(required = false) Integer shopId,
                                 @RequestParam(required = false, defaultValue = "wechat") String channel,
                                 @RequestParam(required = false, defaultValue = "default") String merchantKey) {
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId, holder);
        if (err != null) {
            return err;
        }
        R writeErr = shopScope.assertWritableShopId(holder[0]);
        if (writeErr != null) {
            return writeErr;
        }
        return R.ok(merchantConfigService.getAdminEditForm(holder[0], channel, merchantKey));
    }

    /**
     * 保存商户配置（新建或更新）：body 可带 id；不带 id 时按 channel+merchantKey 匹配本店行。
     */
    @PutMapping("/merchants/save")
    public R saveMerchant(@RequestParam(required = false) Integer shopId,
                          @RequestBody Map<String, Object> body) {
        try {
            int[] holder = new int[1];
            R err = shopScope.resolveTargetShopId(shopId, holder);
            if (err != null) {
                return err;
            }
            R writeErr = shopScope.assertWritableShopId(holder[0]);
            if (writeErr != null) {
                return writeErr;
            }
            PaymentMerchantConfigEntity row = merchantConfigService.saveOrUpdate(holder[0], body);
            paymentConfigSync.reloadShop(holder[0]);
            return merchantWriteResult(row, holder[0]);
        } catch (IllegalArgumentException | IllegalStateException e) {
            return R.error(e.getMessage());
        }
    }

    @PostMapping("/merchants")
    public R createMerchant(@RequestParam(required = false) Integer shopId,
                            @RequestBody Map<String, Object> body) {
        try {
            int[] holder = new int[1];
            R err = shopScope.resolveTargetShopId(shopId, holder);
            if (err != null) {
                return err;
            }
            int sid = holder[0];
            R writeErr = shopScope.assertWritableShopId(sid);
            if (writeErr != null) {
                return writeErr;
            }
            PaymentMerchantConfigEntity row = merchantConfigService.save(sid, null, body);
            paymentConfigSync.reloadShop(sid);
            return merchantWriteResult(row, sid);
        } catch (IllegalArgumentException | IllegalStateException e) {
            return R.error(e.getMessage());
        }
    }

    @PutMapping("/merchants/{id}")
    public R updateMerchant(@PathVariable Long id,
                            @RequestBody Map<String, Object> body) {
        try {
            PaymentMerchantConfigEntity existing = merchantConfigService.getById(id);
            if (existing == null) {
                return R.error("商户配置不存在");
            }
            R scopeErr = shopScope.assertMerchantWritable(existing);
            if (scopeErr != null) {
                return scopeErr;
            }
            int rowShop = existing.getShop_id() != null ? existing.getShop_id() : PaymentAdminShopScope.GLOBAL_SHOP_ID;
            PaymentMerchantConfigEntity row = merchantConfigService.save(rowShop, id, body);
            paymentConfigSync.reloadShop(rowShop);
            return merchantWriteResult(row, rowShop);
        } catch (IllegalArgumentException | IllegalStateException e) {
            return R.error(e.getMessage());
        }
    }

    @DeleteMapping("/merchants/{id}")
    public R deleteMerchant(@PathVariable Long id) {
        PaymentMerchantConfigEntity existing = merchantConfigService.getById(id);
        if (existing == null) {
            return R.error("商户配置不存在");
        }
        R scopeErr = shopScope.assertMerchantWritable(existing);
        if (scopeErr != null) {
            return scopeErr;
        }
        int rowShop = existing.getShop_id() != null ? existing.getShop_id() : PaymentAdminShopScope.GLOBAL_SHOP_ID;
        merchantConfigService.delete(id, rowShop);
        paymentConfigSync.reloadShop(rowShop);
        return R.ok()
                .put("retiredId", id)
                .put("retired", true)
                .put("physicallyDeleted", false)
                .put("capabilities", capabilityService.toAdminMap(rowShop));
    }

    @PostMapping("/merchants/{id}/restore")
    public R restoreMerchant(@PathVariable Long id) {
        try {
            PaymentMerchantConfigEntity existing = merchantConfigService.getById(id);
            if (existing == null) return R.error("商户配置不存在");
            R scopeErr = shopScope.assertMerchantWritable(existing);
            if (scopeErr != null) return scopeErr;
            int rowShop = existing.getShop_id() == null ? PaymentAdminShopScope.GLOBAL_SHOP_ID : existing.getShop_id();
            PaymentMerchantConfigEntity restored = merchantConfigService.restore(id, rowShop);
            paymentConfigSync.reloadShop(rowShop);
            return merchantWriteResult(restored, rowShop).put("restored", true);
        } catch (IllegalArgumentException | IllegalStateException e) {
            return R.error(e.getMessage());
        }
    }

    @GetMapping("/merchant-policy")
    public R getMerchantPolicy(@RequestParam(required = false) Integer shopId) {
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId, holder);
        if (err != null) return err;
        if (holder[0] <= 0) return R.error("商户策略只能查询具体门店");
        return R.ok(merchantPolicyService.get(holder[0]));
    }

    @PutMapping("/merchant-policy")
    public R putMerchantPolicy(@RequestParam(required = false) Integer shopId,
                               @RequestBody Map<String, Object> body) {
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId, holder);
        if (err != null) return err;
        R writeErr = shopScope.assertWritableShopId(holder[0]);
        if (writeErr != null) return writeErr;
        Object raw = body == null ? null : body.get("allowGlobalFallback");
        if (raw == null) return R.error("allowGlobalFallback 不能为空");
        boolean allow = raw instanceof Boolean ? (Boolean) raw : raw != null && "true".equalsIgnoreCase(raw.toString());
        Map<String, Object> saved = merchantPolicyService.save(holder[0], allow);
        paymentConfigSync.reloadShop(holder[0]);
        return R.ok(saved);
    }

    private R merchantWriteResult(PaymentMerchantConfigEntity row, int shopId) {
        return R.ok(merchantConfigService.toAdminEditMap(row))
                .put("capabilities", capabilityService.toAdminMap(shopId));
    }

    @PostMapping("/private-key/upload")
    public R uploadPrivateKey(@RequestParam(required = false) Integer shopId,
                              @RequestParam(required = false, defaultValue = "default") String merchantKey,
                              @RequestParam("file") MultipartFile file) {
        try {
            int[] holder = new int[1];
            R err = shopScope.resolveTargetShopId(shopId, holder);
            if (err != null) {
                return err;
            }
            R writeErr = shopScope.assertWritableShopId(holder[0]);
            if (writeErr != null) {
                return writeErr;
            }
            String ref = merchantConfigService.storePrivateKeyPem(holder[0], merchantKey, file);
            return R.ok()
                    .put("privateKeyRef", ref)
                    .put("private_key_ref", ref)
                    .put("shopId", holder[0])
                    .put("merchantKey", merchantKey);
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        } catch (IOException e) {
            return R.error("上传商户私钥失败：" + e.getMessage());
        } catch (Exception e) {
            return R.error("上传商户私钥失败：" + e.getMessage());
        }
    }

    @PostMapping("/platform-public-key/upload")
    public R uploadPlatformPublicKey(@RequestParam(required = false) Integer shopId,
                                     @RequestParam(required = false, defaultValue = "default") String merchantKey,
                                     @RequestParam("file") MultipartFile file) {
        try {
            int[] holder = new int[1];
            R err = shopScope.resolveTargetShopId(shopId, holder);
            if (err != null) {
                return err;
            }
            R writeErr = shopScope.assertWritableShopId(holder[0]);
            if (writeErr != null) {
                return writeErr;
            }
            PaymentMerchantConfigService.PlatformPublicMaterial stored =
                    merchantConfigService.storePlatformPublicKeyPem(holder[0], merchantKey, file);
            return R.ok()
                    .put("platformPubKeyRef", stored.platformPubKeyRef)
                    .put("platform_pub_key_ref", stored.platformPubKeyRef)
                    .put("materialType", stored.materialType)
                    .put("shopId", holder[0])
                    .put("merchantKey", merchantKey);
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        } catch (IOException e) {
            return R.error("上传微信支付平台公钥证书失败：" + e.getMessage());
        } catch (Exception e) {
            return R.error("上传微信支付平台公钥证书失败：" + e.getMessage());
        }
    }

    @PostMapping("/merchants/{id}/private-key/upload")
    public R uploadMerchantPrivateKey(@PathVariable Long id,
                                      @RequestParam("file") MultipartFile file) {
        try {
            PaymentMerchantConfigEntity existing = merchantConfigService.getById(id);
            if (existing == null) {
                return R.error("商户配置不存在");
            }
            R scopeErr = shopScope.assertMerchantWritable(existing);
            if (scopeErr != null) {
                return scopeErr;
            }
            PaymentMerchantConfigEntity row = merchantConfigService.uploadPrivateKeyForMerchant(existing, file);
            int rowShop = row.getShop_id() != null ? row.getShop_id() : PaymentAdminShopScope.GLOBAL_SHOP_ID;
            paymentConfigSync.reloadShop(rowShop);
            return R.ok(merchantConfigService.toPublicMap(row))
                    .put("privateKeyRef", row.getPrivate_key_ref())
                    .put("private_key_ref", row.getPrivate_key_ref());
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        } catch (IOException e) {
            return R.error("上传商户私钥失败：" + e.getMessage());
        } catch (Exception e) {
            return R.error("上传商户私钥失败：" + e.getMessage());
        }
    }

    @PostMapping("/certificate/upload")
    public R uploadCertificate(@RequestParam(required = false) Integer shopId,
                               @RequestParam(required = false, defaultValue = "default") String merchantKey,
                               @RequestParam(required = false, defaultValue = "AUTO") String type,
                               @RequestParam("file") MultipartFile file) {
        try {
            int[] holder = new int[1];
            R err = shopScope.resolveTargetShopId(shopId, holder);
            if (err != null) {
                return err;
            }
            R writeErr = shopScope.assertWritableShopId(holder[0]);
            if (writeErr != null) {
                return writeErr;
            }
            PaymentMerchantConfigService.UnifiedCertificateResult stored =
                    merchantConfigService.storeCertificateMaterial(holder[0], merchantKey, type, file);
            R r = R.ok()
                    .put("certificateType", stored.getCertificateType())
                    .put("fileRef", stored.getFileRef())
                    .put("filename", stored.getOriginalFilename())
                    .put("fileSize", stored.getFileSize())
                    .put("shopId", holder[0])
                    .put("merchantKey", merchantKey);
            if (stored.getMaterialType() != null) {
                r.put("materialType", stored.getMaterialType());
            }
            // 兼容性字段映射
            if ("CLIENT_CERT_P12".equals(stored.getCertificateType())) {
                r.put("clientCertP12Ref", stored.getFileRef());
                r.put("client_cert_p12_ref", stored.getFileRef());
            } else if ("PRIVATE_KEY".equals(stored.getCertificateType())) {
                r.put("privateKeyRef", stored.getFileRef());
                r.put("private_key_ref", stored.getFileRef());
            } else if ("PLATFORM_PUBLIC_KEY".equals(stored.getCertificateType())) {
                r.put("platformPubKeyRef", stored.getFileRef());
                r.put("platform_pub_key_ref", stored.getFileRef());
            } else if ("ALIPAY_ROOT_CERT".equals(stored.getCertificateType())) {
                r.put("alipayRootCertRef", stored.getFileRef());
            } else if ("ALIPAY_APP_CERT".equals(stored.getCertificateType())) {
                r.put("alipayAppCertRef", stored.getFileRef());
            } else if ("ALIPAY_PUBLIC_CERT".equals(stored.getCertificateType())) {
                r.put("alipayPublicCertRef", stored.getFileRef());
            }
            return r;
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        } catch (IOException e) {
            return R.error("上传证书文件失败：" + e.getMessage());
        } catch (Exception e) {
            return R.error("上传证书文件失败：" + e.getMessage());
        }
    }

    @PostMapping("/merchants/{id}/certificate/upload")
    public R uploadMerchantCertificate(@PathVariable Long id,
                                       @RequestParam(required = false, defaultValue = "AUTO") String type,
                                       @RequestParam("file") MultipartFile file) {
        try {
            PaymentMerchantConfigEntity existing = merchantConfigService.getById(id);
            if (existing == null) {
                return R.error("商户配置不存在");
            }
            R scopeErr = shopScope.assertMerchantWritable(existing);
            if (scopeErr != null) {
                return scopeErr;
            }
            PaymentMerchantConfigService.CertificateBindResult bound =
                    merchantConfigService.uploadCertificateForMerchant(existing, type, file);
            int rowShop = bound.row.getShop_id() != null ? bound.row.getShop_id() : PaymentAdminShopScope.GLOBAL_SHOP_ID;
            paymentConfigSync.reloadShop(rowShop);
            R r = R.ok(merchantConfigService.toPublicMap(bound.row));
            r.put("certificateType", bound.certificateResult.getCertificateType());
            r.put("fileRef", bound.certificateResult.getFileRef());
            r.put("filename", bound.certificateResult.getOriginalFilename());
            r.put("fileSize", bound.certificateResult.getFileSize());
            if (bound.certificateResult.getMaterialType() != null) {
                r.put("materialType", bound.certificateResult.getMaterialType());
            }
            // 兼容性字段映射
            r.put("clientCertP12Ref", bound.row.getClient_cert_p12_ref());
            r.put("client_cert_p12_ref", bound.row.getClient_cert_p12_ref());
            r.put("privateKeyRef", bound.row.getPrivate_key_ref());
            r.put("private_key_ref", bound.row.getPrivate_key_ref());
            r.put("platformPubKeyRef", bound.row.getPlatform_pub_key_ref());
            r.put("platform_pub_key_ref", bound.row.getPlatform_pub_key_ref());
            return r;
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        } catch (IOException e) {
            return R.error("上传商户证书失败：" + e.getMessage());
        } catch (Exception e) {
            return R.error("上传商户证书失败：" + e.getMessage());
        }
    }

    @GetMapping("/notify-urls")
    public R notifyUrls() {
        return R.ok().put("data", merchantConfigService.notifyUrlTemplates());
    }

    /**
     * 微信支付 JSAPI 鉴权配置诊断（不请求微信）。401 时查看 issues、serialMatchCert。
     *
     * @param merchantKey default | small_amount；也可用 legacy 1/2
     */
    @GetMapping("/wechat/pay-auth-audit")
    public R wechatPayAuthAudit(@RequestParam(required = false) Integer shopId,
                                @RequestParam(required = false, defaultValue = "default") String merchantKey) {
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId, holder);
        if (err != null) {
            return err;
        }
        WechatPayCredentialAudit.PayAuthAudit audit =
                wechatMerchantKeyStore.auditPayConfig(holder[0], merchantKey);
        if (audit == null) {
            return R.error("无法生成支付鉴权诊断");
        }
        return R.ok()
                .put("shopId", holder[0])
                .put("merchantKey", audit.merchantKey)
                .put("legacyMerchantId", audit.legacyMerchantId)
                .put("configSource", audit.configSource)
                .put("dbConfigId", audit.dbConfigId)
                .put("mchId", audit.mchIdUsed)
                .put("appId", audit.appIdUsed)
                .put("serialUsed", audit.serialNoUsedInAuth)
                .put("serialDb", audit.dbSerialNo)
                .put("serialYml", audit.ymlSerialNo)
                .put("certSerial", audit.certSerialFromPem)
                .put("certNotAfter", audit.certNotAfter)
                .put("certExpired", audit.certExpired)
                .put("serialMatchCert", audit.serialMatchesCert)
                .put("privateKeyRefDb", audit.dbPrivateKeyRef)
                .put("privateKeyRefUsed", audit.privateKeyRefUsed)
                .put("privateKeyFromDbRef", audit.privateKeyLoadedFromConfiguredRef)
                .put("privateKeyFallbackYml", audit.privateKeyFallbackYml)
                .put("privateKeyFileExists", audit.privateKeyFileExists)
                .put("privateKeyFileReadable", audit.privateKeyFileReadable)
                .put("certPathTried", audit.certPathTried)
                .put("apiV3KeySource", audit.apiV3KeySource)
                .put("apiV3LooksLikeAppSecret", audit.apiV3KeyLooksLikeMiniProgramSecret)
                .put("issues", audit.issues)
                .put("logLine", audit.toLogLine());
    }
}
