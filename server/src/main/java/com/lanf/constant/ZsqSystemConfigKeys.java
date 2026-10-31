package com.lanf.constant;

/**
 * 真省钱相关项在 {@code t_system_config.config_key} 中的键名。
 */
public final class ZsqSystemConfigKeys {

    /** 是否开放 /api/zsq 下 auto 接口与 /api/zsq/auth/login/config（历史键名；现语义为接单后自动发真省钱配送） */
    public static final String AUTO_API_ENABLED = "zsq.auto_api.enabled";

    /** 是否启用外卖真省钱配送状态定时同步 */
    public static final String TAKEOUT_SYNC_ENABLED = "zsq.takeout_sync.enabled";

    private ZsqSystemConfigKeys() {
    }
}
