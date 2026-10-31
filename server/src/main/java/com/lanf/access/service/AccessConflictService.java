package com.lanf.access.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.common.ApiException;
import com.lanf.entity.AccessConflictRule;
import com.lanf.mapper.AccessConflictRuleMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 职责分离 (SoD) 权限冲突检测服务
 */
@Service
public class AccessConflictService {

    @Autowired
    private AccessConflictRuleMapper conflictRuleMapper;

    /**
     * 检测给定的权限码集合是否存在 SoD 冲突
     */
    public List<Map<String, Object>> findConflicts(Collection<String> permissionCodes) {
        if (permissionCodes == null || permissionCodes.size() < 2) {
            return new ArrayList<>();
        }

        Set<String> codeSet = new HashSet<>(permissionCodes);
        List<AccessConflictRule> rules = conflictRuleMapper.selectList(new QueryWrapper<AccessConflictRule>()
                .eq("enabled", 1));

        List<Map<String, Object>> conflicts = new ArrayList<>();
        for (AccessConflictRule rule : rules) {
            if (codeSet.contains(rule.getPermission_a()) && codeSet.contains(rule.getPermission_b())) {
                Map<String, Object> c = new LinkedHashMap<>();
                c.put("ruleId", rule.getId());
                c.put("permissionA", rule.getPermission_a());
                c.put("permissionB", rule.getPermission_b());
                c.put("severity", rule.getSeverity());
                c.put("message", rule.getMessage());
                conflicts.add(c);
            }
        }
        return conflicts;
    }

    /**
     * 校验权限分配，若存在 HARD 级别冲突则抛出 409 异常阻断
     */
    public void validateNoHardConflict(Collection<String> permissionCodes, boolean isSuperAdmin, String forceReason) {
        List<Map<String, Object>> conflicts = findConflicts(permissionCodes);
        if (conflicts.isEmpty()) {
            return;
        }

        boolean hasHard = conflicts.stream().anyMatch(c -> AccessConflictRule.SEVERITY_HARD.equals(c.get("severity")));
        if (hasHard) {
            if (isSuperAdmin && forceReason != null && !forceReason.trim().isEmpty()) {
                // 超级管理员携带强制理由放行
                return;
            }
            Map<String, Object> data = new LinkedHashMap<>();
            data.put("conflicts", conflicts);
            throw new ApiException(409, "ACCESS_ROLE_CONFLICT", "存在职责分离 (SoD) 严禁冲突，禁止同时授予冲突权限", data);
        }
    }
}
