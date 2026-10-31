package com.lanf.util;

import com.lanf.entity.Admin;
import com.lanf.service.IAdminService;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.util.*;
import java.util.stream.Collectors;

/**
 * 操作人姓名解析器：优先使用员工真实姓名(real_name)，回退至用户名(userName)。
 */
@Component
public class AdminNameResolver {

    private final IAdminService adminService;

    public AdminNameResolver(@Lazy IAdminService adminService) {
        this.adminService = adminService;
    }

    /**
     * 解析 Admin 对象的显示名称：优先真实姓名，次之用户名
     */
    public static String resolveDisplayName(Admin admin) {
        if (admin == null) {
            return null;
        }
        if (StringUtils.hasText(admin.getRealName())) {
            return admin.getRealName().trim();
        }
        if (StringUtils.hasText(admin.getUserName())) {
            return admin.getUserName().trim();
        }
        return null;
    }

    /**
     * 解析 Admin 对象的显示名称，提供默认回退文案
     */
    public static String resolveDisplayName(Admin admin, String defaultFallback) {
        String name = resolveDisplayName(admin);
        return StringUtils.hasText(name) ? name : defaultFallback;
    }

    /**
     * 单个 ID 解析
     */
    public static String resolveDisplayName(Integer adminId, IAdminService service) {
        if (adminId == null || service == null) {
            return null;
        }
        try {
            Admin admin = service.getById(adminId);
            return resolveDisplayName(admin);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * 批量解析 ID 对应的显示姓名，避免 N+1 查询
     */
    public static Map<Integer, String> resolveDisplayNames(Collection<Integer> adminIds, IAdminService service) {
        if (adminIds == null || adminIds.isEmpty() || service == null) {
            return Collections.emptyMap();
        }
        Set<Integer> validIds = adminIds.stream().filter(Objects::nonNull).collect(Collectors.toSet());
        if (validIds.isEmpty()) {
            return Collections.emptyMap();
        }
        try {
            List<Admin> list = service.listByIds(validIds);
            if (list == null) {
                return Collections.emptyMap();
            }
            Map<Integer, String> result = new HashMap<>();
            for (Admin admin : list) {
                if (admin != null && admin.getId() != null) {
                    result.put(admin.getId(), resolveDisplayName(admin));
                }
            }
            return result;
        } catch (Exception e) {
            return Collections.emptyMap();
        }
    }

    public String resolveById(Integer adminId) {
        return resolveDisplayName(adminId, this.adminService);
    }

    public Map<Integer, String> resolveByIds(Collection<Integer> adminIds) {
        return resolveDisplayNames(adminIds, this.adminService);
    }

    @lombok.Data
    public static class AdminIdentity {
        private final Integer adminId;
        private final String realName;
        private final String workNo;
        private final String userName;
        private final String effectiveName;
        private final String displayName;

        public AdminIdentity(Integer adminId, String realName, String workNo, String userName) {
            this.adminId = adminId;
            this.realName = StringUtils.hasText(realName) ? realName.trim() : null;
            this.workNo = StringUtils.hasText(workNo) ? workNo.trim() : null;
            this.userName = StringUtils.hasText(userName) ? userName.trim() : null;

            String base = this.realName != null ? this.realName : (this.userName != null ? this.userName : "");
            this.effectiveName = base;
            if (StringUtils.hasText(base) && StringUtils.hasText(this.workNo)) {
                this.displayName = base + " (" + this.workNo + ")";
            } else if (StringUtils.hasText(base)) {
                this.displayName = base;
            } else if (StringUtils.hasText(this.workNo)) {
                this.displayName = "工号 " + this.workNo;
            } else {
                this.displayName = "";
            }
        }
    }

    /**
     * 批量解析管理员多维身份（含真实姓名、工号、复合展示文案）
     */
    public static Map<Integer, AdminIdentity> resolveAdminIdentities(Collection<Integer> adminIds, IAdminService service) {
        if (adminIds == null || adminIds.isEmpty() || service == null) {
            return Collections.emptyMap();
        }
        Set<Integer> validIds = adminIds.stream().filter(Objects::nonNull).collect(Collectors.toSet());
        if (validIds.isEmpty()) {
            return Collections.emptyMap();
        }
        try {
            List<Admin> list = service.listByIds(validIds);
            if (list == null) {
                return Collections.emptyMap();
            }
            Map<Integer, AdminIdentity> map = new HashMap<>();
            for (Admin a : list) {
                if (a != null && a.getId() != null) {
                    map.put(a.getId(), new AdminIdentity(a.getId(), a.getRealName(), a.getWorkNo(), a.getUserName()));
                }
            }
            return map;
        } catch (Exception e) {
            return Collections.emptyMap();
        }
    }

    /**
     * 单个解析管理员多维身份
     */
    public static AdminIdentity resolveAdminIdentity(Integer adminId, IAdminService service) {
        if (adminId == null || service == null) {
            return null;
        }
        try {
            Admin a = service.getById(adminId);
            if (a == null) return null;
            return new AdminIdentity(a.getId(), a.getRealName(), a.getWorkNo(), a.getUserName());
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * 为订单集合批量填充当班收银员的姓名与工号（单次批量回表，彻底杜绝 N+1）
     */
    public static void enrichOrdersCashierInfo(Collection<com.lanf.entity.Order> orders, IAdminService service) {
        if (orders == null || orders.isEmpty() || service == null) {
            return;
        }
        Set<Integer> targetAdminIds = new HashSet<>();
        for (com.lanf.entity.Order o : orders) {
            if (o == null) continue;
            if (o.getCashier_id() != null) {
                targetAdminIds.add(o.getCashier_id());
            }
            if (o.getOrder_admin_id() != null) {
                targetAdminIds.add(o.getOrder_admin_id());
            }
        }
        if (targetAdminIds.isEmpty()) {
            return;
        }
        Map<Integer, AdminIdentity> identities = resolveAdminIdentities(targetAdminIds, service);
        for (com.lanf.entity.Order o : orders) {
            if (o == null) continue;
            Integer cashierAdminId = o.getCashier_id() != null ? o.getCashier_id() : o.getOrder_admin_id();
            if (cashierAdminId != null) {
                AdminIdentity id = identities.get(cashierAdminId);
                if (id != null) {
                    if (o.getCashier_id() == null) {
                        o.setCashier_id(cashierAdminId);
                    }
                    o.setCashier_name(id.getEffectiveName());
                    o.setCashier_work_no(id.getWorkNo());
                    o.setCashier_display_name(id.getDisplayName());
                    o.setDisplay_name(id.getDisplayName());
                }
            }
            if (o.getOrder_admin_id() != null) {
                AdminIdentity orderAdminId = identities.get(o.getOrder_admin_id());
                if (orderAdminId != null && o.getOrder_admin_name() == null) {
                    o.setOrder_admin_name(orderAdminId.getEffectiveName());
                }
            }
        }
    }

    public void enrichOrders(Collection<com.lanf.entity.Order> orders) {
        enrichOrdersCashierInfo(orders, this.adminService);
    }
}

