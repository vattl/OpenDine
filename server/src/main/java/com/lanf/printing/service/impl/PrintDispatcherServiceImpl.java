package com.lanf.printing.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.printing.engine.PrintTemplateEngine;
import com.lanf.printing.engine.PrintTemplateOptions;
import com.lanf.printing.entity.PrintingDevice;
import com.lanf.printing.entity.PrintingJob;
import com.lanf.printing.entity.PrintingRule;
import com.lanf.printing.mapper.PrintingDeviceMapper;
import com.lanf.printing.mapper.PrintingJobMapper;
import com.lanf.printing.mapper.PrintingRuleMapper;
import com.lanf.printing.model.PrintContext;
import com.lanf.printing.model.PrintTemplateDsl;
import com.lanf.printing.model.PrintDispatchResult;
import com.lanf.printing.model.PrintScenario;
import com.lanf.printing.model.PrintResolvedPreview;
import com.lanf.printing.service.PrintDispatcherService;
import com.lanf.service.IFeieyunService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.io.IOException;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * 统一打印调度服务实现类
 */
@Service
public class PrintDispatcherServiceImpl implements PrintDispatcherService {

    private static final Logger log = LoggerFactory.getLogger(PrintDispatcherServiceImpl.class);
    private static final ZoneId ZONE = ZoneId.of("+08:00");
    private static final DateTimeFormatter DATE_CODE_FMT = DateTimeFormatter.ofPattern("yyyyMMdd");
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    public static final String TRANSPORT_CLOUD = "CLOUD";
    public static final String TRANSPORT_LAN = "LAN";
    public static final String TRANSPORT_USB = "USB";
    public static final String TRANSPORT_BLUETOOTH = "BLUETOOTH";

    public static final String STATUS_PENDING_DEVICE = "PENDING_DEVICE";
    public static final String STATUS_SENT = "SENT";
    public static final String STATUS_FAILED = "FAILED";

    @Autowired
    private PrintingDeviceMapper deviceMapper;

    @Autowired
    private PrintingRuleMapper ruleMapper;

    @Autowired
    private PrintingJobMapper jobMapper;

    @Autowired(required = false)
    private IFeieyunService feieyunService;



    @Autowired
    private PrintTemplateEngine templateEngine;

    @Autowired(required = false)
    private com.lanf.service.IShopService shopService;

    @Autowired(required = false)
    private com.lanf.printing.mapper.PrintingTemplateMapper templateMapper;

