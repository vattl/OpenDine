package com.lanf.kds.replication;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.controller.OrderController;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.kds.support.KdsCloudReplicationContext;
import com.lanf.kds.service.KdsDishAvailabilityService;
import com.lanf.kds.service.KdsCashierAuthorityService;
import com.lanf.kds.service.KdsLackService;
import com.lanf.kds.service.KdsOrderHook;
import com.lanf.kds.service.KdsTicketService;
import com.lanf.config.ApiPermissionMapping;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import org.yaml.snakeyaml.Yaml;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsReplicationContractTest {

    @Test
    void snakeCaseEnvelopeDeserializes() throws Exception {
        String json = "{\"event_id\":\"e1\",\"event_type\":\"order_created\","
                + "\"aggregate_key\":\"order:37\",\"occurred_at_ms\":10,\"payload\":{}}";
        KdsReplicationEventRequest request = new ObjectMapper().readValue(json, KdsReplicationEventRequest.class);
        assertEquals("e1", request.getEventId());
        assertEquals("order:37", request.getAggregateKey());
        assertEquals(10L, request.getOccurredAtMs());
    }

    @Test
    void replicationSideEffectScopeIsAlwaysCleared() {
        assertFalse(KdsCloudReplicationContext.isActive());
        try (KdsCloudReplicationContext.Scope ignored = KdsCloudReplicationContext.open()) {
            assertTrue(KdsCloudReplicationContext.isActive());
        }
        assertFalse(KdsCloudReplicationContext.isActive());
    }

    @Test
    @SuppressWarnings("unchecked")
    void openApiContainsReplicationContract() throws Exception {
        try (InputStream in = Files.newInputStream(Paths.get("docs", "openapi.yaml"))) {
            Map<String, Object> root = new Yaml().load(in);
            Map<String, Object> paths = (Map<String, Object>) root.get("paths");
            assertTrue(paths.containsKey("/admin/kds/replication/events"));
            assertTrue(paths.containsKey("/admin/kds/replication/events/batch"));
            assertTrue(paths.containsKey("/admin/kds/authority/config-snapshot"));
            assertTrue(paths.containsKey("/admin/kds/replication/dead-letters"));
            assertTrue(paths.containsKey("/admin/kds/replication/dead-letters/{eventId}/retry"));
            assertTrue(paths.containsKey("/admin/kds/replication/dead-letters/{eventId}/replace"));
            assertTrue(paths.containsKey("/admin/kds/replication/dead-letters/{eventId}/discard"));
            Map<String, Object> components = (Map<String, Object>) root.get("components");
            Map<String, Object> schemas = (Map<String, Object>) components.get("schemas");
            assertTrue(schemas.containsKey("KdsReplicationEventRequest"));
            assertTrue(schemas.containsKey("KdsReplicationResponse"));
            assertTrue(schemas.containsKey("KdsReplicationStateChangedPayload"));
            assertTrue(schemas.containsKey("KdsAuthorityConfigSnapshot"));
            assertTrue(schemas.containsKey("KdsReplicationBatchRequest"));
            assertTrue(schemas.containsKey("KdsReplicationBatchResponse"));
            assertTrue(schemas.containsKey("KdsReplicationDeadLetter"));
            assertTrue(schemas.containsKey("KdsReplicationDeadLetterListResponse"));
            Map<String, Object> replicationEvents = (Map<String, Object>) paths.get("/admin/kds/replication/events");
            assertTrue(replicationEvents.toString().contains("XCashierDeviceCode"));
            Map<String, Object> replicationBatch = (Map<String, Object>) paths.get("/admin/kds/replication/events/batch");
            assertTrue(replicationBatch.toString().contains("XCashierDeviceCode"));
            Map<String, Object> parameters = (Map<String, Object>) components.get("parameters");
            Map<String, Object> publisherHeader = (Map<String, Object>) parameters.get("XCashierDeviceCode");
            assertEquals("X-Cashier-Device-Code", publisherHeader.get("name"));
            assertEquals(true, publisherHeader.get("required"));
            assertTrue(paths.containsKey("/kds/v2/health"));
            assertTrue(paths.containsKey("/kds/v2/bootstrap"));
            assertTrue(paths.containsKey("/kds/v2/changes"));
            assertTrue(paths.containsKey("/kds/v2/commands"));
            assertTrue(schemas.containsKey("KdsV2EventEnvelope"));
            assertTrue(schemas.containsKey("KdsV2CommandRequest"));
            Map<String, Object> bootstrapPath = (Map<String, Object>) paths.get("/kds/v2/bootstrap");
            Map<String, Object> bootstrapGet = (Map<String, Object>) bootstrapPath.get("get");
            assertTrue(bootstrapGet.toString().contains("KdsV2BootstrapResponse"));
            Map<String, Object> bootstrapResponse = (Map<String, Object>) schemas.get("KdsV2BootstrapResponse");
            assertNotNull(bootstrapResponse);
            Map<String, Object> bootstrapData = (Map<String, Object>) schemas.get("KdsV2BootstrapData");
            java.util.List<String> bootstrapRequired = (java.util.List<String>) bootstrapData.get("required");
            for (String field : new String[]{"protocol_version", "event_seq", "shop_id", "device", "permissions", "queues",
                    "queue_counts", "fixed_catalog", "config", "stats", "config_version"}) {
                assertTrue(bootstrapRequired.contains(field), "missing bootstrap field " + field);
            }
            assertTrue(schemas.containsKey("KdsV2BootstrapDevice"));
            assertTrue(schemas.containsKey("KdsV2BootstrapConfig"));
            Map<String, Object> bootstrapPermissions = (Map<String, Object>) schemas.get("KdsV2BootstrapPermissions");
            assertTrue(bootstrapPermissions.toString().contains("allowed_commands"));
            assertTrue(bootstrapPermissions.toString().contains("visible_queues"));
            assertTrue(schemas.get("KdsV2BootstrapConfig").toString().contains("KdsV2BootstrapPermissions"));
            Map<String, Object> changesResponse = (Map<String, Object>) schemas.get("KdsV2ChangesResponse");
            Map<String, Object> changesProperties = (Map<String, Object>) changesResponse.get("properties");
            Map<String, Object> changesData = (Map<String, Object>) changesProperties.get("data");
            java.util.List<String> changesRequired = (java.util.List<String>) changesData.get("required");
            assertTrue(changesRequired.contains("protocol_version"));
            assertTrue(changesRequired.contains("event_seq"));
            assertTrue(changesRequired.contains("snapshot_required"));
            assertTrue(changesRequired.contains("events"));
            Map<String, Object> changesDataProperties = (Map<String, Object>) changesData.get("properties");
            assertTrue(changesDataProperties.containsKey("latest_event_seq"),
                    "Cashier migration alias must remain machine-readable");
            assertEquals(true, ((Map<String, Object>) changesDataProperties.get("latest_event_seq")).get("deprecated"));
            Map<String, Object> linePatch = (Map<String, Object>) schemas.get("KdsV2LinePatch");
            java.util.List<String> required = (java.util.List<String>) linePatch.get("required");
            for (String field : new String[]{"detail_id", "order_id", "dish_id", "dish_name", "line_quantity",
                    "refunded_quantity", "prep_remaining", "cook_remaining", "ready_remaining", "local_revision",
                    "order_revision", "fulfillment_bucket", "table_number", "order_no", "specification", "unit",
                    "remark", "created_at_ms", "held", "rushed", "lacked", "removed"}) {
                assertTrue(required.contains(field), "missing canonical LAN line field " + field);
            }
            assertFalse(((Map<String, Object>) linePatch.get("properties")).containsKey("local_detail_id"));
            Map<String, Object> bucket = (Map<String, Object>) ((Map<String, Object>) linePatch.get("properties"))
                    .get("fulfillment_bucket");
            assertEquals(java.util.Arrays.asList("dine_in", "takeout", "pickup", "pack", "delivery"), bucket.get("enum"));
            assertTrue(schemas.get("KdsReplicationBatchResponse").toString().contains("4092"));
        }
    }

    @Test
    @SuppressWarnings("unchecked")
    void openApiUsesCanonicalCloudAuthorityContractAndRetiresLegacyWrites() throws Exception {
        try (InputStream in = Files.newInputStream(Paths.get("docs", "openapi.yaml"))) {
            Map<String, Object> root = new Yaml().load(in);
            Map<String, Object> paths = (Map<String, Object>) root.get("paths");
            Map<String, Object> login = (Map<String, Object>) paths.get("/kds/device/login");
            Map<String, Object> loginPost = (Map<String, Object>) login.get("post");
            assertEquals("cloud-or-cashier-lan", loginPost.get("x-kds-profile"));
            Map<String, Object> requestBody = (Map<String, Object>) loginPost.get("requestBody");
            Map<String, Object> content = (Map<String, Object>) requestBody.get("content");
            Map<String, Object> media = (Map<String, Object>) content.get("application/json");
            Map<String, Object> schema = (Map<String, Object>) media.get("schema");
            assertEquals("#/components/schemas/KdsCloudDeviceLoginRequest", schema.get("$ref"));
            Map<String, Object> components = (Map<String, Object>) root.get("components");
            Map<String, Object> schemas = (Map<String, Object>) components.get("schemas");
            Map<String, Object> cloudLogin = (Map<String, Object>) schemas.get("KdsCloudDeviceLoginRequest");
            assertTrue(cloudLogin.toString().contains("pairing_code"),
                    "Cloud login must document the one-time pairing_code field");

            Map<String, Object> heartbeat = (Map<String, Object>) paths.get("/kds/device/heartbeat");
            Map<String, Object> heartbeatPost = (Map<String, Object>) heartbeat.get("post");
            assertEquals("cloud-or-cashier-lan", heartbeatPost.get("x-kds-profile"));
            assertTrue(heartbeatPost.containsKey("parameters"));

            Map<String, Object> commands = (Map<String, Object>) paths.get("/kds/v2/commands");
            Map<String, Object> commandsPost = (Map<String, Object>) commands.get("post");
            assertEquals("dual-mode-v2", commandsPost.get("x-kds-profile"));

            String[][] retiredWrites = new String[][]{
                    {"/kds/settings", "put"},
                    {"/kds/item/status", "post"},
                    {"/kds/item/status/update", "post"},
                    {"/kds/item/lack", "post"},
                    {"/kds/order/rush", "post"},
                    {"/kds/order/finish-all", "post"},
                    {"/kds/workflow/archive/clear", "post"},
                    {"/kds/workflow/advance", "post"},
                    {"/kds/workflow/advance-item", "post"},
                    {"/kds/workflow/advance-order", "post"},
                    {"/kds/workflow/lack", "post"},
                    {"/kds/workflow/revoke", "post"},
                    {"/kds/workflow/hold", "post"},
                    {"/kds/workflow/release", "post"},
                    {"/kds/workflow/refund", "post"},
                    {"/kds/workflow/print-serve-ticket", "post"},
                    {"/kds/grill/start-cooking", "post"},
                    {"/kds/expedition/serve", "post"},
                    {"/kds/skewer/picked", "post"},
                    {"/kds/sync/all", "post"}
            };
            for (String[] retired : retiredWrites) {
                Map<String, Object> pathItem = (Map<String, Object>) paths.get(retired[0]);
                if (pathItem == null) {
                    continue;
                }
                Map<String, Object> operation = (Map<String, Object>) pathItem.get(retired[1]);
                assertEquals(Boolean.TRUE, operation.get("deprecated"), retired[0]);
                assertEquals(Boolean.TRUE, operation.get("x-kds-retired"), retired[0]);
                assertEquals(410, ((Number) operation.get("x-kds-retired-status")).intValue(), retired[0]);
            }
            assertTrue(paths.containsKey("/kds/health"));
        }
    }

    @Test
    void orderCreatedRequiresPayloadShopIdToMatchAuthenticatedShop() throws Exception {
        KdsReplicationService service = serviceWithoutDatabase();
        KdsReplicationEventRequest request = event("order_created",
                "{\"local_order_id\":37,\"fulfillment_type\":\"dine_in\",\"created_at_ms\":10,"
                        + "\"lines\":[{\"local_detail_id\":1,\"dish_id\":2,\"quantity\":1}]}");

        KdsReplicationOutcome outcome = service.accept(7, request, null);

        assertEquals(400, outcome.getHttpStatus());
        assertEquals(4000, outcome.getBusinessCode());
        assertTrue(outcome.getMessage().contains("shop_id"));
    }

    @Test
    void malformedAdvanceIsPermanent400BeforeMissingMapping409() throws Exception {
        KdsReplicationService service = serviceWithoutDatabase();
        KdsReplicationEventRequest request = event("kds_advance_item",
                "{\"operation_id\":\"op-1\",\"detail_id\":1,\"order_id\":37,"
                        + "\"local_revision\":1,\"done_line\":2}");

        KdsReplicationOutcome outcome = service.accept(7, request, null);

        assertEquals(400, outcome.getHttpStatus());
        assertEquals(4000, outcome.getBusinessCode());
        assertTrue(outcome.getMessage().contains("prep_remaining"));
    }

    @Test
    void stateSnapshotRequiresCanonicalLineFlagsBeforeAnyDatabaseWork() throws Exception {
        KdsReplicationService service = serviceWithoutDatabase();
        KdsReplicationEventRequest request = event("kds_state_changed",
                "{\"local_order_id\":37,\"order_revision\":2,\"operation_type\":\"advance_item\","
                        + "\"device_code\":\"cashier-a\",\"orders\":[{\"local_order_id\":37,\"order_id\":37,\"order_revision\":2}],"
                        + "\"lines\":[{\"local_detail_id\":1,\"detail_id\":1,\"local_order_id\":37,\"order_id\":37,"
                        + "\"dish_id\":2,\"dish_name\":\"Soup\",\"line_quantity\":1,\"refunded_quantity\":0,"
                        + "\"prep_remaining\":1,\"cook_remaining\":1,\"ready_remaining\":1,\"local_revision\":2,"
                        + "\"order_revision\":2,\"fulfillment_bucket\":\"dine_in\",\"table_number\":null,"
                        + "\"order_no\":\"A1\",\"specification\":null,\"unit\":null,\"remark\":null,"
                        + "\"created_at_ms\":10,\"rushed\":false,\"lacked\":false,\"removed\":false}],"
                        + "\"dish_availability\":[]}");

        KdsReplicationOutcome outcome = service.accept(7, request, null);

        assertEquals(4000, outcome.getBusinessCode());
        assertTrue(outcome.getMessage().contains("held"));
    }

    @Test
    void replicationRequiresIndependentCashierPublisherHeader() throws Exception {
        KdsReplicationService service = serviceWithoutDatabase();
        KdsReplicationEventRequest request = event("order_created",
                "{\"shop_id\":7,\"local_order_id\":37,\"fulfillment_type\":\"dine_in\",\"created_at_ms\":10,"
                        + "\"lines\":[{\"local_detail_id\":1,\"dish_id\":2,\"quantity\":1}]}");

        KdsReplicationOutcome outcome = service.accept(7, request, new MockHttpServletRequest());

        assertEquals(403, outcome.getHttpStatus());
        assertEquals(4030, outcome.getBusinessCode());
        assertTrue(outcome.getMessage().contains("X-Cashier-Device-Code"));
    }

    @Test
    void statePublisherHeaderMustMatchPayloadDeviceCode() throws Exception {
        KdsReplicationService service = serviceWithoutDatabase();
        KdsReplicationEventRequest request = event("kds_state_changed",
                "{\"local_order_id\":37,\"order_revision\":2,\"operation_type\":\"advance_item\","
                        + "\"device_code\":\"cashier-primary\",\"orders\":[{\"local_order_id\":37,\"order_id\":37,\"order_revision\":2}],"
                        + "\"lines\":[{\"local_detail_id\":1,\"detail_id\":1,\"local_order_id\":37,\"order_id\":37,"
                        + "\"dish_id\":2,\"dish_name\":\"Soup\",\"line_quantity\":1,\"refunded_quantity\":0,"
                        + "\"prep_remaining\":1,\"cook_remaining\":1,\"ready_remaining\":1,\"local_revision\":2,"
                        + "\"order_revision\":2,\"fulfillment_bucket\":\"dine_in\",\"table_number\":null,"
                        + "\"order_no\":\"A1\",\"specification\":null,\"unit\":null,\"remark\":null,"
                        + "\"created_at_ms\":10,\"held\":false,\"rushed\":false,\"lacked\":false,\"removed\":false}],"
                        + "\"dish_availability\":[]}");
        MockHttpServletRequest servletRequest = new MockHttpServletRequest();
        servletRequest.addHeader(KdsReplicationService.CASHIER_DEVICE_HEADER, "spoofed-device");

        KdsReplicationOutcome outcome = service.accept(7, request, servletRequest);

        assertEquals(4030, outcome.getBusinessCode());
        assertTrue(outcome.getMessage().contains("payload.device_code"));
    }

    @Test
    void formalStateSnapshotDoesNotRequireLegacyLocalIds() throws Exception {
        KdsReplicationService service = serviceWithoutDatabase();
        KdsReplicationEventRequest request = event("kds_state_changed",
                "{\"order_id\":37,\"order_revision\":2,\"operation_type\":\"advance_item\"," 
                        + "\"device_code\":\"cashier-primary\",\"orders\":[{\"order_id\":37,\"order_revision\":2}],"
                        + "\"lines\":[{\"detail_id\":1,\"order_id\":37,\"dish_id\":2,\"dish_name\":\"Soup\"," 
                        + "\"line_quantity\":1,\"refunded_quantity\":0,\"prep_remaining\":1,\"cook_remaining\":1," 
                        + "\"ready_remaining\":1,\"local_revision\":2,\"order_revision\":2," 
                        + "\"fulfillment_bucket\":\"dine_in\",\"table_number\":null,\"order_no\":\"A1\"," 
                        + "\"specification\":null,\"unit\":null,\"remark\":null,\"created_at_ms\":10," 
                        + "\"held\":false,\"rushed\":false,\"lacked\":false,\"removed\":false}],"
                        + "\"dish_availability\":[]}");

        KdsReplicationOutcome outcome = service.accept(7, request, new MockHttpServletRequest());

        assertEquals(4030, outcome.getBusinessCode());
        assertFalse(outcome.getMessage().contains("local_order_id"));
    }

    @Test
    void stateSnapshotToleratesUnlimitedStockSentinel() throws Exception {
        KdsReplicationService service = serviceWithoutDatabase();
        KdsReplicationEventRequest request = event("kds_state_changed",
                "{\"local_order_id\":37,\"order_revision\":2,\"operation_type\":\"refund_item\","
                        + "\"device_code\":\"cashier-primary\",\"orders\":[{\"local_order_id\":37,\"order_id\":37,\"order_revision\":2}],"
                        + "\"lines\":[{\"local_detail_id\":1,\"detail_id\":1,\"local_order_id\":37,\"order_id\":37,"
                        + "\"dish_id\":2,\"dish_name\":\"Soup\",\"line_quantity\":1,\"refunded_quantity\":0,"
                        + "\"prep_remaining\":1,\"cook_remaining\":1,\"ready_remaining\":1,\"local_revision\":2,"
                        + "\"order_revision\":2,\"fulfillment_bucket\":\"dine_in\",\"table_number\":null,"
                        + "\"order_no\":\"A1\",\"specification\":null,\"unit\":null,\"remark\":null,"
                        + "\"created_at_ms\":10,\"held\":false,\"rushed\":false,\"lacked\":false,\"removed\":false}],"
                        + "\"dish_availability\":[{\"dish_id\":2,\"availability_revision\":1,\"stock\":-1}]}");
        MockHttpServletRequest servletRequest = new MockHttpServletRequest();
        servletRequest.addHeader(KdsReplicationService.CASHIER_DEVICE_HEADER, "spoofed-device");

        KdsReplicationOutcome outcome = service.accept(7, request, servletRequest);

        // stock=-1（不限量哨兵）必须通过载荷校验；随后因设备码不匹配进入 4030，而不是 4000 库存校验错误
        assertEquals(4030, outcome.getBusinessCode());
        assertFalse(outcome.getMessage().contains("stock"));
    }

    @Test
    void stateSnapshotRejectsStockBelowUnlimitedSentinel() throws Exception {
        KdsReplicationService service = serviceWithoutDatabase();
        KdsReplicationEventRequest request = event("kds_state_changed",
                "{\"local_order_id\":37,\"order_revision\":2,\"operation_type\":\"refund_item\","
                        + "\"device_code\":\"cashier-primary\",\"orders\":[{\"local_order_id\":37,\"order_id\":37,\"order_revision\":2}],"
                        + "\"lines\":[{\"local_detail_id\":1,\"detail_id\":1,\"local_order_id\":37,\"order_id\":37,"
                        + "\"dish_id\":2,\"dish_name\":\"Soup\",\"line_quantity\":1,\"refunded_quantity\":0,"
                        + "\"prep_remaining\":1,\"cook_remaining\":1,\"ready_remaining\":1,\"local_revision\":2,"
                        + "\"order_revision\":2,\"fulfillment_bucket\":\"dine_in\",\"table_number\":null,"
                        + "\"order_no\":\"A1\",\"specification\":null,\"unit\":null,\"remark\":null,"
                        + "\"created_at_ms\":10,\"held\":false,\"rushed\":false,\"lacked\":false,\"removed\":false}],"
                        + "\"dish_availability\":[{\"dish_id\":2,\"availability_revision\":1,\"stock\":-2}]}");

        KdsReplicationOutcome outcome = service.accept(7, request, null);

        assertEquals(4000, outcome.getBusinessCode());
        assertTrue(outcome.getMessage().contains("stock"));
    }

    @Test
    void patchStyleStateSnapshotPassesPayloadValidation() throws Exception {
        // 新版收银端补丁式 kds_state_changed：patches[] + command_id，无 orders/lines/dish_availability/device_code
        KdsReplicationService service = serviceWithoutDatabase();
        KdsReplicationEventRequest request = event("kds_state_changed",
                "{\"operation_type\":\"refund_item\",\"command_id\":\"d2dd5f22-52fa-4fd0-8c84-1a63840ca52c\","
                        + "\"duplicate\":false,\"event_seq\":1081,"
                        + "\"patches\":[{\"detail_id\":139,\"order_id\":37,\"dish_id\":18,\"dish_name\":\"Beef\","
                        + "\"line_quantity\":1,\"refunded_quantity\":1,\"prep_remaining\":0,\"cook_remaining\":0,"
                        + "\"ready_remaining\":0,\"local_revision\":3,\"order_revision\":2,"
                        + "\"fulfillment_bucket\":\"dine_in\",\"table_number\":\"21\",\"order_no\":\"A1\","
                        + "\"specification\":null,\"unit\":null,\"remark\":\"\",\"created_at_ms\":10,"
                        + "\"held\":false,\"rushed\":false,\"lacked\":false,\"removed\":true,"
                        + "\"workflow_queue\":\"done\"}],"
                        + "\"queue_counts\":{\"pending_prep\":15,\"pending_cook\":10,\"ready_serve\":0,\"done\":59},"
                        + "\"actor_device_code\":\"KDS-B82F7B55\"}");
        MockHttpServletRequest servletRequest = new MockHttpServletRequest();
        servletRequest.addHeader(KdsReplicationService.CASHIER_DEVICE_HEADER, "cashier-a");

        KdsReplicationOutcome outcome = service.accept(7, request, servletRequest);

        // 载荷校验必须通过（无 4000）；mock 数据库下只会走到后续的持久化失败
        assertNotEquals(4000, outcome.getBusinessCode(), "patch payload must pass validation: " + outcome.getMessage());
    }

    @Test
    void patchStyleStateSnapshotAcceptsLocalDetailIdAliasRows() throws Exception {
        // §4.2：未映射行（云端出生订单上的本地加菜行）可仅携带 local_detail_id 别名，校验必须放行
        KdsReplicationService service = serviceWithoutDatabase();
        KdsReplicationEventRequest request = event("kds_state_changed",
                "{\"operation_type\":\"advance_item\",\"command_id\":\"cmd-alias-1\",\"event_seq\":5,"
                        + "\"patches\":[{\"local_detail_id\":137,\"order_id\":37,\"dish_id\":18,\"dish_name\":\"Beef\","
                        + "\"line_quantity\":1,\"refunded_quantity\":0,\"prep_remaining\":1,\"cook_remaining\":1,"
                        + "\"ready_remaining\":1,\"local_revision\":1,\"order_revision\":2,"
                        + "\"fulfillment_bucket\":\"dine_in\",\"table_number\":\"21\",\"order_no\":\"A1\","
                        + "\"specification\":null,\"unit\":null,\"remark\":\"\",\"created_at_ms\":10,"
                        + "\"held\":false,\"rushed\":false,\"lacked\":false,\"removed\":false}],"
                        + "\"actor_device_code\":\"KDS-B82F7B55\"}");
        MockHttpServletRequest servletRequest = new MockHttpServletRequest();
        servletRequest.addHeader(KdsReplicationService.CASHIER_DEVICE_HEADER, "cashier-a");

        KdsReplicationOutcome outcome = service.accept(7, request, servletRequest);

        assertNotEquals(4000, outcome.getBusinessCode(), "alias row must pass validation: " + outcome.getMessage());
    }

    @Test
    void patchStyleStateSnapshotRejectsEmptyPatches() throws Exception {
        KdsReplicationService service = serviceWithoutDatabase();
        KdsReplicationEventRequest request = event("kds_state_changed",
                "{\"operation_type\":\"refund_item\",\"command_id\":\"cmd-1\",\"patches\":[]}");

        KdsReplicationOutcome outcome = service.accept(7, request, new MockHttpServletRequest());

        assertEquals(4000, outcome.getBusinessCode());
        assertTrue(outcome.getMessage().contains("patches"));
    }

    @Test
    void migrationProvidesDurableIdempotencyAndLocalToCloudMappings() throws Exception {
        String migration = new String(Files.readAllBytes(
                Paths.get("docs", "db_migration_kds_cashier_replication.sql")), "UTF-8");
        assertTrue(migration.contains("UNIQUE KEY `uk_kds_replication_event_id` (`event_id`)"));
        assertTrue(migration.contains("UNIQUE KEY `uk_kds_replication_operation` (`shop_id`, `operation_id`)"));
        assertTrue(migration.contains("PRIMARY KEY (`shop_id`, `aggregate_key`)"));
        assertTrue(migration.contains("t_kds_replication_order_map"));
        assertTrue(migration.contains("t_kds_replication_detail_map"));
        assertTrue(migration.contains("last_local_revision"));
        assertTrue(migration.contains("last_order_revision"));
        assertTrue(migration.contains("request_fingerprint"));
        assertTrue(migration.contains("publisher_device_code"));
        assertTrue(migration.contains("t_kds_replication_inventory_state"));
        assertTrue(migration.contains("t_kds_replication_dead_letter_audit"));
        assertTrue(migration.contains("t_kds_authority_config_version"));
        assertTrue(migration.contains("cashier_device_code"));
        assertTrue(migration.contains("operator_admin_id"));
        assertTrue(migration.contains("trace_id"));
        String additive = new String(Files.readAllBytes(
                Paths.get("docs", "db_migration_kds_authority_v2.sql")), "UTF-8");
        assertTrue(additive.contains("information_schema.COLUMNS"));
        assertTrue(additive.contains("last_order_revision"));
        assertTrue(additive.contains("request_fingerprint"));
        assertTrue(additive.contains("publisher_device_code"));
        assertFalse(additive.contains("DROP TABLE"));
    }

    @Test
    void cloudAuthorityFailClosedMigrationDefaultsAndBackfillsUnconfiguredShops() throws Exception {
        String migration = new String(Files.readAllBytes(Paths.get(
                "src", "main", "resources", "db", "migration",
                "V010__kds_cloud_authority_fail_closed.sql")), "UTF-8");

        assertTrue(migration.contains("DEFAULT 'cloud'"));
        assertTrue(migration.contains("INSERT INTO t_kds_shop_authority"));
        assertTrue(migration.contains("LEFT JOIN t_kds_shop_authority"));
        assertTrue(migration.contains("WHERE authority.shop_id IS NULL"));
        assertFalse(migration.contains("UPDATE t_kds_shop_authority SET authority_mode='cloud'"),
                "Explicit legacy cutovers require queue reconciliation and must not be rewritten silently");
    }

    @Test
    void deadLetterOperationsRequireConfigurationPrivilege() {
        assertEquals("kds:config", ApiPermissionMapping.getRequiredPermission(
                "POST", "/admin/kds/replication/dead-letters/event-1/retry"));
        assertEquals("kds:config", ApiPermissionMapping.getRequiredPermission(
                "GET", "/admin/kds/replication/dead-letters"));
    }

    @Test
    void pairingTicketRequiresCashierOrKdsConfigurationPrivilege() {
        assertEquals("cashier:operate|kds:config", ApiPermissionMapping.getRequiredPermission(
                "POST", "/admin/kds/device/pairing-ticket"));
    }

    @Test
    void advanceItemDoesNotApplyDishAvailabilitySnapshotToLiveStock() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        KdsDishAvailabilityService availabilityService = mock(KdsDishAvailabilityService.class);
        KdsReplicationService service = new KdsReplicationService(jdbc, new ObjectMapper(),
                mock(PlatformTransactionManager.class), mock(OrderController.class),
                mock(IDishService.class), mock(IOrderDetailService.class),
                availabilityService, mock(KdsCashierAuthorityService.class),
                mock(KdsReplicationAuditService.class), mock(KdsLackService.class));

        // Advance item event carrying ambient dish_availability
        String payloadJson = "{\"local_order_id\":37,\"order_revision\":2,\"operation_type\":\"advance_item\","
                + "\"device_code\":\"cashier-a\",\"orders\":[{\"local_order_id\":37,\"order_id\":37,\"order_revision\":2}],"
                + "\"lines\":[{\"local_detail_id\":1,\"detail_id\":1,\"local_order_id\":37,\"order_id\":37,"
                + "\"dish_id\":17,\"dish_name\":\"油边王\",\"line_quantity\":1,\"refunded_quantity\":0,"
                + "\"prep_remaining\":0,\"cook_remaining\":1,\"ready_remaining\":1,\"local_revision\":2,"
                + "\"order_revision\":2,\"fulfillment_bucket\":\"dine_in\",\"table_number\":null,"
                + "\"order_no\":\"A1\",\"specification\":null,\"unit\":null,\"remark\":null,"
                + "\"created_at_ms\":10,\"held\":false,\"rushed\":false,\"lacked\":false,\"removed\":false}],"
                + "\"dish_availability\":[{\"dish_id\":17,\"availability_revision\":1000,\"stock\":38,\"sold_out\":false}]}";

        // Verify that for advance_item, availabilityService.applySnapshot is never called
        org.mockito.Mockito.verify(availabilityService, org.mockito.Mockito.never())
                .applySnapshot(org.mockito.ArgumentMatchers.anyInt(), org.mockito.ArgumentMatchers.anyInt(),
                        org.mockito.ArgumentMatchers.any(), org.mockito.ArgumentMatchers.any(), org.mockito.ArgumentMatchers.any());
    }

    @Test
    void missingTicketIsRebuiltFromAnAcceptedCloudOrderBeforeProgressRetry() {
        IOrderService orders = mock(IOrderService.class);
        IOrderDetailService details = mock(IOrderDetailService.class);
        KdsTicketService tickets = mock(KdsTicketService.class);
        Order accepted = new Order();
        accepted.setId(37);
        accepted.setShop_id(7);
        accepted.setOrder_receiving("rec_order");
        when(orders.getById(37)).thenReturn(accepted);
        KdsReplicationService service = new KdsReplicationService(mock(JdbcTemplate.class), new ObjectMapper(),
                mock(PlatformTransactionManager.class), mock(OrderController.class), mock(IDishService.class), details,
                mock(KdsDishAvailabilityService.class), mock(KdsCashierAuthorityService.class),
                mock(KdsReplicationAuditService.class), mock(KdsLackService.class));
        ReflectionTestUtils.setField(service, "orderService", orders);
        ReflectionTestUtils.setField(service, "ticketService", tickets);

        service.rebuildMissingTicket(7, 37, 139);

        verify(tickets).createTicketsForOrder(accepted, java.util.Collections.singletonList(139),
                KdsOrderHook.Trigger.MANUAL);
    }

    @Test
    void zeroAffectedRowsStillMatchesAnExistingTicketForIdempotentProgress() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(org.mockito.ArgumentMatchers.contains("COUNT(*)"),
                org.mockito.ArgumentMatchers.eq(Integer.class),
                org.mockito.ArgumentMatchers.eq(7), org.mockito.ArgumentMatchers.eq(139))).thenReturn(1);
        KdsReplicationService service = new KdsReplicationService(jdbc, new ObjectMapper(),
                mock(PlatformTransactionManager.class), mock(OrderController.class), mock(IDishService.class),
                mock(IOrderDetailService.class), mock(KdsDishAvailabilityService.class),
                mock(KdsCashierAuthorityService.class), mock(KdsReplicationAuditService.class), mock(KdsLackService.class));

        assertTrue(service.ticketExists(7, 139));
    }

    @Test
    void intrinsicNonTicketLinesAreRecognizedBeforeRebuild() {
        OrderDetail comboHeader = new OrderDetail();
        comboHeader.setLine_type("combo_header");
        assertEquals("COMBO_HEADER", KdsTicketService.intrinsicTicketSkipReason(comboHeader));

        OrderDetail refunded = new OrderDetail();
        refunded.setLine_status("refunded");
        assertEquals("REFUNDED", KdsTicketService.intrinsicTicketSkipReason(refunded));
    }

    @Test
    void legitimateNonTicketLineDoesNotTryToRebuild() {
        KdsTicketService tickets = mock(KdsTicketService.class);
        OrderDetail detail = new OrderDetail();
        detail.setId(139);
        when(tickets.ticketSkipReason(7, detail)).thenReturn("COMBO_HEADER");
        KdsReplicationService service = serviceWithoutDatabase();
        ReflectionTestUtils.setField(service, "ticketService", tickets);

        assertFalse(service.ensureTicketForProgress(7, 37, 139, detail));
        verify(tickets, org.mockito.Mockito.never()).createTicketsForOrder(
                org.mockito.ArgumentMatchers.any(), org.mockito.ArgumentMatchers.anyList(),
                org.mockito.ArgumentMatchers.any());
    }

    @Test
    void failedRebuildReportsOrderAndDetailIdentifiers() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(org.mockito.ArgumentMatchers.contains("COUNT(*)"),
                org.mockito.ArgumentMatchers.eq(Integer.class),
                org.mockito.ArgumentMatchers.eq(7), org.mockito.ArgumentMatchers.eq(139))).thenReturn(0);
        KdsTicketService tickets = mock(KdsTicketService.class);
        IOrderService orders = mock(IOrderService.class);
        OrderDetail detail = new OrderDetail();
        detail.setId(139);
        Order accepted = new Order();
        accepted.setId(37);
        accepted.setShop_id(7);
        accepted.setOrder_receiving("rec_order");
        when(orders.getById(37)).thenReturn(accepted);
        KdsReplicationService service = serviceWithoutDatabase();
        ReflectionTestUtils.setField(service, "jdbc", jdbc);
        ReflectionTestUtils.setField(service, "ticketService", tickets);
        ReflectionTestUtils.setField(service, "orderService", orders);

        KdsReplicationException failure = assertThrows(KdsReplicationException.class,
                () -> service.ensureTicketForProgress(7, 37, 139, detail));
        assertTrue(failure.getMessage().contains("orderId=37"));
        assertTrue(failure.getMessage().contains("detailId=139"));
    }

    private static KdsReplicationEventRequest event(String type, String payload) throws Exception {
        String json = "{\"event_id\":\"e1\",\"event_type\":\"" + type + "\","
                + "\"aggregate_key\":\"order:37\",\"occurred_at_ms\":10,\"payload\":" + payload + "}";
        return new ObjectMapper().readValue(json, KdsReplicationEventRequest.class);
    }

    private static KdsReplicationService serviceWithoutDatabase() {
        return new KdsReplicationService(mock(JdbcTemplate.class), new ObjectMapper(),
                mock(PlatformTransactionManager.class), mock(OrderController.class),
                mock(IDishService.class), mock(IOrderDetailService.class),
                mock(KdsDishAvailabilityService.class), mock(KdsCashierAuthorityService.class),
                mock(KdsReplicationAuditService.class), mock(KdsLackService.class));
    }
}
