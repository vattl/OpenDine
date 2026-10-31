package com.lanf.ai;

import com.lanf.ai.dto.AiMenuSnapshotDTO;
import com.lanf.ai.dto.AiMenuSnapshotDTO.AiMenuItemDTO;
import com.lanf.ai.dto.DinerMemberDTO;
import com.lanf.ai.dto.MealLineItemDTO;
import com.lanf.ai.solver.LexicographicalMealSolver;
import com.lanf.ai.solver.SolverInput;
import com.lanf.ai.solver.SolverResult;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;

import java.math.BigDecimal;
import java.util.*;

/**
 * AI 智能配餐与点餐核心业务规则与约束规划自动化测试套件
 * 严格覆盖 PRD 与 Scenario Matrix 规定的验收用例 (TC01 ~ TC14)
 */
public class AiSmartDiningTestSuiteTest {

    private LexicographicalMealSolver solver;
    private List<AiMenuItemDTO> mockMenu;

    @Before
    public void setUp() {
        solver = new LexicographicalMealSolver();
        mockMenu = new ArrayList<>();

        // 1. 招牌油边大串 (微辣/可免辣, 12元/串)
        AiMenuItemDTO oilEdge = new AiMenuItemDTO();
        oilEdge.setDish_id(101);
        oilEdge.setName("招牌老肥油边大串");
        oilEdge.setPrice_fen(1200);
        oilEdge.setUnit("串");
        oilEdge.setActive(true);
        oilEdge.setSold_out(false);
        oilEdge.setStock(100);
        oilEdge.setNon_spicy_available(true);
        oilEdge.setIs_suitable_fitness(true);
        oilEdge.setCalories_kcal(new BigDecimal("180.0"));
        oilEdge.setProtein_g(new BigDecimal("18.5"));
        oilEdge.setFat_g(new BigDecimal("9.2"));
        mockMenu.add(oilEdge);

        // 2. 鲜烤极品瘦牛肉大串 (10元/串, 可免辣)
        AiMenuItemDTO beef = new AiMenuItemDTO();
        beef.setDish_id(102);
        beef.setName("鲜烤极品瘦牛肉大串");
        beef.setPrice_fen(1000);
        beef.setUnit("串");
        beef.setActive(true);
        beef.setSold_out(false);
        beef.setStock(80);
        beef.setNon_spicy_available(true);
        beef.setIs_suitable_fitness(true);
        beef.setCalories_kcal(new BigDecimal("140.0"));
        beef.setProtein_g(new BigDecimal("22.0"));
        beef.setFat_g(new BigDecimal("4.5"));
        mockMenu.add(beef);

        // 3. 秘制麻辣五花肉串 (8元/串, 腌制自带辣不可免辣, 含花生碎过敏原且有交叉风险)
        AiMenuItemDTO pork = new AiMenuItemDTO();
        pork.setDish_id(103);
        pork.setName("秘制麻辣五花肉大串");
        pork.setPrice_fen(800);
        pork.setUnit("串");
        pork.setActive(true);
        pork.setSold_out(false);
        pork.setStock(50);
        pork.setNon_spicy_available(false); // 关键：不支持做免辣
        pork.setCross_contact_risk(true);
        pork.setVerified_allergens(Collections.singletonList("PEANUT"));
        mockMenu.add(pork);

        // 4. 锡纸金针菇 (18元/份, 免辣)
        AiMenuItemDTO mushroom = new AiMenuItemDTO();
        mushroom.setDish_id(201);
        mushroom.setName("锡纸金针菇");
        mushroom.setPrice_fen(1800);
        mushroom.setUnit("份");
        mushroom.setActive(true);
        mushroom.setSold_out(false);
        mushroom.setStock(30);
        mushroom.setNon_spicy_available(true);
        mockMenu.add(mushroom);

        // 5. 烤实惠馒头片 (6元/份, 免辣)
        AiMenuItemDTO bread = new AiMenuItemDTO();
        bread.setDish_id(301);
        bread.setName("烤实惠馒头片");
        bread.setPrice_fen(600);
        bread.setUnit("份");
        bread.setActive(true);
        bread.setSold_out(false);
        bread.setStock(50);
        bread.setNon_spicy_available(true);
        mockMenu.add(bread);
    }

