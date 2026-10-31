package com.lanf.config;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.constant.InviteFirstOrderRewardConfigKeys;
import com.lanf.constant.WeChatPrepayNineFoldConfigKeys;
import com.lanf.constant.ZsqSystemConfigKeys;
import com.lanf.entity.SystemConfig;
import com.lanf.mapper.SystemConfigMapper;
import com.lanf.util.SystemConfigTableSupport;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import javax.annotation.PostConstruct;
import java.util.List;

/**
 * 系统配置与 Spring 配置 Bean 的同步器：
 * 启动时从 t_system_config 中加载配置并覆盖 InvitePosterSettings 等中的默认值。
 * 自 v1.2.223 起不再覆盖 FeieyunConfig（打印设备参数统一以 t_printing_device 为准）。
 */
@Component
public class SystemConfigSync {

    private static final Logger log = LoggerFactory.getLogger(SystemConfigSync.class);

    @Autowired
    private SystemConfigMapper systemConfigMapper;
    @Autowired
    private InvitePosterSettings invitePosterSettings;
    @Autowired
    private WeChatPrepayNineFoldSettings weChatPrepayNineFoldSettings;
    @Autowired
    private InviteFirstOrderRewardSettings inviteFirstOrderRewardSettings;
    @Autowired
    private ZsqSystemSettings zsqSystemSettings;
    @Autowired
    private SystemConfigTableSupport systemConfigTableSupport;

    @PostConstruct
    public void loadFromDb() {
        try {
            List<SystemConfig> list = systemConfigTableSupport.hasShopIdColumn()
                    ? systemConfigMapper.selectList(new QueryWrapper<SystemConfig>())
                    : systemConfigMapper.selectAllLegacy();
            if (list == null || list.isEmpty()) {
                return;
            }
            for (SystemConfig cfg : list) {
                if (cfg == null || cfg.getConfig_key() == null) continue;
                String key = cfg.getConfig_key().trim();
                String value = cfg.getConfig_value();
                if (value == null) value = "";

                switch (key) {
                    case "invite.poster.background.path":
                        invitePosterSettings.getBackground().setPath(value);
                        break;
                    case "invite.poster.qr.x":
                        setIntSafely(value, v -> invitePosterSettings.getQr().setX(v));
                        break;
                    case "invite.poster.qr.y":
                        setIntSafely(value, v -> invitePosterSettings.getQr().setY(v));
                        break;
                    case "invite.poster.qr.size":
                        setIntSafely(value, v -> invitePosterSettings.getQr().setSize(v));
                        break;
                    case WeChatPrepayNineFoldConfigKeys.ENABLED:
                    case WeChatPrepayNineFoldConfigKeys.PAY_RATE:
                    case WeChatPrepayNineFoldConfigKeys.MIN_BASE_YUAN:
                    case WeChatPrepayNineFoldConfigKeys.TIME_START:
                    case WeChatPrepayNineFoldConfigKeys.TIME_END:
                    case WeChatPrepayNineFoldConfigKeys.ZONE_ID:
                    case WeChatPrepayNineFoldConfigKeys.ELIGIBLE_DINING_TYPES:
                        weChatPrepayNineFoldSettings.applyFromKeyValue(key, value);
                        break;
                    case InviteFirstOrderRewardConfigKeys.ENABLED:
                    case InviteFirstOrderRewardConfigKeys.PERCENT:
                        inviteFirstOrderRewardSettings.applyFromKeyValue(key, value);
                        break;
                    case ZsqSystemConfigKeys.AUTO_API_ENABLED:
                    case ZsqSystemConfigKeys.TAKEOUT_SYNC_ENABLED: {
                        int shopId = cfg.getShop_id() != null ? cfg.getShop_id() : ZsqSystemSettings.GLOBAL_SHOP_ID;
                        zsqSystemSettings.applyFromKeyValue(shopId, key, value);
                        break;
                    }
                    default:
                        break;
                }
            }
            log.info("SystemConfigSync: 已从 t_system_config 覆盖部分配置");
        } catch (Exception e) {
            log.warn("SystemConfigSync: 加载系统配置失败，将继续使用 application.yml 默认值：{}", e.getMessage());
        }
    }

    private interface IntConsumer {
        void accept(int value);
    }

    private void setIntSafely(String value, IntConsumer consumer) {
        try {
            if (value != null && !value.trim().isEmpty()) {
                consumer.accept(Integer.parseInt(value.trim()));
            }
        } catch (NumberFormatException ignore) {
        }
    }
}

