package com.lanf.printing.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.common.ApiException;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shift;
import com.lanf.order.OrderDetailQueryHelper;
import com.lanf.printing.entity.PrintingDevice;
import com.lanf.printing.mapper.PrintingDeviceMapper;
import com.lanf.printing.model.PrintContext;
import com.lanf.printing.model.PrintDispatchResult;
import com.lanf.printing.model.PrintScenario;
import com.lanf.printing.model.UnifiedPrintRequest;
import com.lanf.printing.model.UnifiedPrintResponse;
import com.lanf.printing.service.PrintDispatcherService;
import com.lanf.printing.service.UnifiedPrintService;
import com.lanf.service.IAdminService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShiftService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.util.AdminNameResolver;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * 统一出票与补打调度服务实现类
 */
@Service
public class UnifiedPrintServiceImpl implements UnifiedPrintService {

    private static final Logger log = LoggerFactory.getLogger(UnifiedPrintServiceImpl.class);
    private static final DateTimeFormatter TIME_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    @Autowired
    private IOrderService orderService;

    @Autowired(required = false)
    private IOrderDetailService orderDetailService;

    @Autowired(required = false)
    private IShiftService shiftService;

    @Autowired(required = false)
    private IAdminService adminService;

    @Autowired(required = false)
    private ITakeoutDeliveryService takeoutDeliveryService;

    @Autowired
    private PrintDispatcherService printDispatcherService;

    @Autowired(required = false)
    private PrintingDeviceMapper deviceMapper;

