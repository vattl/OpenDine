package com.lanf.kds.service;

import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.mapper.KdsShopConfigMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.Date;

@Service
public class KdsConfigService {

    public static final String MODE_PRINT_ONLY = "print_only";
    public static final String MODE_KDS_ONLY = "kds_only";
    public static final String MODE_BOTH = "both";

    @Autowired
    private KdsShopConfigMapper shopConfigMapper;
    @Autowired
    private com.lanf.kds.mapper.KdsStationMapper stationMapper;

    public KdsShopConfig save(int shopId, KdsShopConfig input) {
        KdsShopConfig cfg = shopConfigMapper.selectById(shopId);
        if (cfg == null) {
            cfg = defaultConfig(shopId);
        }
        if (input.getKds_mode() != null) {
            String mode = input.getKds_mode().trim();
            if (MODE_PRINT_ONLY.equals(mode) || MODE_KDS_ONLY.equals(mode) || MODE_BOTH.equals(mode)) {
                cfg.setKds_mode(mode);
            }
        }
        if (input.getSync_legacy_rece() != null) {
            cfg.setSync_legacy_rece(input.getSync_legacy_rece());
        }
        if (input.getAuto_off_order_on_kds_done() != null) {
            cfg.setAuto_off_order_on_kds_done(input.getAuto_off_order_on_kds_done() != 0 ? 1 : 0);
        }
        if (input.getServe_print_enabled() != null) {
            cfg.setServe_print_enabled(input.getServe_print_enabled() != 0 ? 1 : 0);
        }
        if (input.getAuto_push_on_create() != null) {
            cfg.setAuto_push_on_create(input.getAuto_push_on_create());
        }
        if (input.getSkewer_gate() != null) {
            cfg.setSkewer_gate(input.getSkewer_gate() != 0 ? 1 : 0);
        }
        if (input.getDefault_screen_tag() != null && KdsScreenTag.isValid(input.getDefault_screen_tag())) {
            cfg.setDefault_screen_tag(input.getDefault_screen_tag().trim());
        }
        if (input.getSla_minutes() != null && input.getSla_minutes() > 0) {
            cfg.setSla_minutes(input.getSla_minutes());
        }
        if (input.getArchive_hours() != null && input.getArchive_hours() > 0) {
            cfg.setArchive_hours(input.getArchive_hours());
        }
        if (input.getLack_sets_sold_out() != null) {
            cfg.setLack_sets_sold_out(input.getLack_sets_sold_out());
        }
        if (input.getMerge_same_dish() != null) {
            cfg.setMerge_same_dish(input.getMerge_same_dish() != 0 ? 1 : 0);
        }
        if (input.getPack_inline_merge() != null) {
            cfg.setPack_inline_merge(input.getPack_inline_merge() != 0 ? 1 : 0);
        }
        if (input.getCombo_merge() != null) {
            cfg.setCombo_merge(input.getCombo_merge() != 0 ? 1 : 0);
        }
        if (input.getEnable_prep_workflow() != null) {
            cfg.setEnable_prep_workflow(input.getEnable_prep_workflow() != 0 ? 1 : 0);
        }
        if (input.getKds_pin() != null && !input.getKds_pin().trim().isEmpty()) {
            cfg.setKds_pin(input.getKds_pin().trim());
        }
        cfg.setUpdated_at(new Date());
        if (shopConfigMapper.selectById(shopId) == null) {
            cfg.setShop_id(shopId);
            shopConfigMapper.insert(cfg);
        } else {
            shopConfigMapper.updateById(cfg);
        }
        return getOrDefault(shopId);
    }

    public KdsShopConfig getOrDefault(int shopId) {
        KdsShopConfig cfg = shopConfigMapper.selectById(shopId);
        if (cfg == null) {
            return defaultConfig(shopId);
        }
        if (cfg.getKds_pin() == null || cfg.getKds_pin().trim().isEmpty()) {
            cfg.setKds_pin("123456");
        }
        return cfg;
    }

    private KdsShopConfig defaultConfig(int shopId) {
        KdsShopConfig cfg = new KdsShopConfig();
        cfg.setShop_id(shopId);
        cfg.setKds_mode(MODE_PRINT_ONLY);
        cfg.setSync_legacy_rece(1);
        cfg.setAuto_off_order_on_kds_done(0);
        cfg.setServe_print_enabled(1);
        cfg.setAuto_push_on_create(1);
        cfg.setSkewer_gate(1);
        cfg.setDefault_screen_tag(KdsScreenTag.MEAT_GRILL);
        cfg.setSla_minutes(10);
        cfg.setArchive_hours(2);
        cfg.setLack_sets_sold_out(0);
        cfg.setMerge_same_dish(1);
        cfg.setPack_inline_merge(1);
        cfg.setCombo_merge(1);
        cfg.setEnable_prep_workflow(1);
        cfg.setKds_pin("123456");
        return cfg;
    }

    public boolean isKdsEnabled(int shopId) {
        String mode = getOrDefault(shopId).getKds_mode();
        return MODE_KDS_ONLY.equals(mode) || MODE_BOTH.equals(mode);
    }

    public boolean isKdsOnly(int shopId) {
        return MODE_KDS_ONLY.equals(getOrDefault(shopId).getKds_mode());
    }

    /** kds_only 时不打飞鹅厨房/前台小票；print_only / both 仍打印。 */
    public boolean shouldFeiePrint(int shopId) {
        return !isKdsOnly(shopId);
    }

    /** 是否启用「先抓串再分流烤制屏」。 */
    public boolean isSkewerGateEnabled(int shopId) {
        KdsShopConfig cfg = getOrDefault(shopId);
        return cfg.getSkewer_gate() == null || cfg.getSkewer_gate() != 0;
    }

    /** 是否启用「待配菜环节」（档口级优先覆盖门店级；未显式配置则默认开启 1）。 */
    public boolean isPrepWorkflowEnabled(int shopId) {
        return isPrepWorkflowEnabled(shopId, null);
    }

    public boolean isPrepWorkflowEnabled(int shopId, Long stationId) {
        if (stationId != null && stationId > 0 && stationMapper != null) {
            com.lanf.kds.entity.KdsStation station = stationMapper.selectById(stationId);
            if (station != null && station.getEnable_prep_workflow() != null) {
                return station.getEnable_prep_workflow() == 1;
            }
        }
        KdsShopConfig cfg = getOrDefault(shopId);
        if (cfg.getEnable_prep_workflow() != null) {
            return cfg.getEnable_prep_workflow() == 1;
        }
        return cfg.getSkewer_gate() == null || cfg.getSkewer_gate() != 0;
    }

    /** 厨显整单完成（40）时是否自动清台（{@code order_receiving=off_order}）。 */
    public boolean isAutoOffOrderOnKdsDone(int shopId) {
        KdsShopConfig cfg = getOrDefault(shopId);
        return cfg.getAuto_off_order_on_kds_done() != null && cfg.getAuto_off_order_on_kds_done() == 1;
    }

    /** 待传菜划单后是否打印飞鹅传菜单。 */
    public boolean isServePrintEnabled(int shopId) {
        KdsShopConfig cfg = getOrDefault(shopId);
        return cfg.getServe_print_enabled() == null || cfg.getServe_print_enabled() != 0;
    }
}