    @Override
    public List<PrintDispatchResult> dispatch(int shopId, String scenario, PrintContext context) {
        if (shopId <= 0 || !StringUtils.hasText(scenario)) {
            log.warn("[printing] dispatch invalid args: shopId={}, scenario={}", shopId, scenario);
            return Collections.emptyList();
        }
        if (context == null) {
            context = new PrintContext();
            context.setShopId(shopId);
        }
        String normScenario = PrintScenario.resolveDispatchCode(scenario, context);
        context.setScenario(normScenario);

        // 结账单底层防御：若目标场景为结账单且有关联订单，必须是已结账订单才允许打印
        if (PrintScenario.CHECKOUT.equalsIgnoreCase(normScenario)) {
            if (context.getOrder() != null && !"success".equalsIgnoreCase(context.getOrder().getTransac_status())) {
                log.warn("[printing] checkout receipt dispatch blocked for unsettled order: order_no={}, status={}",
                        context.getOrder().getOrder_no(), context.getOrder().getTransac_status());
                throw new ApiException(400, "ORDER_NOT_CHECKED_OUT", "订单尚未结账，不能打印结账单，未结账订单只能打印预结单");
            }
        }

        // 1. 若 context 中明确指定了目标设备 target_device_id，则定向构造临时规则直接出票
        List<PrintingRule> matchedRules = null;
        boolean scenarioConfigured = false;
        Object targetDevIdObj = context.getExtra() != null ? context.getExtra().get("target_device_id") : null;
        if (targetDevIdObj instanceof Number) {
            long targetDeviceId = ((Number) targetDevIdObj).longValue();
            PrintingDevice targetDev = deviceMapper.selectById(targetDeviceId);
            if (targetDev != null && Integer.valueOf(shopId).equals(targetDev.getShop_id())) {
                PrintingRule targetRule = new PrintingRule();
                targetRule.setId(0L);
                targetRule.setShop_id(shopId);
                targetRule.setDevice_id(targetDeviceId);
                targetRule.setScenario(normScenario);
                targetRule.setEnabled(1);
                Object copiesOverride = context.getExtra().get("copies_override");
                targetRule.setCopies(copiesOverride instanceof Number ? ((Number) copiesOverride).intValue() : 1);
                Object tplOverride = context.getExtra().get("template_id_override");
                if (tplOverride instanceof Number && templateMapper != null) {
                    com.lanf.printing.entity.PrintingTemplate tpl = templateMapper.selectById(((Number) tplOverride).longValue());
                    if (tpl != null) {
                        targetRule.setTemplate_code(tpl.getTemplate_code());
                    }
                }
                matchedRules = Collections.singletonList(targetRule);
                scenarioConfigured = true;
            }
        }

        // 2. 标准场景规则优先；仅无标准规则时查询历史别名，保证存量配置可用。
        if (!scenarioConfigured) {
            List<String> lookupCodes = PrintScenario.ruleLookupCodes(normScenario);
            for (String code : lookupCodes) {
                List<PrintingRule> rules = ruleMapper.selectList(new QueryWrapper<PrintingRule>()
                        .eq("shop_id", shopId)
                        .eq("scenario", code)
                        .orderByAsc("id"));
                if (rules != null && !rules.isEmpty()) {
                    scenarioConfigured = true;
                    matchedRules = new ArrayList<>();
                    for (PrintingRule r : rules) {
                        if (r.getEnabled() != null && r.getEnabled() == 1) {
                            matchedRules.add(r);
                        }
                    }
                    // 该场景已显式配置规则（即使全部 enabled=0，也代表明确的配置意图，严禁别名或 fallback 兜底覆盖）
                    break;
                }
            }
        }

        // 2. 规则自动兜底与历史数据平滑迁移
        if (!scenarioConfigured) {
            // 当前场景完全没有配置过规则，检查该门店是否已经存在任何出票规则
            Integer totalShopRules = ruleMapper.selectCount(new QueryWrapper<PrintingRule>().eq("shop_id", shopId));
            if (totalShopRules != null && totalShopRules > 0) {
                // 门店已接入出票规则管理，但未配置该场景的规则，默认不对此场景出票
                matchedRules = Collections.emptyList();
            } else if (PrintScenario.allowsUnconfiguredDeviceFallback(normScenario)) {
                // 仅当门店未配置任何打印规则（新店/冷启动空规则状态）时，才尝试默认设备兜底
                matchedRules = resolveFallbackRules(shopId, normScenario);
            } else {
                // 显式 opt-in 场景（如打包单）未配置时严禁默认设备兜底，避免存量门店突然多出票。
                matchedRules = Collections.emptyList();
            }
        }

        if (matchedRules == null || matchedRules.isEmpty()) {
            log.info("[printing] shopId={} scenario={} 未配置生效的打印设备与规则（或已被禁用），跳过出票", shopId, normScenario);
            return Collections.emptyList();
        }

        List<PrintDispatchResult> results = new ArrayList<>();

        // 3. 逐条规则渲染与派发
        for (PrintingRule rule : matchedRules) {
            Long deviceId = rule.getDevice_id();
            if (deviceId == null) {
                continue;
            }
            PrintingDevice device = deviceMapper.selectById(deviceId);
            if (device == null || device.getShop_id() == null || device.getShop_id() != shopId) {
                log.warn("[printing] rule id={} referenced non-existent or foreign device id={}", rule.getId(), deviceId);
                continue;
            }

            Object copiesOverride = context.getExtra() != null ? context.getExtra().get("copies_override") : null;
            int copies;
            if (copiesOverride instanceof Number && ((Number) copiesOverride).intValue() >= 1 && ((Number) copiesOverride).intValue() <= 9) {
                copies = ((Number) copiesOverride).intValue();
            } else {
                copies = (rule.getCopies() != null && rule.getCopies() >= 1 && rule.getCopies() <= 9) ? rule.getCopies() : 1;
            }
            List<String> ticketContents;
            try {
                ticketContents = renderContentsForScenario(normScenario, context, device, rule);
            } catch (Exception e) {
                log.error("[printing] failed to resolve/render template for scenario={} shopId={}: {}", normScenario, shopId, e.getMessage());
                PrintDispatchResult failRes = new PrintDispatchResult();
                failRes.setJobCode("JOB-PRINT-FAIL");
                failRes.setDeviceId(device.getId());
                failRes.setTransport(device.getTransport() != null ? device.getTransport() : "UNKNOWN");
                failRes.setScenario(normScenario);
                failRes.setStatus(STATUS_FAILED);
                failRes.setExecutor(TRANSPORT_CLOUD.equalsIgnoreCase(device.getTransport()) ? "CLOUD" : "DEVICE");
                failRes.setSuccess(false);
                failRes.setError(e.getMessage() != null ? e.getMessage() : "未配置对应的小票模板");
                failRes.setMessage("出票失败: " + failRes.getError());
                results.add(failRes);
                continue;
            }

            for (String ticketContent : ticketContents) {
                if (!StringUtils.hasText(ticketContent)) {
                    continue;
                }
                PrintDispatchResult res = executeAndRecordJob(shopId, device, normScenario, ticketContent, copies, context, context.getAdminId());
                results.add(res);
            }
        }

        return results;
    }