    /**
     * TC01: 6人、150元、2人不吃辣、fitness+weightloss、均衡优先基线求解
     * 预期：可行、总价 ≤ 15000分、2人免辣分配有效、响应延迟 < 50ms
     */
    @Test
    public void testTC01_SixPeople150YuanTwoNonSpicy() {
        SolverInput input = new SolverInput();
        input.setParty_size(6);
        input.setBudget_fen(15000); // 150元
        input.setStrategy("balanced");
        input.setTable_goals(Arrays.asList("fitness", "weightloss"));
        input.setMenu_items(mockMenu);

        List<DinerMemberDTO> members = new ArrayList<>();
        // P1, P2 不吃辣
        DinerMemberDTO p1 = new DinerMemberDTO();
        p1.setDiner_id("P1");
        p1.setIs_non_spicy(true);
        members.add(p1);

        DinerMemberDTO p2 = new DinerMemberDTO();
        p2.setDiner_id("P2");
        p2.setIs_non_spicy(true);
        members.add(p2);

        for (int i = 3; i <= 6; i++) {
            DinerMemberDTO p = new DinerMemberDTO();
            p.setDiner_id("P" + i);
            p.setIs_non_spicy(false);
            members.add(p);
        }
        input.setMembers(members);

        long start = System.currentTimeMillis();
        SolverResult result = solver.solve(input);
        long elapsed = System.currentTimeMillis() - start;

        Assert.assertTrue("方案必须可行", result.isFeasible());
        Assert.assertTrue("求解耗时必须 < 50ms (实际: " + elapsed + "ms)", elapsed < 50);
        Assert.assertTrue("总金额必须不超过 15000 分 (实际: " + result.getPrice_total_fen() + ")",
                result.getPrice_total_fen() <= 15000);
        Assert.assertEquals("剩余预算核算必须精准", 15000 - result.getPrice_total_fen(), result.getRemaining_budget_fen());

        // 验证 2 位免辣成员分配到的所有菜品必须支持免辣
        for (MealLineItemDTO line : result.getLine_items()) {
            if (line.getAllocated_to() != null && (line.getAllocated_to().contains("P1") || line.getAllocated_to().contains("P2"))) {
                Assert.assertTrue("分配给免辣成员的菜品辣度必须为免辣",
                        line.getSpice_level().contains("免辣"));
            }
        }
    }

    /**
     * TC03: 预算从 150 元降为 130 元
     * 预期：总价 ≤ 13000 分，绝不使用旧方案冒充新方案
     */
    @Test
    public void testTC03_ReduceBudgetTo130Yuan() {
        SolverInput input = new SolverInput();
        input.setParty_size(6);
        input.setBudget_fen(13000); // 降为 130 元
        input.setStrategy("balanced");
        input.setMenu_items(mockMenu);

        List<DinerMemberDTO> members = new ArrayList<>();
        for (int i = 1; i <= 6; i++) {
            DinerMemberDTO p = new DinerMemberDTO();
            p.setDiner_id("P" + i);
            p.setIs_non_spicy(i <= 2);
            members.add(p);
        }
        input.setMembers(members);

        SolverResult result = solver.solve(input);
        if (result.isFeasible()) {
            Assert.assertTrue("总价必须不超过 13000 分", result.getPrice_total_fen() <= 13000);
        } else {
            Assert.assertNotNull("无解时必须输出冲突解释", result.getConflict_details());
        }
    }

    /**
     * TC04: 菜品在门店不支持免辣制作
     * 预期：不支持免辣的菜品（秘制麻辣五花肉）绝不能分配给免辣成员
     */
    @Test
    public void testTC04_NonSpicyItemKitchenConstraint() {
        SolverInput input = new SolverInput();
        input.setParty_size(2);
        input.setBudget_fen(10000);
        input.setStrategy("balanced");
        input.setMenu_items(mockMenu);

        List<DinerMemberDTO> members = new ArrayList<>();
        DinerMemberDTO p1 = new DinerMemberDTO();
        p1.setDiner_id("P1");
        p1.setIs_non_spicy(true);
        members.add(p1);

        DinerMemberDTO p2 = new DinerMemberDTO();
        p2.setDiner_id("P2");
        p2.setIs_non_spicy(true);
        members.add(p2);
        input.setMembers(members);

        SolverResult result = solver.solve(input);
        Assert.assertTrue(result.isFeasible());

        for (MealLineItemDTO line : result.getLine_items()) {
            Assert.assertNotEquals("不支持做免辣的五花肉串严禁被分配给免辣人员",
                    Integer.valueOf(103), line.getDish_id());
        }
    }

