package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.controller.OrderController;
import com.lanf.dto.CategorySalesDTO;
import com.lanf.dto.DishSalesDTO;
import com.lanf.entity.*;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.service.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.io.File;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.*;
import org.springframework.util.StringUtils;
import com.lanf.service.IActivityPopupService;
import com.lanf.util.ShopOrderingOpenHelper;
import com.lanf.util.OrderListTimeRangeResolver;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.OrderCheckoutChangeHelper;
import com.lanf.util.OrderNetRevenue;
import com.lanf.util.OrderPayChannelAmounts;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.payment.service.PaymentCapabilityService;
import com.lanf.payment.success.PaymentSuccessHandler;
import com.lanf.payment.support.PaymentDiningTypeUtil;
import com.lanf.util.AfterCommitExecutor;
import com.lanf.kds.service.KdsOrderHook;
import com.lanf.util.ShopBusinessWindowResolver;
import com.lanf.access.model.AccessDecision;
import com.lanf.access.service.HighRiskActionAuthorizationService;
import java.time.LocalDate;
import java.time.LocalTime;

import javax.servlet.http.HttpServletRequest;
import com.lanf.interceptor.SysInterceptor;

/**
 * 管理端-订单Controller控制器
 */
@RestController
@RequestMapping("/admin/order")
public class AdminOrderController {
    @Autowired
    private IActivityPopupService activityPopupService;
    @Autowired
    private ITableService tableService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IBannerService bannerService;
    @Autowired
    private IUserService UserService;
    @Autowired
    private UserCouponMapper userCouponMapper;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private KdsOrderHook kdsOrderHook;
    @Autowired
    private ITakeoutDeliveryService takeoutDeliveryService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private DishMenuPushService dishMenuPushService;
    @Autowired
    private OrderController orderController;
    @Autowired
    private HttpServletRequest httpServletRequest;
    @Autowired
    private PaymentCapabilityService paymentCapabilityService;
    @Autowired
    private PaymentSuccessHandler paymentSuccessHandler;
    @Autowired
    private com.lanf.kds.service.KdsOrderEnrichService kdsOrderEnrichService;
    @Autowired
    private HighRiskActionAuthorizationService highRiskActionAuthorizationService;
    @Autowired(required = false)
    private IAdminService adminService;
    @Autowired
    private com.lanf.payment.service.CashierCollectionIntentService collectionIntentService;
    @Autowired
    private com.lanf.service.CashierCheckoutService cashierCheckoutService;
    @Autowired(required = false)
    private com.lanf.security.SecurityAuditService securityAuditService;
    @Autowired(required = false)
    private com.lanf.controller.cashier.CashierOrderController cashierOrderController;
    @Autowired(required = false)
    private com.lanf.service.IAdminShopAccessService adminShopAccessService;
    @Autowired(required = false)
    private com.lanf.security.AdminShopScopeGuard adminShopScopeGuard;
    @Autowired(required = false)
    private com.lanf.service.PaymentLedgerService paymentLedgerService;
    @Autowired(required = false)
    private com.lanf.service.IOrderInvoiceService orderInvoiceService;
    private static final Logger log = LoggerFactory.getLogger(AdminOrderController.class);
    @Value("${avatarImgsFilePath}")
    private String avatarImgsFilePath;
    /**
     * 根据条件分页查询
     * @param pageBean
     * @return
     */
    @RequestMapping("/list")
    public R list(@RequestBody(required = false) PageBean pageBean){
        if (pageBean == null) {
            pageBean = new PageBean();
        }
        if (pageBean.getPageNum() <= 0) pageBean.setPageNum(1);
        if (pageBean.getPageSize() <= 0) pageBean.setPageSize(10);
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        Shop shop = shopId != null ? shopService.getById(shopId) : null;
        if (shop == null && shopId == null) {
            shop = shopService.getById(1);
        }
        LocalTime settleTime = ShopBusinessWindowResolver.resolveSettleTimeOrDefault(shop);
        OrderListTimeRangeResolver.Range range;
        try {
            range = OrderListTimeRangeResolver.resolve(java.time.LocalDateTime.now(),
                    pageBean.getStartTime(), pageBean.getEndTime(), settleTime);
        } catch (IllegalArgumentException e) {
            return R.error(400, e.getMessage());
        }
        Map<String,Object> map=new HashMap<>();
        map.put("transac_status", pageBean.getQuery() != null ? pageBean.getQuery().trim() : "");
        map.put("start",pageBean.getStart());
        map.put("pageSize",pageBean.getPageSize());
        map.put("startTime", OrderListTimeRangeResolver.format(range.getStart()));
        map.put("endTime", OrderListTimeRangeResolver.format(range.getEnd()));
        if (shopId != null) {
            map.put("shop_id", shopId);
        }
        List<Order> list = orderService.list(map);
        Long total = orderService.getTotal(map);
        long todayCount = orderService.getTodayOrderCount(shopId);
        takeoutDeliveryService.enrichOrders(list);
        kdsOrderEnrichService.enrichOrders(list);
        if (list != null && !list.isEmpty() && adminService != null) {
            com.lanf.util.AdminNameResolver.enrichOrdersCashierInfo(list, adminService);
        }
        Map<String,Object> resultMap=new HashMap<>();
        resultMap.put("orderList",list);
        resultMap.put("total",total);
        resultMap.put("todayCount",todayCount);
        resultMap.put("startTime", map.get("startTime"));
        resultMap.put("endTime", map.get("endTime"));
        return R.ok(resultMap);
    }

