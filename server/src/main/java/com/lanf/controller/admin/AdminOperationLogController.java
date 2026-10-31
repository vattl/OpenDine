package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.lanf.entity.OperationLog;
import com.lanf.entity.R;
import com.lanf.security.AdminShopScopeGuard;
import com.lanf.service.IAdminService;
import com.lanf.service.IOperationLogService;
import com.lanf.util.AdminNameResolver;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;


/**
 * 关键操作日志（防作弊、审计）
 */
@RestController
@RequestMapping("/admin/log")
public class AdminOperationLogController {

    @Autowired
    private IOperationLogService operationLogService;
    @Autowired
    private AdminShopScopeGuard adminShopScopeGuard;
    @Autowired(required = false)
    private IAdminService adminService;

    /**
     * 关键操作日志查询（历史兼容接口）。
     * @deprecated 自 v1.2.132 起废弃，请统一迁移至 {@code GET /admin/logs}（具备近 30 天在线查询硬边界、敏感数据脱敏与归档检索支持）。
     */
    @Deprecated
    @GetMapping("/operation")
    public R operation(@RequestParam(required = false) String module,
                       @RequestParam(required = false) String action,
                       @RequestParam(required = false) String tableNumber,
                       @RequestParam(required = false) String resultStatus,
                       @RequestParam(required = false) String requestKey,
                       @RequestParam(required = false) String traceId,
                       @RequestParam(required = false) Integer shopId,
                       @RequestParam(required = false) Boolean allShops,
                       @RequestParam(required = false) String startTime,
                      @RequestParam(required = false) String endTime,
                      @RequestParam(required = false) Integer pageNum,
                      @RequestParam(required = false) Integer pageSize) {
        QueryWrapper<OperationLog> q = new QueryWrapper<>();
        if (Boolean.TRUE.equals(allShops)) {
            R scopeError = adminShopScopeGuard.requireHeadquarters();
            if (scopeError != null) {
                return scopeError;
            }
        } else {
            int[] target = new int[1];
            R scopeError = adminShopScopeGuard.resolveTargetShopId(shopId, target);
            if (scopeError != null) {
                return scopeError;
            }
            if (target[0] == 0) {
                q.and(w -> w.isNull("shop_id").or().eq("shop_id", 0));
            } else {
                q.eq("shop_id", target[0]);
            }
        }
        if (module != null && !module.isEmpty()) q.eq("module", module);
        if (action != null && !action.isEmpty()) q.eq("action", action);
        if (tableNumber != null && !tableNumber.trim().isEmpty()) {
            String table = tableNumber.trim();
            q.and(w -> w.eq("source_table", table).or().eq("target_table", table));
        }
        if (resultStatus != null && !resultStatus.trim().isEmpty()) {
            q.eq("result_status", resultStatus.trim().toUpperCase(java.util.Locale.ROOT));
        }
        if (requestKey != null && !requestKey.trim().isEmpty()) q.eq("request_key", requestKey.trim());
        if (traceId != null && !traceId.trim().isEmpty()) q.eq("trace_id", traceId.trim());
        if (startTime != null && !startTime.isEmpty()) q.ge("created_at", startTime);
        if (endTime != null && !endTime.isEmpty()) q.le("created_at", endTime);
        q.orderByDesc("created_at");
        int pn = pageNum != null && pageNum > 0 ? pageNum : 1;
        int ps = pageSize != null && pageSize > 0 ? Math.min(pageSize, 100) : 20;
        IPage<OperationLog> page = operationLogService.page(new Page<>(pn, ps), q);
        if (page.getRecords() != null && !page.getRecords().isEmpty()) {
            Map<Integer, String> nameMap = null;
            if (adminService != null) {
                Set<Integer> adminIds = page.getRecords().stream()
                        .map(OperationLog::getAdmin_id).filter(Objects::nonNull).collect(Collectors.toSet());
                nameMap = AdminNameResolver.resolveDisplayNames(adminIds, adminService);
            }
            for (OperationLog r : page.getRecords()) {
                if (r != null) {
                    if (nameMap != null && r.getAdmin_id() != null) {
                        String name = nameMap.get(r.getAdmin_id());
                        r.setAdmin_name(name);
                        r.setOperator_name(name);
                    }
                    if (r.getRequest_snapshot() != null) {
                        r.setRequest_snapshot(com.lanf.adminlog.util.LogMaskUtil.mask(r.getRequest_snapshot()));
                    }
                    if (r.getBefore_state() != null) {
                        r.setBefore_state(com.lanf.adminlog.util.LogMaskUtil.mask(r.getBefore_state()));
                    }
                    if (r.getAfter_state() != null) {
                        r.setAfter_state(com.lanf.adminlog.util.LogMaskUtil.mask(r.getAfter_state()));
                    }
                }
            }
        }
        return R.ok().put("list", page.getRecords()).put("total", page.getTotal());
    }
}
