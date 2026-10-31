package com.lanf.adminlog.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.OperationLog;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * D029 在线日志分类过滤：business=排除 access_denied；security=仅 security 模块；all/null=全量。
 */
class AdminLogServiceCategoryTest {

    private String sqlOf(QueryWrapper<OperationLog> q) {
        return q.getSqlSegment();
    }

    @Test
    @DisplayName("business 排除 access_denied 拒绝噪声")
    void businessExcludesAccessDenied() {
        QueryWrapper<OperationLog> q = new QueryWrapper<>();
        AdminLogService.applyCategoryFilter(q, "business");
        String sql = sqlOf(q);
        assertEquals("(action <> #{ew.paramNameValuePairs.MPGENVAL1})", sql);
    }

    @Test
    @DisplayName("security 仅保留 security 模块")
    void securityKeepsOnlySecurityModule() {
        QueryWrapper<OperationLog> q = new QueryWrapper<>();
        AdminLogService.applyCategoryFilter(q, "security");
        assertEquals("(module = #{ew.paramNameValuePairs.MPGENVAL1})", sqlOf(q));
    }

    @Test
    @DisplayName("all 与 null 不过滤")
    void allAndNullDoNotFilter() {
        QueryWrapper<OperationLog> q1 = new QueryWrapper<>();
        AdminLogService.applyCategoryFilter(q1, "all");
        assertEquals("", sqlOf(q1));

        QueryWrapper<OperationLog> q2 = new QueryWrapper<>();
        AdminLogService.applyCategoryFilter(q2, null);
        assertEquals("", sqlOf(q2));
    }
}