    @Override
    public PrintDispatchResult reprintJob(long jobId, Integer adminId) {
        PrintingJob job = jobMapper.selectById(jobId);
        if (job == null) {
            PrintDispatchResult r = new PrintDispatchResult();
            r.setJobId(jobId);
            r.setSuccess(false);
            r.setError("打印任务记录不存在");
            return r;
        }

        PrintingDevice device = null;
        if (job.getDevice_id() != null) {
            device = deviceMapper.selectById(job.getDevice_id());
        }

        int shopId = job.getShop_id() != null ? job.getShop_id() : 1;
        String payload = job.getPayload_text();

        job.setRetry_count((job.getRetry_count() != null ? job.getRetry_count() : 0) + 1);
        job.setUpdated_at(LocalDateTime.now(ZONE));

        boolean isCloud = device != null && TRANSPORT_CLOUD.equalsIgnoreCase(device.getTransport());
        if (isCloud) {
            job.setExecutor("CLOUD");
            String sn = extractDeviceSn(device);
            if (feieyunService == null || !StringUtils.hasText(sn)) {
                job.setStatus(STATUS_FAILED);
                job.setError("飞鹅云服务未就绪或设备 SN 缺失");
            } else {
                try {
                    executeCloudPrint(device, shopId, sn, payload, 1);
                    job.setStatus(STATUS_SENT);
                    job.setError(null);
                } catch (Exception e) {
                    job.setStatus(STATUS_FAILED);
                    job.setError(e.getMessage() != null ? e.getMessage() : "云打印调用异常");
                }
            }
        } else {
            job.setExecutor("DEVICE");
            job.setStatus(STATUS_PENDING_DEVICE);
            job.setError(null);
        }

        jobMapper.updateById(job);
        log.info("[printing] reprint job executed: jobId={}, status={}, adminId={}", jobId, job.getStatus(), adminId);

        PrintDispatchResult r = new PrintDispatchResult();
        r.setJobId(job.getId());
        r.setJobCode("JOB-PRINT-" + LocalDate.now(ZONE).format(DATE_CODE_FMT) + "-" + job.getId());
        r.setDeviceId(job.getDevice_id());
        r.setTransport(device != null ? device.getTransport() : "UNKNOWN");
        r.setScenario(PrintScenario.canonicalCode(job.getJob_type()));
        r.setStatus(job.getStatus());
        r.setExecutor(job.getExecutor());
        r.setSuccess(STATUS_SENT.equals(job.getStatus()) || STATUS_PENDING_DEVICE.equals(job.getStatus()));
        r.setError(job.getError());
        r.setMessage(r.isSuccess() ? "补打指令已下发" : "补打指令提交失败");
        return r;
    }

    @Override
    public List<PrintDispatchResult> dispatchCustom(int shopId, String scenario, String customContent, Integer adminId) {
        PrintContext ctx = PrintContext.ofCustom(shopId, scenario, customContent);
        ctx.setAdminId(adminId);
        return dispatch(shopId, scenario, ctx);
    }

    @Override
    public List<PrintResolvedPreview> previewExact(int shopId, String scenario, PrintContext context, Long requestedRuleId, Long requestedDeviceId) {
        return resolvePreviews(shopId, scenario, context, requestedRuleId, requestedDeviceId);
    }

