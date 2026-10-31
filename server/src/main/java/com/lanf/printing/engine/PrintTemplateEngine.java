package com.lanf.printing.engine;

import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shift;
import com.lanf.printing.model.PrintTemplateDsl;

import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 统一小票模板渲染引擎接口（完全基于数据库 DSL 动态解释渲染）
 */
public interface PrintTemplateEngine {

    /**
     * 基于可视化设计器 DSL 配置动态渲染小票（支持结账单、预结单、整单、外卖单等）
     */
    String renderDynamicTicket(Order order, PrintTemplateDsl dsl, PrintTemplateOptions options);

    /**
     * 基于可视化设计器 DSL 配置动态渲染后厨小票（支持多档口分类分单）
     */
    List<String> renderDynamicKitchenTickets(Order order, PrintTemplateDsl dsl, Set<String> cidFilter, PrintTemplateOptions options);

    /**
     * 基于 DSL 渲染传菜单（划单后出票）
     */
    String renderDynamicServeTicket(Order order, OrderDetail detail, int serveQty, PrintTemplateDsl dsl, PrintTemplateOptions options);

    /**
     * 基于 DSL 渲染交接班报表
     */
    String renderDynamicShiftTicket(Shift shift, PrintTemplateDsl dsl, Map<String, Object> statistics, PrintTemplateOptions options);

    /**
     * 基于 DSL 渲染退款单据
     */
    String renderDynamicRefundTicket(Order order, PrintTemplateDsl dsl, Map<String, Object> refundInfo, PrintTemplateOptions options);

    /**
     * 基于 DSL 渲染商品标签/杯贴
     */
    String renderDynamicLabelTicket(Order order, OrderDetail detail, PrintTemplateDsl dsl, PrintTemplateOptions options);

    /**
     * 基于 DSL 渲染自检测试单
     */
    String renderDynamicTestTicket(PrintTemplateDsl dsl, String testType, String deviceName, String transport, String brand, int shopId);

    /**
     * 兼容接口：使用场景标准默认 DSL 渲染前台小票
     */
    String renderReceiptTicket(Order order, boolean isAddDishes, PrintTemplateOptions options);

    /**
     * 前端直传原始打印数据（飞鹅标签串，参考飞鹅云 demo 组装形式）按飞鹅规则解析：
     * 保留 {if:} 条件块解析，<BR> 归一换行，场景变量插值（无数据时变量为空），缺失行隐藏，标签原样透传。
     */
    String renderCustomContent(String scenario, com.lanf.printing.model.PrintContext context, String content, PrintTemplateOptions options);

    /**
     * 兼容接口：使用场景标准默认 DSL 渲染后厨制作小票
     */
    List<String> renderKitchenTickets(Order order, Set<String> cidFilter, PrintTemplateOptions options);

    /**
     * 兼容接口：使用场景标准默认 DSL 渲染传菜单
     */
    String renderServeTicket(Order order, OrderDetail detail, int serveQty, PrintTemplateOptions options);

    /**
     * 兼容接口：使用场景标准默认 DSL 渲染交接班报表
     */
    String renderShiftTicket(Shift shift, Map<String, Object> statistics, PrintTemplateOptions options);

    /**
     * 兼容接口：使用场景标准默认 DSL 渲染退款单
     */
    String renderRefundTicket(Order order, Map<String, Object> refundInfo, PrintTemplateOptions options);

    /**
     * 兼容接口：使用场景标准默认 DSL 渲染商品标签
     */
    String renderLabelTicket(Order order, OrderDetail detail, PrintTemplateOptions options);

    /**
     * 兼容接口：使用场景标准默认 DSL 渲染自检测试单
     */
    String renderTestTicket(String testType, String deviceName, String transport, String brand, int shopId);

    /**
     * 解析 JSON 文本为 PrintTemplateDsl
     */
    PrintTemplateDsl parseDsl(String templateJson);

    /**
     * 生成指定场景与纸张尺寸的标准预置模板 DSL
     */
    PrintTemplateDsl buildDefaultDsl(String scenario, String paperSize);
}