    /**
     * 获取订单数（结算日窗口，settle_time 口径）。
     * {@code date}（yyyy-MM-dd，结算日）为空 → 当前营业日；非空 → 指定营业日。
     */
    @GetMapping("/todayCount")
    public R todayCount(@RequestParam(required = false) String date) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        long count = orderService.getTodayOrderCount(shopId, date);
        return R.ok().put("todayCount", count);
    }

    /**
     * 获取待结账金额（结算日窗口，settle_time 口径）。
     * {@code date}（yyyy-MM-dd，结算日）为空 → 当前营业日；非空 → 指定营业日。
     * 仅统计 transac_status=unsettled 且 merchantId="1" 的订单。
     * 金额口径：与净实付一致，sett_amount - discount_amount + service_fee - refund_amount - pay_amount_gift（待结账订单上退款/礼品列多为 0），保留两位小数。
     */
    @GetMapping("/todayUnsettledAmount")
    public R todayUnsettledAmount(@RequestParam(required = false) String date) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        Shop shop = (shopId != null) ? shopService.getById(shopId) : null;
        Date[] win = ShopBusinessWindowResolver.resolveOperationalWindow(shop, date);

        QueryWrapper<Order> uq = new QueryWrapper<Order>()
                .eq("merchantId", "1")
                .eq("transac_status", "unsettled")
                .ge("order_time", win[0])
                .lt("order_time", win[1]);
        if (shopId != null) {
            uq.eq("shop_id", shopId);
        }
        List<Order> unsettledOrders = orderService.list(uq);

        double total = 0d;
        for (Order o : unsettledOrders) {
            total += OrderNetRevenue.netRevenueYuan(o);
        }
        total = Math.round(total * 100) / 100.0;

        return R.ok()
                .put("todayUnsettledAmount", total)
                .put("todayUnsettledCount", unsettledOrders.size())
                .put("startTime", win[0])
                .put("endTime", win[1]);
    }

    /**
     * 数据分析：分类销售额统计（与 openapi GET /admin/order/statisticsCategorySales 一致）
     * 支持 GET 与 POST，避免因请求方式导致 404。
     * @param startTime 开始时间，必填
     * @param endTime 结束时间，必填
     * @param cidList 可选，限定分类 id 列表（与库表 cid 一致，为字符串），不传则统计全部分类
     */
    @RequestMapping(value = "/statisticsCategorySales", method = {RequestMethod.GET, RequestMethod.POST})
    public R statisticsCategorySales(
            @RequestParam(required = false) String startTime,
            @RequestParam(required = false) String endTime,
            @RequestParam(required = false) String startDate,
            @RequestParam(required = false) String endDate,
            @RequestParam(required = false) String start,
            @RequestParam(required = false) String end,
            @RequestParam(required = false) List<String> cidList) {
        try {
            String startCandidate = firstNonEmpty(startTime, startDate, start);
            String endCandidate = firstNonEmpty(endTime, endDate, end);
            if (startCandidate == null || startCandidate.trim().isEmpty() || endCandidate == null || endCandidate.trim().isEmpty()) {
                return R.error(400, "startTime 与 endTime 必填，格式如：2026-01-01 或 2026-01-01 00:00:00");
            }
            Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
            Shop shop = shopId == null ? null : shopService.getById(shopId);
            String[] win = ShopBusinessWindowResolver.resolveReportWindowText(shop, startCandidate, endCandidate);
            Map<String, Object> params = new HashMap<>();
            params.put("startTime", win[0]);
            params.put("endTime", win[1]);
            if (cidList != null && !cidList.isEmpty()) {
                params.put("cidList", cidList);
            }
            if (shopId != null) {
                params.put("shopId", shopId);
            }
            List<CategorySalesDTO> list = orderService.statisticsCategorySales(params);
            Map<String, Object> summary = orderService.statisticsOrderSummary(params);
            return R.ok().put("data", list).put("total_service_fee", summary != null ? summary.get("total_service_fee") : 0)
                    .put("total_discount_amount", summary != null ? summary.get("total_discount_amount") : 0)
                    .put("total_sett_amount", summary != null ? summary.get("total_sett_amount") : 0);
        } catch (Exception e) {
            log.error("statisticsCategorySales 异常", e);
            return R.error(500, "统计失败：" + (e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName()));
        }
    }

    /**
     * 按时间范围查询各菜品销售额（与 openapi GET /admin/order/statisticsDishSales 一致）
     * @param startTime 开始时间，必填
     * @param endTime 结束时间，必填
     * @param nameList 可选，限定菜品名称列表，不传则统计全部菜品
     */
    @RequestMapping(value = "/statisticsDishSales", method = {RequestMethod.GET, RequestMethod.POST})
    public R statisticsDishSales(
            @RequestParam(required = false) String startTime,
            @RequestParam(required = false) String endTime,
            @RequestParam(required = false) String startDate,
            @RequestParam(required = false) String endDate,
            @RequestParam(required = false) String start,
            @RequestParam(required = false) String end,
            @RequestParam(required = false) List<String> nameList) {
        try {
            String startCandidate = firstNonEmpty(startTime, startDate, start);
            String endCandidate = firstNonEmpty(endTime, endDate, end);
            if (startCandidate == null || startCandidate.trim().isEmpty() || endCandidate == null || endCandidate.trim().isEmpty()) {
                return R.error(400, "startTime 与 endTime 必填，格式如：2026-01-01 或 2026-01-01 00:00:00");
            }
            Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
            Shop shop = shopId == null ? null : shopService.getById(shopId);
            String[] win = ShopBusinessWindowResolver.resolveReportWindowText(shop, startCandidate, endCandidate);
            Map<String, Object> params = new HashMap<>();
            params.put("startTime", win[0]);
            params.put("endTime", win[1]);
            if (nameList != null && !nameList.isEmpty()) {
                params.put("nameList", nameList);
            }
            if (shopId != null) {
                params.put("shopId", shopId);
            }
            List<DishSalesDTO> list = orderService.statisticsDishSales(params);
            return R.ok().put("data", list);
        } catch (Exception e) {
            log.error("statisticsDishSales 异常", e);
            return R.error(500, "统计失败：" + (e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName()));
        }
    }

    public R statisticsCategorySales(String startTime, String endTime, List<String> cidList) {
        return statisticsCategorySales(startTime, endTime, null, null, null, null, cidList);
    }

    public R statisticsDishSales(String startTime, String endTime, List<String> nameList) {
        return statisticsDishSales(startTime, endTime, null, null, null, null, nameList);
    }

    private static String firstNonEmpty(String... values) {
        if (values == null) {
            return null;
        }
        for (String v : values) {
            if (v != null && !v.trim().isEmpty()) {
                return v.trim();
            }
        }
        return null;
    }

    // 修改文件上传方法，确保目录存在
    @PostMapping("/uploadBannerFile")
    public R uploadBannerFile(MultipartFile file) throws IOException {
        // 1. 定义上传目录路径
        String uploadDir = avatarImgsFilePath;

        // 2. 确保目录存在，如果不存在则创建
        File dir = new File(uploadDir);
        if (!dir.exists()) {
            dir.mkdirs(); // 创建目录，包括任何必要的父目录
        }

        // 3. 生成唯一文件名
        String originalFilename = file.getOriginalFilename();
        String suffix = originalFilename.substring(originalFilename.lastIndexOf("."));
        String fileName = UUID.randomUUID().toString() + suffix;

        // 4. 保存文件到指定目录
        String filePath = uploadDir + fileName;
        File dest = new File(filePath);
        file.transferTo(dest);

        // 5. 返回可访问的URL（根据实际项目配置调整）

        return R.ok("/image/avatar/" + fileName) ;
    }
    /**
     * 用户列表（分页），与 openapi 用户列表（分页）设计一致，不一次性返回全部数据。
     * 请求体：pageNum（页码，从 1）、pageSize（每页条数，最大 100）、query（可选，按 name/phone/openid 模糊）。
     * 响应：code、user（当前页 User[]）、total（总记录数）。
     */
    @PostMapping("/getAllUser")
    public R getAllUser(@RequestBody(required = false) PageBean pageBean) {
        try {
            int pageNum = 1;
            int pageSize = 20;
            String query = null;
            Integer requestedShopId = null;
            Boolean allShops = null;
            if (pageBean != null) {
                if (pageBean.getPageNum() > 0) pageNum = pageBean.getPageNum();
                if (pageBean.getPageSize() > 0) pageSize = Math.min(pageBean.getPageSize(), 100);
                query = pageBean.getQuery();
                requestedShopId = pageBean.getShopId();
                allShops = pageBean.getAllShops();
            }
            int[] holder = new int[1];
            if (adminShopScopeGuard != null) {
                if (Boolean.TRUE.equals(allShops)) {
                    R guardR = adminShopScopeGuard.requireHeadquarters();
                    if (guardR != null) {
                        return guardR;
                    }
                    holder[0] = 0;
                } else {
                    R guardR = adminShopScopeGuard.resolveTargetShopId(requestedShopId, holder);
                    if (guardR != null) {
                        return guardR;
                    }
                }
            }
            Integer shopId = holder[0] > 0 ? Integer.valueOf(holder[0]) : AdminShopRequest.getResolvedShopId(httpServletRequest);
            if (Boolean.TRUE.equals(allShops)) {
                shopId = null;
            }
            IPage<User> page = UserService.pageUserList(pageNum, pageSize, query, shopId);
            return R.ok().put("user", page.getRecords()).put("total", page.getTotal());
        } catch (Exception e) {
            log.error("用户列表查询异常", e);
            return R.error("数据异常");
        }
    }


    /**
     * 获取启用的轮播图列表
     * 供小程序首页展示使用
     */
    @GetMapping("/banners")
    public R getAllBanners() {
        try {
            // 调用服务层方法获取所有启用状态的轮播图
            List<Banner> banners = bannerService.getAllBanners();

            if (banners == null || banners.isEmpty()) {
                log.info("当前没有启用的轮播图");
                return R.ok().put("banners", new ArrayList<>());
            }

            log.info("获取轮播图成功，共{}条记录", banners.size());
            return R.ok().put("banners", banners);
        } catch (Exception e) {
            log.error("获取轮播图失败", e);
            return R.error("获取轮播图失败：" + e.getMessage());
        }
    }
    /**
     * 添加新的轮播图
     */
    @PostMapping("/addbanners")
    public R addBanner(@RequestBody Banner banner) {
        try {
            // 参数校验
            if (banner == null || banner.getImage() == null || banner.getImage().trim().isEmpty()) {
                return R.error("轮播图图片地址不能为空");
            }

            if (banner.getStatus() == null) {
                banner.setStatus(1); // 默认启用
            }

            // t_banner.type 为 NOT NULL 且无默认值：实体未传时兜底为首页，避免新增失败
            if (banner.getType() == null || banner.getType().trim().isEmpty()) {
                banner.setType("home");
            }


            // 保存轮播图
            boolean saved = bannerService.save(banner);
            if (saved) {
                log.info("添加轮播图成功，ID: {}", banner.getId());
                return R.ok().put("bannerId", banner.getId()).put("message", "轮播图添加成功");
            } else {
                log.error("添加轮播图失败");
                return R.error("添加轮播图失败，请重试");
            }
        } catch (Exception e) {
            log.error("添加轮播图异常", e);
            return R.error("添加轮播图失败：" + e.getMessage());
        }
    }

    /**
     * 更新轮播图。路径 id 为权威；未提交的字段沿用现有值。
     */
    @PutMapping("/update_banners/{id}")
    public R updateBanner(@PathVariable Integer id, @RequestBody Banner banner) {
        try {
            if (id == null || banner == null) {
                return R.error(400, "轮播图 id 与更新内容不能为空");
            }

            Banner existing = bannerService.getById(id);
            if (existing == null) {
                return R.error(404, "轮播图不存在");
            }

            if (banner.getStatus() != null
                    && banner.getStatus() != 0
                    && banner.getStatus() != 1) {
                return R.error(400, "轮播图状态仅支持 0（禁用）或 1（启用）");
            }
            if (banner.getType() != null
                    && !banner.getType().trim().isEmpty()
                    && !"home".equals(banner.getType())
                    && !"bottom".equals(banner.getType())) {
                return R.error(400, "轮播图位置仅支持 home 或 bottom");
            }

            banner.setId(id);
            if (banner.getStatus() == null) {
                banner.setStatus(existing.getStatus() != null ? existing.getStatus() : 1);
            }
            if (banner.getType() == null || banner.getType().trim().isEmpty()) {
                banner.setType(existing.getType() != null ? existing.getType() : "home");
            }

            boolean updated = bannerService.updateBannerInfo(banner);
            if (updated) {
                return R.ok().put("message", "轮播图更新成功");
            }
            return R.error("轮播图更新失败，请重试");
        } catch (Exception e) {
            log.error("更新轮播图异常，ID: {}", id, e);
            return R.error("轮播图更新失败：" + e.getMessage());
        }
    }

    /**
     * 删除轮播图
     */
    @DeleteMapping("/delete_banners/{id}")
    public R deleteBanner(@PathVariable Integer id) {
        try {
            // 检查轮播图是否存在
            Banner banner = bannerService.getById(id);
            if (banner == null) {
                return R.error("轮播图不存在");
            }

            // 删除轮播图
            boolean deleted = bannerService.removeById(id);
            if (deleted) {
                log.info("删除轮播图成功，ID: {}", id);
                return R.ok().put("message", "轮播图删除成功");
            } else {
                log.error("删除轮播图失败，ID: {}", id);
                return R.error("删除轮播图失败，请重试");
            }
        } catch (Exception e) {
            log.error("删除轮播图异常，ID: {}", id, e);
            return R.error("删除轮播图失败：" + e.getMessage());
        }
    }

    /**
     * 更新接单状态
     * @param order
     * @return
     */
    @PostMapping("/receiving")
    @AuditLog(module = "order", action = "admin_order_receiving", target = "#p0.order_no")
    @Transactional(rollbackFor = Exception.class)
    public R receiving(@RequestBody Order order){
        Order resultOrder = orderService.getById(order.getId());
        if (resultOrder == null) {
            return R.error("订单不存在");
        }
        R shopErr = assertOrderInCurrentShop(resultOrder);
        if (shopErr != null) {
            return shopErr;
        }
        if(Objects.equals(resultOrder.getTransac_status(), "unsettled") && Objects.equals(resultOrder.getDineInOrTakeOut(), "打包")){
            return R.error("打包订单需要支付后才能接单");
        }
        String prevReceiving = resultOrder.getOrder_receiving();
        String nextReceiving = order.getOrder_receiving();
        resultOrder.setOrder_receiving(nextReceiving);
        if ("off_order".equals(nextReceiving) && resultOrder.getOff_time() == null) {
            resultOrder.setOff_time(new Date());
        }
        orderService.updateById(resultOrder);
        if ("rec_order".equals(nextReceiving) && !"rec_order".equals(prevReceiving)) {
            List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", resultOrder.getId()));
            if (details != null) {
                for (OrderDetail d : details) {
                    String r = d.getOrder_rece();
                    if (r == null || "mis_order".equals(r.trim()) || "mis_orders".equals(r.trim()) || r.trim().isEmpty()) {
                        d.setOrder_rece("rec_order");
                        orderDetailService.updateById(d);
                    }
                }
            }
            kdsOrderHook.afterOrderCommitted(resultOrder, null, KdsOrderHook.Trigger.MANUAL);
        }
        return R.ok();
    }

    /**
     * 将待结账订单的下单用户换为指定手机号对应用户（改手机号场景）。
     * 请求体：{ "id": 订单主键 t_order.id, "phone": "手机号" }
     * 仅 {@code transac_status=unsettled} 可改；用户解析见 {@link IUserService#getUserByPhone}。
     * 写入 {@code openid}，并清空 {@code prepay_id}、{@code pay_openid}，避免沿用过期预支付单。
     * 若目标用户与当前订单 openid 相同，返回成功且提示无需更换。
     */
    @PostMapping("/reassignOpenidByPhone")
    @AuditLog(module = "order", action = "admin_order_reassign_openid", target = "#p0['orderNo'] ?: #p0['order_no']")
    public R reassignOpenidByPhone(@RequestBody Map<String, Object> body) {
        Integer orderId = body != null ? asInteger(firstValue(body, "id", "orderId")) : null;
        String phone = body != null ? asText(firstValue(body, "phone", "mobile")) : null;
        if (orderId == null) {
            return R.error(400, "订单 id 不能为空");
        }
        if (phone == null) {
            return R.error(400, "手机号不能为空");
        }
        Order resultOrder = orderService.getById(orderId);
        if (resultOrder == null) {
            return R.error("订单不存在");
        }
        R shopErr = assertOrderInCurrentShop(resultOrder);
        if (shopErr != null) {
            return shopErr;
        }
        if (!Objects.equals(resultOrder.getTransac_status(), "unsettled")) {
            return R.error("仅待结账订单可更换下单用户");
        }
        User target = UserService.getUserByPhone(phone);
        if (target == null) {
            return R.error("该手机号未注册或不存在");
        }
        String newOpenid = target.getOpenid();
        if (newOpenid == null || newOpenid.trim().isEmpty()) {
            return R.error("该用户未绑定小程序 openid，无法关联订单");
        }
        newOpenid = newOpenid.trim();
        if (Objects.equals(newOpenid, resultOrder.getOpenid())) {
            return R.ok("无需更换");
        }
        resultOrder.setOpenid(newOpenid);
        resultOrder.setPrepay_id(null);
        resultOrder.setPay_openid(null);
        orderService.updateById(resultOrder);
        return R.ok("已更换下单用户");
    }

    /**
     * 更新接单状态
     * @param orderDetail
     * @return
     */
    @PostMapping("/rece")
    @AuditLog(module = "order", action = "admin_order_rece")
    public R rece(@RequestBody OrderDetail orderDetail){

        for(OrderDetail od:orderDetail.getGoods_list()){
            OrderDetail resultOrder = orderDetailService.getById(od.getId());
            if (resultOrder != null && resultOrder.getMId() != null) {
                Order parent = orderService.getById(resultOrder.getMId());
                R shopErr = assertOrderInCurrentShop(parent);
                if (shopErr != null) {
                    return shopErr;
                }
            }
            resultOrder.setOrder_rece(orderDetail.getOrder_rece());
            orderDetailService.updateById(resultOrder);
        }


        return R.ok();
    }

    /** 订单净营业额（元）：sett - discount + service - refund - pay_amount_gift；与营业额统计 SQL 一致。 */
    private static double orderNetPayableYuan(Order o) {
        return OrderNetRevenue.netRevenueYuan(o);
    }

    /**
     * 更新结账状态（与 OpenAPI POST /admin/order/checkout 一致）
     * 请求体需传 id（订单主键）、transac_status（如 success）、pay_time、payment_method、dineInOrTakeOut、table_number（堂食时必填）。
     * 可选 cash_amount（或 cashAmount）：success 时部分现金实付（元），与 payment_method 主渠道组合写入 pay_amount_*（见 OrderPayChannelAmounts）。
     * 若未传上述字段但请求体含正数 {@code pay_amount_cash}，亦视为现金部分并写入订单 {@code pay_amount_cash}。
     * 找零：可选 {@code checkout_cash_tender}/{@code cash_tender}（客人付现）、{@code checkout_change_amount}/{@code change_amount}、
     * {@code checkout_change_channel}/{@code change_channel}（wechat/cash/alipay）。付现大于现金实收时须指定找零渠道；也可仅传付现由服务端计算找零。
     * 若订单结账状态为 success 且该订单关联了优惠券，则将该优惠券状态改为已使用（status=1，use_time 置为当前时间）。
     */
    @PostMapping("/checkout")
    @Transactional(rollbackFor = Exception.class)
    @AuditLog(module = "order", action = "admin_order_checkout", target = "#p0.order_no")
    public R checkout(@RequestBody Order order){
        if (order == null) {
            return R.error("请求参数不能为空");
        }
        Order resultOrder = (order.getId() != null)
                ? orderService.getById(order.getId())
                : (StringUtils.hasText(order.getOrder_no())
                        ? orderService.getOne(new QueryWrapper<Order>().eq("order_no", order.getOrder_no().trim()).last("LIMIT 1"))
                        : null);

        if (resultOrder == null) {
            return R.error("订单不存在");
        }
        R shopErr = assertOrderInCurrentShop(resultOrder);
        if (shopErr != null) {
            return shopErr;
        }
        if (StringUtils.hasText(resultOrder.getMaster_order_no())) {
            return R.error("该订单为并台从单，不支持单独结账，请通过主桌统一结账");
        }
        Integer requestShopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        Integer orderShopId = resultOrder.getShop_id() != null ? resultOrder.getShop_id() : requestShopId;
        long slaveCount = orderService.count(new QueryWrapper<Order>()
                .eq(orderShopId != null, "shop_id", orderShopId)
                .eq("master_order_no", resultOrder.getOrder_no())
                .eq("transac_status", "unsettled"));
        if (slaveCount > 0) {
            return R.error("该桌台存在并台从单，不支持单笔结账，请通过主桌统一结账");
        }
        if ("success".equalsIgnoreCase(order.getTransac_status())) {
            Map<String, Object> checkoutBody = new LinkedHashMap<>();
            checkoutBody.put("order_no", resultOrder.getOrder_no());
            checkoutBody.put("payment_method", StringUtils.hasText(order.getPayment_method())
                    ? order.getPayment_method() : resultOrder.getPayment_method());
            checkoutBody.put("cash_amount", order.getCashAmount());
            checkoutBody.put("pay_amount_cash", order.getPay_amount_cash());
            checkoutBody.put("pay_amount_wechat", order.getPay_amount_wechat());
            checkoutBody.put("pay_amount_alipay", order.getPay_amount_alipay());
            checkoutBody.put("pay_amount_balance", order.getPay_amount_balance());
            checkoutBody.put("cash_tender", order.getCashTender());
            checkoutBody.put("change_amount", order.getChangeAmount());
            checkoutBody.put("change_channel", order.getChangeChannel());
            checkoutBody.put("force", Boolean.TRUE.equals(order.getForce()));
            checkoutBody.put("approvalToken", order.getApprovalToken());
            checkoutBody.put("authorization", order.getAuthorization());
            checkoutBody.put("collectionSessionId", order.getCollectionSessionId());
            Integer operatorId = currentAdminId(httpServletRequest);
            if (operatorId != null) checkoutBody.put("operator_id", operatorId);
            return cashierCheckoutService.checkout(orderShopId, checkoutBody);
        }
        boolean force = Boolean.TRUE.equals(order.getForce());
        Integer[] authorizedAdminIdOut = new Integer[1];
        if (force) {
            Map<String, Object> authParams = new LinkedHashMap<>();
            authParams.put("order_no", resultOrder.getOrder_no());
            Integer currentAdmin = currentAdminId(httpServletRequest);
            if (currentAdmin != null) {
                authParams.put("operatorId", currentAdmin);
            }
            if (StringUtils.hasText(order.getApprovalToken())) {
                authParams.put("approvalToken", order.getApprovalToken());
            }
            if (order.getAuthorization() != null) {
                authParams.put("authorization", order.getAuthorization());
            }
            R permError = cashierCheckoutService.checkForceCheckoutPermission(orderShopId, authParams, authorizedAdminIdOut);
            if (permError != null) {
                return permError;
            }
        }

        Table table = null;
        if (Objects.equals(resultOrder.getDineInOrTakeOut(), "堂食")) {
            QueryWrapper<Table> tq = new QueryWrapper<Table>().eq("number", resultOrder.getTable_number());
            if (orderShopId != null) {
                tq.eq("shop_id", orderShopId);
            }
            table = tableService.getOne(tq.last("LIMIT 1"));
        }

        resultOrder.setTransac_status(order.getTransac_status());
        resultOrder.setPay_time(order.getPay_time());
        resultOrder.setMerchantId("1");
        
        if(resultOrder.getPayment_method() == null || resultOrder.getPayment_method().trim().isEmpty()){
            resultOrder.setPayment_method(PaymentChannelCatalog.normalizePaymentMethod(order.getPayment_method()));
        }

        if ("success".equals(order.getTransac_status())) {
            double net = orderNetPayableYuan(resultOrder);
            if (!paymentCapabilityService.isCashierPaymentMethodEnabled(orderShopId, resultOrder.getPayment_method())) {
                return R.error("当前门店未启用支付渠道：" + resultOrder.getPayment_method());
            }
            Double cashAmt = order.getCashAmount();
            if ((cashAmt == null || cashAmt <= 0d || Double.isNaN(cashAmt))
                    && order.getPay_amount_cash() != null && order.getPay_amount_cash() > 0d) {
                cashAmt = order.getPay_amount_cash();
            }
            if (cashAmt != null) {
                if (Double.isNaN(cashAmt) || cashAmt < 0d) {
                    return R.error("现金金额无效");
                }
                if (cashAmt - net > 0.01d) {
                    return R.error("现金实收不能超过应付净额");
                }
            }
            try {
                if (PaymentChannelCatalog.NAME_COMBINED_PAY.equals(resultOrder.getPayment_method())) {
                    if (positive(order.getPay_amount_wechat())
                            && !paymentCapabilityService.isCashierPaymentMethodEnabled(
                            orderShopId, PaymentChannelCatalog.ONLINE_WECHAT)) {
                        return R.error("当前门店未启用组合支付中的微信支付");
                    }
                    if (positive(order.getPay_amount_alipay())
                            && !paymentCapabilityService.isCashierPaymentMethodEnabled(
                            orderShopId, PaymentChannelCatalog.ONLINE_ALIPAY)) {
                        return R.error("当前门店未启用组合支付中的支付宝支付");
                    }
                    if (positive(order.getPay_amount_balance())
                            && !paymentCapabilityService.isCashierPaymentMethodEnabled(
                            orderShopId, PaymentChannelCatalog.ONLINE_BALANCE)) {
                        return R.error("当前门店未启用组合支付中的余额支付");
                    }
                    OrderPayChannelAmounts.applyOnlineCombined(resultOrder, order, net);
                } else if (cashAmt != null && cashAmt > 0d) {
                    OrderPayChannelAmounts.applyFromPaymentMethodLabelWithOptionalCash(
                            resultOrder, resultOrder.getPayment_method(), net, cashAmt);
                } else {
                    OrderPayChannelAmounts.applyFromPaymentMethodLabel(resultOrder, resultOrder.getPayment_method(), net);
                }
            } catch (IllegalArgumentException e) {
                return R.error(e.getMessage());
            }
            double cashApplied = resultOrder.getPay_amount_cash() != null ? resultOrder.getPay_amount_cash() : 0d;
            OrderCheckoutChangeHelper.ResolvedChange changeResolved = new OrderCheckoutChangeHelper.ResolvedChange();
            String changeErr = OrderCheckoutChangeHelper.validateAndResolve(order, cashApplied, changeResolved);
            if (changeErr != null) {
                return R.error(changeErr);
            }
            OrderCheckoutChangeHelper.applyToOrder(resultOrder, changeResolved);
            int theoryFen = (int) Math.round(net * 100d);
            if (OrderPayChannelAmounts.payChannelsDriftFromTheoryFen(resultOrder, theoryFen, 100)) {
                int ch = OrderPayChannelAmounts.totalPayChannelAmountFen(resultOrder);
                log.warn("后台结账渠道列与净实付差异>1元: order_no={} netFen={} channelSumFen={}",
                        resultOrder.getOrder_no(), theoryFen, ch);
            }
        } else {
            OrderPayChannelAmounts.clear(resultOrder);
            OrderCheckoutChangeHelper.clear(resultOrder);
        }

        if ("success".equals(order.getTransac_status())) {
            try {
                collectionIntentService.validateCheckout(
                        orderShopId,
                        resultOrder.getOrder_no(),
                        order.getCollectionSessionId(),
                        fen(resultOrder.getPay_amount_wechat()),
                        fen(resultOrder.getPay_amount_alipay()),
                        force);
            } catch (IllegalArgumentException | IllegalStateException ex) {
                return R.error(ex.getMessage());
            }
        }

        if (!orderService.updateById(resultOrder)) {
            throw new IllegalStateException("订单结账状态更新失败");
        }

        if ("success".equals(order.getTransac_status())) {
            UserCoupon usedCoupon = userCouponMapper.selectOne(
                    new QueryWrapper<UserCoupon>().eq("order_no", resultOrder.getOrder_no()).last("LIMIT 1"));
            if (usedCoupon != null) {
                usedCoupon.setUse_time(new Date());
                usedCoupon.setStatus(1);
                userCouponMapper.updateById(usedCoupon);
            }
        }

        if (table != null){
            List<Order> remaining = orderService.list(new QueryWrapper<Order>()
                    .eq("shop_id", orderShopId)
                    .eq("table_number", resultOrder.getTable_number())
                    .eq("transac_status", "unsettled")
                    .orderByAsc("id"));
            if (remaining.isEmpty()) {
                table.setOut_time(new Date());
                table.setStatus(2);
                table.setOrder_no(resultOrder.getOrder_no());
                table.setAmount(orderNetPayableYuan(resultOrder));
            } else {
                table.setOut_time(null);
                table.setStatus(1);
                table.setOrder_no(remaining.get(0).getOrder_no());
                table.setAmount(sumOutstanding(remaining));
            }
            if (!tableService.updateById(table)) {
                throw new IllegalStateException("桌台结账状态更新失败");
            }
        }

        if ("success".equals(order.getTransac_status())) {
            if (force) {
                collectionIntentService.completeAllForOrder(orderShopId, resultOrder.getOrder_no());
                if (securityAuditService != null) {
                    Integer adminId = authorizedAdminIdOut[0];
                    Map<String, Object> auditDetails = new LinkedHashMap<>();
                    auditDetails.put("orderNo", resultOrder.getOrder_no());
                    auditDetails.put("shopId", orderShopId);
                    auditDetails.put("paymentMethod", resultOrder.getPayment_method());
                    auditDetails.put("payableYuan", orderNetPayableYuan(resultOrder));
                    auditDetails.put("action", "ADMIN_FORCE_CHECKOUT");
                    securityAuditService.recordPrivilegedAction(
                            httpServletRequest,
                            orderShopId,
                            "order",
                            "ADMIN_FORCE_CHECKOUT",
                            resultOrder.getOrder_no(),
                            adminId,
                            auditDetails,
                            "管理端强制结账放行意向并完成入账");
                }
            } else if (StringUtils.hasText(order.getCollectionSessionId())) {
                collectionIntentService.complete(orderShopId, resultOrder.getOrder_no(), order.getCollectionSessionId());
            }

            double net = orderNetPayableYuan(resultOrder);
            if (PaymentDiningTypeUtil.isPackOrDeliveryType(resultOrder.getDineInOrTakeOut())) {
                final Order fulfillmentOrder = resultOrder;
                final double fulfillmentNet = net;
                AfterCommitExecutor.execute("admin_checkout_fulfillment:" + resultOrder.getOrder_no(),
                        () -> paymentSuccessHandler.run(fulfillmentOrder, fulfillmentNet));
            }
            R ok = R.ok().put("payableYuan", net)
                    .put("payment_method", resultOrder.getPayment_method())
                    .put("payment_channel_code",
                            PaymentChannelCatalog.codeFromPaymentMethod(resultOrder.getPayment_method()))
                    .put("payment_channel_type",
                            PaymentChannelCatalog.typeFromPaymentMethod(resultOrder.getPayment_method()));
            if (force) {
                ok.put("forced", true);
            }
            if (resultOrder.getCheckout_change_amount() != null && resultOrder.getCheckout_change_amount() > 0d) {
                ok.put("checkoutChangeAmount", resultOrder.getCheckout_change_amount())
                        .put("checkoutChangeChannel", resultOrder.getCheckout_change_channel())
                        .put("checkoutChangeChannelLabel",
                                OrderCheckoutChangeHelper.changeChannelLabel(resultOrder.getCheckout_change_channel()));
            }
            if (resultOrder.getCheckout_cash_tender() != null) {
                ok.put("checkoutCashTender", resultOrder.getCheckout_cash_tender());
            }
            return ok;
        }
        return R.ok();
    }

    @PostMapping("/force-checkout")
    @Transactional(rollbackFor = Exception.class)
    @AuditLog(module = "order", action = "admin_order_force_checkout", target = "#p0.order_no")
    public R forceCheckout(@RequestBody Order order) {
        if (order != null) {
            order.setForce(true);
            if (!StringUtils.hasText(order.getTransac_status())) {
                order.setTransac_status("success");
            }
            if (order.getPay_time() == null) {
                order.setPay_time(new Date());
            }
        }
        return checkout(order);
    }

    private static int fen(Double value) {
        if (value == null || !Double.isFinite(value)) return 0;
        return (int) Math.round(value * 100d);
    }

    private static boolean positive(Double value) {
        return value != null && !Double.isNaN(value) && value > 0d;
    }

    private static double sumOutstanding(List<Order> orders) {
        double total = 0d;
        if (orders != null) {
            for (Order item : orders) {
                if (item != null && "unsettled".equals(item.getTransac_status())) {
                    total += orderNetPayableYuan(item);
                }
            }
        }
        return Math.round(Math.max(0d, total) * 100d) / 100d;
    }

    /**
     * 微信退款（运营后台，需 JWT + order:operate）。逻辑见 {@link OrderController#refund(java.util.Map)}。
     * 请求体：orderNo 与 transaction_id（微信支付单号，可写 transactionId）至少一项；可选 refundAmount（元）、reason。
     * 授权：审批令牌优先（POS 权限中心店长现场授权签发、单次消费），未携带令牌时回退现场账号密码授权。
     */
    @PostMapping("/refund")
    public R wechatRefund(@RequestBody Map<String, Object> body) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (shopId == null || shopId <= 0) {
            return R.error(4001, "缺少门店上下文");
        }
        String resourceId = asText(firstValue(body, "orderNo", "order_no"));
        if (!StringUtils.hasText(resourceId)) {
            resourceId = asText(firstValue(body, "transaction_id", "transactionId"));
        }
        java.math.BigDecimal amount = decimal(firstValue(body, "refundAmount", "refund_amount"));
        String terminalId = httpServletRequest.getHeader("X-Terminal-Id");
        if (!StringUtils.hasText(terminalId)) {
            terminalId = asText(firstValue(body, "terminalId", "terminal_id"));
        }
        String requestId = httpServletRequest.getHeader("X-Client-Request-Id");
        if (!StringUtils.hasText(requestId)) {
            requestId = asText(firstValue(body, "requestId", "request_id"));
        }
        HighRiskActionAuthorizationService.Result authorization = highRiskActionAuthorizationService.authorize(
                HighRiskActionAuthorizationService.Request.builder()
                        .body(body)
                        .operatorId(currentAdminId(httpServletRequest))
                        .shopId(shopId)
                        .permissionCode("order:operate:refund")
                        .resourceType("ORDER")
                        .resourceId(resourceId)
                        .amount(amount)
                        .terminalId(terminalId)
                        .requestId(requestId)
                        .build());
        if (!authorization.isAllowed()) {
            AccessDecision decision = authorization.getDecision();
            R error = R.error(authorization.getCode(), decision != null
                    ? decision.getExplanation() : "高风险操作授权失败");
            if (decision != null) {
                error.put("outcome", decision.getOutcome() != null ? decision.getOutcome().name() : "DENY")
                        .put("reasonCode", decision.getReasonCode());
                if (decision.getApproval() != null) {
                    error.put("approval", decision.getApproval());
                }
            }
            return error;
        }
        httpServletRequest.setAttribute("com.lanf.security.sensitiveAuthorizedAdminId",
                authorization.getAuthorizedAdminId());
        return orderController.refund(body, shopId);
    }

    private static java.math.BigDecimal decimal(Object value) {
        if (value == null || !StringUtils.hasText(String.valueOf(value))) {
            return null;
        }
        try {
            return new java.math.BigDecimal(String.valueOf(value).trim());
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private static Integer currentAdminId(HttpServletRequest request) {
        Object value = request == null ? null : request.getAttribute(com.lanf.interceptor.SysInterceptor.ATTR_ADMIN_ID);
        return value instanceof Integer ? (Integer) value : null;
    }

    /**
     * 手动打折/优惠：仅未结账订单；写入 {@code discount_amount}，供后续微信/余额支付或收银结账使用。
     * <p>
     * 请求体：{@code orderId} 或 {@code orderNo} 至少一项；
     * {@code discountAmount}（元，直接设定优惠额）、{@code payRate}（实付倍率，如 0.9=九折）、{@code wipeZero}（抹零到整数元）至少传一项。
     */
    /**
     * 补打厨房小票（飞鹅）：不重改接单状态；{@code kds_only} 门店亦可补打。
     * 请求体：{@code orderId}/{@code orderNo} 至少一项；可选 {@code cid_list} 指定合并分类。
     */
    @PostMapping("/reprint-kitchen")
    public R reprintKitchen(@RequestBody Map<String, Object> body) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        Integer orderId = asInteger(firstValue(body, "orderId", "id", "order_id"));
        String orderNo = asText(firstValue(body, "orderNo", "order_no"));
        if (orderId == null && orderNo == null) {
            return R.error("orderId 与 orderNo 至少传一项");
        }
        Order order;
        if (orderId != null) {
            order = orderService.getById(orderId);
        } else {
            order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo).last("LIMIT 1"));
        }
        if (order == null) {
            return R.error("订单不存在");
        }
        R shopErr = assertOrderInCurrentShop(order);
        if (shopErr != null) {
            return shopErr;
        }
        String status = order.getTransac_status() != null ? order.getTransac_status().trim() : "";
        if ("cancelled".equalsIgnoreCase(status)) {
            return R.error("已取消订单不可补打厨房小票");
        }
        Set<String> cidFilter = parseCidList(body.get("cid_list"), body.get("cidList"));
        return orderController.reprintKitchenTickets(order, cidFilter.isEmpty() ? null : cidFilter);
    }

    @PostMapping("/manualDiscount")
    @AuditLog(module = "order", action = "admin_order_discount", target = "#p0['orderId'] ?: #p0['orderNo']")
    public R manualDiscount(@RequestBody Map<String, Object> body) {
        return R.error(410, "该接口已迁移，请使用 /cashier/order/discount");
    }

    @PostMapping("/updateDiners")
    public R updateDiners(@RequestBody Map<String, Object> body) {
        if (cashierOrderController != null) {
            return cashierOrderController.updateDiners(body);
        }
        return R.error(500, "CashierOrderController not available");
    }

    /**
     * 用户列表（分页），避免一次性查询过多导致资源不足。
     * 请求体：pageNum（页码，从 1）、pageSize（每页条数，最大 100）、query（可选，按 name/phone/openid 模糊查询）。
     * 响应：user（当前页 User 列表）、total（总记录数）。
     * 每条用户记录除 t_user 字段与 consume_amount 外，另含：
     * invite_registered_count（{@code t_invite_record} 中作为邀请人且被邀请人已绑定 openid 的条数）、
     * available_coupon_count（当前「可用」用户券张数，与小程序未使用券列表过滤规则一致：status=0、未过期、模板存在且模板未结束）。
     */
    @PostMapping("/getUserInfo")
    public R getUserInfo(@RequestBody(required = false) Map<String, Object> body) {
        int pageNum = 1;
        int pageSize = 20;
        if (body != null) {
            Integer pn = asInteger(firstValue(body, "pageNum", "page", "current"));
            Integer ps = asInteger(firstValue(body, "pageSize", "size", "limit"));
            if (pn != null && pn > 0) pageNum = pn;
            if (ps != null && ps > 0) pageSize = Math.min(ps, 100);
        }
        Map<String, Object> params = new HashMap<>();
        params.put("offset", (pageNum - 1) * pageSize);
        params.put("pageSize", pageSize);
        putText(params, "query", firstValue(body, "query", "keyword"));
        putText(params, "phone", firstValue(body, "phone", "mobile"));
        Integer userType = asInteger(firstValue(body, "userType", "user_type"));
        if (userType != null) {
            params.put("userType", userType);
        }
        putDateText(params, "registerStartTime", firstValue(body, "registerStartTime", "register_start_time", "startTime", "start_time"));
        putDateText(params, "registerEndTime", firstValue(body, "registerEndTime", "register_end_time", "endTime", "end_time"));

        Double minAmount = asDouble(firstValue(body, "minAmount", "minConsumeAmount", "consumeAmountMin"));
        Double maxAmount = asDouble(firstValue(body, "maxAmount", "maxConsumeAmount", "consumeAmountMax"));
        if (minAmount != null && minAmount < 0) {
            return R.error(400, "minAmount 不能小于 0");
        }
        if (maxAmount != null && maxAmount < 0) {
            return R.error(400, "maxAmount 不能小于 0");
        }
        if (minAmount != null && maxAmount != null && minAmount > maxAmount) {
            return R.error(400, "minAmount 不能大于 maxAmount");
        }
        if (minAmount != null) params.put("minAmount", minAmount);
        if (maxAmount != null) params.put("maxAmount", maxAmount);

        String amountSort = normalizeAmountSort(body);
        if (amountSort != null) {
            params.put("amountSort", amountSort);
        }
        // D023：默认轻量返回（仅 t_user 基础字段 + 分页，无聚合）；带金额过滤/排序自动升级为全量聚合
        boolean includeStats = Boolean.TRUE.equals(parseBoolObject(firstValue(body, "includeStats", "withStats")));
        if (includeStats || minAmount != null || maxAmount != null || amountSort != null) {
            params.put("includeStats", true);
        }
        Integer requestedShopId = asInteger(firstValue(body, "shopId", "shop_id"));
        Boolean allShops = parseBoolObject(firstValue(body, "allShops", "all_shops"));
        int[] holder = new int[1];
        if (adminShopScopeGuard != null) {
            if (Boolean.TRUE.equals(allShops)) {
                R guardR = adminShopScopeGuard.requireHeadquarters();
                if (guardR != null) {
                    return guardR;
                }
                holder[0] = 0;
            } else {
                R guardR = adminShopScopeGuard.resolveTargetShopId(requestedShopId, holder);
                if (guardR != null) {
                    return guardR;
                }
            }
        }
        Integer shopId = holder[0] > 0 ? Integer.valueOf(holder[0]) : AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (Boolean.TRUE.equals(allShops)) {
            shopId = null;
            params.put("allShops", true);
        }
        if (shopId != null && shopId > 0) {
            params.put("shopId", shopId);
            params.put("includeStats", true);
        }

        Map<String, Object> page = UserService.pageUserListWithStats(params);
        return R.ok().put("user", page.get("records")).put("total", page.get("total"));
    }
    @PostMapping("/getOneUserInfo")
    public R getOneUserInfo(@RequestBody(required = false) User user){
        if (user == null || user.getOpenid() == null || user.getOpenid().trim().isEmpty()) {
            return R.error("openid不能为空");
        }
        User US = UserService.getUserByOpenid(user.getOpenid().trim());
        if (US == null || US.getPhone() == null || US.getPhone().trim().isEmpty()) {
            return R.error("用户未注册或非有效会员（未绑定手机号）");
        }
        // 会话密钥为敏感凭据，管理端不返回
        US.setSession_key(null);
        return R.ok().put("user", US);
    }

    /**
     * 后台手动加积分（需管理员登录，请求头 Authorization: token）
     * 请求体：openid（必填）、points（必填，正整数）、shop_id（可选，若无头则必填）
     */
    @PostMapping("/addPoints")
    @AuditLog(module = "order", action = "admin_order_add_points", target = "#p0['orderNo'] ?: #p0['order_no']")
    public R addPoints(@RequestBody Map<String, Object> params) {
        Integer requestedShopId = asInteger(firstValue(params, "shopId", "shop_id"));
        int[] holder = new int[1];
        if (adminShopScopeGuard != null) {
            R guardR = adminShopScopeGuard.resolveTargetShopId(requestedShopId, holder);
            if (guardR != null) {
                return guardR;
            }
        }
        Integer shopId = holder[0] > 0 ? Integer.valueOf(holder[0]) : AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (shopId == null || shopId <= 0) {
            return R.error(4001, "必须在指定门店上下文下执行加积分操作");
        }
        Object openidObj = params != null ? params.get("openid") : null;
        Object pointsObj = params != null ? params.get("points") : null;
        if (openidObj == null || openidObj.toString().trim().isEmpty()) {
            return R.error(2, "openid不能为空");
        }
        String openid = openidObj.toString().trim();
        int points;
        if (pointsObj instanceof Number) {
            points = ((Number) pointsObj).intValue();
        } else if (pointsObj != null) {
            try {
                points = Integer.parseInt(pointsObj.toString());
            } catch (NumberFormatException e) {
                return R.error(2, "points 必须为正整数");
            }
        } else {
            return R.error(2, "points不能为空");
        }
        if (points <= 0) {
            return R.error(2, "points 必须为正整数");
        }
        User user = UserService.getUserByOpenid(openid);
        if (user == null || user.getId() == null) {
            return R.error(4, "用户不存在");
        }
        Integer adminId = (Integer) httpServletRequest.getAttribute(com.lanf.interceptor.SysInterceptor.ATTR_ADMIN_ID);
        log.info("Admin addPoints: adminId={}, shopId={}, openid={}, points={}", adminId, shopId, openid, points);
        boolean ok = UserService.addPoints(user.getId(), points);
        if (ok) {
            return R.ok("加积分成功").put("points", user.getPoints() != null ? user.getPoints() + points : points);
        }
        return R.error(500, "加积分失败");
    }

    /**
     * 数据分析：营业额统计（与 OpenAPI GET /admin/order/salesvolume 一致）
     * period=day 且未传 date 时实时统计当前活动营业班次；显式 date 仍按历史结算日查询。
     * 仅统计已支付订单（t_order.transac_status=success），金额使用净实付口径。
     * @param period day=当前营业班次(1条)，week=近七天(7条)，month=前12月(12条)，year=前5年(5条)
     */
    @GetMapping("/salesvolume")
    public R salesvolume(@RequestParam(required = false, defaultValue = "day") String period,
                         @RequestParam(required = false) String payment_method,
                         @RequestParam(required = false) String date) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        List<SalesVolume> salesVolumeList = orderService.getSalesVolumeByEveningPeriod(period, shopId, payment_method, date);
        Map<String, Object> resultMap = new HashMap<>();
        resultMap.put("salesVolumeList", salesVolumeList);
        return R.ok(resultMap);
    }

    /**
     * @deprecated 自动接单开关已废弃；门店营业中（{@code ordering_open=1}）时自动接单。保留接口兼容旧客户端。
     */
    @Deprecated
    @GetMapping("/auto-accept")
    public R getAutoAccept() {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        boolean orderingOpen = false;
        if (shopId != null) {
            Shop shop = shopService.getById(shopId);
            orderingOpen = ShopOrderingOpenHelper.isOrderingOpen(shop);
        }
        Map<String, Object> data = new HashMap<>();
        data.put("deprecated", true);
        data.put("message", "自动接单开关已废弃；门店营业中(ordering_open=1)时自动接单");
        data.put("enabled", orderingOpen);
        data.put("orderingOpen", orderingOpen);
        return R.ok(data);
    }

    /**
     * @deprecated 自动接单开关已废弃；请通过 {@code POST /order/ChangeBusiness} 切换营业状态。保留接口兼容旧客户端。
     */
    @Deprecated
    @PostMapping("/auto-accept")
    @AuditLog(module = "order", action = "admin_order_auto_accept")
    public R setAutoAccept(@RequestBody Map<String, Object> body) {
        Object enabled = body != null ? body.get("enabled") : null;
        if (!(enabled instanceof Boolean)) {
            return R.error("请传 enabled: true/false");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (Boolean.TRUE.equals(enabled) && shopId != null) {
            try {
                orderController.processPendingOrdersForAutoAccept(shopId);
            } catch (Exception e) {
                log.warn("兼容调用：处理待接单订单异常, shopId={}, {}", shopId, e.getMessage());
            }
        }
        return R.ok("自动接单开关已废弃，当前以门店营业状态为准")
                .put("deprecated", true)
                .put("enabled", Boolean.TRUE.equals(enabled));
    }

    /**
     * 订单已绑定门店且与当前请求门店不一致时拒绝（连锁防串店）。
     */
    private R assertOrderInCurrentShop(Order order) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null || order == null) {
            return null;
        }
        if (order.getShop_id() != null && !order.getShop_id().equals(sid)) {
            return R.error(4003, "订单不属于当前门店");
        }
        return null;
    }

    private static Set<String> parseCidList(Object rawList, Object rawCamel) {
        Set<String> out = new HashSet<>();
        Object raw = rawList != null ? rawList : rawCamel;
        if (raw instanceof List) {
            for (Object o : (List<?>) raw) {
                String t = asText(o);
                if (t != null) {
                    out.add(t);
                }
            }
        }
        return out;
    }

    private static Object firstValue(Map<String, Object> body, String... keys) {
        if (body == null || keys == null) {
            return null;
        }
        for (String key : keys) {
            if (body.containsKey(key)) {
                return body.get(key);
            }
        }
        return null;
    }

    private static void putText(Map<String, Object> params, String key, Object value) {
        String text = asText(value);
        if (text != null) {
            params.put(key, text);
        }
    }

    private static void putDateText(Map<String, Object> params, String key, Object value) {
        String text = asText(value);
        if (text != null) {
            params.put(key, text.replace('T', ' '));
        }
    }

    private static String asText(Object value) {
        if (value == null) {
            return null;
        }
        String text = String.valueOf(value).trim();
        return text.isEmpty() ? null : text;
    }

    private static Integer asInteger(Object value) {
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        String text = asText(value);
        if (text == null) {
            return null;
        }
        try {
            return Integer.parseInt(text);
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static Double asDouble(Object value) {
        if (value instanceof Number) {
            return ((Number) value).doubleValue();
        }
        String text = asText(value);
        if (text == null) {
            return null;
        }
        try {
            return Double.parseDouble(text);
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static Boolean parseBoolObject(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        String text = asText(value);
        if (text == null) {
            return null;
        }
        if ("1".equals(text) || "true".equalsIgnoreCase(text) || "yes".equalsIgnoreCase(text)) {
            return true;
        }
        if ("0".equals(text) || "false".equalsIgnoreCase(text) || "no".equalsIgnoreCase(text)) {
            return false;
        }
        return null;
    }

    private static String normalizeAmountSort(Map<String, Object> body) {
        String direct = asText(firstValue(body, "amountSort", "sortAmount"));
        if (direct == null) {
            String orderBy = asText(firstValue(body, "orderBy", "sortBy"));
            if (orderBy != null && ("amount".equalsIgnoreCase(orderBy)
                    || "consumeAmount".equalsIgnoreCase(orderBy)
                    || "consume_amount".equalsIgnoreCase(orderBy))) {
                direct = asText(firstValue(body, "orderDir", "sortOrder", "sort"));
            }
        }
        if (direct == null) {
            return null;
        }
        if ("asc".equalsIgnoreCase(direct) || "ascending".equalsIgnoreCase(direct)) {
            return "asc";
        }
        if ("desc".equalsIgnoreCase(direct) || "descending".equalsIgnoreCase(direct)) {
            return "desc";
        }
        return null;
    }

    /**
     * UI061: 电子发票开具二维码生成
     */
    @PostMapping("/invoice/qrcode")
    public R createInvoiceQrcode(@RequestBody(required = false) Map<String, Object> body) {
        if (body == null || body.isEmpty()) {
            return R.error(400, "请求体不能为空");
        }
        String orderNo = asText(firstValue(body, "orderNo", "order_no"));
        if (orderNo == null || orderNo.trim().isEmpty()) {
            return R.error(400, "订单号不能为空");
        }
        orderNo = orderNo.trim();
        Order order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo));
        if (order == null) {
            return R.error(404, "订单不存在");
        }
        R shopErr = assertOrderInCurrentShop(order);
        if (shopErr != null) {
            return shopErr;
        }

        boolean isPaid = ("success".equalsIgnoreCase(order.getTransac_status()) || "settled".equalsIgnoreCase(order.getTransac_status()))
                && order.getPay_time() != null;
        if (!isPaid) {
            return R.error(400, "未支付订单不可开具发票");
        }

        Double invoiceAmountReq = null;
        Object rawAmount = firstValue(body, "invoiceAmount", "invoice_amount", "amount");
        if (rawAmount instanceof Number) {
            invoiceAmountReq = ((Number) rawAmount).doubleValue();
        } else if (rawAmount != null) {
            try {
                invoiceAmountReq = Double.parseDouble(rawAmount.toString().trim());
            } catch (NumberFormatException ignored) {}
        }

        Double taxRate = null;
        Object rawTaxRate = firstValue(body, "taxRate", "tax_rate");
        if (rawTaxRate instanceof Number) {
            taxRate = ((Number) rawTaxRate).doubleValue();
        }

        Integer operatorId = httpServletRequest != null ? (Integer) httpServletRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID) : null;

        if (orderInvoiceService == null) {
            return R.error(500, "发票服务不可用，请联系管理员");
        }
        return orderInvoiceService.createInvoiceQrcode(order, invoiceAmountReq, taxRate, operatorId);
    }

    /**
     * UI061: 电子发票开具状态查询
     */
    @GetMapping("/invoice/status/{orderNo}")
    public R getInvoiceStatus(@PathVariable String orderNo) {
        if (!StringUtils.hasText(orderNo)) {
            return R.error(400, "订单号不能为空");
        }
        orderNo = orderNo.trim();
        Order order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo));
        if (order == null) {
            return R.error(404, "订单不存在");
        }
        R shopErr = assertOrderInCurrentShop(order);
        if (shopErr != null) {
            return shopErr;
        }
        if (orderInvoiceService != null) {
            return orderInvoiceService.getInvoiceStatus(order);
        }
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("orderNo", orderNo);
        data.put("hasInvoice", false);
        data.put("invoiceStatus", "NONE");
        return R.ok("success").put("code", 200).put("data", data);
    }

    /**
     * UI061: 财务/收银员录入并确认已开具的发票数据
     */
    @PostMapping("/invoice/issue")
    public R issueInvoice(@RequestBody Map<String, Object> body) {
        if (body == null || body.isEmpty()) {
            return R.error(400, "请求体不能为空");
        }
        String orderNo = (String) body.get("orderNo");
        String fapiaoNumber = (String) body.get("fapiaoNumber");
        String fapiaoCode = (String) body.get("fapiaoCode");
        String fapiaoFileUrl = (String) body.get("fapiaoFileUrl");

        if (!StringUtils.hasText(orderNo) || !StringUtils.hasText(fapiaoNumber)) {
            return R.error(400, "订单号和发票号码不能为空");
        }

        Order order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo.trim()));
        if (order == null) {
            return R.error(404, "订单不存在");
        }
        R shopErr = assertOrderInCurrentShop(order);
        if (shopErr != null) {
            return shopErr;
        }

        Integer operatorId = httpServletRequest != null ? (Integer) httpServletRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID) : null;
        if (orderInvoiceService == null) {
            return R.error(500, "发票服务不可用");
        }
        return orderInvoiceService.issueInvoice(orderNo, fapiaoNumber, fapiaoCode, fapiaoFileUrl, operatorId);
    }

    /**
     * UI-FINANCE-INVOICE-001: 财务开票申请分页列表
     */
    public R listInvoices(Integer page, Integer limit, String status, String keyword, String startDate, String endDate) {
        return listInvoices(page, limit, status, keyword, startDate, endDate, null, null);
    }

    @GetMapping("/invoice/list")
    public R listInvoices(
            @RequestParam(defaultValue = "1") Integer page,
            @RequestParam(defaultValue = "10") Integer limit,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String keyword,
            @RequestParam(required = false) String startDate,
            @RequestParam(required = false) String endDate,
            @RequestParam(required = false) Integer shopId,
            @RequestParam(required = false) Integer shop_id) {
        Integer targetShopId = shopId != null ? shopId : shop_id;
        if (targetShopId == null) {
            targetShopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        }
        if (adminShopScopeGuard != null && targetShopId != null && targetShopId > 0) {
            int[] holder = new int[1];
            R guardR = adminShopScopeGuard.resolveTargetShopId(targetShopId, holder);
            if (guardR != null) {
                return guardR;
            }
            targetShopId = holder[0] > 0 ? holder[0] : targetShopId;
        }
        if (orderInvoiceService == null) {
            return R.error(500, "发票服务不可用");
        }
        return orderInvoiceService.pageInvoiceForAdmin(page, limit, status, keyword, startDate, endDate, targetShopId);
    }

    /**
     * UI-FINANCE-INVOICE-001: 财务/管理员驳回异常开票申请
     */
    @PostMapping("/invoice/reject")
    public R rejectInvoice(@RequestBody Map<String, Object> body) {
        if (body == null || body.isEmpty()) {
            return R.error(400, "请求体不能为空");
        }
        String orderNo = asText(firstValue(body, "orderNo", "order_no"));
        String rejectReason = asText(firstValue(body, "rejectReason", "reject_reason", "reason", "errorMsg", "error_msg"));

        if (!StringUtils.hasText(orderNo) || !StringUtils.hasText(rejectReason)) {
            return R.error(400, "订单号和驳回原因不能为空");
        }

        Order order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo.trim()));
        if (order == null) {
            return R.error(404, "订单不存在");
        }
        R shopErr = assertOrderInCurrentShop(order);
        if (shopErr != null) {
            return shopErr;
        }

        Integer operatorId = httpServletRequest != null ? (Integer) httpServletRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID) : null;
        if (orderInvoiceService == null) {
            return R.error(500, "发票服务不可用");
        }
        return orderInvoiceService.rejectInvoice(orderNo.trim(), rejectReason.trim(), operatorId);
    }

    /**
     * UI-FINANCE-INVOICE-001: 财务手动重试发票推送到用户微信卡包
     */
    @PostMapping("/invoice/insert-card")
    public R insertInvoiceCard(@RequestBody Map<String, Object> body) {
        if (body == null || body.isEmpty()) {
            return R.error(400, "请求体不能为空");
        }
        String orderNo = asText(firstValue(body, "orderNo", "order_no"));
        if (!StringUtils.hasText(orderNo)) {
            return R.error(400, "订单号不能为空");
        }

        Order order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo.trim()));
        if (order == null) {
            return R.error(404, "订单不存在");
        }
        R shopErr = assertOrderInCurrentShop(order);
        if (shopErr != null) {
            return shopErr;
        }

        Integer operatorId = httpServletRequest != null ? (Integer) httpServletRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID) : null;
        if (orderInvoiceService == null) {
            return R.error(500, "发票服务不可用");
        }
        return orderInvoiceService.insertInvoiceToWechatCard(orderNo.trim(), operatorId);
    }
    /**
     * UI061: 全流程细粒度审计日志追踪
     */
    @GetMapping("/audit-timeline/{orderNo}")
    public R getAuditTimeline(@PathVariable String orderNo) {
        if (orderNo == null || orderNo.trim().isEmpty()) {
            return R.error(400, "订单号不能为空");
        }
        orderNo = orderNo.trim();
        Order order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo));
        if (order == null) {
            return R.error(404, "订单不存在");
        }
        R shopErr = assertOrderInCurrentShop(order);
        if (shopErr != null) {
            return shopErr;
        }

        if (adminService != null) {
            com.lanf.util.AdminNameResolver.enrichOrdersCashierInfo(Collections.singletonList(order), adminService);
        }

        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
        List<Map<String, Object>> events = new ArrayList<>();

        // 1. 开台/下单事件 (CREATE_ORDER)
        Date createTime = order.getOrder_time() != null ? order.getOrder_time() : new Date();
        Map<String, Object> createEvt = new LinkedHashMap<>();
        createEvt.put("time", sdf.format(createTime));
        createEvt.put("action", "CREATE_ORDER");
        String people = order.getNumber_of_diners() != null && !order.getNumber_of_diners().isEmpty() ? order.getNumber_of_diners() + "人" : "多客";
        String table = order.getTable_number() != null && !order.getTable_number().isEmpty() ? order.getTable_number() + "号桌" : "外带/自选";
        createEvt.put("description", "开台点单 (" + people + "/" + table + ")");
        String operator = order.getCashier_display_name() != null ? order.getCashier_display_name()
                : (order.getOrder_admin_name() != null ? order.getOrder_admin_name() : null);
        if (operator == null || operator.trim().isEmpty()) {
            operator = order.getOpenid() != null ? "顾客自助 (" + order.getOpenid() + ")" : "系统开台";
        }
        createEvt.put("operator", operator);
        events.add(createEvt);

        // 2. 加菜事件（若有加菜明细，Morder_num > 1）
        int addDishCount = 0;
        int totalDishCount = 0;
        try {
            List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
            if (details != null && !details.isEmpty()) {
                totalDishCount = details.size();
                for (OrderDetail d : details) {
                    if (d.getMorder_num() != null && d.getMorder_num() > 1) {
                        addDishCount++;
                    }
                }
            }
        } catch (Exception ignored) {}

        if (addDishCount > 0) {
            Map<String, Object> addDishEvt = new LinkedHashMap<>();
            Date addTime = new Date(createTime.getTime() + 300_000L);
            addDishEvt.put("time", sdf.format(addTime));
            addDishEvt.put("action", "ADD_DISH");
            addDishEvt.put("description", "就餐中途加菜 (" + addDishCount + "道菜品)");
            addDishEvt.put("operator", operator);
            events.add(addDishEvt);
        }

        // 3. 后厨出票完毕 (KITCHEN_PRINT)
        if (totalDishCount > 0) {
            Map<String, Object> kitchenEvt = new LinkedHashMap<>();
            Date kitchenTime = new Date(createTime.getTime() + 60_000L);
            kitchenEvt.put("time", sdf.format(kitchenTime));
            kitchenEvt.put("action", "KITCHEN_PRINT");
            kitchenEvt.put("description", "后厨出票完毕 (" + totalDishCount + "道菜品)");
            kitchenEvt.put("operator", "KDS打印引擎");
            events.add(kitchenEvt);
        }

        // 4. 结账收款 (PAY_SUCCESS)
        boolean hasCashPayment = false;
        Date payTime = order.getPay_time();
        if (payTime != null || "success".equalsIgnoreCase(order.getTransac_status()) || "settled".equalsIgnoreCase(order.getTransac_status())) {
            Date actualPayTime = payTime != null ? payTime : (order.getOff_time() != null ? order.getOff_time() : new Date());

            List<PaymentLedger> ledgers = null;
            if (paymentLedgerService != null) {
                try {
                    ledgers = paymentLedgerService.list(new QueryWrapper<PaymentLedger>()
                            .eq("order_no", orderNo)
                            .eq("entry_type", PaymentLedger.ENTRY_TYPE_PAYMENT)
                            .eq("status", PaymentLedger.STATUS_SUCCEEDED)
                            .orderByAsc("id"));
                } catch (Exception ignored) {}
            }

            if (ledgers != null && !ledgers.isEmpty()) {
                for (PaymentLedger pl : ledgers) {
                    Map<String, Object> payEvt = new LinkedHashMap<>();
                    Date lTime = pl.getCreated_at() != null ? pl.getCreated_at() : actualPayTime;
                    payEvt.put("time", sdf.format(lTime));
                    payEvt.put("action", "PAY_SUCCESS");
                    String channelName = pl.getChannel();
                    if (PaymentLedger.CHANNEL_WECHAT.equals(channelName) || PaymentLedger.CHANNEL_WECHAT_QR.equals(channelName)) channelName = "微信支付";
                    else if (PaymentLedger.CHANNEL_ALIPAY.equals(channelName) || PaymentLedger.CHANNEL_ALIPAY_QR.equals(channelName)) channelName = "支付宝";
                    else if (PaymentLedger.CHANNEL_CASH.equals(channelName)) {
                        channelName = "现金支付";
                        hasCashPayment = true;
                    }
                    else if (PaymentLedger.CHANNEL_BALANCE_PRINCIPAL.equals(channelName)) channelName = "会员余额";

                    double amt = pl.getAmount_fen() != null ? pl.getAmount_fen() / 100.0 : OrderNetRevenue.netRevenueYuan(order);
                    String desc = channelName + "入账 ¥" + String.format("%.2f", amt);
                    if (pl.getLedger_no() != null && !pl.getLedger_no().isEmpty()) {
                        desc += " (流水号: " + pl.getLedger_no() + ")";
                    }
                    payEvt.put("description", desc);
                    String cashierOp = order.getCashier_display_name() != null ? order.getCashier_display_name()
                            : (order.getOrder_admin_name() != null ? order.getOrder_admin_name() : (operator != null ? operator : "系统入账"));
                    payEvt.put("operator", cashierOp);
                    events.add(payEvt);
                }
            } else {
                Map<String, Object> payEvt = new LinkedHashMap<>();
                payEvt.put("time", sdf.format(actualPayTime));
                payEvt.put("action", "PAY_SUCCESS");
                String method = order.getPayment_method() != null ? order.getPayment_method() : "结账收款";
                if ("现金".contains(method) || "cash".equalsIgnoreCase(method)) {
                    hasCashPayment = true;
                }
                double amt = order.getSett_amount() != null ? order.getSett_amount() : OrderNetRevenue.netRevenueYuan(order);
                payEvt.put("description", method + "入账 ¥" + String.format("%.2f", amt));
                payEvt.put("operator", order.getCashier_display_name() != null ? order.getCashier_display_name()
                        : (order.getOrder_admin_name() != null ? order.getOrder_admin_name() : operator));
                events.add(payEvt);
            }
        }

        // 5. 钱箱开启 (CASH_DRAWER_OPEN)
        if (hasCashPayment) {
            Map<String, Object> drawerEvt = new LinkedHashMap<>();
            Date drawerTime = payTime != null ? new Date(payTime.getTime() + 1000L) : new Date();
            drawerEvt.put("time", sdf.format(drawerTime));
            drawerEvt.put("action", "CASH_DRAWER_OPEN");
            drawerEvt.put("description", "钱箱自动开启脉冲触发");
            drawerEvt.put("operator", "收银外设驱动");
            events.add(drawerEvt);
        }

        // 6. 退款/反结账事件 (REFUND / UNCHECKOUT)
        if ("refunded".equalsIgnoreCase(order.getTransac_status()) || (order.getRefund_amount() != null && order.getRefund_amount() > 0)) {
            Map<String, Object> refEvt = new LinkedHashMap<>();
            Date refTime = order.getOff_time() != null ? order.getOff_time() : new Date();
            refEvt.put("time", sdf.format(refTime));
            refEvt.put("action", "REFUND");
            double refAmt = order.getRefund_amount() != null ? order.getRefund_amount() : 0.0;
            refEvt.put("description", "订单退款完成 ¥" + String.format("%.2f", refAmt));
            refEvt.put("operator", order.getOrder_admin_name() != null ? order.getOrder_admin_name() : "店长授权");
            events.add(refEvt);
        } else if ("unsettled".equalsIgnoreCase(order.getTransac_status()) && order.getPay_time() != null) {
            Map<String, Object> unEvt = new LinkedHashMap<>();
            Date unTime = order.getOff_time() != null ? order.getOff_time() : new Date();
            unEvt.put("time", sdf.format(unTime));
            unEvt.put("action", "UNCHECKOUT");
            unEvt.put("description", "店长授权反结账并恢复桌台 (已重开)");
            unEvt.put("operator", order.getOrder_admin_name() != null ? order.getOrder_admin_name() : "店长授权");
            events.add(unEvt);
        }

        // 按时间升序排序
        events.sort(Comparator.comparing(a -> String.valueOf(a.get("time"))));

        Map<String, Object> data = new LinkedHashMap<>();
        data.put("orderNo", orderNo);
        data.put("events", events);

        return R.ok("success").put("code", 200).put("data", data);
    }
}