    /**
     * 设计器预览：与真实打印/精确预览共用同一组装内核（renderContentsWithDsl），
     * 支持未保存的临时 DSL（templateDsl/templateJson/templateId）；临时 DSL 时不要求规则/设备，
     * 可选 deviceId 用于读取纸宽等设备参数；未传临时 DSL 时与 previewExact 完全同路径（真实规则）。
     */
    @Override
    public List<PrintResolvedPreview> renderPreviewContents(int shopId, String scenario, PrintContext context,
                                                            PrintTemplateDsl dslOverride, Long requestedRuleId, Long requestedDeviceId) {
        if (shopId <= 0 || !StringUtils.hasText(scenario) || context == null) return Collections.emptyList();
        if (StringUtils.hasText(context.getCustomContent())) {
            PrintResolvedPreview preview = new PrintResolvedPreview();
            PrintTemplateOptions options = buildRenderOptions(null, context);
            String resolved = templateEngine.renderCustomContent(context.getScenario(), context, context.getCustomContent(), options);
            preview.setContents(Collections.singletonList(resolved));
            return Collections.singletonList(preview);
        }
        String norm = PrintScenario.resolveDispatchCode(scenario, context);
        if (dslOverride != null) {
            PrintingDevice device = null;
            if (requestedDeviceId != null) {
                device = deviceMapper.selectById(requestedDeviceId);
                if (device == null || !Integer.valueOf(shopId).equals(device.getShop_id())) {
                    throw new IllegalArgumentException("指定打印设备不存在或不属于当前门店");
                }
            }
            try {
                PrintTemplateOptions options = buildRenderOptions(device, context);
                List<String> contents = renderContentsWithDsl(norm, context, device, dslOverride, options);
                PrintResolvedPreview preview = new PrintResolvedPreview();
                preview.setDeviceId(device != null ? device.getId() : null);
                preview.setDeviceName(device != null ? device.getName() : null);
                preview.setTransport(device != null ? device.getTransport() : null);
                preview.setPaperSize(options.getPaperWidth());
                preview.setContents(contents);
                return Collections.singletonList(preview);
            } catch (IllegalStateException ex) {
                throw ex;
            } catch (Exception ex) {
                throw new IllegalStateException("设计器预览渲染失败: " + ex.getMessage(), ex);
            }
        }
        return resolvePreviews(shopId, norm, context, requestedRuleId, requestedDeviceId);
    }

    /** 只读精确预览内核：按生效规则逐台设备渲染，零 job 零云调用 */
    private List<PrintResolvedPreview> resolvePreviews(int shopId, String scenario, PrintContext context,
                                                       Long requestedRuleId, Long requestedDeviceId) {
        if (shopId <= 0 || !StringUtils.hasText(scenario) || context == null) return Collections.emptyList();
        String norm = PrintScenario.resolveDispatchCode(scenario, context);
        List<PrintingRule> rules = ruleMapper.selectList(new QueryWrapper<PrintingRule>()
                .eq("shop_id", shopId).eq("scenario", norm).eq("enabled", 1).orderByAsc("id"));
        if (rules == null || rules.isEmpty()) {
            throw new IllegalStateException("未配置生效打印规则[场景: " + norm + "]");
        }
        List<PrintResolvedPreview> result = new ArrayList<>();
        for (PrintingRule rule : rules) {
            if (requestedRuleId != null && !requestedRuleId.equals(rule.getId())) continue;
            if (rule.getDevice_id() == null) continue;
            PrintingDevice device = deviceMapper.selectById(rule.getDevice_id());
            if (device == null || !Integer.valueOf(shopId).equals(device.getShop_id())) continue;
            if (requestedDeviceId != null && !requestedDeviceId.equals(device.getId())) continue;
            try {
                PrintResolvedPreview preview = new PrintResolvedPreview();
                preview.setRuleId(rule.getId()); preview.setDeviceId(device.getId());
                preview.setDeviceName(device.getName()); preview.setTransport(device.getTransport());
                com.lanf.printing.entity.PrintingTemplate tpl = resolveTemplateEntity(device, context, rule, norm);
                if (tpl == null) throw new IllegalStateException("未配置小票打印模板[场景: " + norm + "]");
                preview.setTemplateId(tpl.getId()); preview.setTemplateCode(tpl.getTemplate_code());
                Map<String, Object> connection = extractDeviceConnection(device);
                Object paper = connection == null ? null : (connection.get("paperSize") != null ? connection.get("paperSize") : connection.get("paper_size"));
                preview.setPaperSize(paper == null ? "58mm" : String.valueOf(paper));
                preview.setContents(renderContentsForScenario(norm, context, device, rule));
                result.add(preview);
            } catch (Exception ex) {
                throw new IllegalStateException("精确预览渲染失败(rule=" + rule.getId() + "): " + ex.getMessage(), ex);
            }
        }
        if (result.isEmpty()) throw new IllegalArgumentException("指定打印规则或设备不存在、未启用或不属于当前门店");
        return result;
    }

