package com.lanf.config;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Admin;
import com.lanf.service.IAdminService;
import com.lanf.util.AdminPasswordUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * 启动时无侵入升级管理员历史明文密码为 BCrypt。
 * 仅对非 BCrypt 密码进行迁移，不改变账号与接口协议。
 */
@Component
public class AdminPasswordMigrationRunner implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(AdminPasswordMigrationRunner.class);

    private final IAdminService adminService;

    public AdminPasswordMigrationRunner(IAdminService adminService) {
        this.adminService = adminService;
    }

    @Override
    public void run(ApplicationArguments args) {
        List<Admin> admins = adminService.list(new QueryWrapper<Admin>().select("id", "userName", "password"));
        if (admins == null || admins.isEmpty()) {
            return;
        }
        int total = 0;
        int migrated = 0;
        int skipped = 0;
        for (Admin admin : admins) {
            total++;
            if (admin == null || admin.getId() == null) {
                skipped++;
                continue;
            }
            String current = admin.getPassword();
            if (!AdminPasswordUtil.needsUpgrade(current)) {
                skipped++;
                continue;
            }
            if (current == null || current.trim().isEmpty()) {
                skipped++;
                continue;
            }
            admin.setPassword(AdminPasswordUtil.encode(current.trim()));
            try {
                boolean ok = adminService.updateById(admin);
                if (ok) {
                    migrated++;
                } else {
                    skipped++;
                    log.warn("管理员密码迁移失败：adminId={}, userName={}", admin.getId(), admin.getUserName());
                }
            } catch (DataIntegrityViolationException e) {
                if (passwordColumnTooShort(e)) {
                    log.error("管理员密码迁移已中止：t_admin.password 列长度不足（BCrypt 需约 60 字符）。"
                            + " 请在库中执行 docs/db_migration_admin_password_bcrypt.sql 后重启。");
                    return;
                }
                throw e;
            }
        }
        log.info("管理员密码迁移完成: total={}, migrated={}, skipped={}", total, migrated, skipped);
    }

    private static boolean passwordColumnTooShort(DataIntegrityViolationException e) {
        String msg = e.getMessage();
        if (msg == null) {
            return false;
        }
        return msg.contains("Data too long") && msg.toLowerCase().contains("password");
    }
}
