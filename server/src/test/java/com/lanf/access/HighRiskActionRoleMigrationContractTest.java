package com.lanf.access;

import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class HighRiskActionRoleMigrationContractTest {

    @Test
    void migrationDefinesEveryExactExecuteAndApprovalPermission() throws Exception {
        String sql = migration();
        for (String permission : permissions()) {
            assertTrue(sql.contains("'" + permission + "'"), permission);
        }
    }

    @Test
    void builtInCashierLosesExactActionsButKeepsInitiationOutsideThisMigration() throws Exception {
        String sql = migration();
        int deleteStart = sql.indexOf("DELETE role_permission");
        int grantStart = sql.indexOf("INSERT IGNORE INTO `t_role_permission`", deleteStart);
        assertTrue(deleteStart >= 0 && grantStart > deleteStart);
        String revokeBlock = sql.substring(deleteStart, grantStart);
        assertTrue(revokeBlock.contains("role_row.role_code = 'cashier'"));
        for (String permission : permissions()) {
            assertTrue(revokeBlock.contains("'" + permission + "'"), permission);
        }
        String managementGrant = sql.substring(grantStart);
        assertFalse(managementGrant.contains("'cashier'"));
        assertTrue(managementGrant.contains("'store_manager'"));
        assertTrue(managementGrant.contains("'boss'"));
    }

    private static String migration() throws Exception {
        Path path = Paths.get("src/main/resources/db/migration/V042__high_risk_action_role_migration.sql");
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }

    private static List<String> permissions() {
        return Arrays.asList(
                "order:operate:refund",
                "order:operate:changePrice",
                "order:operate:discount",
                "order:operate:reopen",
                "order:operate:refund:approve",
                "order:operate:changePrice:approve",
                "order:operate:discount:approve",
                "order:operate:reopen:approve");
    }
}