    // ---------------- 渲染与执行核心 ----------------

    private List<String> renderContentsForScenario(String scenario, PrintContext context, PrintingDevice device, PrintingRule rule) {
        if (StringUtils.hasText(context.getCustomContent())) {
            PrintTemplateOptions options = buildRenderOptions(device, context);
            String resolved = templateEngine.renderCustomContent(scenario, context, context.getCustomContent(), options);
            return Collections.singletonList(resolved);
        }
        PrintTemplateOptions options = buildRenderOptions(device, context);
        PrintTemplateDsl dsl = loadTemplateDsl(scenario, device, context, rule);
        return renderContentsWithDsl(PrintScenario.normalizeScenario(scenario), context, device, dsl, options);
    }

    /** 统一设备参数组装：纸宽/自动切刀/蜂鸣/品牌抬头（真实打印与各类预览共用） */
    private PrintTemplateOptions buildRenderOptions(PrintingDevice device, PrintContext context) {
        PrintTemplateOptions options = PrintTemplateOptions.defaultOptions();
        Map<String, Object> conn = extractDeviceConnection(device);
        if (conn != null) {
            Object paperSize = conn.get("paperSize");
            if (paperSize == null) paperSize = conn.get("paper_size");
            if (paperSize != null && StringUtils.hasText(paperSize.toString())) {
                options.setPaperWidth(paperSize.toString().trim());
            }
            Object autoCut = conn.get("autoCut");
            if (autoCut == null) autoCut = conn.get("auto_cut");
            if (autoCut instanceof Boolean) {
                options.setAutoCut((Boolean) autoCut);
            } else if (autoCut instanceof Number) {
                options.setAutoCut(((Number) autoCut).intValue() == 1);
            }
            Object beeper = conn.get("beeper");
            if (beeper instanceof Boolean) {
                options.setBeeper((Boolean) beeper);
            } else if (beeper instanceof Number) {
                options.setBeeper(((Number) beeper).intValue() == 1);
            }
        }
        if (context.getOrder() != null && context.getOrder().getShop_id() != null && shopService != null) {
            try {
                com.lanf.entity.Shop s = shopService.getById(context.getOrder().getShop_id());
                if (s != null && StringUtils.hasText(s.getName())) {
                    options.setBrandHeader(s.getName().trim());
                }
            } catch (Exception ignored) {}
        }
        if (context.getExtra() != null && !context.getExtra().isEmpty()) {
            options.getBindings().putAll(context.getExtra());
        }
        return options;
    }

    /** 从数据库按规则/门店解析模板 DSL，未配置即抛异常（真实打印与精确预览同源） */
    private PrintTemplateDsl loadTemplateDsl(String scenario, PrintingDevice device, PrintContext context, PrintingRule rule) {
        com.lanf.printing.entity.PrintingTemplate tpl = resolveTemplateEntity(device, context, rule, scenario);
        PrintTemplateDsl dsl = null;
        if (tpl != null && StringUtils.hasText(tpl.getTemplate_json()) && templateEngine != null) {
            dsl = templateEngine.parseDsl(tpl.getTemplate_json());
        }
        if (dsl == null) {
            String displayName = PrintScenario.getScenarioDisplayName(scenario);
            log.error("[printing] 数据库中未配置小票打印模板: scenario={}, shopId={}", scenario, device != null ? device.getShop_id() : context.getShopId());
            throw new IllegalStateException("未配置小票打印模板[场景: " + displayName + "(" + scenario + ")]，请先在模板设计器中配置模板");
        }
        return dsl;
    }