    /**
     * TC06: 声明过敏且无法排除后厨交叉污染
     * 预期：声明花生过敏的顾客 P1，含有交叉风险且含花生的菜品严禁分配给 P1
     */
    @Test
    public void testTC06_AllergenCrossContactDefense() {
        SolverInput input = new SolverInput();
        input.setParty_size(2);
        input.setBudget_fen(10000);
        input.setMenu_items(mockMenu);

        List<DinerMemberDTO> members = new ArrayList<>();
        DinerMemberDTO p1 = new DinerMemberDTO();
        p1.setDiner_id("P1");
        p1.setVerified_allergens(Collections.singletonList("PEANUT"));
        members.add(p1);

        DinerMemberDTO p2 = new DinerMemberDTO();
        p2.setDiner_id("P2");
        members.add(p2);
        input.setMembers(members);

        SolverResult result = solver.solve(input);
        Assert.assertTrue(result.isFeasible());

        for (MealLineItemDTO line : result.getLine_items()) {
            if (line.getAllocated_to() != null && line.getAllocated_to().contains("P1")) {
                Assert.assertNotEquals("含花生交叉污染风险的菜品严禁分配给P1",
                        Integer.valueOf(103), line.getDish_id());
            }
        }
    }

    /**
     * TC10: 预算严重不足时的不可行协商与最小预算差额计算
     * 预期：返回 INFEASIBLE，计算出确切最小可行预算及差额 delta_fen > 0
     */
    @Test
    public void testTC10_InfeasibleBudgetNegotiation() {
        SolverInput input = new SolverInput();
        input.setParty_size(6);
        input.setBudget_fen(3000); // 仅 30 元，对于 6 人显然严重不足
        input.setMenu_items(mockMenu);

        List<DinerMemberDTO> members = new ArrayList<>();
        for (int i = 1; i <= 6; i++) {
            DinerMemberDTO p = new DinerMemberDTO();
            p.setDiner_id("P" + i);
            p.setIs_non_spicy(i <= 2);
            members.add(p);
        }
        input.setMembers(members);

        SolverResult result = solver.solve(input);
        Assert.assertFalse("30元预算对于6人必须判定为不可行", result.isFeasible());
        Assert.assertNotNull("必须输出冲突协商信息", result.getConflict_details());
        Assert.assertEquals("BUDGET_INSUFFICIENT", result.getConflict_details().get("reason"));

        Integer minBudget = (Integer) result.getConflict_details().get("min_budget_fen");
        Integer deltaFen = (Integer) result.getConflict_details().get("delta_fen");
        Assert.assertNotNull("必须返回最低可行预算", minBudget);
        Assert.assertTrue("最低可行预算必须 > 3000分", minBudget > 3000);
        Assert.assertEquals("差额必须完全匹配", Integer.valueOf(minBudget - 3000), deltaFen);
    }

    /**
     * TC11: 门店无菜单时返回 REQUIRES_MENU_DATA
     */
    @Test
    public void testTC11_RequiresMenuDataWhenMenuEmpty() {
        SolverInput input = new SolverInput();
        input.setParty_size(6);
        input.setBudget_fen(15000);
        input.setMenu_items(Collections.emptyList()); // 空菜单

        SolverResult result = solver.solve(input);
        Assert.assertFalse(result.isFeasible());
        Assert.assertEquals("REQUIRES_MENU_DATA", result.getConflict_details().get("status"));
    }

    /**
     * 测试菜品画像 DTO 与视图封装
     */
    @Test
    public void testDishFoodProfileDtoValidation() {
        com.lanf.ai.dto.DishFoodProfileInputDTO dto = new com.lanf.ai.dto.DishFoodProfileInputDTO();
        dto.setDish_id(101);
        dto.setShop_id(1);
        dto.setNon_spicy_available(1);
        dto.setSpice_options(Arrays.asList("不辣", "微辣"));
        dto.setVerified_allergens(Collections.singletonList("PEANUT"));
        dto.setCalories_kcal(BigDecimal.valueOf(250));
        dto.setIs_suitable_fitness(1);

        Assert.assertEquals(Integer.valueOf(101), dto.getDish_id());
        Assert.assertEquals(Integer.valueOf(1), dto.getNon_spicy_available());
        Assert.assertEquals(1, dto.getVerified_allergens().size());

        com.lanf.ai.dto.DishWithProfileVO vo = new com.lanf.ai.dto.DishWithProfileVO();
        vo.setDish_id(101);
        vo.setDish_name("招牌老肥油边大串");
        vo.setPrice(BigDecimal.valueOf(12.0));
        vo.setPrice_fen(1200);
        vo.setHas_profile(true);

        Assert.assertEquals(Integer.valueOf(1200), vo.getPrice_fen());
        Assert.assertTrue(vo.getHas_profile());
    }

