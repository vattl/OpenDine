package com.lanf.config;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.ApiPermission;
import com.lanf.mapper.ApiPermissionMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import javax.annotation.PostConstruct;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 基于 t_api_permission 的接口-权限映射。
 * SysInterceptor 通过本组件根据 method+path 动态解析所需权限码。
 * 前端可通过 /admin/rbac/api-permissions 接口维护映射，再由本组件 reload() 生效。
 */
@Component
public class DbApiPermissionMapping {

    private static final Logger log = LoggerFactory.getLogger(DbApiPermissionMapping.class);

    @Autowired
    private ApiPermissionMapper apiPermissionMapper;

    /** 内存缓存的映射表，按 path_pattern 长度降序排序，优先匹配更长路径 */
    private volatile List<Entry> mappings = Collections.emptyList();

    @PostConstruct
    public void init() {
        reload();
    }

    /**
     * 重新从 t_api_permission 加载所有映射到内存。
     * 供配置变更后调用（例如 AdminRbacController 中修改 api-permissions 后）。
     */
    public synchronized void reload() {
        try {
            List<ApiPermission> list = apiPermissionMapper.selectList(new QueryWrapper<ApiPermission>());
            List<Entry> newList = new ArrayList<>();
            if (list != null) {
                for (ApiPermission ap : list) {
                    if (ap == null) continue;
                    if (ap.getMethod() == null || ap.getPath_pattern() == null || ap.getPermission_code() == null) {
                        continue;
                    }
                    String method = ap.getMethod().trim().toUpperCase();
                    String path = ap.getPath_pattern().trim();
                    String code = ap.getPermission_code().trim();
                    if (method.isEmpty() || path.isEmpty() || code.isEmpty()) {
                        continue;
                    }
                    newList.add(new Entry(method, path, code));
                }
            }
            // 按路径长度降序，优先匹配更长路径
            newList.sort((a, b) -> Integer.compare(b.pathPattern.length(), a.pathPattern.length()));
            mappings = newList;
            log.info("接口权限映射已从 t_api_permission 加载完成，共 {} 条", mappings.size());
            validateInventoryDrift(newList);
        } catch (Exception e) {
            log.error("加载 t_api_permission 失败；保留最后一次成功快照，首次加载失败时接口权限将失败关闭：{}", e.getMessage());
        }
    }

    private void validateInventoryDrift(List<Entry> loaded) {
        Map<String, String> database = new LinkedHashMap<>();
        for (Entry entry : loaded) {
            database.put(entry.pathPattern, entry.permissionCode);
        }
        Map<String, String> inventory = ApiPermissionMapping.inventory();
        long missing = inventory.entrySet().stream()
                .filter(entry -> !database.containsKey(entry.getKey()))
                .count();
        long different = inventory.entrySet().stream()
                .filter(entry -> database.containsKey(entry.getKey()))
                .filter(entry -> !entry.getValue().equals(database.get(entry.getKey())))
                .count();
        long extra = database.keySet().stream()
                .filter(path -> !inventory.containsKey(path))
                .count();
        if (missing > 0 || different > 0 || extra > 0) {
            log.error("t_api_permission 与审计清单存在漂移: missing={}, different={}, extra={}; "
                            + "运行时仍严格以数据库为权威",
                    missing, different, extra);
        } else {
            log.info("t_api_permission 与审计清单一致，共 {} 条", inventory.size());
        }
    }

    /**
     * 根据请求方法和路径解析所需权限码。
     *
     * @param method 请求方法，如 GET、POST
     * @param path   请求路径，如 /admin/order/list（不含 query）
     * @return 所需权限码；若未配置或首次加载失败则返回 null，由调用方失败关闭
     */
    public String getRequiredPermission(String method, String path) {
        if (path == null) path = "";
        String normalizedPath = path.split("\\?")[0].trim();
        List<Entry> local = mappings;
        if (local == null || local.isEmpty()) {
            return null;
        }
        for (Entry e : local) {
            if (("*".equals(e.method) || e.method.equalsIgnoreCase(method))
                    && matchesPath(e.pathPattern, normalizedPath)) {
                return e.permissionCode;
            }
        }
        return null;
    }

    static boolean matchesPath(String pattern, String path) {
        if (pattern == null || path == null) {
            return false;
        }
        if (!pattern.contains("*")) {
            return path.equals(pattern) || (pattern.endsWith("/") && path.startsWith(pattern));
        }
        String[] expected = pattern.split("/", -1);
        String[] actual = path.split("/", -1);
        if (expected.length != actual.length) {
            return false;
        }
        for (int i = 0; i < expected.length; i++) {
            if (!"*".equals(expected[i]) && !expected[i].equals(actual[i])) {
                return false;
            }
        }
        return true;
    }

    private static class Entry {
        final String method;
        final String pathPattern;
        final String permissionCode;

        Entry(String method, String pathPattern, String permissionCode) {
            this.method = method;
            this.pathPattern = pathPattern;
            this.permissionCode = permissionCode;
        }
    }

    /** Map.merge 去重：同一路径重复登记时保留先出现的权限码（先登记者通常为更具体的配置）。 */
    public static String mergePermissionCode(String existing, String incoming) {
        return existing != null ? existing : incoming;
    }
}