    /** 场景数据组装分发：全部业务打印类型统一由此 switch 组装（真实打印/精确预览/设计器预览共用） */
    private List<String> renderContentsWithDsl(String norm, PrintContext context, PrintingDevice device, PrintTemplateDsl dsl, PrintTemplateOptions options) {
        switch (norm) {
            case "KITCHEN":
                return templateEngine.renderDynamicKitchenTickets(context.getOrder(), dsl, context.getCidFilter(), options);
            case "EXPEDITE":
                if (context.getOrderDetail() != null) {
                    String serve = templateEngine.renderDynamicServeTicket(context.getOrder(), context.getOrderDetail(),
                            context.getServeQty() != null ? context.getServeQty() : 1, dsl, options);
                    return StringUtils.hasText(serve) ? Collections.singletonList(serve) : Collections.emptyList();
                } else {
                    return templateEngine.renderDynamicKitchenTickets(context.getOrder(), dsl, context.getCidFilter(), options);
                }
            case "SHIFT":
                String shift = templateEngine.renderDynamicShiftTicket(context.getShift(), dsl, context.getExtra(), options);
                return StringUtils.hasText(shift) ? Collections.singletonList(shift) : Collections.emptyList();
            case "REFUND":
                String refund = templateEngine.renderDynamicRefundTicket(context.getOrder(), dsl, context.getExtra(), options);
                return StringUtils.hasText(refund) ? Collections.singletonList(refund) : Collections.emptyList();
            case "LABEL":
                String label = templateEngine.renderDynamicLabelTicket(context.getOrder(), context.getOrderDetail(), dsl, options);
                return StringUtils.hasText(label) ? Collections.singletonList(label) : Collections.emptyList();
            case "TEST":
                String test = templateEngine.renderDynamicTestTicket(dsl, "order", device != null ? device.getName() : "测试设备",
                        device != null ? device.getTransport() : "CLOUD", device != null ? device.getBrand() : "飞鹅", context.getShopId() != null ? context.getShopId() : 1);
                return StringUtils.hasText(test) ? Collections.singletonList(test) : Collections.emptyList();
            default:
                // ORDER, FULL_ORDER, PRE_CHECKOUT, CHECKOUT, TAKEOUT, PACKING
                String dynamicTicket = templateEngine.renderDynamicTicket(context.getOrder(), dsl, options);
                return StringUtils.hasText(dynamicTicket) ? Collections.singletonList(dynamicTicket) : Collections.emptyList();
        }
    }