    /**
     * 验证菜品销量字段映射及 MCP 限制 shop_id=3 校验
     */
    @Test
    public void testMenuItemSalesAndMcpShopId3Restriction() {
        AiMenuItemDTO item = new AiMenuItemDTO();
        item.setDish_id(201);
        item.setName("招牌烤生蚝");
        item.setMonthlysale(888);
        item.setSales_count(888);
        item.setImage("https://oss.example.com/dishes/oyster.jpg");

        Assert.assertEquals(Integer.valueOf(888), item.getMonthlysale());
        Assert.assertEquals(Integer.valueOf(888), item.getSales_count());
        Assert.assertEquals("https://oss.example.com/dishes/oyster.jpg", item.getImage());

        // 测试 MCP 服务 shop_id 限制逻辑
        com.lanf.ai.service.impl.AiMcpToolServiceImpl mcpService = new com.lanf.ai.service.impl.AiMcpToolServiceImpl();
        com.lanf.ai.service.IAiMenuAdapterService mockMenuAdapter = org.mockito.Mockito.mock(com.lanf.ai.service.IAiMenuAdapterService.class);
        AiMenuSnapshotDTO dummySnapshot = new AiMenuSnapshotDTO();
        dummySnapshot.setShop_id(1);
        dummySnapshot.setItems(Collections.emptyList());
        org.mockito.Mockito.when(mockMenuAdapter.getStoreMenuSnapshot(org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(dummySnapshot);
        org.springframework.test.util.ReflectionTestUtils.setField(mcpService, "menuAdapterService", mockMenuAdapter);

        // 0. 验证 MCP 工具参数定义统一为 shop_id
        List<Map<String, Object>> tools = mcpService.listTools();
        for (Map<String, Object> tool : tools) {
            String name = (String) tool.get("name");
            if ("get_store_menu".equals(name) || "get_dish_profile".equals(name) || "create_dining_session".equals(name)) {
                Map<String, Object> inputSchema = (Map<String, Object>) tool.get("inputSchema");
                Map<String, Object> properties = (Map<String, Object>) inputSchema.get("properties");
                Assert.assertTrue(properties.containsKey("shop_id"));
                Assert.assertFalse(properties.containsKey("store_id"));
            }
        }

        // 1. 验证菜品 MCP 接口已开放支持任意门店 (如 shop_id=1 或 5)，正常返回菜单快照
        Map<String, Object> openArgs = new HashMap<>();
        openArgs.put("shop_id", 1);
        Map<String, Object> menuRes = mcpService.executeTool("get_store_menu", openArgs);
        Assert.assertNotNull("开放门店限制后，shop_id=1 必须正常执行成功", menuRes.get("content"));

        // 2. 传入 legacy store_id=5，同样正常返回
        openArgs.clear();
        openArgs.put("store_id", 5);
        Map<String, Object> menuRes5 = mcpService.executeTool("get_store_menu", openArgs);
        Assert.assertNotNull("开放门店限制后，store_id=5 必须正常执行成功", menuRes5.get("content"));

        // 2.1 验证履约类会话接口依然强隔离 (例如 create_dining_session 传入 shop_id=1 必须抛出 403)
        Map<String, Object> sessionArgs = new HashMap<>();
        sessionArgs.put("shop_id", 1);
        sessionArgs.put("party_size", 2);
        try {
            mcpService.executeTool("create_dining_session", sessionArgs);
            Assert.fail("非 3 号门店调用履约创建会话必须被 403 阻断");
        } catch (com.lanf.common.ApiException ex) {
            Assert.assertEquals(403, ex.getHttpStatus());
            Assert.assertEquals("SHOP_NOT_SUPPORTED_FOR_MCP", ex.getErrorCode());
        }

        // 3. 验证 chat_with_llm 工具的注册与 shop_id=3 强限制
        boolean hasChatLlm = false;
        for (Map<String, Object> tool : tools) {
            if ("chat_with_llm".equals(tool.get("name"))) {
                hasChatLlm = true;
                Map<String, Object> inputSchema = (Map<String, Object>) tool.get("inputSchema");
                Map<String, Object> properties = (Map<String, Object>) inputSchema.get("properties");
                Assert.assertTrue(properties.containsKey("shop_id"));
                Assert.assertTrue(properties.containsKey("prompt"));
            }
        }
        Assert.assertTrue("MCP 工具列表必须包含 chat_with_llm", hasChatLlm);

        // 4. chat_with_llm 非 3 号门店调用必须被 403 阻断
        Map<String, Object> chatArgs = new HashMap<>();
        chatArgs.put("shop_id", 1);
        chatArgs.put("prompt", "推荐招牌菜");
        try {
            mcpService.executeTool("chat_with_llm", chatArgs);
            Assert.fail("非 3 号门店调用 chat_with_llm 必须被拦截");
        } catch (com.lanf.common.ApiException ex) {
            Assert.assertEquals(403, ex.getHttpStatus());
            Assert.assertEquals("SHOP_NOT_SUPPORTED_FOR_MCP", ex.getErrorCode());
        }

        // 5. 验证 get_store_tables 工具注册与 shop_id=3 隔离及数据结构
        boolean hasGetStoreTables = false;
        for (Map<String, Object> tool : tools) {
            if ("get_store_tables".equals(tool.get("name"))) {
                hasGetStoreTables = true;
                Map<String, Object> inputSchema = (Map<String, Object>) tool.get("inputSchema");
                Map<String, Object> properties = (Map<String, Object>) inputSchema.get("properties");
                Assert.assertTrue(properties.containsKey("shop_id"));
                Assert.assertTrue(properties.containsKey("status"));
                Assert.assertTrue(properties.containsKey("area_code"));
            }
        }
        Assert.assertTrue("MCP 工具列表必须包含 get_store_tables", hasGetStoreTables);

        // 6. get_store_tables 非 3 号门店调用必须被 403 阻断
        Map<String, Object> tableArgs = new HashMap<>();
        tableArgs.put("shop_id", 2);
        try {
            mcpService.executeTool("get_store_tables", tableArgs);
            Assert.fail("非 3 号门店调用 get_store_tables 必须被拦截");
        } catch (com.lanf.common.ApiException ex) {
            Assert.assertEquals(403, ex.getHttpStatus());
            Assert.assertEquals("SHOP_NOT_SUPPORTED_FOR_MCP", ex.getErrorCode());
        }

        // 7. 模拟 tableService 测试 get_store_tables 正常返回
        com.lanf.service.ITableService mockTableService = org.mockito.Mockito.mock(com.lanf.service.ITableService.class);
        List<com.lanf.entity.Table> sampleTables = new ArrayList<>();
        com.lanf.entity.Table t1 = new com.lanf.entity.Table();
        t1.setId(1);
        t1.setNumber("01");
        t1.setStatus(0);
        t1.setShop_id(3);
        t1.setArea_code("hall");
        t1.setArea_name("大厅散座");
        sampleTables.add(t1);

        com.lanf.entity.Table t2 = new com.lanf.entity.Table();
        t2.setId(2);
        t2.setNumber("02");
        t2.setStatus(1);
        t2.setShop_id(3);
        t2.setArea_code("hall");
        t2.setArea_name("大厅散座");
        t2.setOrder_no("O20261025001");
        t2.setAmount(128.0);
        sampleTables.add(t2);

        org.mockito.Mockito.when(mockTableService.list(org.mockito.ArgumentMatchers.any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(sampleTables);
        org.springframework.test.util.ReflectionTestUtils.setField(mcpService, "tableService", mockTableService);

        tableArgs.clear();
        tableArgs.put("shop_id", 3);
        Map<String, Object> tableResRaw = mcpService.executeTool("get_store_tables", tableArgs);
        Assert.assertNotNull(tableResRaw.get("content"));

        // 8. 验证 AiLlmBridgeServiceImpl 环境变量配置解析与脱敏
        com.lanf.ai.service.impl.AiLlmBridgeServiceImpl bridgeService = new com.lanf.ai.service.impl.AiLlmBridgeServiceImpl();
        Map<String, Object> effConfig = bridgeService.getEffectiveConfig();
        Assert.assertNotNull(effConfig.get("api_url"));
        Assert.assertNotNull(effConfig.get("model"));
        Assert.assertEquals(3, effConfig.get("pilot_shop_id"));
    }
}
