-- 门店线下收款码：上传后解码为跳转串；C 端 POST /pay/offline-collect/temp-qrcode 将其再编码为二维码图供扫一扫；GET /pay/offline-collect/jump 为短时 token 备用
ALTER TABLE `t_shop`
    ADD COLUMN `offline_collect_wechat_payload` VARCHAR(2048) NULL DEFAULT NULL COMMENT '微信个人收款码解码后的跳转串（如 wxp://）' AFTER `remark`,
    ADD COLUMN `offline_collect_alipay_payload` VARCHAR(2048) NULL DEFAULT NULL COMMENT '支付宝收款码解码后的跳转串' AFTER `offline_collect_wechat_payload`,
    ADD COLUMN `offline_collect_wechat_image_path` VARCHAR(512) NULL DEFAULT NULL COMMENT '上传的微信收款码图片相对/绝对路径（可选备份）' AFTER `offline_collect_alipay_payload`,
    ADD COLUMN `offline_collect_alipay_image_path` VARCHAR(512) NULL DEFAULT NULL COMMENT '上传的支付宝收款码图片路径' AFTER `offline_collect_wechat_image_path`;