    @Override
    public UnifiedPrintResponse dispatch(UnifiedPrintRequest request, Integer operatorAdminId, Integer shopIdContext) {
        if (request == null) {
            throw new ApiException(400, "PARAM_ERROR", "打印请求体不能为空");
        }

        boolean isReprint = request.getIsReprint() == null || Boolean.TRUE.equals(request.getIsReprint());

        // 1. 查找订单
        Order order = null;
        if (request.getOrderId() != null && orderService != null) {
            order = orderService.getById(request.getOrderId());
        }
        if (order == null && StringUtils.hasText(request.getOrderNo()) && orderService != null) {
            String targetOrderNo = request.getOrderNo().trim();
            QueryWrapper<Order> qw = new QueryWrapper<Order>().eq("order_no", targetOrderNo);
            if (shopIdContext != null && shopIdContext > 0) {
                qw.eq("shop_id", shopIdContext);
            }
            qw.last("LIMIT 1");
            order = orderService.getOne(qw);

            if (order == null && shopIdContext != null && shopIdContext > 0) {
                Order anyOrder = orderService.getOne(new QueryWrapper<Order>().eq("order_no", targetOrderNo).last("LIMIT 1"));
                if (anyOrder != null) {
                    throw new ApiException(403, "SHOP_SCOPE_MISMATCH", "订单不属于当前门店");
                }
            }
        }

        String rawScenario = request.getScenario();
        boolean isShiftScenario = StringUtils.hasText(rawScenario) && "shift".equalsIgnoreCase(rawScenario.trim());
        boolean hasCustomContent = StringUtils.hasText(request.getCustomContent());

        if ((request.getOrderId() != null || StringUtils.hasText(request.getOrderNo())) && order == null) {
            throw new ApiException(404, "ORDER_NOT_FOUND", "订单不存在: " + (StringUtils.hasText(request.getOrderNo()) ? request.getOrderNo() : request.getOrderId()));
        }

        if (order == null && !isShiftScenario && !hasCustomContent && request.getShiftId() == null) {
            throw new ApiException(400, "PRINT_ORDER_REQUIRED", "请提供订单号 (order_no) 或订单 ID (order_id)");
        }

        // 2. 校验并解析门店上下文
        if (order != null && shopIdContext != null && shopIdContext > 0 && order.getShop_id() != null) {
            if (!shopIdContext.equals(order.getShop_id())) {
                throw new ApiException(403, "SHOP_SCOPE_MISMATCH", "订单不属于当前门店");
            }
        }
        int effectiveShopId = (shopIdContext != null && shopIdContext > 0)
                ? shopIdContext
                : (order != null && order.getShop_id() != null ? order.getShop_id() : 1);

        // 3. 填充订单菜品明细与外卖配送信息
        if (order != null) {
            if (orderDetailService != null) {
                QueryWrapper<OrderDetail> qw = new QueryWrapper<OrderDetail>().eq("mId", order.getId());
                OrderDetailQueryHelper.onlyActive(qw);
                qw.orderByAsc("id");
                List<OrderDetail> details = orderDetailService.list(qw);
                order.setGoods_list(details != null ? details : Collections.emptyList());
            }
            if (takeoutDeliveryService != null) {
                try {
                    takeoutDeliveryService.enrichOrder(order);
                } catch (Exception ignored) {
                }
            }
        }

        // 4. 场景智能推导
        String scenario;
        if (StringUtils.hasText(rawScenario)) {
            scenario = PrintScenario.canonicalCode(rawScenario);
        } else if (order != null) {
            scenario = PrintScenario.KITCHEN;
        } else if (request.getShiftId() != null || isShiftScenario) {
            scenario = PrintScenario.SHIFT;
        } else if (hasCustomContent) {
            scenario = PrintScenario.CHECKOUT;
        } else {
            scenario = PrintScenario.KITCHEN;
        }

        // 结账单打印限制：必须订单结账后才能打印结账单，未结账订单只能打印预结单
        if (PrintScenario.CHECKOUT.equals(scenario)) {
            if (order != null && !"success".equalsIgnoreCase(order.getTransac_status())) {
                throw new ApiException(400, "ORDER_NOT_CHECKED_OUT", "订单尚未结账，不能打印结账单，未结账订单只能打印预结单");
            }
        }

        // 5. 构造 PrintContext
        PrintContext context = new PrintContext();
        context.setShopId(effectiveShopId);
        context.setScenario(scenario);
        context.setAdminId(operatorAdminId);

        if (order != null) {
            context.setOrder(order);
            context.setAddDishes(order.getOrderNumber() != null && order.getOrderNumber() > 1);
            if (request.getCidList() != null && !request.getCidList().isEmpty()) {
                Set<String> cids = new HashSet<>();
                for (String c : request.getCidList()) {
                    if (StringUtils.hasText(c)) {
                        cids.add(c.trim());
                    }
                }
                if (!cids.isEmpty()) {
                    context.setCidFilter(cids);
                }
            }
        }

        if (PrintScenario.SHIFT.equals(scenario)) {
            Shift shift = null;
            if (shiftService != null) {
                if (request.getShiftId() != null) {
                    shift = shiftService.getById(request.getShiftId());
                } else {
                    shift = shiftService.getOne(new QueryWrapper<Shift>()
                            .eq("shop_id", effectiveShopId)
                            .orderByDesc("id")
                            .last("LIMIT 1"));
                }
            }
            if (shift != null) {
                if (shift.getShop_id() != null && !Integer.valueOf(effectiveShopId).equals(shift.getShop_id())) {
                    throw new ApiException(403, "SHIFT_FORBIDDEN", "班次不属于当前门店");
                }
                context.setShift(shift);
                context.getExtra().put("orderCount", shift.getOrder_count());
                context.getExtra().put("totalAmount", shift.getTotal_amount());
            }
        }

        if (hasCustomContent) {
            context.setCustomContent(request.getCustomContent().trim());
        }

        // 覆写配置项
        if (request.getDeviceId() != null) {
            if (deviceMapper != null) {
                PrintingDevice dev = deviceMapper.selectById(request.getDeviceId());
                if (dev == null || !Integer.valueOf(effectiveShopId).equals(dev.getShop_id())) {
                    throw new ApiException(404, "DEVICE_NOT_FOUND", "指定打印设备不存在或不属于当前门店");
                }
            }
            context.getExtra().put("target_device_id", request.getDeviceId());
        }

        if (request.getTemplateId() != null && request.getTemplateId() > 0) {
            context.getExtra().put("template_id_override", request.getTemplateId());
        }

        if (request.getCopies() != null && request.getCopies() >= 1 && request.getCopies() <= 9) {
            context.getExtra().put("copies_override", request.getCopies());
        }

        // 补打元数据组装
        context.getExtra().put("is_reprint", isReprint);
        if (isReprint) {
            context.getExtra().put("reprint_badge", "【补打】");
            String opName = "系统";
            if (operatorAdminId != null && adminService != null) {
                String resolved = AdminNameResolver.resolveDisplayName(operatorAdminId, adminService);
                if (StringUtils.hasText(resolved)) {
                    opName = resolved;
                }
            }
            context.getExtra().put("reprint_operator", opName);
            context.getExtra().put("reprint_time", LocalDateTime.now().format(TIME_FMT));
        }

        if (StringUtils.hasText(request.getReason())) {
            context.getExtra().put("reason", request.getReason().trim());
            context.getExtra().put("reprint_reason", request.getReason().trim());
        }

        // 6. 执行派发
        List<PrintDispatchResult> results = printDispatcherService.dispatch(effectiveShopId, scenario, context);
        if (results == null) {
            results = Collections.emptyList();
        }

        // 7. 汇总下发结果
        List<UnifiedPrintResponse.JobItem> jobItems = new ArrayList<>();
        int successCount = 0;
        int failedCount = 0;

        for (PrintDispatchResult r : results) {
            boolean success = r.isSuccess();
            if (success) {
                successCount++;
            } else {
                failedCount++;
            }
            jobItems.add(UnifiedPrintResponse.JobItem.builder()
                    .jobId(r.getJobId())
                    .deviceId(r.getDeviceId())
                    .deviceName(r.getDeviceName())
                    .transport(r.getTransport())
                    .status(r.getStatus())
                    .success(success)
                    .error(r.getError())
                    .build());
        }

        String summary;
        if (jobItems.isEmpty()) {
            summary = "当前场景未配置生效的打印规则或打印设备";
        } else if (failedCount == 0) {
            summary = String.format("成功下发 %d 个打印任务", successCount);
        } else {
            summary = String.format("下发完成: %d 成功, %d 失败", successCount, failedCount);
        }

        return UnifiedPrintResponse.builder()
                .orderNo(order != null ? order.getOrder_no() : request.getOrderNo())
                .scenario(scenario)
                .scenarioName(PrintScenario.displayName(scenario))
                .isReprint(isReprint)
                .jobCount(jobItems.size())
                .successCount(successCount)
                .failedCount(failedCount)
                .summary(summary)
                .jobs(jobItems)
                .build();
    }
}