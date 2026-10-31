package com.lanf.config;

import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ApiPermissionMappingAuthorityContractTest {

    private static final Pattern SQL_MAPPING = Pattern.compile(
            "\\('\\*',\\s*'([^']+)',\\s*'([^']+)'\\)");

    @Test
    void databaseAuthorityMigrationContainsEveryReviewedInventoryMappingExactly() throws Exception {
        String sql = migration();
        Matcher matcher = SQL_MAPPING.matcher(sql);
        Map<String, String> migrationMappings = new LinkedHashMap<>();
        while (matcher.find()) {
            migrationMappings.put(matcher.group(1), matcher.group(2));
        }

        assertEquals(ApiPermissionMapping.inventory(), migrationMappings,
                "V041 database authority migration must exactly match the reviewed route inventory");
    }

    @Test
    void sensitivePermissionSeedUsesTheBaselineRemarkColumn() throws Exception {
        String sql = migration();

        assertTrue(sql.contains("(permission_code, permission_name, module, remark, sort_order)"),
                "t_permission seed columns must match the baseline schema");
        assertFalse(sql.contains("(permission_code, permission_name, module, description, sort_order)"),
                "t_permission has no description column");
    }

    private static String migration() throws Exception {
        return new String(Files.readAllBytes(Paths.get(
                "src/main/resources/db/migration/V041__authorization_mapping_authority.sql")),
                StandardCharsets.UTF_8);
    }
}