    private com.lanf.printing.entity.PrintingTemplate resolveTemplateEntity(PrintingDevice device, PrintContext context, PrintingRule rule, String scenario) {
        if (templateMapper == null) {
            return null;
        }
        int sid = device != null && device.getShop_id() != null ? device.getShop_id() : (context.getOrder() != null && context.getOrder().getShop_id() != null ? context.getOrder().getShop_id() : (context.getShopId() != null ? context.getShopId() : 0));
        String normalizedScenario = PrintScenario.normalizeScenario(scenario);

        // 0. 优先按 template_id_override 查找
        Long targetTplId = null;
        if (context != null && context.getExtra() != null && context.getExtra().get("template_id_override") instanceof Number) {
            targetTplId = ((Number) context.getExtra().get("template_id_override")).longValue();
        }
        if (targetTplId != null && targetTplId > 0) {
            com.lanf.printing.entity.PrintingTemplate tpl = templateMapper.selectById(targetTplId);
            if (tpl != null && StringUtils.hasText(tpl.getTemplate_json())) {
                return tpl;
            }
        }

        // 1. 优先按规则绑定的 template_code 查找
        if (rule != null && StringUtils.hasText(rule.getTemplate_code())) {
            com.lanf.printing.entity.PrintingTemplate tpl = templateMapper.selectOne(new QueryWrapper<com.lanf.printing.entity.PrintingTemplate>()
                    .and(w -> w.eq("shop_id", sid).or().eq("shop_id", 0))
                    .eq("template_code", rule.getTemplate_code().trim())
                    .orderByDesc("shop_id")
                    .last("LIMIT 1"));
            if (tpl != null && StringUtils.hasText(tpl.getTemplate_json())) {
                return tpl;
            }
        }

        // 2. 查找当前门店在该场景下的默认模板 (is_default = 1)
        if (sid > 0) {
            com.lanf.printing.entity.PrintingTemplate shopDefault = templateMapper.selectOne(new QueryWrapper<com.lanf.printing.entity.PrintingTemplate>()
                    .eq("shop_id", sid)
                    .eq("scenario", normalizedScenario)
                    .eq("is_default", 1)
                    .last("LIMIT 1"));
            if (shopDefault != null && StringUtils.hasText(shopDefault.getTemplate_json())) {
                return shopDefault;
            }

            // 3. 查找当前门店在该场景下的任意模板
            com.lanf.printing.entity.PrintingTemplate shopAny = templateMapper.selectOne(new QueryWrapper<com.lanf.printing.entity.PrintingTemplate>()
                    .eq("shop_id", sid)
                    .eq("scenario", normalizedScenario)
                    .orderByDesc("id")
                    .last("LIMIT 1"));
            if (shopAny != null && StringUtils.hasText(shopAny.getTemplate_json())) {
                return shopAny;
            }
        }

        // 4. 查找系统全局该场景下的默认模板 (shop_id = 0, is_default = 1 / is_system = 1)
        com.lanf.printing.entity.PrintingTemplate sysDefault = templateMapper.selectOne(new QueryWrapper<com.lanf.printing.entity.PrintingTemplate>()
                .eq("shop_id", 0)
                .eq("scenario", normalizedScenario)
                .and(w -> w.eq("is_default", 1).or().eq("is_system", 1))
                .orderByDesc("is_default")
                .last("LIMIT 1"));
        if (sysDefault != null && StringUtils.hasText(sysDefault.getTemplate_json())) {
            return sysDefault;
        }

        // 5. 查找系统全局该场景下的任意模板
        com.lanf.printing.entity.PrintingTemplate sysAny = templateMapper.selectOne(new QueryWrapper<com.lanf.printing.entity.PrintingTemplate>()
                .eq("shop_id", 0)
                .eq("scenario", normalizedScenario)
                .orderByDesc("id")
                .last("LIMIT 1"));
        if (sysAny != null && StringUtils.hasText(sysAny.getTemplate_json())) {
            return sysAny;
        }

        return null;
    }

    private PrintDispatchResult executeAndRecordJob(int shopId, PrintingDevice device, String scenario,
                                                    String payloadText, int copies, PrintContext context, Integer adminId) {
        PrintingJob job = new PrintingJob();
        job.setShop_id(shopId);
        job.setDevice_id(device.getId());
        job.setJob_type(scenario);
        job.setPayload_text(payloadText);
        job.setRetry_count(0);
        // 业务溯源透传：由调用方在 PrintContext.extra 携带 bizType/bizId（如 KDS 划菜 detail_id）
        if (context != null && context.getExtra() != null) {
            Object bizType = context.getExtra().get("bizType");
            Object bizId = context.getExtra().get("bizId");
            if (bizType != null) {
                job.setBiz_type(String.valueOf(bizType));
            }
            if (bizId instanceof Number) {
                job.setBiz_id(((Number) bizId).longValue());
            }
        }
        job.setCreated_at(LocalDateTime.now(ZONE));
        job.setUpdated_at(job.getCreated_at());

        boolean isCloud = TRANSPORT_CLOUD.equalsIgnoreCase(device.getTransport());
        if (isCloud) {
            job.setExecutor("CLOUD");
            String sn = extractDeviceSn(device);
            if (feieyunService == null || !StringUtils.hasText(sn)) {
                job.setStatus(STATUS_FAILED);
                job.setError("飞鹅云打印服务未配置或设备 SN 为空");
            } else {
                try {
                    executeCloudPrint(device, shopId, sn, payloadText, copies);
                    job.setStatus(STATUS_SENT);
                } catch (IOException e) {
                    log.warn("[printing] cloud print IO exception: shop_id={}, device_id={}, sn={}, msg={}",
                            shopId, device.getId(), sn, e.getMessage());
                    job.setStatus(STATUS_FAILED);
                    job.setError(e.getMessage() != null ? e.getMessage() : "飞鹅云打印网络通信失败");
                } catch (Exception e) {
                    log.warn("[printing] cloud print error: shop_id={}, device_id={}, sn={}, msg={}",
                            shopId, device.getId(), sn, e.getMessage());
                    job.setStatus(STATUS_FAILED);
                    job.setError(e.getMessage() != null ? e.getMessage() : "云端打印执行异常");
                }
            }
        } else {
            job.setExecutor("DEVICE");
            job.setStatus(STATUS_PENDING_DEVICE);
        }

        jobMapper.insert(job);
        log.info("[printing] dispatch job created: shop_id={}, device_id={}, job_id={}, status={}, executor={}",
                shopId, device.getId(), job.getId(), job.getStatus(), job.getExecutor());

        PrintDispatchResult res = new PrintDispatchResult();
        res.setJobId(job.getId());
        res.setJobCode("JOB-PRINT-" + LocalDate.now(ZONE).format(DATE_CODE_FMT) + "-" + job.getId());
        res.setDeviceId(device.getId());
        res.setDeviceName(device.getName());
        res.setTransport(device.getTransport());
        res.setScenario(scenario);
        res.setCopies(copies);
        res.setStatus(job.getStatus());
        res.setExecutor(job.getExecutor());
        res.setPayloadText(payloadText);
        res.setError(job.getError());
        res.setSuccess(STATUS_SENT.equals(job.getStatus()) || STATUS_PENDING_DEVICE.equals(job.getStatus()));
        res.setMessage(res.isSuccess() ? "打印指令已成功下发" : "打印指令派发失败");
        return res;
    }

    // ---------------- 降级与历史平滑兼容 ----------------

    /**
     * 兜底规则：仅当门店未配置任何打印规则时，取该门店最新一台 t_printing_device 作为默认设备。
     * 自 v1.2.223 起不再读取 t_shop_printer_config（门店配置）与 feieyun.*（全局配置）。
     */
    private List<PrintingRule> resolveFallbackRules(int shopId, String scenario) {
        // 1. 查找 t_printing_device 是否有已有设备
        List<PrintingDevice> devices = deviceMapper.selectList(new QueryWrapper<PrintingDevice>()
                .eq("shop_id", shopId)
                .orderByDesc("id"));

        if (devices != null && !devices.isEmpty()) {
            PrintingDevice defaultDev = devices.get(0);
            PrintingRule autoRule = new PrintingRule();
            autoRule.setShop_id(shopId);
            autoRule.setScenario(scenario);
            autoRule.setDevice_id(defaultDev.getId());
            autoRule.setCopies(1);
            autoRule.setEnabled(1);
            return Collections.singletonList(autoRule);
        }

        // 无任何设备：不再回退门店配置/全局配置，返回空规则（打印跳过，由管理端配置设备）
        return Collections.emptyList();
    }

    private void executeCloudPrint(PrintingDevice device, int shopId, String sn, String payloadText, int copies) throws IOException {
        Map<String, Object> conn = extractDeviceConnection(device);
        String user = conn != null && conn.get("user") != null ? String.valueOf(conn.get("user")).trim() : null;
        String ukey = conn != null && conn.get("ukey") != null ? String.valueOf(conn.get("ukey")).trim() : null;
        String apiUrl = conn != null && conn.get("url") != null ? String.valueOf(conn.get("url")).trim() : null;
        if (!StringUtils.hasText(apiUrl) && conn != null && conn.get("apiUrl") != null) {
            apiUrl = String.valueOf(conn.get("apiUrl")).trim();
        }

        // 设备凭据以 t_printing_device.connection_json 为唯一来源，缺失即失败，不再回退全局/门店配置
        if (!StringUtils.hasText(user) || !StringUtils.hasText(ukey)) {
            throw new IOException("打印设备未配置飞鹅云凭据(connection.user/ukey)，无法云端打印");
        }
        if (!StringUtils.hasText(apiUrl)) {
            throw new IOException("打印设备未配置飞鹅云接口地址(connection.url/apiUrl)，无法云端打印");
        }
        feieyunService.printWithCredential(apiUrl, user, ukey, sn, payloadText, copies);
    }

    private Map<String, Object> extractDeviceConnection(PrintingDevice device) {
        if (device == null || !StringUtils.hasText(device.getConnection_json())) {
            return Collections.emptyMap();
        }
        try {
            return OBJECT_MAPPER.readValue(device.getConnection_json(),
                    new TypeReference<Map<String, Object>>() {});
        } catch (Exception e) {
            return Collections.emptyMap();
        }
    }

    private String extractDeviceSn(PrintingDevice device) {
        Map<String, Object> conn = extractDeviceConnection(device);
        Object sn = conn.get("sn");
        return sn != null ? sn.toString().trim() : null;
    }
}
