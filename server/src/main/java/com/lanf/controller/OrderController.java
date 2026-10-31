package com.lanf.controller;
import com.lanf.audit.diff.OrderRefundDiffProvider;
import com.lanf.audit.annotation.AuditLog;

import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.lanf.constant.MiniProgramAuthCodes;
import com.lanf.event.DishCatalogChangedEvent;
import com.lanf.dto.InviteRecordDTO;
import com.lanf.dto.CouponRuleValidateRequest;
import com.lanf.dto.CouponRuleValidateResult;
import com.lanf.dto.OrderDTO;
import com.lanf.dto.UserCouponDTO;
import com.lanf.entity.*;
import com.lanf.mapper.DishShopMapper;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.util.DishShopOverrides;
import com.lanf.mapper.UserMapper;

import lombok.Data;
import org.springframework.beans.BeanUtils;
import org.springframework.http.*;
import com.lanf.service.*;
import com.wechat.pay.contrib.apache.httpclient.auth.Signer;
import org.springframework.context.event.EventListener;
import org.springframework.beans.factory.annotation.Autowired;
import com.lanf.security.JwtTokenService;
import com.lanf.interceptor.UserIdentityInterceptor;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.util.ShopBusinessWindowResolver;
import java.time.LocalDate;
import com.lanf.security.SecurityAuditService;
import com.lanf.security.SensitiveOperationAuthorizationService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Lazy;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.util.ObjectUtils;
import org.springframework.util.StringUtils;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;
import com.lanf.entity.InviteRecord;
import com.lanf.mapper.InviteRecordMapper;
import com.lanf.service.InviteService;
import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import javax.crypto.AEADBadTagException;
import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import javax.servlet.ServletInputStream;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.*;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.*;

import java.security.spec.X509EncodedKeySpec;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.Base64;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import com.lanf.service.ICouponService;
import java.util.concurrent.TimeUnit;

import com.wechat.pay.contrib.apache.httpclient.util.PemUtil;
import com.wechat.pay.contrib.apache.httpclient.auth.PrivateKeySigner;
import com.lanf.util.ShopOrderingOpenHelper;
import com.lanf.config.ServiceFeeConfig;
import com.lanf.payment.service.PaymentNinefoldService;
import com.lanf.util.OrderPackagingFeeCalculator;
import com.lanf.util.OrderNetRevenue;
import com.lanf.util.OrderPayChannelAmounts;
import com.lanf.util.SafeLogValue;
import com.lanf.util.UserWalletSplitUtil;
import com.lanf.util.DishCustomerMenuFilters;
import com.lanf.util.DishSoldOutSync;
import com.lanf.util.ShopChainSupport;
import com.lanf.payment.channel.wechat.WechatJsapiChannel;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.payment.channel.wechat.WechatPayV3Crypto;
import com.lanf.payment.config.PaymentFacadeProperties;
import com.lanf.payment.support.PaymentDiningTypeUtil;
import com.lanf.payment.facade.PaymentFacadeService;
import com.lanf.payment.notify.WechatPaymentNotifyService;
import com.lanf.payment.settlement.PayableAmountContext;
import com.lanf.payment.settlement.PaymentSettlementService;
import com.lanf.payment.success.PaymentSuccessHandler;
import com.lanf.payment.support.WxRechargeGiftTierValidator;

import com.lanf.order.OrderDetailLineStatus;
import com.lanf.order.OrderRevisionService;
import com.lanf.common.ApiException;
import java.security.PrivateKey;
import java.util.stream.Collectors;


import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.multipart.MultipartFile;

/**
 * 订单控制器
 */
@RestController
@RequestMapping("/order")
public class OrderController {
    /**
     * 厨房票默认合并的 cid 组（前端未传 cid_list 时生效）。
     */
    private static final Set<String> DEFAULT_MERGED_KITCHEN_CIDS = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "a20260320122903000000010",
            "a20260330044440000000031",
            "a20260330044631000000466",
            "a20260330045342000000796"
    )));
    @Autowired
    private ITableService tableService;
    @Autowired
    private com.lanf.kds.service.KdsOrderHook kdsOrderHook;
    @Autowired
    private com.lanf.kds.delivery.CashierKdsProjectionService cashierKdsProjectionService;
    @Autowired
    private com.lanf.kds.service.KdsConfigService kdsConfigService;
    @Autowired
    private com.lanf.kds.service.KdsDetailStatusResolver kdsDetailStatusResolver;
    @Autowired(required = false)
    private CashierCheckoutService cashierCheckoutService;
    @Autowired(required = false)
    private com.lanf.service.IShopMemberWalletService shopMemberWalletService;
    @Autowired
    private com.lanf.service.IOrderLogService orderLogService;
    @Autowired
    private OrderRevisionService orderRevisionService;

    public static final String CASHIER_QUICK_ORDER_ATTRIBUTE =
            "com.lanf.order.cashierQuickOrder";

    public static final String CHANNEL_CASHIER = "cashier";
    public static final String CHANNEL_TAKEOUT = "takeout";
    public static final String CHANNEL_AI = "ai";
    public static final String CHANNEL_MINI_PROGRAM = "mini_program";

    private static final Logger log = LoggerFactory.getLogger(OrderController.class);

    

    private final Cache<String, Boolean> processedNotifications = Caffeine.newBuilder()
            .expireAfterWrite(5, TimeUnit.MINUTES) // 5分钟后自动过期
            .maximumSize(10000) // 最大缓存1万条记录，避免内存溢出
            .build();
    /** 按订单号加锁，防止同一订单被并发回调重复处理（如重复反积分） */
    private final Cache<String, Object> paymentOrderLocks = Caffeine.newBuilder()
            .expireAfterWrite(10, TimeUnit.MINUTES)
            .maximumSize(5000)
            .build();
    /** 串行化同一订单的自动打印、手工接单与补偿任务，避免同进程重复出纸。 */
    private final Cache<Integer, Object> fulfillmentOrderLocks = Caffeine.newBuilder()
            .expireAfterAccess(10, TimeUnit.MINUTES)
            .maximumSize(5000)
            .build();

    /** 订单使用账户余额全额支付时写入 {@link Order#getPayment_method()} */
    private static final String PAYMENT_METHOD_BALANCE = "余额支付";
    /** 余额支付占位 transaction_id 前缀（非微信单号）；退款走本地退回余额 */
    private static final String BALANCE_TX_ID_PREFIX = "BAL_";

    private static boolean isBalancePaymentTransactionId(String transactionId) {
        return StringUtils.hasText(transactionId) && transactionId.startsWith(BALANCE_TX_ID_PREFIX);
    }

    /**
     * 商户业务单号前缀约定（与微信 {@code out_trade_no} 解析后的主单号一致）：点餐写 {@code t_order}，充值写 {@code t_member_recharge}，
     * 支付/关单/退款回调可通过前缀直接分流，无需猜测业务类型。
     */
    private static final String MERCHANT_NO_PREFIX_DINING = "ORD";
    private static final String MERCHANT_NO_PREFIX_WX_RECHARGE = "RCH";

    /** 是否为微信会员充值商户单号（{@code t_member_recharge.order_no}） */
    private static boolean isWxRechargeMerchantNo(String businessNo) {
        return StringUtils.hasText(businessNo) && businessNo.startsWith(MERCHANT_NO_PREFIX_WX_RECHARGE);
    }

    /**
     * C 端微信充值固定「充送」档位（本金 → 赠送，单位元）。仅当请求中赠送金额 &gt; 0 时强制校验；
     * 不传赠送或传 0 则不要求命中档位（任意合法本金均可）。
     */
    private static final Map<BigDecimal, BigDecimal> WX_RECHARGE_GIFT_TIERS = wxRechargeGiftTierMap();

    private static Map<BigDecimal, BigDecimal> wxRechargeGiftTierMap() {
        Map<BigDecimal, BigDecimal> m = new LinkedHashMap<>();
        m.put(new BigDecimal("200.00"), new BigDecimal("10.00"));
        m.put(new BigDecimal("500.00"), new BigDecimal("50.00"));
        m.put(new BigDecimal("1000.00"), new BigDecimal("120.00"));
        m.put(new BigDecimal("5000.00"), new BigDecimal("750.00"));
        m.put(new BigDecimal("10000.00"), new BigDecimal("2000.00"));
        return Collections.unmodifiableMap(m);
    }

    /** 单笔微信充值本金下限（元） */
    private static final double WX_RECHARGE_MIN_YUAN = 50.00d;

    /** 单笔微信充值本金上限（含 10000 元活动档） */
    private static final double WX_RECHARGE_MAX_YUAN = 10000.00d;

    /**
     * @return 校验通过返回 null，否则返回 R.error
     */
    private static R validateWxRechargeGiftAgainstTiers(BigDecimal rechargeBd, BigDecimal giftBd) {
        if (giftBd == null || giftBd.compareTo(BigDecimal.ZERO) <= 0) {
            return null;
        }
        BigDecimal expected = WX_RECHARGE_GIFT_TIERS.get(rechargeBd);
        if (expected == null) {
            return R.error("非活动档位不能使用赠送金额，活动本金为：200 / 500 / 1000 / 5000 / 10000 元");
        }
        if (giftBd.compareTo(expected) != 0) {
            return R.error(String.format(
                    "赠送金额与活动规则不符：充值 %s 元应送 %s 元（当前赠送 %s 元）",
                    rechargeBd.toPlainString(), expected.toPlainString(), giftBd.toPlainString()));
        }
        return null;
    }

    /** 统一展示用时间格式：yyyy-MM-dd HH:mm:ss */
    private static final String TIME_FORMAT_DISPLAY = "yyyy-MM-dd HH:mm:ss";

    @Autowired
    private IOrderService orderService;
    @Autowired
    private IOrderDetailService orderDetailService;

    @Autowired
    private UserCouponMapper UserCouponMapper;

    @Autowired
    private ICouponService CouponService;

    @Autowired
    private com.lanf.printing.engine.PrintTemplateEngine printTemplateEngine;

    @Autowired
    private com.lanf.payment.service.WechatRefundSettlementService wechatRefundSettlementService;

    @Autowired
    private com.lanf.printing.service.PrintDispatcherService printDispatcherService;
    @Autowired
    private com.lanf.printing.service.KdsSupplementalPrintService kdsSupplementalPrintService;

    @Autowired
    private DishMenuPushService dishMenuPushService;

    @Autowired(required = false)
    private com.lanf.notify.service.UnifiedNotificationService unifiedNotificationService;

    @Autowired
    private ServiceFeeConfig serviceFeeConfig;

    @Autowired
    private PaymentNinefoldService paymentNinefoldService;

    @Autowired
    private IUserService userService;

    @Autowired
    private WechatMiniProgramAuthService wechatMiniProgramAuthService;
    @Autowired
    private JwtTokenService jwtTokenService;
    @Value("${auth.user-token-ttl-ms:604800000}")
    private long userTokenTtlMillis;

    @Autowired
    private IMemberRechargeService memberRechargeService;

    @Autowired
    private com.lanf.payment.service.PaymentOnlineGuardService paymentOnlineGuardService;
    @Autowired
    private PaymentFacadeService paymentFacadeService;
    @Autowired
    private PaymentFacadeProperties paymentFacadeProperties;
    @Autowired
    private WechatPaymentNotifyService wechatPaymentNotifyService;
    @Autowired
    private WechatJsapiChannel wechatJsapiChannel;
    @Autowired
    private WechatMerchantKeyStore merchantKeyStore;
    @Lazy
    @Autowired
    private PaymentSettlementService paymentSettlementService;
    @Autowired
    private com.lanf.payment.service.WechatJsapiPaymentService wechatJsapiPaymentService;
    @Lazy
    @Autowired
    private PaymentSuccessHandler paymentSuccessHandler;

    @Autowired
    private ITakeoutDeliveryService takeoutDeliveryService;

    @Autowired
    private IAdminShopAccessService adminShopAccessService;

    @Autowired
    private SecurityAuditService securityAuditService;
    @Autowired
    private SensitiveOperationAuthorizationService sensitiveOperationAuthorizationService;
    /** POS 权限中心审批令牌服务；未装配（老环境/单测）时自动回退现场账号密码授权。 */
    @Autowired(required = false)
    private com.lanf.access.service.ApprovalService approvalService;
    @Autowired
    private IShiftService shiftService;
    @Autowired
    private IDailyStatService dailyStatService;
    @Autowired(required = false)
    private com.lanf.mapper.DailyCloseSnapshotMapper dailyCloseSnapshotMapper;
    @Autowired
    private IAdminPermissionService adminPermissionService;

    @Autowired
    private ITakeoutZsqIntegrationService takeoutZsqIntegrationService;

    @Autowired
    private InviteService InviteService;

    @Autowired
    private InviteController inviteController;

    @Autowired
    private RestTemplate restTemplate;

    @Value("${ai.api.url:}")
    private String aiApiUrl;

    @Value("${ai.api.key:}")
    private String aiApiKey;

    /** 方舟场景须为推理接入点 ep-xxx；通义等为具体模型名 */
    @Value("${ai.model:}")
    private String aiModel;

    @Autowired
    private IDishService dishService;
    @Autowired
    private DishShopMapper dishShopMapper;
    @Autowired
    private IDishShopStockService dishShopStockService;

    @Autowired
    private IComboMealService comboMealService;

    @Autowired
    private IShopService shopService;

    @Autowired
    private ICategoryService categoryService;

    @Autowired
    private IActivityPopupService activityPopupService;

    @Autowired
    private ObjectMapper objectMapper;  // 注入Spring注入ObjectMapper
    @Autowired
    private com.lanf.service.AiToolResponseParser aiToolResponseParser;

    @Autowired
    private IBannerService bannerService;

    // 微信小程序配置参数 - 商户1
    @Value("${weixin.appid}")
    private String appid;

    @Value("${weixin.secret}")
    private String appsecret;

    @Value("${weixin.mchid:}")
    private String mchid1;

    @Value("${weixin.private-key-path:}")
    private String privateKeyPath1; // 商户1私钥文件路径（.pem格式）

    @Value("${weixin.notify-url:}")
    private String notifyUrl1;

    @Value("${weixin.refund-notify-url:}")
    private String refundNotifyUrl1;

    @Value("${weixin.api-v3-key:}")
    private String apiV3Key1;  // 商户1 APIv3密钥

    @Value("${weixin.serial_no:}")
    private String serialNo1;  // 商户1证书序列号

    @Value("${weixin.pubSerial:}")
    private String pubSerial1;  // 公钥ID

    @Value("${weixin.pubSerial-path:}")
    private String pubKey1;  // 公钥
    private PublicKey wechatPublicKey1;

    // 微信小程序配置参数 - 商户2

    @Value("${weixin2.mchid:}")
    private String mchid2;

    @Value("${weixin2.private-key-path:}")
    private String privateKeyPath2; // 商户2私钥文件路径（.pem格式）

    @Value("${weixin2.notify-url:}")
    private String notifyUrl2;

    @Value("${weixin2.refund-notify-url:}")
    private String refundNotifyUrl2;

    @Value("${weixin2.api-v3-key:}")
    private String apiV3Key2;  // 商户2 APIv3密钥

    @Value("${weixin2.pubSerial-path:}")
    private String pubKey2;  // 公钥
    private PublicKey wechatPublicKey2;

    @Value("${weixin2.serial_no:}")
    private String serialNo2;  // 商户2证书序列号

    @Value("${weixin2.pubSerial:}")
    private String pubSerial2;  // 公钥ID


    private PublicKey wechatPublicKey;  // 微信支付平台证书内容(PEM格式)

    @Autowired
    private com.lanf.service.CustomerProfileService customerProfileService;

    @Value("${activateImgsFilePath}")
    private String activateImgsFilePath;

    // 基础耗时参数（中间值）
    private static final double PICK_MATERIAL_TIME = 3.0; // 捡食材时间
    private static final double MAKE_TIME_VERY_LOW_AMOUNT = 15.0; // 订单金额 < 30 制作时间
    private static final double MAKE_TIME_LOW_AMOUNT = 20.0; // 30 <= 订单金额 < 100 制作时间
    private static final double MAKE_TIME_MID_AMOUNT = 35.0; // 100 <= 订单金额 <= 200 制作时间
    private static final double MAKE_TIME_HIGH_AMOUNT = 40.0; // 订单金额 > 200 制作时间
    private static final double PACK_TIME = 3.5; // 打包时间

    // 新增成员变量 - 存储两个商户的私钥和签名器
    private PrivateKey privateKey1;
    private PrivateKey privateKey2;
    private PrivateKeySigner signer1;
    private PrivateKeySigner signer2;

    // 使用Caffeine缓存处理中的订单
    private final Cache<String, Boolean> processingOrders = Caffeine.newBuilder()
            .expireAfterWrite(5, TimeUnit.MINUTES)
            .build();
    /** Delays order-key release without creating one native thread per successful request. */
    private final java.util.concurrent.ThreadPoolExecutor processingOrderCleanup =
            new java.util.concurrent.ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS,
                    new java.util.concurrent.ArrayBlockingQueue<>(128), task -> {
                        Thread thread = new Thread(task, "order-key-cleanup");
                        thread.setDaemon(true);
                        return thread;
                    }, new java.util.concurrent.ThreadPoolExecutor.AbortPolicy());

    // 缓存access_token，区分两个商户
    private final Cache<String, String> tokenCache = Caffeine.newBuilder()
            .initialCapacity(2)
            .maximumSize(2)
            .expireAfterWrite(7000, TimeUnit.SECONDS)
            .build();
    // AI 菜单缓存：减少推荐场景重复查库
    private final Cache<String, List<Category>> aiOnSaleMenuCache = Caffeine.newBuilder()
            .expireAfterWrite(60, TimeUnit.SECONDS)
            .maximumSize(1)
            .build();
    // 多轮对话缓存：按 openid 隔离会话，30 分钟无交互自动过期
    private final Cache<String, List<Map<String, Object>>> aiChatMemoryCache = Caffeine.newBuilder()
            .expireAfterWrite(30, TimeUnit.MINUTES)
            .maximumSize(5000)
            .build();

    /** 大模型工具调用链最大递归深度（含纠错重试），避免死循环 */
    private static final int MAX_AI_TOOL_RECURSION_DEPTH = 8;
    /** 自然语言点餐 /chatSuggest：允许更多轮工具纠错与补参 */
    private static final int MAX_AI_TOOL_RECURSION_DEPTH_SUGGEST = 14;

    /** 单次 AI 请求内是否真实走通 create_order / add_dishes（防模型捏造「下单成功」） */
    private static final class AiToolTurnTracker {
        boolean createOrderInvoked;
        boolean createOrderOk;
        /** 加菜成功同属真实写单，不应再拦截「下单成功/订单号」类话术 */
        boolean addDishesOk;
        String serverOrderNo;
        /** 本轮 query_order / get_order_by_table / order_history 等查询成功返回的订单号，回复中引用不算捏造 */
        Set<String> trustedOrderNosFromQuery;
    }

    private static final ThreadLocal<AiToolTurnTracker> AI_TOOL_TURN = new ThreadLocal<>();

    /** /ai/chatSuggest 当前请求的会话默认值：补全模型未带的 openid、桌号等 */
    private static final class AiSuggestSession {
        String openid;
        String tableNumber;
        /** 连锁：与 chatSuggest 请求体/头解析后的门店，用于 merge 到 create_order */
        Integer shopId;
    }

    private static final ThreadLocal<AiSuggestSession> AI_SUGGEST_SESSION = new ThreadLocal<>();

    private static int maxAiToolRecursionDepth() {
        return AI_SUGGEST_SESSION.get() != null ? MAX_AI_TOOL_RECURSION_DEPTH_SUGGEST : MAX_AI_TOOL_RECURSION_DEPTH;
    }

    private static final Pattern ORDER_NO_MENTION_PATTERN =
            Pattern.compile("(?:订单号|单号)[:：\\s]*([A-Za-z0-9_-]{6,40})");
    /** 助手正文中 ```json ... ``` 内嵌工具参数 */
    /** 长文本内嵌单对象工具调用：{"name":"任意工具名" ...}（匹配起点为 {，不限于 create_order） */

    @Autowired
    private UserMapper userMapper;


    private Integer resolveChainShop(HttpServletRequest request, Integer bodyShopId, String bodyShopCode) {
        return ShopChainSupport.resolveShopChain(request, bodyShopId, bodyShopCode,
                shopService::requireActiveShopIdByCode);
    }

    private static Integer shopIdOrDefault(Integer shopId) {
        return shopId != null ? shopId : 1;
    }

    /**
     * 打印分发门店：严格使用订单自身 shop_id（订单必须归属门店）。
     */
    private Integer resolveOrderOwnedShopIdForPrint(Order order) {
        if (order == null || !StringUtils.hasText(order.getOrder_no())) {
            throw new RuntimeException("订单不存在或订单号为空，无法分发门店打印机");
        }
        Order latest = orderService.getOne(new QueryWrapper<Order>()
                .eq("order_no", order.getOrder_no().trim())
                .orderByDesc("id")
                .last("LIMIT 1"));
        if (latest == null || latest.getShop_id() == null) {
            throw new RuntimeException("订单未绑定门店，无法分发门店打印机");
        }
        return latest.getShop_id();
    }

    /**
     * C 端：优先从请求头/参数解析门店；缺失时默认归到门店 1（兼容旧版小程序）。
     */
    private Integer requireResolvedCShop(HttpServletRequest request) {
        return shopIdOrDefault(resolveChainShop(request, null, null));
    }

    /**
     * {@code /order/table_verify}：query 传入 {@code shop_id} 且为正整数时优先使用；否则与 {@link #requireResolvedCShop} 一致。
     */
    private Integer resolveTableVerifyShopId(Integer shopIdParam, HttpServletRequest request) {
        if (shopIdParam != null && shopIdParam > 0) {
            return shopIdParam;
        }
        return requireResolvedCShop(request);
    }

    /** 历史订单/桌台 shop_id 为空时，仅视为归属于门店 1 */
    private static boolean orderBelongsToShop(Order order, Integer shopId) {
        if (order == null || shopId == null) {
            return false;
        }
        Integer oid = order.getShop_id();
        if (oid != null) {
            return shopId.equals(oid);
        }
        return Integer.valueOf(1).equals(shopId);
    }

    private static boolean tableBelongsToShop(Table table, Integer shopId) {
        if (table == null || shopId == null) {
            return false;
        }
        Integer tid = table.getShop_id();
        if (tid != null) {
            return shopId.equals(tid);
        }
        return Integer.valueOf(1).equals(shopId);
    }

    /**
     * 桌台查询按门店限定；shop_id 为空的迁移前数据仅当 shopId==1 时命中。
     */
    private static void appendTableShopScope(QueryWrapper<Table> qw, Integer shopId) {
        if (qw == null || shopId == null) {
            return;
        }
        if (Integer.valueOf(1).equals(shopId)) {
            qw.and(w -> w.eq("shop_id", 1).or(w2 -> w2.isNull("shop_id")));
        } else {
            qw.eq("shop_id", shopId);
        }
    }

    /**
     * 订单查询按门店限定；{@code shop_id} 为 null 的迁移前数据仅当 {@code shopId==1} 时命中。
     */
    private static void appendOrderShopScope(QueryWrapper<Order> qw, Integer shopId) {
        if (qw == null || shopId == null) {
            return;
        }
        if (Integer.valueOf(1).equals(shopId)) {
            qw.and(w -> w.eq("shop_id", 1).or(w2 -> w2.isNull("shop_id")));
        } else {
            qw.eq("shop_id", shopId);
        }
    }

    /**
     * AI 工具执行无 HttpServletRequest：可从参数取 shop_id，缺省为 1（与历史单店数据兼容）。
     */
    private static Integer aiToolShopIdOrDefault(Map<String, Object> args) {
        if (args == null || args.get("shop_id") == null) {
            return 1;
        }
        return shopIdOrDefault(ShopChainSupport.parseBodyShopId(args.get("shop_id")));
    }

    private R tableVerifyWithShop(String number, Integer shopId) {
        if (number == null || number.trim().isEmpty()) {
            return R.error("台号不能为空");
        }
        shopId = shopIdOrDefault(shopId);
        QueryWrapper<Table> qw = new QueryWrapper<Table>().eq("number", number.trim());
        appendTableShopScope(qw, shopId);
        Table table = tableService.getOne(qw.last("LIMIT 1"));
        if (table == null) {
            return R.error("台号不存在");
        }
        return R.ok();
    }

    private R tableStatusWithShop(String number, Integer shopId) {
        if (number == null || number.trim().isEmpty()) {
            return R.error("台号不能为空");
        }
        shopId = shopIdOrDefault(shopId);
        QueryWrapper<Table> qw = new QueryWrapper<Table>().eq("number", number.trim());
        appendTableShopScope(qw, shopId);
        Table table = tableService.getOne(qw.last("LIMIT 1"));
        if (table == null) {
            return R.error("台号不存在");
        }
        Map<String, Object> map = new HashMap<>();
        map.put("status", table.getStatus());
        return R.ok(map);
    }

    private void applyShopContextToOrderDto(OrderDTO order, HttpServletRequest request) {
        if (order == null) {
            return;
        }
        // 请求体仅合并 shop_id；shop_code 为内部编码，不采信外部请求体传入值。
        // 兼容旧版小程序：未传门店时默认归到门店 1。
        final Integer resolved = Optional
                .ofNullable(resolveChainShop(request, order.getShop_id(), null))
                .orElse(1);
        order.setShop_id(resolved);
        order.setShop_code(null);
        validateShopOpen(resolved);
    }


    /**
     * 下单渠道与操作员落库（服务端权威，不信任客户端传值）：
     * channel 判定优先级 cashier（收银标记）> takeout（diningType=外卖）> ai（AI 工具链活跃）> mini_program（默认 C 端）；
     * order_admin_id 取 B 端 JWT（SysInterceptor.ATTR_ADMIN_ID），C 端/AI 为 null。
     */
    private void resolveOrderChannelAndOperator(OrderDTO order, HttpServletRequest request) {
        String channel = CHANNEL_MINI_PROGRAM;
        if (request != null && Boolean.TRUE.equals(request.getAttribute(CASHIER_QUICK_ORDER_ATTRIBUTE))) {
            channel = CHANNEL_CASHIER;
        } else if ("外卖".equals(order.getDineInOrTakeOut())) {
            channel = CHANNEL_TAKEOUT;
        } else if (AI_TOOL_TURN.get() != null) {
            channel = CHANNEL_AI;
        }
        order.setOrder_channel(channel);
        Integer adminId = null;
        if (request != null) {
            Object attr = request.getAttribute(com.lanf.interceptor.SysInterceptor.ATTR_ADMIN_ID);
            if (attr != null) {
                try {
                    adminId = Integer.valueOf(attr.toString());
                } catch (NumberFormatException e) {
                    adminId = null;
                }
            }
        }
        order.setOrder_admin_id(adminId);
        if (order.getCashier_id() == null && adminId != null
                && (CHANNEL_CASHIER.equals(channel) || (request != null && Boolean.TRUE.equals(request.getAttribute(CASHIER_QUICK_ORDER_ATTRIBUTE))))) {
            order.setCashier_id(adminId);
        }
    }
    private void validateShopOpen(Integer shopId) {
        Shop sh = shopService.getById(shopId);
        if (sh == null || sh.getStatus() == null || sh.getStatus() != 1) {
            throw new RuntimeException("门店不可用或不存在");
        }
    }

    private Set<Integer> parseJsonIntIdSet(String json) {
        Set<Integer> set = new HashSet<>();
        if (!StringUtils.hasText(json) || "[]".equals(json.trim())) {
            return set;
        }
        try {
            List<?> arr = objectMapper.readValue(json.trim(), List.class);
            if (arr != null) {
                for (Object o : arr) {
                    if (o instanceof Number) {
                        set.add(((Number) o).intValue());
                    } else if (o != null) {
                        String s = o.toString().trim();
                        if (!s.isEmpty()) {
                            set.add(Integer.parseInt(s));
                        }
                    }
                }
            }
        } catch (Exception e) {
            throw new RuntimeException("配置中的 JSON 数组格式异常，请联系管理员");
        }
        return set;
    }

    private void validateCouponShopScope(Coupon tmpl, Integer orderShopId) {
        if (tmpl == null) {
            return;
        }
        String raw = tmpl.getApply_shop_ids();
        // 约定：apply_shop_ids 为空/[] 视为不可用
        if (!StringUtils.hasText(raw) || "[]".equals(raw.trim())) {
            throw new RuntimeException("该优惠券未配置适用门店，暂不可使用");
        }
        Set<Integer> shops = parseJsonIntIdSet(raw);
        if (shops.isEmpty()) {
            throw new RuntimeException("该优惠券未配置适用门店，暂不可使用");
        }
        if (orderShopId == null) {
            throw new RuntimeException("该优惠券仅限指定门店使用，请先选择门店");
        }
        if (!shops.contains(orderShopId)) {
            throw new RuntimeException("该优惠券不适用于当前门店");
        }
    }

    /**
     * 出餐时间估算（按门店未结单数）；无 HTTP 上下文时由 AI 工具传入 shop_id，缺省为 1。
     */
    private R calculateFinishTimeWithShop(Order od, Integer shopId) {
        shopId = shopIdOrDefault(shopId);
        Order anchorOrder = resolveAnchorOrder(od, shopId);
        Date anchorTime = (anchorOrder != null && anchorOrder.getOrder_time() != null)
                ? anchorOrder.getOrder_time()
                : ((od != null && od.getOrder_time() != null) ? od.getOrder_time() : new Date());
        Integer anchorOrderId = anchorOrder != null ? anchorOrder.getId() : (od != null ? od.getId() : null);
        int unfinishedOrderCount = orderService.countUnfinishedOrdersBefore(shopId, anchorTime, anchorOrderId);
        int orderNum = unfinishedOrderCount ;

        String isDineIn = od != null ? od.getDineInOrTakeOut() : null;
        double actualMakeTime = resolveMakeTimeByAmount(od);

        int parallelNum = orderNum >= 10 ? 4 : 3;
        int groupNum = (int) Math.ceil((double) orderNum / parallelNum);
        double firstOrderTime = (Objects.equals(isDineIn, "打包") || isWaimaiType(isDineIn))
                ? PICK_MATERIAL_TIME + actualMakeTime + PACK_TIME
                : PICK_MATERIAL_TIME + actualMakeTime;

        double finishTime = firstOrderTime + (groupNum - 1) * actualMakeTime;
        finishTime = Math.round(finishTime * 10) / 10.0;

        // 返回剩余出餐时间：总估算时间减去「已等待时间」
        Date orderTimeForWait = (anchorOrder != null && anchorOrder.getOrder_time() != null)
                ? anchorOrder.getOrder_time()
                : (od != null ? od.getOrder_time() : null);
        double waitedMinutes = 0D;
        if (orderTimeForWait != null) {
            long diffMs = System.currentTimeMillis() - orderTimeForWait.getTime();
            if (diffMs > 0) {
                waitedMinutes = diffMs / 60000.0;
            }
        }
        waitedMinutes = Math.round(waitedMinutes * 10) / 10.0;
        int waitedFloorMinutes = (int) Math.floor(waitedMinutes);
        int rawMinTellTime = (int) Math.floor(finishTime);
        int rawMaxTellTime = rawMinTellTime + 5;
        int minTellTime = Math.max(0, rawMinTellTime - waitedFloorMinutes);
        int maxTellTime = Math.max(minTellTime, rawMaxTellTime - waitedFloorMinutes);
        String suggestTellTime = minTellTime + "-" + maxTellTime + "分钟";

        return R.ok()
                .put("makeTime", suggestTellTime)
                .put("waitedMinutes", Math.max(0D, waitedMinutes))
                .put("aheadOrderCount", unfinishedOrderCount);
    }

    /**
     * 估算锚点订单：优先按 id/order_no 回表获取真实下单时间，确保「前方几单」按更早订单准确统计。
     */
    private Order resolveAnchorOrder(Order od, Integer shopId) {
        if (od == null) {
            return null;
        }
        if (od.getId() != null) {
            QueryWrapper<Order> qw = new QueryWrapper<Order>().eq("id", od.getId());
            if (shopId != null) {
                qw.eq("shop_id", shopId);
            }
            Order byId = orderService.getOne(qw, false);
            if (byId != null) {
                return byId;
            }
            // 兜底：避免因门店上下文不一致导致找不到锚点，按 id 全局回查一次
            Order byIdFallback = orderService.getOne(new QueryWrapper<Order>().eq("id", od.getId()), false);
            if (byIdFallback != null) {
                return byIdFallback;
            }
        }
        if (od.getOrder_no() != null && !od.getOrder_no().trim().isEmpty()) {
            QueryWrapper<Order> qw = new QueryWrapper<Order>().eq("order_no", od.getOrder_no().trim());
            if (shopId != null) {
                qw.eq("shop_id", shopId);
            }
            Order byNo = orderService.getOne(qw, false);
            if (byNo != null) {
                return byNo;
            }
            // 兜底：避免因门店上下文不一致导致找不到锚点，按 order_no 全局回查一次
            return orderService.getOne(new QueryWrapper<Order>().eq("order_no", od.getOrder_no().trim()), false);
        }
        return null;
    }

    /**
     * 按订单金额分档估算制作时长：
     * <30 => 15 分钟；30-100 => 20 分钟；100-200 => 35 分钟；>200 => 40 分钟。
     */
    private double resolveMakeTimeByAmount(Order od) {
        double amount = (od != null && od.getSett_amount() != null) ? od.getSett_amount() : 0D;
        if (amount < 35D) {
            return MAKE_TIME_VERY_LOW_AMOUNT;
        }
        if (amount < 100D) {
            return MAKE_TIME_LOW_AMOUNT;
        }
        if (amount <= 200D) {
            return MAKE_TIME_MID_AMOUNT;
        }
        return MAKE_TIME_HIGH_AMOUNT;
    }

    @PostMapping("/calculateFinishTime")
    public R calculateFinishTime(@RequestBody Order od, HttpServletRequest request) {
        Integer shopId;
        try {
            shopId = requireResolvedCShop(request);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
        return calculateFinishTimeWithShop(od, shopId);
    }


    @PostMapping("/Business")
    public R getBusiness(HttpServletRequest request) {
        try {
            return getBusinessForShop(requireResolvedCShop(request));
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    /**
     * 按门店读取 C 端「营业接单 / 评价展示」开关（数据来自 {@code t_shop.ordering_open}、{@code t_shop.ordering_review}）。
     */
    private R getBusinessForShop(Integer shopId) {
        shopId = shopIdOrDefault(shopId);
        Shop shop = shopService.getById(shopId);
        if (shop == null) {
            return R.error(404, "门店不存在");
        }
        boolean business = !Integer.valueOf(0).equals(shop.getOrdering_open());
        boolean isReview = Integer.valueOf(1).equals(shop.getOrdering_review());
        return Objects.requireNonNull(R.ok().put("business", business)).put("isReview", isReview).put("shopId", shopId);
    }

    /** 门店营业中（{@code ordering_open=1}）时自动接单；不再依赖运营端自动接单开关。 */
    private boolean shouldAutoAcceptForOrder(Order order) {
        if (order == null) {
            return false;
        }
        Integer shopId = shopIdOrDefault(order.getShop_id());
        Shop shop = shopService.getById(shopId);
        return ShopOrderingOpenHelper.isOrderingOpen(shop);
    }

    private void pushKdsAfterAccepted(Order order, java.util.List<Integer> newDetailIds,
                                      com.lanf.kds.service.KdsOrderHook.Trigger trigger) {
        try {
            kdsOrderHook.afterOrderCommitted(order, newDetailIds, trigger);
        } catch (Exception ex) {
            log.warn("KDS 推送异常，订单号：{}，{}", order != null ? order.getOrder_no() : null, ex.getMessage());
        }
    }

    @PostMapping("/ChangeBusiness")
    public R ChangeBusiness(@RequestBody Map<String, String> body, HttpServletRequest request) {
        Integer shopId;
        try {
            shopId = requireResolvedCShop(request);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
        return changeBusinessCore(shopId, body, request);
    }

    /**
     * 营业状态变更核心逻辑：收银端 {@code POST /cashier/shop/business} 与运营端
     * {@code POST /order/ChangeBusiness} 共用（含开门强制开班 / 关门强制交班·日结 / force 逃生）。
     *
     * @param shopId 已解析的门店 ID（X-Shop-Id）
     */
    public R changeBusinessCore(Integer shopId, Map<String, String> body, HttpServletRequest request) {
        String bus = body != null ? body.get("bus") : null;
        if (bus == null) {
            return R.error("参数传递错误");
        }
        boolean open = "1".equals(bus);
        Shop shop = shopService.getById(shopId);
        if (shop == null) {
            return R.error(404, "门店不存在");
        }
        if (!open) {
            // 关门流程：门店开启 shift_required 时，未交班拦截（force=1 且 admin:manage 可跳过）
            // 注意：打烊与日结先后因果已解耦，打烊不再拦截今日未日结，允许店内在席顾客继续结账并为日结提供清台前提。
            List<String> blockers = new ArrayList<>();
            if (Integer.valueOf(1).equals(shop.getShift_required())) {
                long openShifts = shiftService.count(new QueryWrapper<Shift>()
                        .eq("shop_id", shopId).isNull("end_time"));
                if (openShifts > 0) {
                    blockers.add(openShifts + " 个进行中班次未交班");
                }
            }
            if (!blockers.isEmpty()) {
                boolean force = "1".equals(body.get("force")) || "true".equalsIgnoreCase(body.get("force"));
                boolean canForce = false;
                Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
                if (force && adminId != null) {
                    canForce = adminPermissionService.getPermissionCodesByAdminId(adminId).contains("admin:manage");
                }
                if (!canForce) {
                    return R.error(4000, "无法打烊：" + String.join("、", blockers));
                }
                try {
                    securityAuditService.recordPrivilegedAction(request, shopId, "shop", "close_forced",
                            String.valueOf(shopId), adminId, null, "跳过强制校验：" + String.join("、", blockers));
                } catch (Exception ignore) {
                    // 审计日志失败不阻塞打烊
                }
            }
        } else {
            // 开门强制流程：
            // 1. 门店开启 shift_required 时，未开班不得营业（force=1 且 admin:manage 可跳过）
            // 2. 门店开启 settle_required 时，前一营业日若有订单且未日结，不得营业（force=1 且 admin:manage 可跳过）
            List<String> blockers = new ArrayList<>();
            if (Integer.valueOf(1).equals(shop.getShift_required())) {
                long openShifts = shiftService.count(new QueryWrapper<Shift>()
                        .eq("shop_id", shopId).isNull("end_time"));
                if (openShifts == 0) {
                    blockers.add("未开班不得营业，请先开班");
                }
            }
            if (Integer.valueOf(1).equals(shop.getSettle_required())) {
                LocalDate todayBizDay = ShopBusinessWindowResolver.operationalBusinessDay(shop);
                LocalDate prevBizDay = todayBizDay.minusDays(1);
                boolean prevSettled = (dailyCloseSnapshotMapper != null && dailyCloseSnapshotMapper.selectCount(
                        new QueryWrapper<DailyCloseSnapshot>()
                                .eq("shop_id", shopId)
                                .eq("business_day", prevBizDay)
                                .eq("state", DailyCloseSnapshot.STATE_CLOSED)) > 0)
                        || dailyStatService.count(new QueryWrapper<DailyStat>()
                                .eq("stat_date", prevBizDay).eq("shop_id", shopId)) > 0
                        || dailyStatService.count(new QueryWrapper<DailyStat>()
                                .eq("stat_date", prevBizDay).isNull("shop_id")) > 0;
                if (!prevSettled) {
                    long prevOrderCount = orderService.count(new QueryWrapper<Order>()
                            .eq(shopId != null && !Integer.valueOf(1).equals(shopId), "shop_id", shopId)
                            .apply("DATE(order_time) = {0}", prevBizDay));
                    if (prevOrderCount > 0) {
                        blockers.add("前一营业日(" + prevBizDay + ")尚未日结，请先完成日结再开始营业");
                    }
                }
            }
            if (!blockers.isEmpty()) {
                boolean force = "1".equals(body.get("force")) || "true".equalsIgnoreCase(body.get("force"));
                boolean canForce = false;
                Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
                if (force && adminId != null) {
                    canForce = adminPermissionService.getPermissionCodesByAdminId(adminId).contains("admin:manage");
                }
                if (!canForce) {
                    return R.error(4001, String.join("、", blockers));
                }
                try {
                    securityAuditService.recordPrivilegedAction(request, shopId, "shop", "open_forced",
                            String.valueOf(shopId), adminId, null, "跳过强制校验：" + String.join("、", blockers));
                } catch (Exception ignore) {
                    // 审计日志失败不阻塞营业
                }
            }
        }
        shopService.update(new UpdateWrapper<Shop>()
                .eq("id", shopId)
                .set("ordering_open", open ? 1 : 0));
        dishMenuPushService.notifyBusinessChanged(open, shopId);
        if (open) {
            try {
                processPendingOrdersForAutoAccept(shopId);
            } catch (Exception e) {
                log.warn("门店开始营业时处理待接单订单异常, shopId={}, {}", shopId, e.getMessage());
            }
        }
        return R.ok().put("business", open).put("shopId", shopId);
    }

    @PostMapping("/ChangeIsReview")
    public R ChangeIsReview(HttpServletRequest request) {
        Integer shopId;
        try {
            shopId = requireResolvedCShop(request);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
        Shop shop = shopService.getById(shopId);
        if (shop == null) {
            return R.error(404, "门店不存在");
        }
        int next = Integer.valueOf(1).equals(shop.getOrdering_review()) ? 0 : 1;
        shopService.update(new LambdaUpdateWrapper<Shop>()
                .eq(Shop::getId, shopId)
                .set(Shop::getOrdering_review, next));
        return next == 1 ? R.ok("真") : R.ok("假");
    }
    /**
     * 创建订单
     */
    @Transactional(rollbackFor = Exception.class)
    @RequestMapping("/create")
    public R create(@RequestBody OrderDTO order, HttpServletRequest request) {
        try {
            applyShopContextToOrderDto(order, request);
            resolveOrderChannelAndOperator(order, request);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
        Shop currentShop = shopService.getById(order.getShop_id());
        boolean isCashier = request != null && Boolean.TRUE.equals(request.getAttribute(CASHIER_QUICK_ORDER_ATTRIBUTE));
        if (!isCashier && !ShopOrderingOpenHelper.isOrderingOpen(currentShop)) {
            return R.error(4003, "门店已打烊，暂不接单");
        }
        // 堂食：按桌台做防重；打包：不做并发限制，一个二维码可多次下单
        boolean isDineIn = Objects.equals(order.getDineInOrTakeOut(), "堂食");

        // 桌号 666 为打包专用二维码，只在堂食模式下禁止使用
        if (isDineIn && Objects.equals(order.getTable_number(), "666")) {
            return R.error("桌号666是打包专用二维码，请重新扫码");
        }

        // 收银端可将自己预开的空桌转为订单；C 端仍不能抢占该桌。
        if (shouldBlockPreopenedTable(isDineIn, request)) {
            QueryWrapper<Table> occupiedQuery = new QueryWrapper<Table>().eq("number", order.getTable_number());
            appendTableShopScope(occupiedQuery, order.getShop_id());
            Table occupiedTable = tableService.getOne(occupiedQuery.last("LIMIT 1"));
            if (occupiedTable != null && Integer.valueOf(1).equals(occupiedTable.getStatus())
                    && !StringUtils.hasText(occupiedTable.getOrder_no())) {
                return R.error("该桌台已开台占用，请联系服务员");
            }
        }

        // 打包订单：不使用 processingOrders 防重，一个二维码可以多次下单打包
        if (!isDineIn) {
            try {
                boolean ok = processOrder(order);
                if (!ok) {
                    return R.error("创建订单失败");
                }
                
                logOrder(order.getOrder_no(), "create", "openid", order.getOpenid(), order.getShop_id(), null);
                return R.ok().put("order_no", order.getOrder_no()).put("id", order.getId());
            } catch (Exception e) {
                log.error("外带/外卖订单创建失败", e);
                String packMsg = (e.getMessage() != null && !e.getMessage().isEmpty())
                        ? e.getMessage() : "系统繁忙，请稍后再试";
                return R.error(packMsg);
            }
        }

        // 堂食订单：检测该桌是否存在未结账订单，存在则走加菜，否则创建新单
        QueryWrapper<Order> unsettledQw = new QueryWrapper<Order>()
                .eq("table_number", order.getTable_number())
                .eq("dineInOrTakeOut", "堂食")
                .eq("transac_status", "unsettled");
        if (order.getShop_id() != null) {
            unsettledQw.eq("shop_id", order.getShop_id());
        }
        Order existingUnsettled = orderService.getOne(unsettledQw
                .orderByDesc("order_time")
                .last("LIMIT 1"));
        if (existingUnsettled != null) {
            String existingOrderNo = existingUnsettled.getOrder_no();
            String tip = (existingOrderNo != null && !existingOrderNo.trim().isEmpty())
                    ? "该桌台存在未结账订单，订单号：" + existingOrderNo.trim() + "，请使用加菜或先结清后再开新单。"
                    : "该桌台存在未结账订单！";
            R r = R.error(tip);
            if (existingOrderNo != null && !existingOrderNo.trim().isEmpty()) {
                r.put("order_no", existingOrderNo.trim());
            }
            return r;
        }

        // 不存在未结账订单，按新单创建
        String orderKey = generateOrderKey(order.getShop_id(), order.getTable_number());
        java.util.concurrent.atomic.AtomicReference<Throwable> orderError = new java.util.concurrent.atomic.AtomicReference<>();
        try {
            // 检查是否有其他线程正在处理该桌台的订单
            if (processingOrders.asMap().containsKey(orderKey)) {
                return R.error("该桌台正在处理订单，请稍后再试");
            }

            // 使用Caffeine的get方法获取处理结果
            Boolean isProcessing = processingOrders.get(orderKey, k -> {
                try {
                    // 执行订单处理逻辑
                    return processOrder(order);
                } catch (Exception e) {
                    // 捕获processOrder中的异常并保留，供返回给前端
                    log.error("处理订单时发生异常", e);
                    orderError.set(e);
                    return false; // 返回false表示处理失败
                }
            });

            // 根据处理结果返回响应（确保这部分代码必然执行）
            if (isProcessing != null && isProcessing) {
                

                logOrder(order.getOrder_no(), "create", "openid", order.getOpenid(), order.getShop_id(), null);
                return R.ok().put("order_no", order.getOrder_no()).put("id", order.getId());
            } else {
                Throwable err = orderError.get();
                String msg = (err != null && err.getMessage() != null && !err.getMessage().isEmpty())
                        ? err.getMessage() : "创建订单失败，请勿多人同时下单";
                return R.error(msg);
            }
        } catch (Exception e) {
            // 捕获外层所有可能的异常，确保返回响应，并返回捕获到的错误信息
            log.error("订单接口整体异常", e);
            String msg = (e.getMessage() != null && !e.getMessage().isEmpty()) ? e.getMessage() : "系统繁忙，请稍后再试";
            return R.error(msg);
        } finally {
            // 在响应返回后，异步清理缓存，避免阻塞
            if (orderKey != null) {
                String finalOrderKey = orderKey;
                Runnable cleanup = () -> {
                    try {
                        // 短暂延迟，确保响应已发出
                        Thread.sleep(100);
                        processingOrders.invalidate(finalOrderKey);
                        log.info("异步清理缓存成功，orderKey: {}", finalOrderKey);
                    } catch (Exception e) {
                        log.error("异步清理缓存失败，orderKey: {}", finalOrderKey, e);
                    }
                };
                try {
                    processingOrderCleanup.execute(cleanup);
                } catch (java.util.concurrent.RejectedExecutionException rejected) {
                    // Saturation must not leave this per-table guard live for its five-minute cache TTL.
                    processingOrders.invalidate(finalOrderKey);
                    log.warn("订单缓存清理队列已满，立即释放 orderKey: {}", finalOrderKey);
                }
            }
        }
    }

    @PreDestroy
    public void shutdownProcessingOrderCleanup() {
        processingOrderCleanup.shutdownNow();
    }

    /**
     * 生成随机订单key，包含数字和字母，长度为32位
     */
    private String generateRandomOrderKey() {
        String characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        StringBuilder sb = new StringBuilder(32);
        Random random = new Random();

        for (int i = 0; i < 32; i++) {
            int index = random.nextInt(characters.length());
            sb.append(characters.charAt(index));
        }

        // 可以加入时间戳前缀进一步降低冲突概率
        return System.currentTimeMillis() + "-" + sb.toString();
    }

    /**
     * 通过微信官方API获取用户手机号
     * 使用最新的getuserphonenumber接口，通过code换取手机号
     */
    @PostMapping("/getOfficialPhoneNumber")
    public R getOfficialPhoneNumber(@RequestBody Map<String, String> params) {
        try {
            // 1. 获取请求参数
            String code = params.get("code");
            String openid = params.get("openid");
            String invite_code = params.get("invite_code");

            // 2. 参数校验
            if (code == null || code.trim().isEmpty()) {
                return R.error("code不能为空");
            }

            // 3. 获取 access_token 并调用微信获取手机号接口（42001 时清除缓存重试一次）
            Map<String, String> requestBody = new HashMap<>();
            requestBody.put("code", code);
            if (openid != null && !openid.trim().isEmpty()) {
                requestBody.put("openid", openid);
            }
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);

            String responseStr = null;
            JsonObject responseJson = null;
            int errCode = -1;
            final int maxAttempts = 2;

            for (int attempt = 0; attempt < maxAttempts; attempt++) {
                String accessToken = getAccessToken();
                if (accessToken == null) {
                    return R.error("获取access_token失败");
                }
                String url = "https://api.weixin.qq.com/wxa/business/getuserphonenumber?access_token=" + accessToken;
                HttpEntity<Map<String, String>> requestEntity = new HttpEntity<>(requestBody, headers);
                responseStr = restTemplate.postForObject(url, requestEntity, String.class);
                if (responseStr == null) {
                    return R.error("调用微信接口失败，未获取到响应");
                }
                responseJson = JsonParser.parseString(responseStr).getAsJsonObject();
                errCode = responseJson.get("errcode").getAsInt();
                if (errCode == 0) {
                    break;
                }
                // access_token 过期：清除缓存后重试一次
                if (errCode == 42001 && attempt == 0) {
                    log.warn("微信 access_token 已过期(42001)，清除缓存并重试");
                    tokenCache.invalidate("access_token");
                    continue;
                }
                String errMsg = responseJson.get("errmsg").getAsString();
                log.error("微信获取手机号接口错误: [{}] {}", errCode, errMsg);
                if (errCode == 40029) {
                    return R.error("code无效或已过期，请重新获取");
                } else if (errCode == 45011) {
                    return R.error("接口调用太频繁，请稍后再试");
                } else if (errCode == 40013) {
                    return R.error("appid无效，请检查配置");
                } else {
                    return R.error("获取手机号失败: " + errMsg);
                }
            }

            if (errCode != 0) {
                return R.error("获取手机号失败，请稍后重试");
            }

            // 5. 解析手机号信息
            JsonObject phoneInfo = responseJson.getAsJsonObject("phone_info");
            if (phoneInfo == null) {
                return R.error("未获取到手机号信息");
            }

            String phoneNumber = phoneInfo.get("phoneNumber").getAsString();
            String purePhoneNumber = phoneInfo.get("purePhoneNumber").getAsString();
            String countryCode = phoneInfo.get("countryCode").getAsString();

            // 6. 如果提供了openid，更新用户手机号
            if (openid != null && !openid.trim().isEmpty()) {
                User user = userService.getUserByOpenid(openid);
                if (user != null) {
                    user.setPhone(phoneNumber);
                    userService.updateById(user);
                    if(StringUtils.hasText(invite_code)){
                        // 2. 查询邀请人（通过邀请码）
                        User inviterUser = userMapper.selectByInvite_code(invite_code);

                        // 3. 关键：先判断inviterUser是否为null，避免空指针
                        if (inviterUser != null) {
                            // 4. 严谨判空：inviterUser的openid非null且非空字符串
                            String inviterOpenid = inviterUser.getOpenid();
                            if (StringUtils.hasText(inviterOpenid)) {
                                // 5. 创建邀请记录（修正字段赋值逻辑，区分邀请人和被邀请人）
                                InviteRecord inviteRecord = new InviteRecord();
                                inviteRecord.setInviter_openid(inviterOpenid); // 邀请人openid（关键：补充赋值）
                                inviteRecord.setInvitee_openid(openid); // 被邀请人openid（当前用户，仅赋值一次）
                                inviteRecord.setInvite_code(invite_code); // 邀请码
                                inviteRecord.setCreate_time(new Date()); // 创建时间
                                inviteRecord.setStatus(0); // 初始化状态：0-未发放奖励（与giveReward方法兼容）

                                try {
                                    // 6. 保存邀请记录 + 发放奖励（建议放在同一事务中，保证数据一致性）
                                    InviteService.save(inviteRecord);
                                    InviteService.giveReward(invite_code, openid);
                                    log.info("event=invite_reward_created");
                                } catch (Exception e) {
                                    log.error("event=invite_reward_failed");
                                    // 可根据业务需求抛出异常或返回错误提示
                                    throw new RuntimeException("邀请奖励处理失败", e);
                                }
                            } else {
                                log.warn("event=invite_identity_missing");
                            }
                        }

                    }
                }
            }

            // 7. 构建返回结果
            Map<String, Object> result = new HashMap<>();
            result.put("phoneNumber", phoneNumber);
            result.put("purePhoneNumber", purePhoneNumber);
            result.put("countryCode", countryCode);
            result.put("updateSuccess", openid != null);

            return R.ok().put("data", result);

        } catch (Exception e) {
            log.error("获取用户手机号手机号失败", e);
            return R.error("获取手机号失败");
        }
    }

    /**
     * 新增：优惠券复检核心方法（独立封装，便于维护）
     * @param order 订单对象（需包含优惠券ID/码、用户openid、订单金额等字段）
     * @param isAddDishes true=加菜场景（一单只能用一次优惠），false=首次下单（可用优惠券）
     */
    private void validateCoupon(OrderDTO order, boolean isAddDishes) {
        // coupon_id 语义：t_user_coupon.id（用户券记录ID）；inputCouponId 为请求原始值（推断前），用于加菜「禁止再叠新券」判断
        Long inputCouponId = order.getCoupon_id();
        Long couponId = inputCouponId;
        log.info("用户couponId: {} (input)", couponId);

        // 未传用户券ID时：若该单已在 t_user_coupon 绑定 order_no，则按绑定记录推断用户券（支付等场景可不重复传 coupon_id）
        if (couponId == null || couponId == 0L || couponId < 0) {
            String orderNoHint = order.getOrder_no();
            String uidHint = order.getOpenid();
            if (StringUtils.hasText(orderNoHint) && StringUtils.hasText(uidHint)) {
                UserCoupon bound = UserCouponMapper.selectOne(
                        new QueryWrapper<UserCoupon>()
                                .eq("order_no", orderNoHint.trim())
                                .eq("user_openid", uidHint.trim())
                                .eq("status", 0)
                                .last("LIMIT 1"));
                if (bound != null && bound.getId() != null) {
                    couponId = bound.getId();
                    order.setCoupon_id(couponId);
                }
            }
        }

        // 未使用优惠券：null、0 或 ≤0；优惠金额以服务端为准，清零前端虚报
        if (couponId == null || couponId == 0L || couponId < 0) {
            order.setDiscount_amount(0d);
            return;
        }

        // 1.1 仅加菜时判断：一单只能用一次优惠。仅当客户端显式传了 coupon_id、且本单已绑定过用户券时拒绝（推断绑券不算「再叠券」）
        if (isAddDishes) {
            String orderNo = order.getOrder_no();
            if (orderNo != null && !orderNo.isEmpty()) {
                long usedCount = UserCouponMapper.selectCount(
                        new QueryWrapper<UserCoupon>().eq("order_no", orderNo));
                if (usedCount > 0 && inputCouponId != null && inputCouponId > 0) {
                    throw new RuntimeException("一单只能用一次优惠，当前订单已使用过优惠券");
                }
            }
        }

        // 2. 统一复用 /coupon/validateRule 的服务层规则校验（不占用券，不核销）
        String uid = order.getOpenid();
        if (uid == null || uid.trim().isEmpty()) {
            throw new RuntimeException("使用优惠券时 openid 不能为空");
        }
        CouponRuleValidateRequest vr = new CouponRuleValidateRequest();
        vr.setOpenid(uid.trim());
        vr.setCoupon_id(couponId);
        vr.setShop_id(order.getShop_id());
        vr.setDineInOrTakeOut(order.getDineInOrTakeOut());
        vr.setGoods_list(order.getGoods_list());
        // 不以客户端传入的优惠金额参与校验；由 CouponService 按券规则计算
        vr.setDiscount_amount(null);
        com.lanf.dto.R<CouponRuleValidateResult> vrResp = CouponService.validateCouponRule(vr);
        if (vrResp == null || vrResp.getCode() == null || vrResp.getCode() != 0) {
            String msg = (vrResp != null && StringUtils.hasText(vrResp.getMsg())) ? vrResp.getMsg() : "优惠券规则校验失败";
            throw new RuntimeException(msg);
        }
        CouponRuleValidateResult vrData = vrResp.getData();
        double serverDiscount = 0d;
        if (vrData != null && vrData.getDiscount_amount() != null) {
            serverDiscount = Math.round(vrData.getDiscount_amount() * 100) / 100.0;
        }

        // 3. 查询用户优惠券（后续用于占用与并发保护）
        UserCouponDTO Usercoupon = userService.selectByCouponById(couponId, uid.trim());
        if (Usercoupon == null) {
            throw new RuntimeException("优惠券不存在，请核对后重新提交");
        }

        String currentOrderNo = order.getOrder_no();
        if (currentOrderNo == null || currentOrderNo.trim().isEmpty()) {
            throw new RuntimeException("订单号为空，无法绑定优惠券");
        }

        // 4. 优惠券占用校验（原子抢占，避免并发/重复提交导致“刚领取却提示被占用”）
        // 4.1 仅当 order_no 为空时写入当前订单号，保证同一张券只有一个请求能抢占成功
        int claimed = UserCouponMapper.update(null, new UpdateWrapper<UserCoupon>()
                .set("order_no", currentOrderNo)
                .eq("id", Usercoupon.getId())
                .and(w -> w.isNull("order_no").or().eq("order_no", "")));
        if (claimed == 0) {
            // 已被占用：查当前绑定的订单号；若绑定的是当前订单（如创建订单时已抢占），直接通过
            String boundOrderNo = Usercoupon.getOrder_no();
            UserCoupon fresh = UserCouponMapper.selectById(Usercoupon.getId());
            if (fresh != null) boundOrderNo = fresh.getOrder_no();
            if (boundOrderNo != null && !boundOrderNo.trim().isEmpty()) {
                if (currentOrderNo.equals(boundOrderNo.trim())) {
                    // 已绑定当前订单（如先创建订单再调 getPrepayId），通过占用校验，继续后续校验
                } else {
                    Order boundOrder = orderService.getOne(new QueryWrapper<Order>().eq("order_no", boundOrderNo));
                    if (boundOrder != null && !"cancelled".equals(boundOrder.getTransac_status())) {
                        throw new RuntimeException("该优惠券已被其他订单占用，无法使用");
                    }
                    // 订单已取消，允许重新绑定到当前订单
                    UserCouponMapper.update(null, new UpdateWrapper<UserCoupon>().set("order_no", currentOrderNo).eq("id", Usercoupon.getId()));
                }
            } else {
                throw new RuntimeException("该优惠券已被其他订单占用，无法使用");
            }
        }

        // 订单号已在步骤 4 原子抢占时绑定；规则校验已统一由 CouponService.validateCouponRule 完成
        order.setDiscount_amount(serverDiscount);
        log.info("优惠券校验通过（复用统一规则接口），已绑定订单，优惠券ID：{}，服务端优惠金额：{}", couponId, serverDiscount);
    }

    /**
     * 根据优惠券类型和订单原价计算优惠金额（用于加菜时重算）。
     * full_reduction/direct_reduction：固定 discount_value 元；discount 折扣：优惠 = 原价 * (100 - discount_value) / 100。
     * @param totalRaw 订单原价（未优惠前总金额）
     * @param coupon 优惠券主表信息，可为 null
     * @return 优惠金额（元），无券或无法计算时返回 0
     */
    private double calcDiscountFromCoupon(double totalRaw, com.lanf.entity.Coupon coupon) {
        if (coupon == null || coupon.getCoupon_type() == null || totalRaw <= 0) {
            return 0d;
        }
        double dv = coupon.getDiscount_value() != null ? coupon.getDiscount_value().doubleValue() : 0d;
        String type = coupon.getCoupon_type().trim().toLowerCase();
        if ("direct_reduction".equals(type) || "full_reduction".equals(type)) {
            return Math.min(dv, totalRaw); // 优惠不超过原价
        }
        if ("discount".equals(type) && dv > 0 && dv <= 100) {
            return totalRaw * (100 - dv) / 100;
        }
        return 0d;
    }

    /**
     * 按券类型计算应得优惠金额（历史方法；下单链路以 {@link CouponService#validateCouponRule} 计算结果为准）。
     * full_reduction/立减：固定 discount_value 元；discount 折扣：原价=sett_amount，应优惠=原价*(100-discount_value)/100。
     * @return 应得优惠金额（元），若无法计算则返回 null（不校验）
     */
    private Double calcExpectedDiscount(UserCouponDTO coupon, Double settAmount, Double frontDiscount) {
        if (coupon == null || coupon.getCoupon_type() == null) {
            return null;
        }
        String type = coupon.getCoupon_type().trim().toLowerCase();
        Double dv = coupon.getDiscount_value();
        if ("direct_reduction".equals(type) || "full_reduction".equals(type)) {
            return (dv != null) ? dv : null;
        }
        if ("discount".equals(type) && dv != null && dv > 0 && settAmount != null) {
            // sett_amount=原价，优惠 = 原价 * (100 - discount_value) / 100
            return settAmount * (100 - dv) / 100;
        }
        return null;
    }

    /**
     * 按券类型计算「适用原价」对应的应得优惠（立减/满减/折扣）。
     * 折扣券：优惠 = 适用原价 * (100 - 折扣值) / 100
     */
    private Double calcExpectedDiscountForBarbecue(UserCouponDTO coupon, double eligibleRaw) {
        if (coupon == null || coupon.getCoupon_type() == null) {
            return null;
        }
        String type = coupon.getCoupon_type().trim().toLowerCase();
        Double dv = coupon.getDiscount_value();

        // 立减：优惠金额 = 券面值，不超过适用原价
        if ("direct_reduction".equals(type)) {
            if (dv == null) return null;
            return Math.min(dv, eligibleRaw);
        }

        // 满减：满门槛后减固定金额，优惠 = 券面值，不超过适用原价
        if ("full_reduction".equals(type)) {
            if (dv == null) return null;
            return Math.min(dv, eligibleRaw);
        }

        // 折扣：优惠 = 适用原价 * (100 - 折扣值) / 100
        if ("discount".equals(type) && dv != null && dv > 0 && dv <= 100) {
            return eligibleRaw * (100 - dv) / 100;
        }
        return null;
    }

    /** 行小计与「单价×数量」允许误差（元），避免浮点舍入误杀 */
    private static final double ORDER_LINE_PRICE_EPS = 0.02;

    /** t_order.discount_amount 大于 0 视为库表侧已有优惠（含历史已写入的券后/九折等） */
    /** 校验券并填充应付上下文；失败时 {@code R.code != 0} */
    private R fillPayableAmountContext(Order order, Long couponId, String openidForCoupon, PayableAmountContext ctx) {
        return paymentSettlementService.fillPayableAmountContext(order, couponId, openidForCoupon, ctx);
    }

    /**
     * 支付成功后公共处理：核销券、反积分、桌台、打印（与微信支付回调一致）。
     */
    private void runPostPaymentSuccessSideEffects(Order latestOrder, double paidYuan) {
        paymentSuccessHandler.run(latestOrder, paidYuan);
    }

    /**
     * 与 {@link #getPrepayId} 一致：校验券、写回订单 {@code discount_amount}，并返回应付金额（元）与商户号。
     *
     * @param allowNineFold 是否允许叠加夜间九折（余额支付须传 {@code false}）
     */
    private R settleOrderPayableAmounts(Order order, Long couponId, String openidForCoupon, boolean allowNineFold) {
        return paymentSettlementService.settle(order, couponId, openidForCoupon, allowNineFold);
    }

    private static int parseGoodsQuantityPositive(String quantityRaw) {
        if (!StringUtils.hasText(quantityRaw)) {
            throw new RuntimeException("存在数量为空或非法的明细，请检查");
        }
        Matcher m = Pattern.compile("(\\d+)").matcher(quantityRaw.trim());
        if (!m.find()) {
            throw new RuntimeException("数量格式非法：" + quantityRaw.trim());
        }
        int n = Integer.parseInt(m.group(1));
        if (n <= 0) {
            throw new RuntimeException("数量须为正整数");
        }
        return n;
    }

    private Dish resolveDishByMenuName(String dishName) {
        return resolveDishByMenuName(dishName, null);
    }

    /**
     * 按菜单名解析菜品；带 shopId 时额外匹配门店覆盖名（t_dish_shop.name_override，方案 A），
     * 使「门店改了菜名后下单/加菜/套餐校验/优惠券金额」按门店菜单名也能命中。
     */
    private Dish resolveDishByMenuName(String dishName, Integer shopId) {
        Dish dish = dishService.getOne(new LambdaQueryWrapper<Dish>()
                .eq(Dish::getName, dishName)
                .last("LIMIT 1"));
        if (dish == null) {
            String compact = dishName.replaceAll("\\s+", "");
            if (!compact.equals(dishName)) {
                dish = dishService.getOne(new LambdaQueryWrapper<Dish>()
                        .eq(Dish::getName, compact)
                        .last("LIMIT 1"));
            }
        }
        if (dish == null && shopId != null) {
            dish = resolveByShopNameOverride(shopId, dishName);
            if (dish == null) {
                String compact = dishName.replaceAll("\\s+", "");
                if (!compact.equals(dishName)) {
                    dish = resolveByShopNameOverride(shopId, compact);
                }
            }
        }
        return dish;
    }

    /**
     * 门店覆盖名匹配：t_dish_shop.name_override 命中后取总部菜品（方案 A）。
     */
    private Dish resolveByShopNameOverride(Integer shopId, String dishName) {
        if (shopId == null || !StringUtils.hasText(dishName)) {
            return null;
        }
        DishShop link = dishShopMapper.selectOne(new QueryWrapper<DishShop>()
                .eq("shop_id", shopId)
                .eq("name_override", dishName)
                .last("LIMIT 1"));
        if (link == null || link.getDish_id() == null) {
            return null;
        }
        return dishService.getById(link.getDish_id());
    }

    /**
     * 订单明细补充菜品ID（dish_id），便于前端按优惠券适用菜品筛选。
     */
    private List<Map<String, Object>> enrichOrderDetailsWithDishId(List<OrderDetail> details, Integer shopId) {
        if (details == null || details.isEmpty()) {
            return Collections.emptyList();
        }
        List<Map<String, Object>> out = new ArrayList<>(details.size());
        for (OrderDetail od : details) {
            if (od == null) {
                continue;
            }
            @SuppressWarnings("unchecked")
            Map<String, Object> item = objectMapper.convertValue(od, Map.class);
            Integer dishId = null;
            if (StringUtils.hasText(od.getName())) {
                Dish dish = resolveDishByMenuName(od.getName().trim(), shopId);
                if (dish != null) {
                    dishId = dish.getId();
                }
            }
            item.put("dish_id", dishId);
            out.add(item);
        }
        return out;
    }

    /**
     * 是否按「有限库存」处理：null 或负数表示不限量；正数表示有限库存；0 在下架时视为卖空（需跟踪），在上架时视为未启用库存（兼容）。
     */
    private static boolean isStockTrackedByValue(Integer stock, boolean onsale) {
        if (stock == null || stock < 0) {
            return false;
        }
        if (stock > 0) {
            return true;
        }
        return !onsale;
    }

    private static final class DishStockRef {
        final Integer shopId;
        final Integer dishId;
        final String dishName;
        final boolean fromShop;
        final boolean tracked;
        final boolean onsale;
        final Integer stock;
        final Integer soldOut;
        final BigDecimal unitprice;

        DishStockRef(Integer shopId, Integer dishId, String dishName, boolean fromShop, boolean tracked, boolean onsale, Integer stock, Integer soldOut, BigDecimal unitprice) {
            this.shopId = shopId;
            this.dishId = dishId;
            this.dishName = dishName;
            this.fromShop = fromShop;
            this.tracked = tracked;
            this.onsale = onsale;
            this.stock = stock;
            this.soldOut = soldOut;
            this.unitprice = unitprice;
        }
    }

    /**
     * 连锁严格库存：仅允许门店库存（t_dish_shop.stock），不回退总部 t_dish.stock。
     */
    private DishStockRef resolveDishStockRef(Integer shopId, Integer dishId, Dish dish) {
        if (shopId == null) {
            throw new RuntimeException("订单缺少门店ID，无法执行门店库存操作");
        }
        if (dishId == null || dish == null) {
            throw new RuntimeException("菜品信息缺失，无法执行门店库存操作");
        }
        DishShop link = dishShopMapper.selectOne(new QueryWrapper<DishShop>()
                .eq("shop_id", shopId)
                .eq("dish_id", dishId)
                .last("LIMIT 1"));
        if (link == null) {
            throw new RuntimeException("菜品「" + dish.getName() + "」未挂到当前门店，无法执行库存操作");
        }
        if (link.getStock() == null) {
            throw new RuntimeException("菜品「" + dish.getName() + "」门店库存未配置，请先在门店设置库存");
        }
        Integer s = link.getStock();
        Integer soldOut = link.getSold_out();
        if (soldOut == null && s != null && s >= 0) {
            soldOut = s <= 0 ? 1 : 0;
        }
        BigDecimal unitprice = link.getUnitprice();
        boolean effectiveOnsale = link.getOnsale_override() != null ? link.getOnsale_override() == 1 : dish.isOnsale();
        // 与 DishShopStockServiceImpl 一致：跟踪与否以持久标志为准，标志缺失（迁移未执行）时回退旧启发式
        boolean tracked = link.getStock_enabled() != null
                ? link.getStock_enabled() == 1
                : isStockTrackedByValue(s, effectiveOnsale);
        return new DishStockRef(shopId, dishId, dish.getName(), true, tracked, effectiveOnsale, s, soldOut, unitprice);
    }

    /** 同一单内多行同名菜品合并后校验/扣减库存 */
    private Map<Integer, Integer> aggregateDishQuantitiesForStock(List<OrderDetail> goodsList, Integer shopId) {
        Map<Integer, Integer> map = new HashMap<>();
        if (goodsList == null) {
            return map;
        }
        for (OrderDetail od : goodsList) {
            if (!StringUtils.hasText(od.getName())) {
                continue;
            }
            if ("combo_header".equalsIgnoreCase(od.getLine_type())) {
                continue;
            }
            Dish dish = resolveDishByMenuName(od.getName().trim(), shopId);
            if (dish == null || dish.getId() == null) {
                continue;
            }
            DishStockRef ref = resolveDishStockRef(shopId, dish.getId(), dish);
            if (!ref.tracked) {
                continue;
            }
            int q = parseGoodsQuantityPositive(od.getQuantity());
            map.merge(dish.getId(), q, Integer::sum);
        }
        return map;
    }

    private void validateAggregatedStock(List<OrderDetail> goodsList, Integer shopId) {
        dishShopStockService.validateCanDeduct(goodsList, shopId);
    }

    /**
     * 下单/加菜成功后扣减库存；并发下用 stock 条件更新保证不超卖。
     */
    private void applyStockDeductionForGoodsList(List<OrderDetail> goodsList, Integer shopId) {
        dishShopStockService.deductForDetails(goodsList, shopId);
    }

    /** 取消未支付订单时回退占用库存（跳过已退菜行） */
    private void restoreStockForCancelledOrder(Integer orderId, Integer shopId) {
        if (orderId == null) {
            return;
        }
        List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", orderId));
        for (OrderDetail od : details) {
            if (OrderDetailLineStatus.isRefunded(od.getLine_status())) {
                continue;
            }
            try {
                dishShopStockService.restoreForDetail(od, shopId);
            } catch (RuntimeException ex) {
                log.warn("取消订单回退库存跳过，明细 id={} name={}: {}", od.getId(), od.getName(), ex.getMessage());
            }
        }
    }

    /**
     * 校验订单明细中的套餐商业化运营规则（限购、时段、用餐方式等）。
     * 收银端（isCashier=true）豁免商业化限制。
     */
    private void validateComboCommercialRulesInCart(List<OrderDetail> goodsList, Integer shopId, String openid, String diningType, boolean isCashier) {
        if (isCashier || (openid != null && "cashier_system".equalsIgnoreCase(openid.trim()))) {
            return;
        }
        if (goodsList == null || goodsList.isEmpty() || comboMealService == null) {
            return;
        }
        Map<Long, Integer> totalQtyByCombo = new HashMap<>();
        for (OrderDetail od : goodsList) {
            if (od != null && "combo_header".equalsIgnoreCase(od.getLine_type()) && od.getCombo_id() != null) {
                int q = parseGoodsQuantityPositive(od.getQuantity());
                totalQtyByCombo.merge(od.getCombo_id(), q, Integer::sum);
            }
        }
        for (Map.Entry<Long, Integer> entry : totalQtyByCombo.entrySet()) {
            comboMealService.validateComboCommercialRules(entry.getKey(), shopId, entry.getValue(), openid, diningType, false);
        }
    }

    private void validateComboCommercialRulesInCart(List<OrderDetail> goodsList, Integer shopId, String openid, String diningType) {
        validateComboCommercialRulesInCart(goodsList, shopId, openid, diningType, false);
    }

    /**
     * 下单/加菜：明细须在库且在售，核心价格合法且与库内单价×数量一致（防止 AI/前端篡改金额、0 价、负数）。
     * 套餐：combo_header 走套餐价校验；combo_component 价为 0 仅作子菜销量/库存，不按单品行计价。
     */
    private void validateOrderDetailsOnSale(List<OrderDetail> goodsList, Integer shopId) {
        if (goodsList == null || goodsList.isEmpty()) {
            return;
        }
        for (OrderDetail od : goodsList) {
            String rawName = od.getName();
            if (!StringUtils.hasText(rawName)) {
                throw new RuntimeException("存在菜品名称为空的明细，请检查");
            }
            if (!StringUtils.hasText(od.getUnit())) {
                throw new RuntimeException("菜品「" + rawName.trim() + "」缺少单位 unit，请检查");
            }
            if (!StringUtils.hasText(od.getCid())) {
                throw new RuntimeException("菜品「" + rawName.trim() + "」缺少 cid，请检查");
            }
            int qty = parseGoodsQuantityPositive(od.getQuantity());
            Double lineTotal = od.getTotal_price();
            String lt = od.getLine_type();

            if ("combo_component".equalsIgnoreCase(lt)) {
                if (lineTotal == null) {
                    od.setTotal_price(0d);
                    lineTotal = 0d;
                }
                if (lineTotal < 0 || Math.abs(lineTotal) > ORDER_LINE_PRICE_EPS) {
                    throw new RuntimeException("菜品「" + rawName.trim() + "」为套餐子行，total_price 须为 0");
                }
                String dishName = rawName.trim();
                Dish dish = od.getDish_id() != null && od.getDish_id() > 0
                        ? dishService.getById(od.getDish_id()) : null;
                if (dish == null) {
                    dish = resolveDishByMenuName(dishName, shopId);
                }
                if (dish == null) {
                    throw new RuntimeException("菜品「" + dishName + "」不存在，请从在售菜单中选择");
                }
                DishStockRef stockRef = resolveDishStockRef(shopId, dish.getId(), dish);
                if (!stockRef.onsale) {
                    throw new RuntimeException("菜品「" + dish.getName() + "」已下架，暂时无法下单");
                }
                if (stockRef.soldOut != null && stockRef.soldOut == 1) {
                    throw new RuntimeException("菜品「" + dish.getName() + "」已售罄，暂时无法下单");
                }
                continue;
            }

            if ("combo_header".equalsIgnoreCase(lt)) {
                if (lineTotal == null || lineTotal <= 0) {
                    throw new RuntimeException("套餐「" + rawName.trim() + "」小计须大于 0");
                }
                String dishName = rawName.trim();
                Dish dish = od.getDish_id() != null && od.getDish_id() > 0
                        ? dishService.getById(od.getDish_id()) : null;
                if (dish == null) {
                    dish = resolveDishByMenuName(dishName, shopId);
                }
                if (dish == null) {
                    throw new RuntimeException("菜品「" + dishName + "」不存在，请从在售菜单中选择");
                }
                DishStockRef stockRef = resolveDishStockRef(shopId, dish.getId(), dish);
                if (!stockRef.onsale) {
                    throw new RuntimeException("菜品「" + dish.getName() + "」已下架，暂时无法下单");
                }
                if (stockRef.soldOut != null && stockRef.soldOut == 1) {
                    throw new RuntimeException("菜品「" + dish.getName() + "」已售罄，暂时无法下单");
                }
                comboMealService.assertHeaderPriceMatches(od, shopId);
                continue;
            }

            if (lineTotal == null) {
                throw new RuntimeException("菜品「" + rawName.trim() + "」缺少总价 total_price，请检查");
            }
            if (lineTotal <= 0) {
                throw new RuntimeException("菜品「" + rawName.trim() + "」小计须大于 0，禁止 0 或负数");
            }

            String dishName = rawName.trim();
            Dish dish = od.getDish_id() != null && od.getDish_id() > 0
                    ? dishService.getById(od.getDish_id()) : null;
            if (dish == null) {
                dish = resolveDishByMenuName(dishName, shopId);
            }
            if (dish == null) {
                throw new RuntimeException("菜品「" + dishName + "」不存在，请从在售菜单中选择");
            }
            DishStockRef stockRef = resolveDishStockRef(shopId, dish.getId(), dish);
            if (!stockRef.onsale) {
                throw new RuntimeException("菜品「" + dish.getName() + "」已下架，暂时无法下单");
            }
            if (stockRef.soldOut != null && stockRef.soldOut == 1) {
                throw new RuntimeException("菜品「" + dish.getName() + "」已售罄，暂时无法下单");
            }
            double unitPrice = stockRef.unitprice != null
                    ? stockRef.unitprice.doubleValue()
                    : (dish.getUnitprice() != null ? dish.getUnitprice() : 0d);
            double expectedLine = Math.round(unitPrice * qty * 100) / 100.0;
            if (Math.abs(lineTotal - expectedLine) > ORDER_LINE_PRICE_EPS) {
                throw new RuntimeException("菜品「" + dish.getName() + "」金额与售价不符（单价×数量应为 ¥"
                        + String.format(Locale.US, "%.2f", expectedLine) + "），请按菜单价格重新下单");
            }
        }
        validateAggregatedStock(goodsList, shopId);
    }

    /** 后台菜品变更后清空 AI 在售菜单本地缓存，避免推荐到过期的上架状态 */
    @EventListener
    public void onDishCatalogChanged(DishCatalogChangedEvent event) {
        aiOnSaleMenuCache.invalidateAll();
    }

    /**
     * 处理订单的实际逻辑
     */
    /**
     * 保存订单明细；套餐子行写入 parent_detail_id 指向刚保存的头行。
     */
    private List<Integer> persistOrderDetailsWithComboParents(Order orderEntity, List<OrderDetail> details, int orderNumber, boolean updateMonthlySale) {
        List<Integer> insertedDetailIds = new ArrayList<>();
        Map<String, Integer> headerIdByInstance = new HashMap<>();
        Map<String, Integer> dishIdByName = new HashMap<>();
        for (OrderDetail od : details) {
            String dishName = od.getName();
            if (!StringUtils.hasText(dishName) && !"combo_component".equalsIgnoreCase(od.getLine_type())) {
                log.error("菜品名称为空，跳过该明细保存，订单明细：{}", od);
                continue;
            }
            if (updateMonthlySale && StringUtils.hasText(dishName)) {
                Dish DD = dishService.getOne(new LambdaQueryWrapper<Dish>()
                        .eq(Dish::getName, dishName)
                        .last("LIMIT 1"));
                if (DD != null) {
                    try {
                        Integer oldMonthlySale = Optional.ofNullable(DD.getMonthlysale()).orElse(0);
                        int addQuantity = 0;
                        try {
                            addQuantity = parseGoodsQuantityPositive(od.getQuantity());
                        } catch (RuntimeException ex) {
                            addQuantity = 0;
                        }
                        Integer newMonthlySale = Math.max(oldMonthlySale + addQuantity, 0);
                        DD.setMonthlysale(newMonthlySale);
                        dishService.updateById(DD);
                    } catch (Exception e) {
                        log.warn("菜品销量更新异常，菜品名称：{}", dishName, e);
                    }
                } else {
                    log.warn("未查询到菜品，跳过销量更新，菜品名称：{}", dishName);
                }
            }

            od.setMId(orderEntity.getId());
            od.setMorder_no(orderEntity.getOrder_no());
            od.setMorder_num(orderNumber);
            od.setOrder_rece("mis_order");
            if (od.getDish_id() == null && StringUtils.hasText(dishName)) {
                Integer dishId = dishIdByName.computeIfAbsent(dishName, name -> {
                    Dish d = dishService.getOne(new LambdaQueryWrapper<Dish>()
                            .select(Dish::getId)
                            .eq(Dish::getName, name)
                            .last("LIMIT 1"));
                    return d != null ? d.getId() : null;
                });
                if (dishId != null) {
                    od.setDish_id(dishId);
                }
            }

            if ("combo_component".equalsIgnoreCase(od.getLine_type())) {
                Integer hid = headerIdByInstance.get(od.getCombo_instance_id());
                if (hid == null) {
                    throw new RuntimeException("套餐子行须在头行之后落库，请检查套餐展开顺序");
                }
                od.setParent_detail_id(hid);
                // 套餐子菜为内部组件，不占用独立客户端行号，避免 (mId, client_line_id) 唯一键冲突
                od.setClient_line_id(null);
            }

            boolean saveDetailSuccess = orderDetailService.save(od);
            if (!saveDetailSuccess) {
                log.error("订单明细保存失败，菜品名称：{}，订单ID：{}", dishName, orderEntity.getId());
                throw new RuntimeException("订单明细保存失败");
            }
            if ("combo_header".equalsIgnoreCase(od.getLine_type()) && StringUtils.hasText(od.getCombo_instance_id())) {
                headerIdByInstance.put(od.getCombo_instance_id(), od.getId());
            }
            if (od.getId() != null) {
                insertedDetailIds.add(od.getId());
            }
        }
        return insertedDetailIds;
    }

    private Boolean processOrder(OrderDTO order) {
        try {
            // 兜底生成订单号：若上游（前端/AI）未传或传空，后端自动生成
            if (order.getOrder_no() == null || order.getOrder_no().trim().isEmpty()) {
                order.setOrder_no(generateOrderNo());
                log.info("order_no 为空，已自动生成订单号：{}", order.getOrder_no());
            }
            Order existingOrder = orderService.getOne(new QueryWrapper<Order>().eq("order_no", order.getOrder_no()));
            if (existingOrder != null) {
                throw new RuntimeException("请勿重复下单");
            }
            if(Objects.equals(order.getOrder_receiving(), "mis_orders")){
                order.setOrder_receiving("mis_order");
            }

            if (order.getGoods_list() == null || order.getGoods_list().isEmpty()) {
                throw new RuntimeException("订单明细不能为空");
            }
            boolean isCashier = CHANNEL_CASHIER.equalsIgnoreCase(order.getOrder_channel())
                    || "cashier_system".equalsIgnoreCase(order.getOpenid());
            comboMealService.normalizeCartLines(order.getGoods_list(), order.getShop_id(), order.getOpenid(), order.getDineInOrTakeOut(), isCashier);
            validateComboCommercialRulesInCart(order.getGoods_list(), order.getShop_id(), order.getOpenid(), order.getDineInOrTakeOut(), isCashier);
            validateOrderDetailsOnSale(order.getGoods_list(), order.getShop_id());

            // sett_amount 仅存 商品原价+打包费（外卖另含配送费，不含服务费）；服务费 = 整单(sett_amount)*5%
            double goodsSubtotal = 0d;
            if (order.getGoods_list() != null) {
                for (OrderDetail od : order.getGoods_list()) {
                    if (od != null && od.getTotal_price() != null) {
                        goodsSubtotal += od.getTotal_price();
                    }
                }
            }
            goodsSubtotal = Math.round(goodsSubtotal * 100) / 100.0;
            order.setSett_amount(resolveSettAmountWithPackagingCheck(
                    order.getDineInOrTakeOut(), goodsSubtotal, order.getSett_amount(), order.getDelivery_fee()));

            // 服务费：按配置截止日期，此前为整单(sett_amount)*5%，截止日及之后不收。前端未传时由后端计算并回填
            if (order.getService_fee() == null) {
                if (serviceFeeConfig.isServiceFeeCharged()) {
                    double sett = order.getSett_amount() != null ? order.getSett_amount() : 0d;
                    order.setService_fee(Math.round(sett * 0.05 * 100) / 100.0);
                } else {
                    order.setService_fee(0d);
                }
            }
            
            validateCoupon(order, false); // 首次下单，可用优惠券（校验时已含 sett_amount、service_fee）

            // 验证商户ID是否有效
            if (order.getMerchantId() == null || (!order.getMerchantId().equals("1") && !order.getMerchantId().equals("2"))) {
                order.setMerchantId("1");
            }

            Table table = null;
            if (Objects.equals(order.getDineInOrTakeOut(), "堂食") ) {
                Integer orderShopId = shopIdOrDefault(order.getShop_id());
                // 检查台号是否存在（FOR UPDATE 行锁串行化同一桌台并发建单，保证并发互斥）
                QueryWrapper<Table> tableQw = new QueryWrapper<Table>().eq("number", order.getTable_number());
                appendTableShopScope(tableQw, orderShopId);
                table = tableService.getOne(tableQw.last("LIMIT 1 FOR UPDATE"));
                if (table == null) {
                    throw new RuntimeException("台号不存在");
                }

                // 检查该台号是否已有未完成订单（同门店维度，避免跨店桌号冲突）
                QueryWrapper<Order> openTableQw = new QueryWrapper<Order>()
                        .eq("table_number", order.getTable_number())
                        .eq("transac_status", "unsettled");
                appendOrderShopScope(openTableQw, orderShopId);
                existingOrder = orderService.getOne(openTableQw.last("LIMIT 1"));

                if (existingOrder != null) {
                    throw new RuntimeException("该台号已有未完成订单，订单号：" + existingOrder.getOrder_no());
                }
            }

            // 处理用户信息
            User user = userService.getUserByOpenid(order.getOpenid());
            if (user == null) {
                user = new User();
                user.setOpenid(order.getOpenid());
                user.setTime(new Date());
                userService.save(user);
            }

            // 设置订单时间
            order.setOrder_time(new Date());
            // 新建订单默认：未结账、未接单（processOrder 仅用于首单创建，不信任客户端篡改结账/接单状态）
            order.setTransac_status("unsettled");
            if (isPackOrDeliveryType(order.getDineInOrTakeOut())) {
                // 打包/外卖须结账后才接单，禁止客户端预置已接单
                order.setOrder_receiving("mis_order");
            } else if (!StringUtils.hasText(order.getOrder_receiving())) {
                order.setOrder_receiving("mis_order");
            }
            // 下单次数：首单创建固定为 1，每次加菜在 addDishes 中基于库内值 +1
            order.setOrderNumber(1);

            Order orderEntity = new Order();
            BeanUtils.copyProperties(order, orderEntity);
            boolean saveOrderSuccess = orderService.save(orderEntity);
            if (!saveOrderSuccess) {
                log.error("订单主表保存失败，订单信息：{}", order);
                throw new RuntimeException("订单创建失败"); // 自定义业务异常，友好提示
            }
            order.setId(orderEntity.getId());
            log.info("订单主表保存成功，订单ID：{}，订单号：{}", orderEntity.getId(), orderEntity.getOrder_no());

            persistOrderDetailsWithComboParents(orderEntity, order.getGoods_list(), orderEntity.getOrderNumber(), true);

            applyStockDeductionForGoodsList(order.getGoods_list(), orderEntity.getShop_id());

            // 3. 更新桌台状态（仅当桌台存在时）；待结账金额=实付，实付=(sett_amount+service_fee)-discount_amount（与 OpenAPI 一致）；订单号写入 t_table.order_no
            if (table != null && Objects.equals(order.getDineInOrTakeOut(), "堂食") ) {
                if (table.getOpen_time() == null || Integer.valueOf(0).equals(table.getStatus())) {
                    table.setOpen_time(new Date());
                }
                table.setOut_time(null);
                double orderPrice = (orderEntity.getSett_amount() != null ? orderEntity.getSett_amount() : 0d) + (orderEntity.getService_fee() != null ? orderEntity.getService_fee() : 0d);
                double paidAmount = Math.round((orderPrice - (orderEntity.getDiscount_amount() != null ? orderEntity.getDiscount_amount() : 0d)) * 100) / 100.0;
                table.setAmount(paidAmount);
                table.setStatus(1);
                table.setOrder_no(orderEntity.getOrder_no());
                boolean updateTableSuccess = tableService.updateById(table);
                if (!updateTableSuccess) {
                    log.error("桌台状态更新失败，桌台信息：{}", table);
                    throw new RuntimeException("桌台状态更新失败"); // 桌台更新失败则回滚订单
                }
                log.info("桌台状态更新成功，桌台ID：{}，状态：{}", table.getId(), table.getStatus());
            }

            // 自动接单：非打包/外卖订单在下单成功后即接单并打印厨房小票、前台小票；打包与外卖需支付成功后再接单打印（在支付回调中处理）
            if (shouldAutoAcceptForOrder(orderEntity) && !isPackOrDeliveryType(orderEntity.getDineInOrTakeOut())) {
                try {
                    doAutoAcceptAndPrint(orderEntity);
                } catch (Exception ex) {
                    log.warn("创建订单后自动接单打印异常，订单号：{}，{}", orderEntity.getOrder_no(), ex.getMessage());
                }
            }
            kdsOrderHook.afterOrderCommitted(orderEntity, null, com.lanf.kds.service.KdsOrderHook.Trigger.CREATE);

            log.info("订单及关联数据保存成功，订单ID：{}", orderEntity.getId());
            return true;
        } catch (Exception e) {
            log.error("创建订单失败", e); // 只打印一次日志，消除冗余

            // 区分：如果是RuntimeException（业务异常），抛原异常（保留精准提示）；否则抛通用提示
            if (e instanceof RuntimeException) {
                throw e; // 业务异常（如优惠券不存在），抛原异常给前端
            } else {
                throw new RuntimeException("创建订单失败，请重试"); // 系统异常，抛通用提示
            }
        }
    }

    static boolean shouldBlockPreopenedTable(boolean isDineIn, HttpServletRequest request) {
        return isDineIn && (request == null
                || !Boolean.TRUE.equals(request.getAttribute(CASHIER_QUICK_ORDER_ATTRIBUTE)));
    }

    static String generateOrderKey(String tableNumber) {
        return generateOrderKey(null, tableNumber);
    }

    static String generateOrderKey(Integer shopId, String tableNumber) {
        return "processing:" + (shopId != null ? shopId : 0) + ":" + (tableNumber != null ? tableNumber : "");
    }

    static void ensureTableAvailableForNewOrder(Table table) {
        if (table != null && Integer.valueOf(2).equals(table.getStatus())) {
            throw new RuntimeException("该桌台已结账待清台，请先清台后再下单");
        }
    }

    /**
     * 取餐通知
     */
    @PostMapping("/notice")
    public R notice(@RequestBody Order od){
        Order order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", od.getOrder_no()));
        if (order == null) {
            return R.error("订单不存在");
        }
        if(od.getNotice() == null){
            od.setNotice(0);
        }
        order.setNotice(od.getNotice());
        if (Integer.valueOf(1).equals(order.getNotice())) {
            String pickupCode = order.getId() != null ? String.valueOf(order.getId()) : order.getOrder_no();
            if (dishMenuPushService != null) {
                try {
                    dishMenuPushService.notifyMealPickupReady(
                            order.getShop_id(), order.getId(), order.getOrder_no(),
                            order.getTable_number(), order.getDineInOrTakeOut(), pickupCode);
                } catch (Exception ignored) {
                }
            }
            if (unifiedNotificationService != null && order.getOpenid() != null) {
                try {
                    unifiedNotificationService.publishCustomerOrderPickupReady(order, pickupCode);
                } catch (Exception ignored) {
                }
            }
        }
        boolean res = orderService.updateById(order);
        if (res) {
            return R.ok();
        }else {
            return R.error("更新失败");
        }

    }

    /**
     * 获取订单打印内容（对外接口），可选同时下发打印
     * @param orderId 订单主键 t_order.id
     * @param type front=前台小票（预结单/结账单），kitchen=厨房小票（按分类多张）
     * @return front 时返回 content；kitchen 时返回 contents 数组；
     */
    @GetMapping("/printContent")
    public R getPrintContent(@RequestParam Integer orderId,
                             @RequestParam(required = false, defaultValue = "false") Boolean type
                             ) {
        return R.error(410, "该接口已迁移至收银专属路由：/cashier/order/printContent，请更新调用地址");
    }

    public R printContentForCashier(Integer orderId, Boolean type, Integer shopId) {
        Order order = orderService.getById(orderId);
        if (order == null) {
            return R.error("订单不存在");
        }
        List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
        order.setGoods_list(details);
        if (details == null || details.isEmpty()) {
            return R.error("订单无明细");
        }
        takeoutDeliveryService.enrichOrder(order);
        String content = generatePrintContent(order, type);
        if (content != null && !content.isEmpty()) {
            int printShopId = resolveOrderOwnedShopIdForPrint(order);
            if (printDispatcherService != null) {
                List<com.lanf.printing.model.PrintDispatchResult> results = printDispatcherService.dispatch(
                        printShopId, com.lanf.printing.model.PrintScenario.ORDER,
                        com.lanf.printing.model.PrintContext.ofOrder(order, type != null && type));
                boolean ok = !results.isEmpty() && results.stream().anyMatch(com.lanf.printing.model.PrintDispatchResult::isSuccess);
                return R.ok().put("content", content).put("printSuccess", ok)
                        .put("printData", toPayloadSummary(results));
            }
        }
        return R.ok().put("content", content != null ? content : "").put("printSuccess", false);
    }

    /**
     * 自动接单并打印（对外接口）
     * 将订单置为已接单，仅打印未接单的菜品，打印后将对应明细标记为已接单。
     * @param orderId 订单主键 t_order.id
     */
    @PostMapping("/autoAcceptAndPrint")
    public R autoAcceptAndPrint(@RequestParam Integer orderId) {
        Order order = orderService.getById(orderId);
        if (order == null) {
            return R.error("订单不存在");
        }
        try {
            PrintResult pr = doAutoAcceptAndPrint(order);
            if (!pr.success) {
                return R.error("接单并打印失败，订单已保留待重试状态").put("printData", toPayloadSummary(pr.printResults));
            }
            takeoutDeliveryService.enrichOrder(order);
            return R.ok("接单并打印成功").put("order", order).put("printData", toPayloadSummary(pr.printResults));
        } catch (Exception e) {
            log.warn("自动接单并打印异常, orderId={}, {}", orderId, e.getMessage());
            return R.error("接单并打印失败");
        }
    }

    /**
     * 取消订单（小程序前端已使用）
     * 请求体：{ "order_no": "string", "openid": "string" }
     */
    @Transactional(rollbackFor = Exception.class)
    @PostMapping("/cancel")
    public R cancelOrder(@RequestBody Map<String, Object> requestBody, HttpServletRequest request) {
        try {
            String order_no = requestBody.get("order_no") != null ? requestBody.get("order_no").toString().trim() : null;
            String openid = requestBody.get("openid") != null ? requestBody.get("openid").toString().trim() : null;
            Integer bodyShop = null;
            String bodyShopCode = null;
            try {
                bodyShop = ShopChainSupport.parseBodyShopId(requestBody.get("shop_id"));
                bodyShopCode = ShopChainSupport.parseBodyShopCode(requestBody.get("shop_code"));
            } catch (RuntimeException e) {
                return R.error(e.getMessage());
            }
            Integer resolvedShop;
            try {
                resolvedShop = resolveChainShop(request, bodyShop, bodyShopCode);
            } catch (RuntimeException e) {
                return R.error(e.getMessage());
            }
            resolvedShop = shopIdOrDefault(resolvedShop);
            if (order_no == null || order_no.isEmpty()) {
                return R.error("订单号不能为空");
            }
            if (openid == null || openid.isEmpty()) {
                return R.error("openid不能为空");
            }
            Order order = orderService.getOne(new QueryWrapper<Order>()
                    .eq("order_no", order_no)
                    .eq("openid", openid));
            if (order == null) {
                if (isWxRechargeMerchantNo(order_no) && memberRechargeService.cancelPendingWechat(order_no, openid)) {
                    return R.ok("取消成功");
                }
                return R.error("订单不存在或无权操作");
            }
            if (!orderBelongsToShop(order, resolvedShop)) {
                return R.error("订单不存在或无权操作");
            }
            if ("success".equals(order.getTransac_status())) {
                return R.error("已支付订单不可取消");
            }
            try {
                takeoutZsqIntegrationService.cancelZsqForOrder(order.getId(), "用户取消", false);
            } catch (Exception ex) {
                log.warn("真省钱取消（非阻断）order_no={}: {}", order_no, ex.getMessage());
            }
            // 取消订单：结账状态 transac_status 与接单状态 order_receiving 同时置为 cancelled
            // （order_receiving 枚举已含 cancelled；存量库需执行 docs/db_migration_order_receiving_cancelled.sql 确保枚举）
            boolean updated = orderService.update(new UpdateWrapper<Order>()
                    .eq("order_no", order_no)
                    .eq("openid", openid)
                    .eq("transac_status", "unsettled")
                    .set("transac_status", "cancelled")
                    .set("order_receiving", "cancelled"));
            if (updated) {
                restoreStockForCancelledOrder(order.getId(), order.getShop_id());
                takeoutDeliveryService.markCancelledIfPresent(order_no);
                try {
                    kdsOrderHook.afterOrderCancelled(order);
                } catch (Exception ex) {
                    log.warn("取消订单 KDS 同步异常: {}", ex.getMessage());
                }
                logOrder(order_no, "cancel", "openid", openid, resolvedShop, null);
                return R.ok("取消成功");
            }
            return R.error("取消失败");
        } catch (Exception e) {
            log.error("取消订单失败", e);
            return R.error("取消订单失败");
        }
    }

    /**
     * 根据 openid 获取用户历史订单（POST），支持分页与状态筛选；**不按门店过滤**，返回该用户全部门店订单。
     * 请求体：openid 必填；page、pageSize、status 可选。status: unsettled/success/cancelled/all，默认 all（是否退款看 refund_amount）
     */
    @PostMapping("/history")
    public R getOrderHistoryByOpenid(@RequestBody Map<String, Object> requestBody) {
        try {
            String openid = requestBody.get("openid") != null ? requestBody.get("openid").toString().trim() : null;
            if (openid == null || openid.isEmpty()) {
                return R.error("openid不能为空");
            }

            int page = 1;
            int pageSize = 20;
            if (requestBody.get("page") != null) {
                if (requestBody.get("page") instanceof Number) {
                    page = ((Number) requestBody.get("page")).intValue();
                } else {
                    try { page = Integer.parseInt(requestBody.get("page").toString()); } catch (NumberFormatException ignored) { }
                }
                if (page < 1) page = 1;
            }
            if (requestBody.get("pageSize") != null) {
                if (requestBody.get("pageSize") instanceof Number) {
                    pageSize = ((Number) requestBody.get("pageSize")).intValue();
                } else {
                    try { pageSize = Integer.parseInt(requestBody.get("pageSize").toString()); } catch (NumberFormatException ignored) { }
                }
                if (pageSize < 1) pageSize = 20;
                if (pageSize > 100) pageSize = 100;
            }

            String status = requestBody.get("status") != null ? requestBody.get("status").toString().trim().toLowerCase() : "all";
            if (status.isEmpty()) status = "all";

            QueryWrapper<Order> qw = new QueryWrapper<Order>()
                    .eq("openid", openid)
                    .orderByDesc("order_time");
            if (!"all".equals(status)) {
                qw.eq("transac_status", status);
            }

            List<Order> allMatched = orderService.list(qw);
            int total = allMatched.size();

            int fromIndex = (page - 1) * pageSize;
            int toIndex = Math.min(fromIndex + pageSize, total);
            List<Order> pageList = (fromIndex >= total) ? new ArrayList<>() : allMatched.subList(fromIndex, toIndex);

            takeoutDeliveryService.enrichOrders(pageList);
            java.util.Map<Integer, com.lanf.kds.entity.KdsTicket> ticketByDetail = kdsDetailStatusResolver.resolveByOrderIds(
                    pageList.stream().map(Order::getId).collect(java.util.stream.Collectors.toList()));
            List<Map<String, Object>> resultList = new ArrayList<>();
            for (Order order : pageList) {
                Map<String, Object> orderMap = new HashMap<>();
                orderMap.put("id", order.getId());
                orderMap.put("order_no", order.getOrder_no());
                orderMap.put("order_time", order.getOrder_time());
                orderMap.put("sett_amount", order.getSett_amount());   // 商品原价+打包费（不含服务费）
                orderMap.put("discount_amount", order.getDiscount_amount()); // 优惠金额，实付 = (sett_amount+service_fee)-discount_amount
                orderMap.put("service_fee", order.getService_fee());   // 新年服务费
                orderMap.put("refund_amount", order.getRefund_amount()); // 累计退款（元）
                orderMap.put("transac_status", order.getTransac_status());
                orderMap.put("dineInOrTakeOut", order.getDineInOrTakeOut());
                orderMap.put("table_number", order.getTable_number());
                orderMap.put("shop_id", order.getShop_id());
                orderMap.put("pay_time", order.getPay_time());
                orderMap.put("receiving", order.getOrder_receiving());
                orderMap.put("takeout_delivery_id", order.getTakeout_delivery_id());
                orderMap.put("delivery_fee", order.getDelivery_fee());
                orderMap.put("takeout_dispatch_status", order.getTakeout_dispatch_status());
                List<OrderDetail> details = orderDetailService.list(
                        new QueryWrapper<OrderDetail>().eq("mId", order.getId())
                );
                kdsDetailStatusResolver.enrichDetails(details, ticketByDetail);
                orderMap.put("orderDetails", details);
                resultList.add(orderMap);
            }

            return R.ok()
                    .put("hasHistory", total > 0)
                    .put("orderCount", resultList.size())
                    .put("total", total)
                    .put("orders", resultList);

        } catch (Exception e) {
            log.error("获取用户历史订单失败", e);
            return R.error("获取历史订单失败");
        }
    }

    /**
     * 会员充值流水（微信 + 后台），按 openid 分页；默认仅 success，可传 status=all|pending|cancelled|success。
     */
    @PostMapping("/rechargeHistory")
    public R memberRechargeHistory(@RequestBody Map<String, Object> requestBody) {
        try {
            String openid = requestBody.get("openid") != null ? requestBody.get("openid").toString().trim() : null;
            if (openid == null || openid.isEmpty()) {
                return R.error("openid不能为空");
            }
            int page = 1;
            int pageSize = 20;
            if (requestBody.get("page") != null) {
                if (requestBody.get("page") instanceof Number) {
                    page = ((Number) requestBody.get("page")).intValue();
                } else {
                    try {
                        page = Integer.parseInt(requestBody.get("page").toString());
                    } catch (NumberFormatException ignored) {
                    }
                }
                if (page < 1) {
                    page = 1;
                }
            }
            if (requestBody.get("pageSize") != null) {
                if (requestBody.get("pageSize") instanceof Number) {
                    pageSize = ((Number) requestBody.get("pageSize")).intValue();
                } else {
                    try {
                        pageSize = Integer.parseInt(requestBody.get("pageSize").toString());
                    } catch (NumberFormatException ignored) {
                    }
                }
                if (pageSize < 1) {
                    pageSize = 20;
                }
                if (pageSize > 100) {
                    pageSize = 100;
                }
            }
            String status = requestBody.get("status") != null ? requestBody.get("status").toString().trim().toLowerCase() : "success";
            if (status.isEmpty()) {
                status = "success";
            }
            IPage<MemberRecharge> pg = memberRechargeService.pageByOpenid(openid, page, pageSize, status);
            return R.ok()
                    .put("total", pg.getTotal())
                    .put("page", pg.getCurrent())
                    .put("pageSize", pg.getSize())
                    .put("list", pg.getRecords());
        } catch (Exception e) {
            log.error("获取会员充值流水失败", e);
            return R.error("获取充值记录失败");
        }
    }

    /**
     * 验证台号
     *
     * @param shop_id 可选；传入且为正整数时优先作为门店维度（高于请求头解析），用于校验该门店下是否存在该桌号
     */
    @GetMapping("/table_verify")
    public R table_verify(@RequestParam String number,
                          @RequestParam(value = "shop_id", required = false) Integer shopIdParam,
                          HttpServletRequest request) {
        try {
            return tableVerifyWithShop(number, resolveTableVerifyShopId(shopIdParam, request));
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }


    /**
     * 获取台号状态
     */
    @GetMapping("/table_status")
    public R table_status(String number, HttpServletRequest request) {
        try {
            return tableStatusWithShop(number, requireResolvedCShop(request));
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    /** 按桌号查堂食订单（HTTP 与 AI 工具共用） */
    private R getOrderByTableWithShop(String table_number, String transac_status, Integer shopId) {
        shopId = shopIdOrDefault(shopId);
        QueryWrapper<Order> oq = new QueryWrapper<Order>()
                .eq("table_number", table_number)
                .eq("transac_status", transac_status)
                .eq("dineInOrTakeOut", "堂食")
                .orderByDesc("order_time");
        appendOrderShopScope(oq, shopId);
        List<Order> orderList = orderService.list(oq);
        Map<String, Object> map = new HashMap<>();
        if (orderList.isEmpty()) {
            return R.error("当前桌为空闲状态");
        }

        Order order = orderList.get(0);
        takeoutDeliveryService.enrichOrder(order);
        List<OrderDetail> goods_list = orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
        if (Objects.equals(order.getDineInOrTakeOut(), "打包")) {
            return R.error("当前桌为空闲状态");
        }

        kdsDetailStatusResolver.enrichDetails(goods_list, order.getId());
        map.put("goods_list", goods_list);
        map.put("menu", order);
        return R.ok(map);
    }

    /**
     * 根据条件获取订单
     */
    @RequestMapping("/get")
    public R get(String table_number, String transac_status, HttpServletRequest request) {
        try {
            R result = getOrderByTableWithShop(table_number, transac_status, requireResolvedCShop(request));
            return requireOwnedOrderInResponse(result, authenticatedUserOpenid(request), "menu");
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }


    /**
     * 根据order_no获取订单
     */
    @RequestMapping("/getOrder")
    public R get(String order_no, HttpServletRequest request) {
        String openid = authenticatedUserOpenid(request);
        Integer resolvedShop = requireResolvedCShop(request);
        Order order = orderService.getOne(
                new QueryWrapper<Order>()
                        .eq("order_no", order_no)
                        .orderByDesc("order_time")
                        .last("LIMIT 1")
        );
        if (order == null || !orderBelongsToShop(order, resolvedShop)) {
            return R.error("未找到相关订单");
        }
        boolean isOwner = openid.equals(order.getOpenid());
        boolean isTableCompanion = "堂食".equals(order.getDineInOrTakeOut())
                && "unsettled".equals(order.getTransac_status());
        boolean hasAddedDish = false;
        if (!isOwner && !isTableCompanion && orderLogService != null) {
            hasAddedDish = orderLogService.count(new QueryWrapper<OrderLog>()
                    .eq("order_no", order_no)
                    .eq("action", "add_dish")
                    .eq("operator_type", "openid")
                    .eq("operator_id", openid)) > 0;
        }
        if (!isOwner && !isTableCompanion && !hasAddedDish) {
            return R.error(403, "无权查看该订单");
        }

        takeoutDeliveryService.enrichOrder(order);
        List<OrderDetail> goods_list = orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
        if(goods_list == null){
           return R.error(500,"获取订单失败");
        }
        Map<String,Object> map = new HashMap<>();
        kdsDetailStatusResolver.enrichDetails(goods_list, order.getId());
        map.put("goods_list", enrichOrderDetailsWithDishId(goods_list, order.getShop_id()));
        map.put("menu", order);
        TakeoutDelivery delivery = null;
        if (order.getId() != null && "外卖".equals(order.getDineInOrTakeOut())) {
            delivery = takeoutDeliveryService.getByOrderId(order.getId());
        }
        map.put("delivery", delivery);
        return R.ok(map);
    }
    /** 删除订单接口（仅 super_admin）。外卖单会同步删除 {@code t_takeout_delivery}，不受配送状态限制。 */
    @Transactional(rollbackFor = Exception.class)
    @DeleteMapping("/delete/{id}")
    public R deleteOrder(@PathVariable Integer id,
                         @RequestBody(required = false) Map<String, Object> body,
                         HttpServletRequest request) {
        Integer adminId = currentAdminId(request);
        if (adminId == null || !adminShopAccessService.isSuperAdmin(adminId)) {
            securityAuditService.recordAccessDenied(
                    request, adminId, null, 403,
                    "super_admin_required_for_order_delete", "super_admin");
            return R.error(403, "仅超级管理员可删除订单");
        }
        try {
            Order order = orderService.getById(id);
            if (order == null) {
                return R.error("订单不存在");
            }

            // 授权：审批令牌优先（POS 权限中心店长现场授权签发、单次消费），未携带令牌时回退现场账号密码授权。
            Integer authorizedAdminId;
            String approvalToken = null;
            if (body != null) {
                Object tokenValue = body.get("approvalToken");
                if (tokenValue == null) {
                    tokenValue = body.get("approval_token");
                }
                approvalToken = tokenValue == null ? null : tokenValue.toString().trim();
            }
            if (StringUtils.hasText(approvalToken) && approvalService != null) {
                String terminalId = request.getHeader("X-Terminal-Id");
                if (!StringUtils.hasText(terminalId) && body != null) {
                    Object tid = body.get("terminalId");
                    if (tid == null) {
                        tid = body.get("terminal_id");
                    }
                    if (tid != null) {
                        terminalId = tid.toString().trim();
                    }
                }

                BigDecimal amount = null;
                if (body != null && body.get("amount") != null) {
                    try {
                        amount = new BigDecimal(body.get("amount").toString().trim());
                    } catch (Exception ignore) {
                    }
                }
                if (amount == null) {
                    double netRev = OrderNetRevenue.netRevenueYuan(order);
                    amount = BigDecimal.valueOf(Math.max(0d, netRev)).setScale(2, RoundingMode.HALF_UP);
                }
                com.lanf.access.model.AccessContext ctx = com.lanf.access.model.AccessContext.builder()
                        .adminId(adminId)
                        .shopId(order.getShop_id())
                        .permissionCode("order:delete")
                        .resourceType("ORDER")
                        .resourceId(order.getOrder_no())
                        .terminalId(terminalId)
                        .amount(amount)
                        .build();
                if (!approvalService.validateAndConsume(approvalToken, ctx)) {
                    securityAuditService.recordAccessDenied(
                            request, adminId, order.getShop_id(), 40321,
                            "order_delete_approval_token_invalid", "order:delete");
                    return R.error(40321, "授权令牌无效、已过期或不匹配当前业务");
                }
                authorizedAdminId = adminId;
            } else {
                SensitiveOperationAuthorizationService.Decision authorization =
                        sensitiveOperationAuthorizationService.authorize(
                                body, "order:delete", order.getShop_id(), true);
                if (!authorization.isAllowed()) {
                    securityAuditService.recordAccessDenied(
                            request, adminId, order.getShop_id(), authorization.getCode(),
                            "order_delete_authorization_failed", "order:delete");
                    return R.error(authorization.getCode(), authorization.getMessage());
                }
                authorizedAdminId = authorization.getAdmin().getId();
            }

            if ("外卖".equals(order.getDineInOrTakeOut())) {
                takeoutDeliveryService.deleteByOrderId(order.getId());
            }

            try {
                kdsOrderHook.afterOrderCancelled(order);
            } catch (Exception ex) {
                log.warn("删除订单时同步作废 KDS 异常: {}", ex.getMessage());
            }

            orderDetailService.remove(new QueryWrapper<OrderDetail>().eq("Morder_no", order.getOrder_no()));
            orderService.removeById(id);
            processingOrders.invalidate(order.getOrder_no());

            Map<String, Object> auditSnapshot = new LinkedHashMap<>();
            auditSnapshot.put("orderNo", order.getOrder_no());
            auditSnapshot.put("takeout", "外卖".equals(order.getDineInOrTakeOut()));
            auditSnapshot.put("authorizedAdminId", authorizedAdminId);
            securityAuditService.recordPrivilegedAction(
                    request, order.getShop_id(), "order", "force_delete",
                    String.valueOf(id), adminId, auditSnapshot,
                    "order_force_deleted_by_super_admin");

            return R.ok("订单删除成功");
        } catch (Exception e) {
            log.error("删除订单失败", e);
            return R.error("删除订单失败");
        }
    }

    private static Integer currentAdminId(HttpServletRequest request) {
        Object value = request == null ? null : request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        return value instanceof Integer ? (Integer) value : null;
    }

    private R getTableInfoWithShop(String tableNumber, Integer shopId) {
        return getTableInfoWithShop(tableNumber, shopId, null);
    }

    private R getTableInfoWithShop(String tableNumber, Integer shopId, String openid) {
        shopId = shopIdOrDefault(shopId);

        Table table = tableService.getOne(new QueryWrapper<Table>().eq("number", tableNumber));
        if (table == null || !tableBelongsToShop(table, shopId)) {
            return R.error("台号不存在");
        }

        Order order = null;
        if (org.springframework.util.StringUtils.hasText(openid)) {
            // 优先查找该顾客在该桌的未结账订单
            QueryWrapper<Order> unsettledWrapper = new QueryWrapper<>();
            unsettledWrapper.eq("table_number", tableNumber)
                    .eq("openid", openid)
                    .eq("transac_status", "unsettled")
                    .orderByDesc("order_time")
                    .last("LIMIT 1");
            appendOrderShopScope(unsettledWrapper, shopId);
            order = orderService.getOne(unsettledWrapper);

            // 若当前顾客在该桌无未结账订单，但该桌存在未结账堂食订单（同桌点单场景）
            if (order == null) {
                QueryWrapper<Order> tableUnsettledWrapper = new QueryWrapper<>();
                tableUnsettledWrapper.eq("table_number", tableNumber)
                        .eq("transac_status", "unsettled")
                        .eq("dineInOrTakeOut", "堂食")
                        .orderByDesc("order_time")
                        .last("LIMIT 1");
                appendOrderShopScope(tableUnsettledWrapper, shopId);
                order = orderService.getOne(tableUnsettledWrapper);
            }

            // 若无未结账订单，查找该顾客在该桌的最近订单（如刚刚已结账）
            if (order == null) {
                QueryWrapper<Order> anyUserOrderWrapper = new QueryWrapper<>();
                anyUserOrderWrapper.eq("table_number", tableNumber)
                        .eq("openid", openid)
                        .orderByDesc("order_time")
                        .last("LIMIT 1");
                appendOrderShopScope(anyUserOrderWrapper, shopId);
                order = orderService.getOne(anyUserOrderWrapper);
            }

            // 若该顾客在该桌没有任何订单
            if (order == null) {
                QueryWrapper<Order> anyOrderWrapper = new QueryWrapper<>();
                anyOrderWrapper.eq("table_number", tableNumber);
                appendOrderShopScope(anyOrderWrapper, shopId);
                int otherCount = orderService.count(anyOrderWrapper);
                if (otherCount > 0) {
                    return R.error(403, "无权查看该桌订单");
                }
                return R.error("未找到该台号的订单信息");
            }
        } else {
            QueryWrapper<Order> queryWrapper = new QueryWrapper<>();
            queryWrapper.eq("table_number", tableNumber)
                    .orderByDesc("order_time")
                    .last("LIMIT 1");
            appendOrderShopScope(queryWrapper, shopId);
            order = orderService.getOne(queryWrapper);
            if (order == null) {
                return R.error("未找到该台号的订单信息");
            }
        }

        Map<String, Object> resultMap = new HashMap<>();
        resultMap.put("tableStatus", table.getStatus());
        resultMap.put("qrcode", table.getQrcode());
        resultMap.put("open_time", table.getOpen_time());
        resultMap.put("out_time", table.getOut_time());
        resultMap.put("tableNumber", tableNumber);
        resultMap.put("checkoutStatus", order.getTransac_status());
        resultMap.put("orderReceiving", order.getOrder_receiving());
        double orderPrice = (order.getSett_amount() != null ? order.getSett_amount() : 0d) + (order.getService_fee() != null ? order.getService_fee() : 0d);
        double amount = orderPrice - (order.getDiscount_amount() != null ? order.getDiscount_amount() : 0d);
        resultMap.put("amount", amount);
        resultMap.put("service_fee", order.getService_fee());
        resultMap.put("orderTime", order.getOrder_time());
        resultMap.put("orderNo", order.getOrder_no());
        resultMap.put("remark", order.getRemark());
        resultMap.put("DineInOrTakeOut", order.getDineInOrTakeOut());
        resultMap.put("orderNumber", order.getOrderNumber());

        return R.ok(resultMap);
    }

    /**
     * 根据台号获取订单信息
     */
    @GetMapping("/table-info/{tableNumber}")
    public R getTableInfo(@PathVariable String tableNumber, HttpServletRequest request) {
        try {
            String openid = authenticatedUserOpenid(request);
            Integer shopId = requireResolvedCShop(request);
            return getTableInfoWithShop(tableNumber, shopId, openid);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    /**
     * 加菜接口
     */
    @Transactional(rollbackFor = Exception.class)
    @RequestMapping("/addDishes")
    public R addDishes(@RequestBody OrderDTO order, HttpServletRequest request) {
        try {
            // 从请求中获取订单编号和菜品列表
            String orderNo = order.getOrder_no();
            if (orderNo == null || orderNo.isEmpty()) {
                return R.error("订单编号不能为空");
            }

            // 串行化同一订单的加菜金额、轮次和明细写入，避免并发请求互相覆盖。
            Order existingOrder = orderService.getOne(new QueryWrapper<Order>()
                    .eq("order_no", orderNo).last("LIMIT 1 FOR UPDATE"));
            if (existingOrder == null) {
                return R.error("订单不存在");
            }

            String effectiveOpenid = order.getOpenid();
            if (!StringUtils.hasText(effectiveOpenid)) {
                try {
                    effectiveOpenid = authenticatedUserOpenid(request);
                    order.setOpenid(effectiveOpenid);
                } catch (Exception ignored) {}
            }
            if (!StringUtils.hasText(effectiveOpenid)) {
                return R.error(403, "无权给该订单加菜");
            }

            boolean isOwner = effectiveOpenid.equals(existingOrder.getOpenid());
            boolean isTableCompanion = "堂食".equals(existingOrder.getDineInOrTakeOut())
                    && "unsettled".equals(existingOrder.getTransac_status())
                    && StringUtils.hasText(existingOrder.getTable_number())
                    && (order.getTable_number() == null || existingOrder.getTable_number().trim().equalsIgnoreCase(order.getTable_number().trim()));
            if (!isOwner && !isTableCompanion) {
                return R.error(403, "无权给该订单加菜");
            }
            if (!StringUtils.hasText(order.getTable_number()) && StringUtils.hasText(existingOrder.getTable_number())) {
                order.setTable_number(existingOrder.getTable_number());
            }

            try {
                applyShopContextToOrderDto(order, request);
            resolveOrderChannelAndOperator(order, request);
            } catch (RuntimeException e) {
                return R.error(e.getMessage());
            }
            Integer reqShop = order.getShop_id();
            if (existingOrder.getShop_id() != null && reqShop != null && !existingOrder.getShop_id().equals(reqShop)) {
                return R.error("订单不属于当前门店");
            }
            if (existingOrder.getShop_id() != null && reqShop == null) {
                order.setShop_id(existingOrder.getShop_id());
            }
            Integer finalShopId = order.getShop_id() != null ? order.getShop_id() : existingOrder.getShop_id();
            Shop dishShop = shopService.getById(finalShopId);
            boolean isCashierAdd = (request != null && Boolean.TRUE.equals(request.getAttribute(CASHIER_QUICK_ORDER_ATTRIBUTE)))
                    || CHANNEL_CASHIER.equalsIgnoreCase(order.getOrder_channel())
                    || "cashier_system".equalsIgnoreCase(order.getOpenid());
            if (!isCashierAdd && !ShopOrderingOpenHelper.isOrderingOpen(dishShop)) {
                return R.error(4003, "门店已打烊，暂不接单");
            }
            QueryWrapper<Table> tableQw = new QueryWrapper<Table>().eq("number", order.getTable_number());
            appendTableShopScope(tableQw, order.getShop_id());
            Table table = tableService.getOne(tableQw.last("LIMIT 1 FOR UPDATE"));

            // 修复字符串比较方式
            if ("success".equals(existingOrder.getTransac_status())) {
                return R.error("订单已结账");
            }
            int currentRevision = orderRevisionService.assertExpected(
                    existingOrder, order.getExpectedVersion());
            existingOrder = wechatJsapiPaymentService.prepareForAmountMutation(existingOrder);
            if (isPackOrDeliveryType(existingOrder.getDineInOrTakeOut())) {
                return R.error("打包或外卖订单不支持加菜，如需更多商品请重新下单");
            }
           
            // 验证商户ID是否有效
            if (order.getMerchantId() == null || (!order.getMerchantId().equals("1") && !order.getMerchantId().equals("2"))) {
                order.setMerchantId("1");
            }
            // 下单次数：每次加菜在库内原值基础上 +1（不依赖请求体中的 orderNumber，避免错传）
            int currentOrderNumber = existingOrder.getOrderNumber() != null ? existingOrder.getOrderNumber() : 0;
            int nextOrderNumber = currentOrderNumber + 1;
            if (order.getGoods_list() == null || order.getGoods_list().isEmpty()) {
                return R.error("加菜明细不能为空");
            }
            comboMealService.normalizeCartLines(order.getGoods_list(), existingOrder.getShop_id(), existingOrder.getOpenid(), existingOrder.getDineInOrTakeOut(), isCashierAdd);
            validateComboCommercialRulesInCart(order.getGoods_list(), existingOrder.getShop_id(), existingOrder.getOpenid(), existingOrder.getDineInOrTakeOut(), isCashierAdd);
            validateOrderDetailsOnSale(order.getGoods_list(), existingOrder.getShop_id());

            // 统计加菜商品小计；优先以前端合法传参为准，未传或<=0时从标准化明细重算
            double addedGoodsSubtotal = 0d;
            for (OrderDetail od : order.getGoods_list()) {
                if (od != null && od.getTotal_price() != null) {
                    addedGoodsSubtotal += od.getTotal_price();
                }
            }
            addedGoodsSubtotal = Math.round(addedGoodsSubtotal * 100) / 100.0;
            Double newAmountRaw = (order.getSett_amount() != null && order.getSett_amount() > 0)
                    ? order.getSett_amount()
                    : addedGoodsSubtotal;
            Double oldOriginalPrice = existingOrder.getSett_amount() != null ? existingOrder.getSett_amount() : 0.0;

            // 加菜前先统计「适用菜品金额」（不再通过 cid/类目限制，统一按优惠券白名单 apply_dish_ids）
            Integer couponShopId = reqShop != null ? reqShop : existingOrder.getShop_id();
            double totalEligibleRaw = 0d;
            List<OrderDetail> existingDetails = orderDetailService.list(
                    new QueryWrapper<OrderDetail>().eq("mId", existingOrder.getId()));
            List<OrderDetail> allDetailsForCoupon = new ArrayList<>();
            if (existingDetails != null) allDetailsForCoupon.addAll(existingDetails);
            allDetailsForCoupon.addAll(order.getGoods_list());

            // 若该单已绑定优惠券，则按券模板的 apply_dish_ids 计算适用金额；否则按整单金额（后续 discountAmount 仍为 0）
            String applyDishIdsText = null;
            UserCoupon usedUserCoupon0 = UserCouponMapper.selectOne(
                    new QueryWrapper<UserCoupon>().eq("order_no", orderNo).last("LIMIT 1"));
            if (usedUserCoupon0 != null && usedUserCoupon0.getCoupon_id() != null) {
                Coupon coupon0 = CouponService.selectByCouponById(usedUserCoupon0.getCoupon_id());
                applyDishIdsText = coupon0 != null ? coupon0.getApply_dish_ids() : null;
            }

            Set<Integer> allow = null;
            if (StringUtils.hasText(applyDishIdsText) && !"[]".equals(applyDishIdsText.trim())) {
                allow = new HashSet<>();
                try {
                    List<?> arr = objectMapper.readValue(applyDishIdsText.trim(), List.class);
                    if (arr != null) {
                        for (Object o : arr) {
                            if (o instanceof Number) {
                                allow.add(((Number) o).intValue());
                            } else if (o != null) {
                                String s = o.toString().trim();
                                if (!s.isEmpty()) allow.add(Integer.parseInt(s));
                            }
                        }
                    }
                } catch (Exception e) {
                    throw new RuntimeException("优惠券适用菜品配置异常，请联系管理员");
                }
                if (allow.isEmpty()) allow = null;
            }

            for (OrderDetail od : allDetailsForCoupon) {
                if (od == null) continue;
                Double tp = od.getTotal_price();
                if (tp == null) continue;
                if (allow == null) {
                    totalEligibleRaw += tp;
                    continue;
                }
                if (!StringUtils.hasText(od.getName())) continue;
                // 有 dish_id 优先走主键（老明细可能只有名称）；名称回退时按门店覆盖名匹配
                Dish d = od.getDish_id() != null && od.getDish_id() > 0
                        ? dishService.getById(od.getDish_id()) : null;
                if (d == null) {
                    d = resolveDishByMenuName(od.getName().trim(), couponShopId);
                }
                if (d == null || d.getId() == null) continue;
                if (allow.contains(d.getId())) {
                    totalEligibleRaw += tp;
                }
            }

            List<Integer> newDetailIds = persistOrderDetailsWithComboParents(existingOrder, order.getGoods_list(), nextOrderNumber, false);

            applyStockDeductionForGoodsList(order.getGoods_list(), existingOrder.getShop_id());

            // 加菜后按订单号查用户优惠券是否关联此单，有则按「适用菜品金额」重算优惠；sett_amount 仅存 商品+打包费；服务费按配置截止日期
            double totalRaw = oldOriginalPrice + newAmountRaw; // 整单 商品+打包费 = 原订单 sett_amount + 本次加菜金额
            double totalServiceFee = serviceFeeConfig.isServiceFeeCharged()
                ? Math.round(totalRaw * 0.05 * 100) / 100.0
                : 0d;
            double discountAmount = 0d;
            UserCoupon usedUserCoupon = UserCouponMapper.selectOne(
                    new QueryWrapper<UserCoupon>().eq("order_no", orderNo).last("LIMIT 1"));
            if (usedUserCoupon != null && usedUserCoupon.getCoupon_id() != null) {
                Coupon coupon = CouponService.selectByCouponById(usedUserCoupon.getCoupon_id());
                discountAmount = calcDiscountFromCoupon(totalEligibleRaw, coupon); // 按适用菜品金额计算优惠，不含服务费
            }
            existingOrder.setDiscount_amount(Math.round(discountAmount * 100) / 100.0);
            existingOrder.setService_fee(totalServiceFee); // 服务费 = 整单(sett_amount) * 5%，已保留两位
            existingOrder.setSett_amount(Math.round(totalRaw * 100) / 100.0); // 订单表 sett_amount，保留两位小数
            // order_time 是首单创建时间；加菜只能追加明细和更新金额，不能刷新订单归属时间。
            existingOrder.setOrderNumber(nextOrderNumber);
            // 修复：仅在订单尚未接单且不满足自动接单条件时才降级为 mis_order。
            // 若原订单已接单（rec_order）或满足自动接单条件，保留 rec_order，避免事务提交后
            // processIntent 立即读到 mis_order 而触发 30 秒重试惩罚延迟。
            boolean autoAccept = shouldAutoAcceptForOrder(existingOrder);
            String previousAcceptance = existingOrder.getOrder_receiving();
            boolean isAlreadyAccepted = "rec_order".equals(previousAcceptance);
            if (!autoAccept && !isAlreadyAccepted) {
                existingOrder.setOrder_receiving("mis_order");
            }
            existingOrder.setRemark(order.getRemark());
            if (!orderService.updateById(existingOrder)) {
                throw new IllegalStateException("订单金额更新失败");
            }
            int revision = orderRevisionService.increment(existingOrder, currentRevision);

            if (table != null) {
                QueryWrapper<Order> unsettledOrdersQuery = new QueryWrapper<Order>()
                        .eq("table_number", existingOrder.getTable_number())
                        .eq("transac_status", "unsettled");
                appendOrderShopScope(unsettledOrdersQuery, finalShopId);
                List<Order> unsettledOrders = orderService.list(unsettledOrdersQuery);
                double tableAmount = unsettledOrders == null ? 0d : unsettledOrders.stream()
                        .filter(Objects::nonNull)
                        .mapToDouble(OrderNetRevenue::netRevenueYuan)
                        .sum();
                table.setAmount(Math.round(Math.max(0d, tableAmount) * 100d) / 100d);
                tableService.updateById(table);
            }
            Integer committedOrderId = existingOrder.getId();
            List<Integer> committedDetailIds = new ArrayList<>(newDetailIds);

            // 加菜对齐首单：在主事务内完成自动接单与 KDS 工单处理，确保事务提交后 WebSocket 秒级广播至各档口 KDS
            if (autoAccept || isAlreadyAccepted) {
                try {
                    doAutoAcceptAndPrint(existingOrder, null, committedDetailIds);
                } catch (Exception ex) {
                    log.warn("加菜后自动接单打印异常，订单号：{}，{}", existingOrder.getOrder_no(), ex.getMessage());
                }
            }
            try {
                kdsOrderHook.afterAddedDishesCommitted(existingOrder, committedDetailIds);
            } catch (Exception ex) {
                log.warn("加菜后 KDS 钩子处理异常，订单号：{}，{}", existingOrder.getOrder_no(), ex.getMessage());
            }

            cashierKdsProjectionService.publishAfterCommit(committedOrderId, "ORDER_UPDATED", null, null, committedDetailIds);
            logOrder(orderNo, "add_dish", "openid", effectiveOpenid, existingOrder.getShop_id(), null);
            List<Map<String, Object>> detailMappings = new ArrayList<>();
            if (order.getGoods_list() != null) {
                for (int i = 0; i < order.getGoods_list().size() && i < newDetailIds.size(); i++) {
                    OrderDetail od = order.getGoods_list().get(i);
                    Integer cloudDetailId = newDetailIds.get(i);
                    Map<String, Object> dm = new LinkedHashMap<>();
                    dm.put("cloud_detail_id", cloudDetailId);
                    dm.put("dish_id", od.getDish_id());
                    if (StringUtils.hasText(od.getClient_line_id())) {
                        dm.put("client_line_id", od.getClient_line_id());
                        try {
                            long localDetailId = Long.parseLong(od.getClient_line_id().trim());
                            dm.put("local_detail_id", localDetailId);
                        } catch (NumberFormatException ignored) {}
                    }
                    detailMappings.add(dm);
                }
            }
            return R.ok("加菜成功")
                    .put("id", existingOrder.getId())
                    .put("order_no", existingOrder.getOrder_no())
                    .put("detail_ids", newDetailIds)
                    .put("detail_mappings", detailMappings)
                    .put("revision", revision);
        } catch (ApiException e) {
            try {
                org.springframework.transaction.interceptor.TransactionAspectSupport.currentTransactionStatus().setRollbackOnly();
            } catch (Exception rex) {
                log.warn("加菜事务标记回滚异常", rex);
            }
            throw e;
        } catch (Exception e) {
            log.error("加菜失败", e);
            try {
                org.springframework.transaction.interceptor.TransactionAspectSupport.currentTransactionStatus().setRollbackOnly();
            } catch (Exception rex) {
                log.warn("加菜事务标记回滚异常", rex);
            }
            String msg = (e.getMessage() != null && !e.getMessage().trim().isEmpty())
                    ? e.getMessage().trim()
                    : "加菜失败";
            return R.error(msg);
        }
    }

    /**
     * 发送订阅消息接口
     */
    @PostMapping("/sendSubscribe")
    public R sendSubscribe(@RequestBody Map<String, Object> params) {
        try {
            // 获取请求参数
            String openid = (String) params.get("openid");
            String templateId = (String) params.get("templateId");
            String order_no = (String) params.get("order_no");
            Map<String, Object> data = (Map<String, Object>) params.get("data");




            // 参数校验
            if (openid == null || templateId == null || data == null || order_no == null) {
                return R.error("参数不完整");
            }

            // 获取access_token
            String accessToken = getAccessToken();
            if (accessToken == null) {
                return R.error("获取access_token失败");
            }

            // 构建微信订阅消息接口请求参数
            Map<String, Object> requestBody = new HashMap<>();
            requestBody.put("touser", openid);
            requestBody.put("template_id", templateId);
            requestBody.put("page", "pages/order-details/details?order_no=" + order_no );
            requestBody.put("data", data);
            requestBody.put("miniprogram_state", "formal");
            requestBody.put("lang", "zh_CN");

            // 调用微信订阅消息接口
            String url = "https://api.weixin.qq.com/cgi-bin/message/subscribe/send?access_token=" + accessToken;
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestBody, headers);

            Map<String, Object> response = restTemplate.postForObject(url, entity, Map.class);

            // 处理微信接口返回结果
            if (response != null && response.get("errcode").equals(0)) {
                return R.ok("订阅消息发送成功");
            } else {
                String errMsg = response != null ? (String) response.get("errmsg") : "未知错误";
                return R.error("订阅消息发送失败: " + errMsg);
            }
        } catch (Exception e) {
            log.error("发送订阅消息异常", e);
            return R.error("发送订阅消息异常");
        }
    }

    /**
     * 获取access_token的方法 - 支持指定商户
     */
    private String getAccessToken() {
        try {
            return tokenCache.get("access_token", this::loadAccessToken);
        } catch (Exception e) {
            log.error("获取access_token失败", e);
            return null;
        }
    }



    private String loadAccessToken(String s) {
        // 稳定版接口调用凭据接口地址
        String url = "https://api.weixin.qq.com/cgi-bin/stable_token";

        // 检查appid和secret是否配置
        if (appid == null || appid.trim().isEmpty() || appsecret == null || appsecret.trim().isEmpty()) {
            throw new RuntimeException("appid或secret未配置或配置为空");
        }

        // 构建请求体
        Map<String, Object> requestBody = new HashMap<>();
        requestBody.put("grant_type", "client_credential");
        requestBody.put("appid", appid);
        requestBody.put("secret", appsecret);
        requestBody.put("force_refresh", false);

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        HttpEntity<Map<String, Object>> requestEntity = new HttpEntity<>(requestBody, headers);

        try {
            Map<String, Object> response = restTemplate.postForObject(url, requestEntity, Map.class);
            log.info("event=wechat_token_response_received");

            // 处理响应结果
            if (response != null) {
                Object errCodeObj = response.get("errcode");
                int errCode = -1;

                if (errCodeObj != null) {
                    if (errCodeObj instanceof Number) {
                        errCode = ((Number) errCodeObj).intValue();
                    }
                } else {
                    errCode = 0; // 不存在错误码，视为成功响应
                }

                if (errCode == 0) {
                    String accessToken = (String) response.get("access_token");
                    if (accessToken != null && !accessToken.isEmpty()) {
                        return accessToken;
                    } else {
                        throw new RuntimeException("获取稳定版access_token失败: 响应中不包含有效的access_token");
                    }
                } else {
                    String errMsg = (String) response.getOrDefault("errmsg", "未知错误");
                    throw new RuntimeException("获取稳定版access_token失败: " + errCode + " - " + errMsg);
                }
            } else {
                throw new RuntimeException("获取稳定版access_token失败: 未收到响应");
            }
        } catch (Exception e) {
            throw new RuntimeException("获取稳定版access_token异常: " + e.getMessage(), e);
        }
    }

    /**
     * 获取启用的轮播图列表
     * 供小程序首页展示使用
     */
    @GetMapping("/banners")
    public R getEnabledBanners() {
        try {
            // 调用服务层方法获取所有启用状态的轮播图
            List<Banner> banners = bannerService.getEnabledBanners();

            if (banners == null || banners.isEmpty()) {
                log.info("当前没有启用的轮播图");
                return R.ok().put("banners", new ArrayList<>());
            }

            log.info("获取轮播图成功，共{}条记录", banners.size());
            return R.ok().put("banners", banners);
        } catch (Exception e) {
            log.error("获取轮播图失败", e);
            return R.error("获取轮播图失败");
        }
    }

    /**
     * 通过code获取openid
     */
    @PostMapping("/getOpenid")
    public R getOpenid(@RequestBody Map<String, String> params) {
        String code = params != null ? params.get("code") : null;
        if (code == null || code.trim().isEmpty()) {
            return R.error("code不能为空");
        }
        try {
            String openid = wechatMiniProgramAuthService.exchangeCodeForOpenid(code.trim());
            String userToken = jwtTokenService.createToken(openid, "user", userTokenTtlMillis,
                    Collections.emptyMap());
            return R.ok()
                    .put("openid", openid)
                    .put("user_token", userToken)
                    .put("expires_in", userTokenTtlMillis / 1000);
        } catch (IllegalArgumentException | IllegalStateException e) {
            return R.error("获取openid失败");
        } catch (Exception e) {
            log.error("event=wechat_identity_failed");
            return R.error("获取openid异常");
        }
    }

    /** 小票标题：自提打包 / 外卖配送；堂食返回 null */
    private String resolvePrintModeTitle(Order order) {
        if (order == null || !StringUtils.hasText(order.getDineInOrTakeOut())) {
            return null;
        }
        if (isWaimaiType(order.getDineInOrTakeOut())) {
            return "外卖配送";
        }
        if (isTakeOutType(order.getDineInOrTakeOut()) || "打包".equals(order.getDineInOrTakeOut().trim())) {
            return "自提打包";
        }
        return null;
    }

    private String resolvePrintModeLabel(Order order) {
        String title = resolvePrintModeTitle(order);
        return title != null ? title : (order != null && order.getDineInOrTakeOut() != null
                ? order.getDineInOrTakeOut() : "未知");
    }

    private TakeoutDelivery resolveTakeoutDeliveryForPrint(Order order) {
        if (order == null || !isWaimaiType(order.getDineInOrTakeOut()) || order.getId() == null) {
            return null;
        }
        return takeoutDeliveryService.getByOrderId(order.getId());
    }

    private void appendPrintModeHeader(StringBuilder content, Order order, boolean kitchenTicket) {
        String modeTitle = resolvePrintModeTitle(order);
        if (modeTitle != null) {
            String idLabel = order.getId() != null ? String.valueOf(order.getId())
                    : (StringUtils.hasText(order.getOrder_no()) ? order.getOrder_no() : "");
            content.append("<CB>").append(modeTitle).append("：").append(idLabel).append("</CB><BR>");
            return;
        }
        Integer orderNum = order.getOrderNumber();
        if (orderNum != null && orderNum > 1 && kitchenTicket) {
            content.append("<C>第").append(orderNum).append("次加菜</C><BR>");
        }
        content.append("<CB>台号：").append(order.getTable_number() != null ? order.getTable_number() : "未知")
                .append("</CB><BR>");
    }

    private void appendTakeoutDeliverySection(StringBuilder content, Order order) {
        if (order == null || !isWaimaiType(order.getDineInOrTakeOut())) {
            return;
        }
        TakeoutDelivery d = resolveTakeoutDeliveryForPrint(order);
        if (d == null) {
            return;
        }
        content.append("<BR>-----------配送信息--------------<BR>");
        if (StringUtils.hasText(d.getReceiver_name())) {
            content.append("<B>收件人：").append(d.getReceiver_name().trim()).append("</B><BR>");
        }
        if (StringUtils.hasText(d.getReceiver_phone())) {
            content.append("<B>电话：").append(d.getReceiver_phone().trim()).append("</B><BR>");
        }
        if (StringUtils.hasText(d.getAddress_full())) {
            content.append("地址：").append(d.getAddress_full().trim()).append("<BR>");
        }
        if (d.getDelivery_fee() != null && d.getDelivery_fee().doubleValue() > 0) {
            content.append("配送费：").append(String.format("%.2f", d.getDelivery_fee().doubleValue())).append("元<BR>");
        }
        content.append("--------------------------------<BR>");
    }

    // 生成打印内容（统一委托打印模板引擎）
    public String generatePrintContent(Order order, boolean type) {
        if (printTemplateEngine != null) {
            return printTemplateEngine.renderReceiptTicket(order, type, com.lanf.printing.engine.PrintTemplateOptions.defaultOptions());
        }
        return "";
    }

    /**
     * 生成厨房小票内容（统一委托打印模板引擎）
     */
    private List<String> generateKitchenTicketContents(Order order, Set<String> cidFilter) {
        if (printTemplateEngine != null) {
            return printTemplateEngine.renderKitchenTickets(order, cidFilter, com.lanf.printing.engine.PrintTemplateOptions.defaultOptions());
        }
        return Collections.emptyList();
    }

    private String normalizeCidKey(String rawCid) {
        if (rawCid == null) {
            return "default";
        }
        String t = rawCid.trim();
        return t.isEmpty() ? "default" : t;
    }

    private String normalizeDiningType(String raw) {
        if (!StringUtils.hasText(raw)) {
            return "";
        }
        String t = raw.trim();
        if ("堂食".equals(t) || "dine_in".equalsIgnoreCase(t) || "dinein".equalsIgnoreCase(t)) {
            return "dine_in";
        }
        if ("打包".equals(t) || "take_out".equalsIgnoreCase(t) || "takeout".equalsIgnoreCase(t)
                || "自提".equals(t) || "打包自提".equals(t) || "pickup".equalsIgnoreCase(t)
                || "pick_up".equalsIgnoreCase(t) || "pack".equalsIgnoreCase(t)) {
            return "take_out";
        }
        return t.toLowerCase();
    }

    private boolean isTakeOutType(String raw) {
        return "take_out".equals(normalizeDiningType(raw));
    }

    /** 外卖（小程序 {@code dineInOrTakeOut=外卖}，或英文别名） */
    private boolean isWaimaiType(String raw) {
        if (!StringUtils.hasText(raw)) {
            return false;
        }
        String t = raw.trim();
        return "外卖".equals(t) || "delivery".equalsIgnoreCase(t) || "waimai".equalsIgnoreCase(t);
    }

    /** 打包或外卖：与堂食区分，先支付后厨打单等逻辑与打包一致 */
    private boolean isPackOrDeliveryType(String raw) {
        return isTakeOutType(raw) || isWaimaiType(raw);
    }

    /**
     * 二次校验 sett_amount：打包/外卖若前端未含打包费则后端补入；外卖另校验配送费。
     */
    private double resolveSettAmountWithPackagingCheck(String dineInOrTakeOut, double goodsSubtotalYuan,
                                                       Double frontSettAmountYuan, Double deliveryFeeYuan) {
        if (isTakeOutType(dineInOrTakeOut)) {
            return OrderPackagingFeeCalculator.resolveSettForTakeOut(goodsSubtotalYuan, frontSettAmountYuan);
        }
        if (isWaimaiType(dineInOrTakeOut)) {
            return OrderPackagingFeeCalculator.resolveSettForWaimai(
                    goodsSubtotalYuan, frontSettAmountYuan, deliveryFeeYuan);
        }
        return OrderPackagingFeeCalculator.resolveSettForDineIn(goodsSubtotalYuan, frontSettAmountYuan);
    }

    /** 判断菜品是否未接单（order_rece 为空或 mis_order 表示未接单） */
    private boolean isDetailUnaccepted(OrderDetail d) {
        String r = d.getOrder_rece();
        return r == null || r.trim().isEmpty() || "mis_order".equals(r.trim());
    }

    /** 订单头是否待自动接单（新建单默认为 mis_order，非 rec_order/off_order）。 */
    private static boolean isOrderPendingAutoAccept(Order order) {
        if (order == null) {
            return false;
        }
        String r = order.getOrder_receiving();
        if (r == null || r.trim().isEmpty()) {
            return true;
        }
        String t = r.trim();
        return "mis_order".equals(t) || "mis_orders".equals(t);
    }

    /**
     * 自动接单并打印：更新 order_receiving 为 rec_order；仅打印未接单的菜品（order_rece 为空或 mis_order），打印后将对应明细的 order_rece 更新为 rec_order。
     */
    /** 打印执行结果（内部传递用） */
    static class PrintResult {
        final boolean success;
        final List<com.lanf.printing.model.PrintDispatchResult> printResults;
        PrintResult(boolean success, List<com.lanf.printing.model.PrintDispatchResult> printResults) {
            this.success = success;
            this.printResults = printResults != null ? printResults : Collections.emptyList();
        }
    }

    /** 将 PrintDispatchResult 列表转为前端友好的精简 map 列表 */
    static List<Map<String, Object>> toPayloadSummary(List<com.lanf.printing.model.PrintDispatchResult> results) {
        if (results == null || results.isEmpty()) return Collections.emptyList();
        List<Map<String, Object>> list = new ArrayList<>();
        for (com.lanf.printing.model.PrintDispatchResult r : results) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("deviceId", r.getDeviceId());
            m.put("deviceName", r.getDeviceName());
            m.put("scenario", r.getScenario());
            m.put("status", r.getStatus());
            m.put("payloadText", r.getPayloadText());
            m.put("error", r.getError());
            list.add(m);
        }
        return list;
    }

    private PrintResult doAutoAcceptAndPrint(Order order, Set<String> cidFilter) {
        return doAutoAcceptAndPrint(order, cidFilter, null);
    }

    /**
     * @param detailIds 非空时仅处理本次加菜明细；为空时处理整单所有待接单明细
     * @return 目标明细是否全部打印并确认成功
     */
    private PrintResult doAutoAcceptAndPrint(Order order, Set<String> cidFilter, Collection<Integer> detailIds) {
        if (order == null || order.getId() == null) return new PrintResult(false, Collections.emptyList());
        Object fulfillmentLock = fulfillmentOrderLocks.get(order.getId(), ignored -> new Object());
        synchronized (fulfillmentLock) {
            return doAutoAcceptAndPrintLocked(order, cidFilter, detailIds);
        }
    }

    private PrintResult doAutoAcceptAndPrintLocked(Order order, Set<String> cidFilter, Collection<Integer> detailIds) {
        List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
        Set<Integer> targetIds = detailIds == null ? Collections.emptySet()
                : detailIds.stream().filter(Objects::nonNull).collect(Collectors.toSet());
        List<OrderDetail> unaccepted = details == null ? Collections.emptyList() : details.stream()
                .filter(this::isDetailUnaccepted)
                .filter(d -> targetIds.isEmpty() || targetIds.contains(d.getId()))
                .collect(Collectors.toList());
        if (unaccepted.isEmpty()) {
            return new PrintResult(reconcileOrderAcceptance(order, details, detailIds != null), Collections.emptyList());
        }
        order.setGoods_list(unaccepted);
        takeoutDeliveryService.enrichOrder(order);
        int printShopId = resolveOrderOwnedShopIdForPrint(order);
        boolean feiePrint = printShopId <= 0 || kdsConfigService.shouldFeiePrint(printShopId);
        boolean kdsEnabled = printShopId > 0 && kdsConfigService.isKdsEnabled(printShopId);
        boolean scheduleSupplementalPrint = feiePrint && kdsEnabled;
        if (!feiePrint) {
            log.info("kds_only 跳过飞鹅打印: order_no={}, shop_id={}", order.getOrder_no(), printShopId);
        } else if (scheduleSupplementalPrint) {
            log.info("KDS 模式附加打印延后至订单事务提交后异步执行: order_no={}, shop_id={}",
                    order.getOrder_no(), printShopId);
        }
        boolean printSucceeded = true;
        List<com.lanf.printing.model.PrintDispatchResult> allResults = new ArrayList<>();
        if (feiePrint && !scheduleSupplementalPrint) {
            if (printDispatcherService != null) {
                // 1. 统一调度派发后厨小票
                List<com.lanf.printing.model.PrintDispatchResult> kitchenRes = printDispatcherService.dispatch(
                        printShopId, com.lanf.printing.model.PrintScenario.KITCHEN,
                        com.lanf.printing.model.PrintContext.ofKitchen(order, cidFilter));
                allResults.addAll(kitchenRes);

                // 2. 统一调度派发前台加单/制作小票（外卖订单用外卖单模板）
                String frontScenario = PaymentDiningTypeUtil.isWaimaiType(order.getDineInOrTakeOut())
                        ? com.lanf.printing.model.PrintScenario.TAKEOUT
                        : com.lanf.printing.model.PrintScenario.ORDER;
                List<com.lanf.printing.model.PrintDispatchResult> orderRes = printDispatcherService.dispatch(
                        printShopId, frontScenario,
                        com.lanf.printing.model.PrintContext.ofOrder(order, true));
                allResults.addAll(orderRes);

                // 3. 打包/自提订单可通过独立 PACKING 规则路由至打包台打印机；无规则时安全跳过。
                List<com.lanf.printing.model.PrintDispatchResult> packingRes = Collections.emptyList();
                if (PaymentDiningTypeUtil.isTakeOutType(order.getDineInOrTakeOut())) {
                    packingRes = printDispatcherService.dispatch(
                            printShopId, com.lanf.printing.model.PrintScenario.PACKING,
                            com.lanf.printing.model.PrintContext.ofOrder(order, true));
                    allResults.addAll(packingRes);
                }

                boolean noPrintersConfigured = kitchenRes.isEmpty() && orderRes.isEmpty() && packingRes.isEmpty();
                if (kdsEnabled || noPrintersConfigured) {
                    // KDS 模式或未配置物理打印机规则：打印作为附加通道，不阻断数字化接单与 KDS 投影下发
                    printSucceeded = true;
                    if (!kitchenRes.isEmpty() || !orderRes.isEmpty()) {
                        boolean allKitchenFails = !kitchenRes.isEmpty() && kitchenRes.stream().allMatch(r -> !r.isSuccess());
                        boolean allOrderFails = !orderRes.isEmpty() && orderRes.stream().allMatch(r -> !r.isSuccess());
                        boolean allPackingFails = !packingRes.isEmpty() && packingRes.stream().allMatch(r -> !r.isSuccess());
                        if (allKitchenFails || allOrderFails || allPackingFails) {
                            log.warn("物理打印部分或全部失败，因 KDS 启用已放行数字化接单: order_no={}, shop_id={}",
                                    order.getOrder_no(), printShopId);
                        }
                    }
                } else {
                    // 纯打印模式（print_only）且配置了打印机：若所有打印机均派发失败，则保留订单待重试
                    boolean hasKitchenFails = kitchenRes.isEmpty() || kitchenRes.stream().allMatch(r -> !r.isSuccess());
                    boolean hasOrderFails = orderRes.isEmpty() || orderRes.stream().allMatch(r -> !r.isSuccess());
                    boolean hasPackingFails = !packingRes.isEmpty() && packingRes.stream().allMatch(r -> !r.isSuccess());
                    if (hasKitchenFails || hasOrderFails || hasPackingFails) {
                        printSucceeded = false;
                    }
                }
            }
        }
        if (!printSucceeded) {
            keepOrderPending(order);
            return new PrintResult(false, allResults);
        }
        boolean detailsUpdated = true;
        for (OrderDetail d : unaccepted) {
            try {
                d.setOrder_rece("rec_order");
                if (!orderDetailService.updateById(d)) {
                    d.setOrder_rece("mis_order");
                    detailsUpdated = false;
                    log.warn("更新明细接单状态失败: detailId={}", d.getId());
                }
            } catch (Exception e) {
                d.setOrder_rece("mis_order");
                detailsUpdated = false;
                log.warn("更新明细接单状态失败: detailId={}, {}", d.getId(), e.getMessage());
            }
        }
        List<OrderDetail> latestDetails = orderDetailService.list(
                new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
        boolean acceptanceUpdated = reconcileOrderAcceptance(order, latestDetails, detailIds != null);
        if (scheduleSupplementalPrint && detailsUpdated && acceptanceUpdated) {
            if (kdsSupplementalPrintService != null) {
                List<Integer> acceptedDetailIds = unaccepted.stream()
                        .map(OrderDetail::getId)
                        .filter(Objects::nonNull)
                        .collect(Collectors.toList());
                kdsSupplementalPrintService.scheduleAfterCommit(
                        printShopId, order.getId(), acceptedDetailIds, cidFilter);
            } else {
                log.error("KDS 附加打印服务不可用，数字化接单继续: order_no={}, shop_id={}",
                        order.getOrder_no(), printShopId);
            }
        }
        return new PrintResult(detailsUpdated && acceptanceUpdated, allResults);
    }

    private void keepOrderPending(Order order) {
        order.setOrder_receiving("mis_order");
        try {
            if (!orderService.updateById(order)) {
                log.warn("保留订单待重试状态失败: order_no={}", order.getOrder_no());
            }
        } catch (Exception e) {
            log.warn("保留订单待重试状态异常: order_no={}, {}", order.getOrder_no(), e.getMessage());
        }
    }

    private boolean reconcileOrderAcceptance(Order order, List<OrderDetail> details, boolean intentAlreadyRecorded) {
        boolean hasUnaccepted = details != null && details.stream().anyMatch(this::isDetailUnaccepted);
        order.setOrder_receiving(hasUnaccepted ? "mis_order" : "rec_order");
        try {
            boolean updated = hasUnaccepted || intentAlreadyRecorded
                    ? orderService.updateById(order)
                    : cashierKdsProjectionService.persistAcceptedOrder(order.getId(), () -> orderService.updateById(order));
            if (!updated) {
                log.warn("更新订单接单状态失败: order_no={}", order.getOrder_no());
                return false;
            }
            if (!hasUnaccepted && isWaimaiType(order.getDineInOrTakeOut())) {
                takeoutDeliveryService.markAcceptedIfPresent(order.getOrder_no(), order.getId());
                takeoutDeliveryService.enrichOrder(order);
            }
            if (!hasUnaccepted) {
                log.info("自动接单成功: order_no={}", order.getOrder_no());
            }
            return true;
        } catch (Exception e) {
            log.warn("自动接单更新失败: {}", e.getMessage());
            return false;
        }
    }

    private PrintResult doAutoAcceptAndPrint(Order order) {
        return doAutoAcceptAndPrint(order, null);
    }

    /**
     * 补打厨房小票：按当前有效明细重打，不修改 {@code order_receiving}/{@code order_rece}；
     * {@code kds_only} 门店亦会下发飞鹅（运营手动补打）。
     *
     * @param cidFilter 非空时仅影响分单合并（与 {@link #autoAcceptAndPrintByCid} 一致）；{@code null} 使用默认合并组
     */
    public R reprintKitchenTickets(Order order, Set<String> cidFilter) {
        if (order == null) {
            return R.error("订单不存在");
        }
        QueryWrapper<OrderDetail> dq = new QueryWrapper<OrderDetail>().eq("mId", order.getId());
        dq.and(w -> w.isNull("line_status").or().eq("line_status", OrderDetailLineStatus.NORMAL));
        List<OrderDetail> details = orderDetailService.list(dq);
        if (details == null || details.isEmpty()) {
            return R.error("订单无有效明细，无法补打");
        }
        order.setGoods_list(details);
        takeoutDeliveryService.enrichOrder(order);
        int printShopId;
        try {
            printShopId = resolveOrderOwnedShopIdForPrint(order);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }

        if (printDispatcherService != null) {
            List<com.lanf.printing.model.PrintDispatchResult> results = printDispatcherService.dispatch(
                    printShopId, com.lanf.printing.model.PrintScenario.KITCHEN,
                    com.lanf.printing.model.PrintContext.ofKitchen(order, cidFilter));
            int printed = (int) results.stream().filter(com.lanf.printing.model.PrintDispatchResult::isSuccess).count();
            int failed = results.size() - printed;
            List<String> errors = new ArrayList<>();
            for (com.lanf.printing.model.PrintDispatchResult r : results) {
                if (!r.isSuccess() && r.getError() != null) {
                    errors.add(r.getError());
                }
            }
            if (results.isEmpty()) {
                return R.error("未配置后厨打印设备或规则").put("order_no", order.getOrder_no());
            }
            if (printed == 0) {
                return R.error("厨房小票补打失败").put("ticket_count", results.size())
                        .put("printed_count", 0).put("failed_count", failed)
                        .put("order_no", order.getOrder_no()).put("errors", errors)
                        .put("printData", toPayloadSummary(results));
            }
            log.info("补打厨房小票: order_no={}, tickets={}, printed={}, failed={}",
                    order.getOrder_no(), results.size(), printed, failed);
            return R.ok(failed > 0 ? "部分厨房小票补打成功" : "厨房小票补打成功")
                    .put("ticket_count", results.size())
                    .put("printed_count", printed)
                    .put("failed_count", failed)
                    .put("order_no", order.getOrder_no())
                    .put("errors", errors)
                    .put("printData", toPayloadSummary(results));
        }
        return R.error("未配置打印调度服务");
    }

    /**
     * 供收银侧按指定 cid 数组打印厨房票：命中 cid 合并一张，剩余按分类分别打印。
     */
    public R autoAcceptAndPrintByCid(Integer orderId, List<String> cidList) {
        Order order = orderService.getById(orderId);
        if (order == null) {
            return R.error("订单不存在");
        }
        Set<String> cidFilter = new HashSet<>();
        if (cidList != null) {
            for (String c : cidList) {
                cidFilter.add(normalizeCidKey(c));
            }
        }
        try {
            PrintResult pr = doAutoAcceptAndPrint(order, cidFilter.isEmpty() ? null : cidFilter);
            if (!pr.success) {
                return R.error("接单并打印失败，订单已保留待重试状态").put("printData", toPayloadSummary(pr.printResults));
            }
            return R.ok("接单并打印成功").put("printData", toPayloadSummary(pr.printResults));
        } catch (Exception e) {
            log.warn("按cid接单并打印异常, orderId={}, {}", orderId, e.getMessage());
            return R.error("接单并打印失败");
        }
    }

    /**
     * 处理待接单订单：门店营业中（{@code ordering_open=1}）时，查询待接单订单并逐个自动接单并打印。
     * 堂食等：未支付（unsettled）即接单打印；打包/外卖：已支付（success）才接单打印。
     */
    public void processPendingOrdersForAutoAccept() {
        processPendingOrdersForAutoAccept(null);
    }

    /**
     * @param shopId 仅处理指定门店；{@code null} 表示全部门店（跳过休息中门店的订单）
     */
    public void processPendingOrdersForAutoAccept(Integer shopId) {
        Date retrySince = new Date(System.currentTimeMillis() - TimeUnit.DAYS.toMillis(2));
        QueryWrapper<Order> qw = new QueryWrapper<Order>()
                .and(w -> w.isNull("order_receiving").or().eq("order_receiving", "")
                        .or().eq("order_receiving", "mis_order").or().eq("order_receiving", "mis_orders"))
                .in("transac_status", "success", "unsettled")
                .ge("order_time", retrySince)
                .orderByAsc("order_time", "id")
                .last("LIMIT 50");
        if (shopId != null) {
            qw.eq("shop_id", shopId);
        }
        List<Order> pending = orderService.list(qw);
        if (pending == null || pending.isEmpty()) return;
        for (Order order : pending) {
            try {
                if (!isOrderPendingAutoAccept(order)) {
                    continue;
                }
                if (!shouldAutoAcceptForOrder(order)) {
                    continue;
                }
                boolean remotePayFirst = isPackOrDeliveryType(order.getDineInOrTakeOut());
                String status = order.getTransac_status();
                if (remotePayFirst && "success".equals(status)) {
                    PrintResult result = doAutoAcceptAndPrint(order);
                    if (result.success) {
                        pushKdsAfterAccepted(order, null, com.lanf.kds.service.KdsOrderHook.Trigger.MANUAL);
                    }
                } else if (!remotePayFirst && "unsettled".equals(status)) {
                    PrintResult result = doAutoAcceptAndPrint(order);
                    if (result.success) {
                        pushKdsAfterAccepted(order, null, com.lanf.kds.service.KdsOrderHook.Trigger.MANUAL);
                    }
                }
            } catch (Exception e) {
                log.warn("待接单订单处理异常，order_no={}，{}", order.getOrder_no(), e.getMessage());
            }
        }
    }

    /**
     * KDS 建单失败不能通过重新打印来补偿。仅检查最近两天已经接单、且尚无有效工单的订单，
     * 由工单唯一约束保证多实例下重复执行仍然安全。
     */
    public void repairAcceptedKdsTickets() {
        Date retrySince = new Date(System.currentTimeMillis() - TimeUnit.DAYS.toMillis(2));
        List<Order> accepted = orderService.list(new QueryWrapper<Order>()
                .eq("order_receiving", "rec_order")
                .ge("order_time", retrySince)
                .orderByAsc("order_time", "id")
                .last("LIMIT 50"));
        if (accepted == null || accepted.isEmpty()) {
            return;
        }
        for (Order order : accepted) {
            if (order == null || order.getId() == null || order.getShop_id() == null
                    || !kdsConfigService.isKdsEnabled(order.getShop_id())) {
                continue;
            }
            try {
                if (kdsOrderHook.hasMissingTicketsForOrder(order)) {
                    kdsOrderHook.ensureTicketsForAcceptedOrder(order);
                }
            } catch (Exception ex) {
                log.warn("已接单订单 KDS 建单补偿失败，order_no={}，{}", order.getOrder_no(), ex.getMessage());
            }
        }
    }

    // 格式化日期（假设输入为时间戳字符串，根据实际格式调整）
    private String formatDate(String timeStr) {
        if (timeStr == null || timeStr.isEmpty()) {
            return "";
        }
        try {
            long timestamp = Long.parseLong(timeStr);
            SimpleDateFormat sdf = new SimpleDateFormat(TIME_FORMAT_DISPLAY);
            return sdf.format(new Date(timestamp));
        } catch (NumberFormatException e) {
            // 如果不是时间戳，直接返回原字符串（根据实际格式调整）
            return timeStr;
        }
    }

    /** 辣度排序优先级（厨房小票按此排序：特辣>中辣>微辣>不辣） */
    private int getSpicyPriority(String selectedSpicy) {
        String text = getSpicyText(selectedSpicy);
        if (text == null || text.isEmpty()) return 0;
        if (text.contains("特辣")) return 3;
        if (text.contains("中辣")) return 2;
        if (text.contains("微辣")) return 1;
        return 0;
    }

    /** 小票规格行：无有效规格时不输出（避免 append(null) 打出字面量 null） */
    private static void appendPrintSpecLine(StringBuilder content, String selectedSpicyRaw) {
        String text = getSpicyText(selectedSpicyRaw);
        if (text != null && !text.isEmpty()) {
            content.append(text).append("<BR><BR>");
        } else {
            content.append("<BR>");
        }
    }

    /** 小票菜名后括号规格：无有效规格时返回空串 */
    private static String formatPrintSpecInParens(String selectedSpicyRaw) {
        String text = getSpicyText(selectedSpicyRaw);
        if (text == null || text.isEmpty()) {
            return "";
        }
        return "(" + text + ")";
    }

    private static boolean isMeaningfulSpecPart(String s) {
        if (s == null) {
            return false;
        }
        String t = s.trim();
        return !t.isEmpty() && !"null".equalsIgnoreCase(t);
    }

    private static void addSpecPart(List<String> parts, Object item) {
        if (item == null) {
            return;
        }
        String s = item.toString().trim();
        if (isMeaningfulSpecPart(s)) {
            parts.add(s);
        }
    }

    // 处理规格/辣度文本（selectedSpicy JSON → 逗号分隔展示）
    private static String getSpicyText(String spicy) {
        if (spicy == null || spicy.trim().isEmpty()) {
            return null;
        }
        String trimmed = spicy.trim();
        if ("null".equalsIgnoreCase(trimmed)) {
            return null;
        }

        try {
            ObjectMapper objectMapper = new ObjectMapper();
            // 兼容两种格式：值为数组 {"辣度":["微辣"]} 或 值为字符串 {"辣度":"微辣"}
            Map<String, Object> spicys = objectMapper.readValue(trimmed, new TypeReference<Map<String, Object>>() {});
            List<String> parts = new ArrayList<>();
            for (Object val : spicys.values()) {
                if (val instanceof List) {
                    for (Object item : (List<?>) val) {
                        addSpecPart(parts, item);
                    }
                } else {
                    addSpecPart(parts, val);
                }
            }
            return parts.isEmpty() ? null : String.join(",", parts);
        } catch (Exception e) {
            return isMeaningfulSpecPart(trimmed) ? trimmed : null;
        }
    }

    // 计算单价
    private double calculatePrice(OrderDetail good) {
        if (good.getTotal_price() == null || good.getQuantity() == null) {
            return 0;
        }
        try {
            double total = Double.parseDouble(String.valueOf(good.getTotal_price()));
            int quantity = Integer.parseInt(good.getQuantity());
            return quantity > 0 ? total / quantity : 0;
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    // 解析数量
    private int parseQuantity(String quantityStr) {
        if (quantityStr == null) {
            return 0;
        }
        try {
            return Integer.parseInt(quantityStr);
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    // 计算总价
    private double calculateTotalPrice(OrderDetail good, double price, int quantity) {
        if (good.getTotal_price() != null) {
            try {
                return Double.parseDouble(String.valueOf(good.getTotal_price()));
            } catch (NumberFormatException e) {
                // 忽略异常，使用计算值
            }
        }
        return price * quantity;
    }

    // 右补空格（模拟JS的padEnd）
    private String padEnd(int length) {
        if (length <= 0) {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < length; i++) {
            sb.append(" ");
        }
        return sb.toString();
    }

    // 左补空格（模拟JS的padStart）
    private String padStart(String str, int length) {
        if (str == null) {
            str = "";
        }
        int need = length - str.length();
        if (need <= 0) {
            return str;
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < need; i++) {
            sb.append(" ");
        }
        sb.append(str);
        return sb.toString();
    }

    // 注册时间判断函数
    private boolean isRegisteredOver7Days(Date registerTime) {
        if (registerTime == null) {
            // 若注册时间为空，按业务需求处理（此处默认返回false）
            return false;
        }
        long sevenDaysMillis = 7 * 24 * 60 * 60 * 1000L; // 7天的毫秒数
        long currentTimeMillis = System.currentTimeMillis();
        long registerTimeMillis = registerTime.getTime();

        // 计算当前时间与注册时间的差值，判断是否超过7天
        return (currentTimeMillis - registerTimeMillis) > sevenDaysMillis;
    }
    public static class StreamUtils {
        // 替代 readAllBytes() 的兼容方法
        public static byte[] readAllBytes(ServletInputStream inputStream) throws IOException {
            ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
            byte[] buffer = new byte[1024];
            int bytesRead;

            while ((bytesRead = inputStream.read(buffer)) != -1) {
                outputStream.write(buffer, 0, bytesRead);
            }

            return outputStream.toByteArray();
        }
    }
    /**
     * 根据商户订单号查询微信支付订单
     * 订单支付成功后，可使用商户订单号查询；未支付订单也可查询
     */
    @GetMapping("/queryByOutTradeNo/{outTradeNo}")
    public R queryByOutTradeNo(@PathVariable String outTradeNo,
                               @RequestParam(required = false) String merchantId,
                               HttpServletRequest request) {
        Object identity = request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID);
        if (identity == null || !StringUtils.hasText(identity.toString())) {
            return R.error(401, "用户登录已过期，请重新登录");
        }
        return queryByOutTradeNoOwned(outTradeNo, merchantId, identity.toString());
    }

    /** 外部打印和 KDS 副作用只允许在订单事务成功提交后执行。 */
    static void runAfterCommit(Runnable action) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    runPostCommitAction(action);
                }
            });
            return;
        }
        runPostCommitAction(action);
    }

    private static void runPostCommitAction(Runnable action) {
        try {
            action.run();
        } catch (Exception ex) {
            log.error("订单提交后处理异常", ex);
        }
    }

    private void fulfillAddedDishes(Integer orderId, List<Integer> newDetailIds, boolean autoAccept) {
        Order committedOrder = orderId != null ? orderService.getById(orderId) : null;
        if (committedOrder == null) {
            log.warn("加菜提交后处理失败，订单不存在: orderId={}", orderId);
            return;
        }
        if (autoAccept && !doAutoAcceptAndPrint(committedOrder, null, newDetailIds).success) {
            log.warn("加菜后自动接单打印失败，保留待重试状态，订单号：{}", committedOrder.getOrder_no());
        }
        kdsOrderHook.afterAddedDishesCommitted(committedOrder, newDetailIds);
    }

    private R queryByOutTradeNoOwned(String outTradeNo, String merchantId, String authenticatedOpenid) {
        try {
            // 参数校验
            if (outTradeNo == null || outTradeNo.trim().isEmpty()) {
                return R.error("商户订单号不能为空");
            }

            String orderNoForDb = parseOrderNoFromOutTradeNo(outTradeNo);
            Order localOrder = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNoForDb));
            if (localOrder != null) {
                if (!authenticatedOpenid.equals(localOrder.getOpenid())) {
                    return R.error(403, "无权查询该订单");
                }
                merchantId = localOrder.getMerchantId();
            } else if (isWxRechargeMerchantNo(orderNoForDb)) {
                MemberRecharge recharge = memberRechargeService.getOne(new QueryWrapper<MemberRecharge>()
                        .eq("order_no", orderNoForDb).eq("openid", authenticatedOpenid).last("LIMIT 1"));
                if (recharge == null) {
                    return R.error(403, "无权查询该充值订单");
                }
                merchantId = "1";
            } else {
                return R.error("订单不存在");
            }

            // 商户配置由已完成归属校验的本地订单决定，不信任前端 merchantId。
            String mchid;
            PrivateKey privateKey;
            String serialNo;
            String pubSerial;

            // 根据商户ID获取对应的配置
            if ("2".equals(merchantId)) {
                mchid = mchid2;
                privateKey = privateKey2;
                serialNo = serialNo2;
                pubSerial = pubSerial2;
            } else {
                mchid = mchid1;
                privateKey = privateKey1;
                serialNo = serialNo1;
                pubSerial = pubSerial1;
            }

            // 1. 生成请求参数和签名
            String nonceStr = generateNonceStr();
            String timestamp = String.valueOf(System.currentTimeMillis() / 1000);
            String urlPath = "/v3/pay/transactions/out-trade-no/" + outTradeNo;

            // 生成签名（GET请求body为空）
            String signature = generatePaymentSignature(
                    "GET",
                    urlPath,
                    timestamp,
                    nonceStr,
                    "",  // GET请求body为空
                    privateKey
            );

            // 2. 构建请求URL
            String url = "https://api.mch.weixin.qq.com" + urlPath + "?mchid=" + mchid;

            // 3. 设置请求头
            HttpHeaders headers = new HttpHeaders();
            headers.set("Accept", "application/json");
            headers.set("Authorization", String.format(
                    "WECHATPAY2-SHA256-RSA2048 mchid=\"%s\",nonce_str=\"%s\",timestamp=\"%s\",signature=\"%s\",serial_no=\"%s\"",
                    mchid, nonceStr, timestamp, signature, serialNo
            ));
            headers.set("Wechatpay-Serial", pubSerial);

            HttpEntity<String> requestEntity = new HttpEntity<>(headers);

            // 4. 发送请求
            String response = restTemplate.exchange(
                    url,
                    HttpMethod.GET,
                    requestEntity,
                    String.class
            ).getBody();

            // 5. 解析响应
            if (response == null) {
                return R.error("查询订单失败，未获取到响应");
            }

            Map<String, Object> responseMap = objectMapper.readValue(response, Map.class);

            // 6. 检查是否有错误信息
            if (responseMap.containsKey("code")) {
                String errorCode = (String) responseMap.get("code");
                String errorMsg = (String) responseMap.getOrDefault("message", "未知错误");
                return R.error("查询失败: " + errorCode + " - " + errorMsg);
            }

            // 7. 处理返回结果
            return R.ok().put("orderInfo", responseMap);

        } catch (Exception e) {
            log.error("查询订单异常", e);
            return R.error("查询订单异常");
        }
    }

    /**
     * 微信会员充值：仅依赖 {@code t_member_recharge}（与点餐 {@code t_order} 无关）。
     */
    private void handleWechatMemberRechargePaymentNotify(PrintWriter out, String notifyId,
                                                         String rechargeNo, String outTradeNo,
                                                         Map<String, Object> paymentResult) throws IOException {
        Boolean alreadyProcessed = processedNotifications.getIfPresent(notifyId);
        if (Boolean.TRUE.equals(alreadyProcessed)) {
            out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
            return;
        }
        String tradeStatus = (String) paymentResult.get("trade_state");
        if (!"SUCCESS".equals(tradeStatus)) {
            processedNotifications.put(notifyId, true);
            out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
            return;
        }
        Object lock = paymentOrderLocks.get(rechargeNo, k -> new Object());
        synchronized (lock) {
            MemberRecharge latest = memberRechargeService.getOne(
                    new QueryWrapper<MemberRecharge>().eq("order_no", rechargeNo).eq("channel", "wechat").last("LIMIT 1"));
            if (latest == null) {
                log.error("微信充值流水不存在: {}", rechargeNo);
                out.write("{\"code\":\"FAIL\",\"message\":\"记录不存在\"}");
                return;
            }
            if ("success".equals(latest.getStatus())) {
                log.info("微信充值已入账，跳过重复回调: {}", rechargeNo);
                processedNotifications.put(notifyId, true);
                out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
                return;
            }
            if (!"pending".equals(latest.getStatus())) {
                log.error("微信充值流水状态异常: {} status={}", rechargeNo, latest.getStatus());
                out.write("{\"code\":\"FAIL\",\"message\":\"状态异常\"}");
                return;
            }
            String transactionId = (String) paymentResult.get("transaction_id");
            String successTime = (String) paymentResult.get("success_time");
            Map<String, Object> amount = (Map<String, Object>) paymentResult.get("amount");
            Integer total = amount != null ? (Integer) amount.get("total") : 0;

            double expectYuan = latest.getRecharge_amount() != null ? latest.getRecharge_amount().doubleValue() : 0d;
            if (expectYuan > 0 && total != null) {
                int expectFen = (int) Math.round(expectYuan * 100);
                if (total <= 0 || total > expectFen) {
                    log.error("微信充值金额异常(分): 期望<={}, 实付={}", expectFen, total);
                    out.write("{\"code\":\"FAIL\",\"message\":\"金额不匹配\"}");
                    return;
                }
            }
            double paidYuan = (total != null ? total : 0) / 100.0;
            Date payTime = parseDate(successTime);
            User u = userService.getUserByOpenid(latest.getOpenid());
            if (u == null || u.getId() == null) {
                log.error("event=recharge_user_missing");
                out.write("{\"code\":\"FAIL\",\"message\":\"用户不存在\"}");
                return;
            }
            BigDecimal paidBd = BigDecimal.valueOf(paidYuan).setScale(2, RoundingMode.HALF_UP);
            BigDecimal giftBd = latest.getGift_amount() != null
                    ? latest.getGift_amount().setScale(2, RoundingMode.HALF_UP)
                    : BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
            if (!userService.addBalanceAndGift(u.getId(), paidBd, giftBd)) {
                BigDecimal totalTry = paidBd.add(giftBd).setScale(2, RoundingMode.HALF_UP);
                log.error("微信充值回调入账失败: userId={}, principal={}, gift={}, total={}", u.getId(), paidBd, giftBd, totalTry);
                out.write("{\"code\":\"FAIL\",\"message\":\"入账失败\"}");
                return;
            }
            log.info("微信充值入账: rechargeNo={} out_trade_no={} paidYuan={} giftYuan={} totalCredit={}",
                    rechargeNo, outTradeNo, paidYuan, giftBd, paidBd.add(giftBd).setScale(2, RoundingMode.HALF_UP));
            memberRechargeService.markSuccessWechat(rechargeNo, transactionId, payTime);
        }
        processedNotifications.put(notifyId, true);
        out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
    }

    /**
     * 微信支付回调通知处理接口
     */
    @PostMapping("/pay/notify")
    public void handlePaymentNotify(HttpServletRequest request, HttpServletResponse response) throws IOException {
        // 支付回调属于资金权威路径，不允许通过灰度开关回退到缺少支付尝试校验的旧实现。
        wechatPaymentNotifyService.handle(request, response);
    }

    public void paymentHandlePaymentNotify(HttpServletRequest request, HttpServletResponse response) throws IOException {
        response.setContentType("application/json;charset=UTF-8");
        PrintWriter out = response.getWriter();

        try {
            // 1. 读取请求体
            byte[] bodyBytes = StreamUtils.readAllBytes(request.getInputStream());
            String body = new String(bodyBytes, StandardCharsets.UTF_8);
            log.info("event=wechat_payment_callback_received bodySummary={}", SafeLogValue.summarize(body));
            String serial = request.getHeader("Wechatpay-Serial");
            String merchantId = "";
            // 2. 验证签名
            boolean signatureValid = verifyPaymentSignature(body, request);
            String apiV3Key = "";
            if(serial.equals(pubSerial1)){
                apiV3Key = apiV3Key1;
                merchantId ="1";
            }else{
                apiV3Key = apiV3Key2;
                merchantId ="2";
            }
            if (!signatureValid) {
                log.error("微信支付回调签名验证失败");
                out.write("{\"code\":\"FAIL\",\"message\":\"签名验证失败\"}");
                return;
            }

            // 3. 解析通知内容
            Map<String, Object> notifyData = objectMapper.readValue(body, Map.class);

            // 提取基本信息
            String notifyId = (String) notifyData.get("id");
            String eventType = (String) notifyData.get("event_type");
            String resourceType = (String) notifyData.get("resource_type");

            // 4. 验证资源类型
            if (!"encrypt-resource".equals(resourceType)) {
                log.error("不支持的资源类型: {}", resourceType);
                out.write("{\"code\":\"FAIL\",\"message\":\"不支持的资源类型\"}");
                return;
            }

            // 5. 支付失败/关单：将该订单关联的优惠券改回未使用（仅支付成功才核销，参考 openapi 支付回调）
            if ("TRANSACTION.FAIL".equals(eventType) || "TRANSACTION.CLOSED".equals(eventType)) {
                Map<String, Object> resourceFail = (Map<String, Object>) notifyData.get("resource");
                if (resourceFail != null && "AEAD_AES_256_GCM".equals(resourceFail.get("algorithm"))) {
                    String ciphertextFail = (String) resourceFail.get("ciphertext");
                    String associatedDataFail = (String) resourceFail.get("associated_data");
                    String nonceFail = (String) resourceFail.get("nonce");
                    if (ciphertextFail != null && associatedDataFail != null && nonceFail != null) {
                        try {
                            String decryptFail = decryptPaymentData(ciphertextFail, associatedDataFail, nonceFail, apiV3Key);
                            Map<String, Object> decMap = objectMapper.readValue(decryptFail, Map.class);
                            String outTradeNoFail = (String) decMap.get("out_trade_no");
                            if (outTradeNoFail != null && !outTradeNoFail.isEmpty()) {
                                String orderNoFail = parseOrderNoFromOutTradeNo(outTradeNoFail);
                                if (!isWxRechargeMerchantNo(orderNoFail)) {
                                    UserCoupon uc = UserCouponMapper.selectOne(new QueryWrapper<UserCoupon>().eq("order_no", orderNoFail).last("LIMIT 1"));
                                    if (uc != null) {
                                        uc.setOrder_no(null);
                                        uc.setUse_time(null);
                                        uc.setStatus(0);
                                        UserCouponMapper.updateById(uc);
                                        log.info("支付未成功，优惠券已退回未使用: order_no={}, user_coupon_id={}", orderNoFail, uc.getId());
                                    }
                                }
                            }
                        } catch (Exception e) {
                            log.warn("支付失败/关单回调解密或回退优惠券异常: {}", e.getMessage());
                        }
                    }
                }
                out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
                return;
            }

            // 6. 非支付成功且非失败/关单的事件，直接返回成功
            if (!"TRANSACTION.SUCCESS".equals(eventType)) {
                log.info("非支付成功事件，不做处理: {}", eventType);
                out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
                return;
            }

            // 7. 获取加密资源并解密（支付成功分支）
            Map<String, Object> resource = (Map<String, Object>) notifyData.get("resource");
            if (resource == null) {
                log.error("回调报文中resource字段不存在");
                out.write("{\"code\":\"FAIL\",\"message\":\"资源信息缺失\"}");
                return;
            }

            // 验证加密算法
            String algorithm = (String) resource.get("algorithm");
            if (!"AEAD_AES_256_GCM".equals(algorithm)) {
                log.error("不支持的加密算法: {}", algorithm);
                out.write("{\"code\":\"FAIL\",\"message\":\"不支持的加密算法\"}");
                return;
            }

            // 提取加密相关参数
            String ciphertext = (String) resource.get("ciphertext");
            String associatedData = (String) resource.get("associated_data");
            String nonce = (String) resource.get("nonce");
            String originalType = (String) resource.get("original_type");

            // 7. 解密；若为微信会员充值（t_member_recharge.channel=wechat）则不走 t_order
            String decryptData = decryptPaymentData(ciphertext, associatedData, nonce, apiV3Key);
            Map<String, Object> paymentResult = objectMapper.readValue(decryptData, Map.class);
            String outTradeNo = (String) paymentResult.get("out_trade_no");
            String orderNo = parseOrderNoFromOutTradeNo(outTradeNo);

            if (isWxRechargeMerchantNo(orderNo)) {
                handleWechatMemberRechargePaymentNotify(out, notifyId, orderNo, outTradeNo, paymentResult);
                return;
            }

            int maxRetries = 10;
            int retryCount = 0;
            Order order = null;

            while (retryCount < maxRetries) {
                order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo));

                if (order != null) {
                    break;
                }

                retryCount++;
                log.info("第{}次查询未找到订单: {}", retryCount, outTradeNo);

                try {
                    Thread.sleep(500);
                } catch (InterruptedException e) {
                    log.error("查询订单时线程中断", e);
                    Thread.currentThread().interrupt();
                    break;
                }
            }

            if (order == null) {
                log.error("经过{}次查询仍未找到对应的订单: {} (out_trade_no={})", maxRetries, orderNo, outTradeNo);
                out.write("{\"code\":\"FAIL\",\"message\":\"订单不存在\"}");
                return;
            }

            log.info("event=wechat_payment_callback_decrypted payloadSummary={}",
                    SafeLogValue.summarize(decryptData));

            String transactionId = (String) paymentResult.get("transaction_id");
            String tradeStatus = (String) paymentResult.get("trade_state");
            String bankType = (String) paymentResult.get("bank_type");
            String successTime = (String) paymentResult.get("success_time");
            Map<String, Object> payer = (Map<String, Object>) paymentResult.get("payer");
            String openid = (String) payer.get("openid");
            Map<String, Object> amount = (Map<String, Object>) paymentResult.get("amount");
            Integer total = amount != null ? (Integer) amount.get("total") : 0;

            // 9. 处理重复通知
            Boolean alreadyProcessed = processedNotifications.getIfPresent(notifyId);
            if (alreadyProcessed != null && alreadyProcessed) {
                log.info("通知已处理，直接返回成功: {}", notifyId);
                out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
                return;
            }

            // 10. 处理支付结果（按业务订单号加锁，防止重复回调导致二次更新/反积分）
            if ("SUCCESS".equals(tradeStatus)) {
                if (order != null) {
                    Object orderLock = paymentOrderLocks.get(orderNo, k -> new Object());
                    synchronized (orderLock) {
                        // 锁内再次查询订单最新状态，防止并发/重复回调重复处理
                        Order latestOrder = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo));
                        if (latestOrder == null) {
                            log.error("未找到对应的订单: {}", orderNo);
                            out.write("{\"code\":\"FAIL\",\"message\":\"订单不存在\"}");
                            return;
                        }
                        if ("success".equals(latestOrder.getTransac_status())) {
                            log.info("订单已支付成功，跳过重复处理（幂等）: {}", orderNo);
                            processedNotifications.put(notifyId, true);
                            out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
                            return;
                        }

                        // 验证订单金额：订单原价=sett_amount+service_fee（元），微信 total 为实付（分），实付须不超过订单原价
                        double orderOriginal = (latestOrder.getSett_amount() != null ? latestOrder.getSett_amount() : 0d) + (latestOrder.getService_fee() != null ? latestOrder.getService_fee() : 0d);
                        if (orderOriginal > 0 && total != null) {
                            int originalPriceFen = (int) Math.round(orderOriginal * 100);
                            if (total <= 0 || total > originalPriceFen) {
                                log.error("订单金额异常 - 订单原价(分): {}, 实付(分): {}", originalPriceFen, total);
                                out.write("{\"code\":\"FAIL\",\"message\":\"金额不匹配\"}");
                                return;
                            }
                        }

                        if ("unsettled".equals(latestOrder.getTransac_status())) {
                            latestOrder.setTransac_status("success");
                            logOrder(latestOrder.getOrder_no(), "pay", "openid", openid, latestOrder.getShop_id(), null);
                            latestOrder.setTransaction_id(transactionId);
                            latestOrder.setMerchantId(merchantId);
                            latestOrder.setPayment_method("微信支付");
                            latestOrder.setPay_openid(openid);
                            latestOrder.setPay_time(parseDate(successTime));
                            if(latestOrder.getOpenid() == null || latestOrder.getOpenid().isEmpty()){
                               latestOrder.setOpenid(openid); 
                            }
                            // 订单原价=sett_amount+service_fee（元）；优惠金额=订单原价-实付，保留两位小数
                            double paidYuan = (total != null ? total : 0) / 100.0;
                            if (orderOriginal >= paidYuan) {
                                latestOrder.setDiscount_amount(Math.round((orderOriginal - paidYuan) * 100) / 100.0);
                            }
                            OrderPayChannelAmounts.applySingleChannel(latestOrder, "wechat", paidYuan);
                            if (total != null) {
                                int chFen = OrderPayChannelAmounts.totalPayChannelAmountFen(latestOrder);
                                if (Math.abs(chFen - total) > 0) {
                                    log.warn("微信入账后渠道列合计与回调 total(分)不一致: order_no={} channelSumFen={} wxTotalFen={}",
                                            orderNo, chFen, total);
                                }
                            }
                            orderService.updateById(latestOrder);
                            log.info("订单支付状态更新成功: {} (out_trade_no={})", orderNo, outTradeNo);

                            runPostPaymentSuccessSideEffects(latestOrder, paidYuan);
                        }
                    }
                } else {
                    log.error("未找到对应的订单: {}", orderNo);
                }
            }

            // 11. 标记通知为已处理，避免同一 notify 再次进入
            processedNotifications.put(notifyId, true);

            // 12. 返回成功响应
            out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");

        } catch (Exception e) {
            log.error("处理回调通知异常", e);
            out.write("{\"code\":\"FAIL\",\"message\":\"处理异常\"}");
        } finally {
            out.flush();
            out.close();
        }
    }



    /**
     * 验证支付通知的签名
     */
    private boolean verifyPaymentSignature(String body, HttpServletRequest request) throws Exception {
        // 1. 获取签名相关参数
        String signature = request.getHeader("Wechatpay-Signature");
        String timestamp = request.getHeader("Wechatpay-Timestamp");
        String nonce = request.getHeader("Wechatpay-Nonce");
        String serial = request.getHeader("Wechatpay-Serial");  // 公钥序列号（仍需验证）
        log.info(serial);
        // 验证必要参数
        if (signature == null || timestamp == null || nonce == null || serial == null) {
            log.error("签名参数不完整");
            return false;
        }

        if (!serial.equals(pubSerial1) && !serial.equals(pubSerial2)) {
            log.error("公钥序列号不匹配 - 回调: {}", serial);
            return false;
        }
        if(serial.equals(pubSerial1)){
            wechatPublicKey = wechatPublicKey1;
        }else{
            wechatPublicKey = wechatPublicKey2;
        }
        // 3. 构建签名串（格式不变）
        String signatureStr = String.format("%s\n%s\n%s\n", timestamp, nonce, body);

        // 4. 使用公钥验证签名
        Signature sig = Signature.getInstance("SHA256withRSA");

        sig.initVerify(wechatPublicKey);  // 直接使用加载的公钥
        sig.update(signatureStr.getBytes(StandardCharsets.UTF_8));

        boolean valid = sig.verify(Base64.getDecoder().decode(signature));
        if (!valid) {
            log.error("签名验证失败 signatureSummary={}", SafeLogValue.summarize(signatureStr));
        }
        return valid;
    }





    /**
     * AES-GCM解密（微信支付V3接口标准解密方式）
     */
    private String decryptAesGcm(String encryptedData, String apiV3Key) throws Exception {
        byte[] encryptedBytes = Base64.getDecoder().decode(encryptedData);

        // 拆分nonce、ciphertext和tag
        byte[] nonce = new byte[12];
        byte[] ciphertext = new byte[encryptedBytes.length - 12 - 16];
        byte[] tag = new byte[16];

        System.arraycopy(encryptedBytes, 0, nonce, 0, 12);
        System.arraycopy(encryptedBytes, 12, ciphertext, 0, ciphertext.length);
        System.arraycopy(encryptedBytes, 12 + ciphertext.length, tag, 0, 16);

        // 解密
        SecretKeySpec key = new SecretKeySpec(apiV3Key.getBytes(StandardCharsets.UTF_8), "AES");
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        GCMParameterSpec parameterSpec = new GCMParameterSpec(128, nonce);

        cipher.init(Cipher.DECRYPT_MODE, key, parameterSpec);
        byte[] decryptedData = cipher.doFinal(ByteBuffer.allocate(ciphertext.length + tag.length)
                .put(ciphertext)
                .put(tag)
                .array());

        return new String(decryptedData, StandardCharsets.UTF_8);
    }




    /**
     * 解密微信支付回调的加密数据 - 支持指定APIv3密钥
     */
    private String decryptPaymentData(String ciphertext, String associatedData,
                                      String nonce, String apiV3Key) throws Exception {
        try{
            if (ciphertext == null || ciphertext.isEmpty()) {
                throw new IllegalArgumentException("加密数据不能为空");
            }

            // 1. 验证APIv3密钥
            if (apiV3Key == null || apiV3Key.length() != 32) {
                throw new IllegalArgumentException("APIv3密钥不正确（必须是32位字符串）");
            }

            // 2. 解码
            byte[] ciphertextBytes = Base64.getDecoder().decode(ciphertext);
            byte[] associatedDataBytes = associatedData != null ? associatedData.getBytes(StandardCharsets.UTF_8) : new byte[0];
            byte[] nonceBytes = nonce.getBytes(StandardCharsets.UTF_8);
            byte[] keyBytes = apiV3Key.getBytes(StandardCharsets.UTF_8);

            // 3. 初始化加密器
            SecretKey key = new SecretKeySpec(keyBytes, "AES");
            GCMParameterSpec parameterSpec = new GCMParameterSpec(128, nonceBytes);

            // 4. 解密
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key, parameterSpec);
            if (associatedDataBytes.length > 0) {
                cipher.updateAAD(associatedDataBytes);
            }

            byte[] decryptedData = cipher.doFinal(ciphertextBytes);
            return new String(decryptedData, StandardCharsets.UTF_8);

        }catch (AEADBadTagException e) {
            log.error("解密Tag不匹配 apiV3KeyLength={} nonceSummary={} associatedDataSummary={} ciphertextLength={}",
                    apiV3Key.length(), SafeLogValue.summarize(nonce), SafeLogValue.summarize(associatedData),
                    ciphertext.length(), e);
            throw e; // 重新抛出，不吞异常
        }

    }


    /**
     * 解析日期字符串
     */
    private Date parseDate(String dateStr) {
        try {
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX");
            return sdf.parse(dateStr);
        } catch (ParseException e) {
            log.error("解析日期失败: " + dateStr, e);
            return new Date();
        }
    }

    /**
     * 微信退款（商户 API v3，/v3/refund/domestic/refunds）。仅供 {@link com.lanf.controller.admin.AdminOrderController} 在 JWT+权限校验后调用。
     * <ul>
     *   <li>入参 {@code orderNo}（业务订单号）与 {@code transaction_id}（微信支付单号，兼容 {@code transactionId}）至少传一项；两者都传时须与同一订单一致</li>
     *   <li>仅 transac_status=success 的订单可退</li>
     *   <li>若 transaction_id 以 {@code BAL_} 开头（余额支付占位单号）：不向微信发起，按剩余可退金额退回用户钱包（按原单本金/赠送金比例入账 {@code principal_balance}/{@code gift_balance} 与 {@code balance}），并本请求内累加 refund_amount、备注</li>
     *   <li>否则须已写入微信 transaction_id，向微信发起退款；本地 refund_amount / remark 由 /order/refund/notify 在 SUCCESS 后写入</li>
     *   <li>按「剩余可退金额」校验：实付全额减去已入账的 refund_amount</li>
     *   <li>默认退剩余全额；可选 refundAmount（元）部分退</li>
     *   <li>外卖单：已发配送须 {@code dispatch_status=completed} 方可退；退款不会自动取消真省钱配送单</li>
     * </ul>
     */
    @AuditLog(module = "refund", action = "refund_apply", target = "#p0['orderNo'] ?: #p0['order_no']", diff = OrderRefundDiffProvider.class)
    public R refund(@RequestBody Map<String, Object> params) {
        return refund(params, null);
    }

    public R refund(Map<String, Object> params, Integer shopId) {
        try {
            String orderNoParam = params != null && params.get("orderNo") != null ? params.get("orderNo").toString().trim() : null;
            String wxTxnParam = null;
            if (params != null) {
                Object tid = params.get("transaction_id");
                if (tid == null) {
                    tid = params.get("transactionId");
                }
                if (tid != null) {
                    wxTxnParam = tid.toString().trim();
                }
            }
            if (!StringUtils.hasText(orderNoParam) && !StringUtils.hasText(wxTxnParam)) {
                return R.error("请提供 orderNo（业务订单号）或 transaction_id（微信支付单号）至少一项");
            }

            Order order = null;
            if (StringUtils.hasText(orderNoParam)) {
                QueryWrapper<Order> qw = new QueryWrapper<Order>().eq("order_no", orderNoParam);
                if (shopId != null && shopId > 0) {
                    qw.eq("shop_id", shopId);
                }
                order = orderService.getOne(qw);
                if (order != null && StringUtils.hasText(wxTxnParam)) {
                    String dbTid = order.getTransaction_id() != null ? order.getTransaction_id().trim() : "";
                    if (!wxTxnParam.equals(dbTid)) {
                        return R.error("订单号与微信支付单号不匹配");
                    }
                }
            }
            if (order == null && StringUtils.hasText(wxTxnParam)) {
                QueryWrapper<Order> qw = new QueryWrapper<Order>().eq("transaction_id", wxTxnParam);
                if (shopId != null && shopId > 0) {
                    qw.eq("shop_id", shopId);
                }
                order = orderService.getOne(qw);
            }
            if (order == null) {
                return R.error("订单不存在");
            }
            String orderNo = order.getOrder_no();

            if (!"success".equals(order.getTransac_status())) {
                return R.error("仅已支付订单可退款");
            }
            if (com.lanf.receivable.service.ReceivableService.PAYMENT_METHOD_RECEIVABLE
                    .equals(order.getPayment_method())) {
                return R.error(409, "挂账订单未发生支付，不能走支付退款；请在应收模块执行未回款撤销或按财务流程处理已回款订单");
            }
            String takeoutRefundBlock = takeoutDeliveryService.getRefundBlockReason(order);
            if (takeoutRefundBlock != null) {
                return R.error(takeoutRefundBlock);
            }
            if (isBalancePaymentTransactionId(order.getTransaction_id())) {
                return refundBalancePaidOrderLocal(order, params);
            }
            if (com.lanf.payment.support.PaymentChannelCatalog.NAME_COMBINED_PAY.equals(order.getPayment_method())
                    || (order.getTransaction_id() != null && order.getTransaction_id().startsWith("CASHIER_COMBINED_"))) {
                return R.error("组合支付剩余现金或线下扫码部分需人工退款并完成账务核对，禁止发起自动微信退款");
            }
            if (!StringUtils.hasText(order.getTransaction_id())) {
                return R.error("订单缺少微信支付单号 transaction_id，无法发起退款");
            }

            double paidYuan = (order.getSett_amount() != null ? order.getSett_amount() : 0d)
                    + (order.getService_fee() != null ? order.getService_fee() : 0d)
                    - (order.getDiscount_amount() != null ? order.getDiscount_amount() : 0d);
            if (paidYuan <= 0d) {
                return R.error("订单实付金额异常，无法退款");
            }
            int totalFen = (int) Math.round(paidYuan * 100d);
            int alreadyRefundedFen = (int) Math.round((order.getRefund_amount() != null ? order.getRefund_amount() : 0d) * 100d);
            int remainingFen = totalFen - alreadyRefundedFen;
            if (remainingFen <= 0) {
                return R.error("无可退金额");
            }
            int refundFen = remainingFen;
            if (params != null && params.get("refundAmount") != null && StringUtils.hasText(params.get("refundAmount").toString())) {
                try {
                    double refundYuan = Double.parseDouble(params.get("refundAmount").toString().trim());
                    refundFen = (int) Math.round(refundYuan * 100d);
                } catch (NumberFormatException ex) {
                    return R.error("退款金额格式错误");
                }
            }
            if (refundFen <= 0 || refundFen > remainingFen) {
                return R.error("退款金额不合法（需大于0且不超过剩余可退金额）");
            }
            final int driftToleranceFen = 100;
            int channelFen = OrderPayChannelAmounts.totalPayChannelAmountFen(order);
            if (OrderPayChannelAmounts.payChannelsDriftFromTheoryFen(order, remainingFen, driftToleranceFen)) {
                log.warn("订单剩余可退(分)与渠道列合计差异>1元: order_no={} remainingFen={} channelSumFen={}",
                        orderNo, remainingFen, channelFen);
            }
            int cappedFen = OrderPayChannelAmounts.capRefundFenWithChannelTotal(refundFen, remainingFen, channelFen);
            if (cappedFen < refundFen) {
                log.warn("退款申请已按渠道列合计截断: order_no={} requestedFen={} cappedFen={} channelSumFen={}",
                        orderNo, refundFen, cappedFen, channelFen);
                refundFen = cappedFen;
            }
            if (refundFen <= 0) {
                return R.error("订单渠道可退金额为0，请核对 pay_amount_* 或账务数据");
            }
            String reason = params != null && params.get("reason") != null ? params.get("reason").toString().trim() : "";
            String idempotencyKey = params != null && params.get("idempotency_key") != null
                    ? params.get("idempotency_key").toString().trim()
                    : (params != null && params.get("out_refund_no") != null
                    ? params.get("out_refund_no").toString().trim()
                    : "RFD_" + System.currentTimeMillis());
            return wechatJsapiChannel.domesticRefund(order, refundFen, totalFen, reason, idempotencyKey);
        } catch (Exception e) {
            log.error("退款异常", e);
            return R.error("退款异常");
        }
    }

    /**
     * 微信退款结果通知（V3）。需在退款 API 中传入 notify_url 指向本地址。
     * 仅在 event_type=REFUND.SUCCESS 且解密后 refund_status=SUCCESS 时累加 {@code refund_amount}（不修改 transac_status，是否退款以 refund_amount 为准）。
     */
    /** HTTP 映射见 {@link OrderRefundController} */
    public void handleRefundNotify(HttpServletRequest request, HttpServletResponse response) throws IOException {
        response.setContentType("application/json;charset=UTF-8");
        PrintWriter out = response.getWriter();
        try {
            byte[] bodyBytes = StreamUtils.readAllBytes(request.getInputStream());
            String body = new String(bodyBytes, StandardCharsets.UTF_8);
            log.info("event=wechat_refund_callback_received bodySummary={}", SafeLogValue.summarize(body));

            WechatMerchantKeyStore.NotifyContext ctx = merchantKeyStore.resolveNotifyContext(request, body);
            if (ctx == null || !ctx.signatureValid) {
                log.error("退款回调签名验证失败 serial={}", request.getHeader("Wechatpay-Serial"));
                out.write("{\"code\":\"FAIL\",\"message\":\"签名验证失败\"}");
                return;
            }

            Map<String, Object> notifyData = objectMapper.readValue(body, Map.class);
            String eventType = (String) notifyData.get("event_type");
            String notifyId = (String) notifyData.get("id");
            String resourceType = (String) notifyData.get("resource_type");

            if (eventType == null || !eventType.startsWith("REFUND.")) {
                log.warn("退款回调地址收到非退款事件: {}", eventType);
                out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
                return;
            }

            if (!"encrypt-resource".equals(resourceType)) {
                log.error("退款回调不支持的资源类型: {}", resourceType);
                out.write("{\"code\":\"FAIL\",\"message\":\"不支持的资源类型\"}");
                return;
            }

            Map<String, Object> resource = (Map<String, Object>) notifyData.get("resource");
            if (resource == null) {
                out.write("{\"code\":\"FAIL\",\"message\":\"资源信息缺失\"}");
                return;
            }
            if (!"AEAD_AES_256_GCM".equals(resource.get("algorithm"))) {
                out.write("{\"code\":\"FAIL\",\"message\":\"不支持的加密算法\"}");
                return;
            }

            String ciphertext = (String) resource.get("ciphertext");
            Object adObj = resource.get("associated_data");
            String associatedData = adObj != null ? adObj.toString() : null;
            String nonce = (String) resource.get("nonce");
            if (ciphertext == null || nonce == null) {
                out.write("{\"code\":\"FAIL\",\"message\":\"密文参数缺失\"}");
                return;
            }

            String plain = decryptRefundResource(ciphertext, associatedData, nonce, ctx.apiV3KeyCandidates);
            if (plain == null) {
                log.error("退款回调解密失败（APIv3 密钥候选均不匹配）");
                out.write("{\"code\":\"FAIL\",\"message\":\"解密失败\"}");
                return;
            }
            Map<String, Object> dec = objectMapper.readValue(plain, Map.class);
            log.info("event=wechat_refund_callback_decrypted payloadSummary={}", SafeLogValue.summarize(plain));

            if (!"REFUND.SUCCESS".equals(eventType)) {
                log.info("退款回调事件（不更新订单）: {}", eventType);
                out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
                return;
            }

            String refundStatus = dec.get("refund_status") != null ? dec.get("refund_status").toString() : "";
            if (!"SUCCESS".equals(refundStatus)) {
                log.info("REFUND.SUCCESS 通知但 refund_status 非 SUCCESS: {}", refundStatus);
                out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
                return;
            }

            Map<String, Object> amountMap = (Map<String, Object>) dec.get("amount");
            int refundFen = jsonNumberToInt(amountMap != null ? amountMap.get("refund") : null);
            if (refundFen <= 0) {
                log.warn("退款成功回调金额为0 payloadSummary={}", SafeLogValue.summarize(plain));
                out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
                return;
            }

            String transactionId = (String) dec.get("transaction_id");
            String outTradeNo = (String) dec.get("out_trade_no");
            String mchId = dec.get("mchid") != null ? dec.get("mchid").toString() : "";
            String outRefundNo = dec.get("out_refund_no") != null ? dec.get("out_refund_no").toString() : "";
            if (!StringUtils.hasText(transactionId) || !StringUtils.hasText(mchId)
                    || !StringUtils.hasText(outTradeNo) || !StringUtils.hasText(outRefundNo)) {
                out.write("{\"code\":\"FAIL\",\"message\":\"退款身份字段缺失\"}");
                return;
            }
            Object orderLock = paymentOrderLocks.get(outRefundNo, k -> new Object());
            synchronized (orderLock) {
                if (Boolean.TRUE.equals(processedNotifications.getIfPresent(notifyId))) {
                    log.info("退款回调已处理（幂等）: notifyId={}", notifyId);
                } else {
                    try {
                        wechatRefundSettlementService.settleNotification(
                                outRefundNo, refundFen, transactionId, mchId);
                    } catch (Exception ex) {
                        log.error("退款回调入账失败（返回 FAIL 触发微信重试）: outRefundNo={} err={}",
                                outRefundNo, ex.getMessage(), ex);
                        out.write("{\"code\":\"FAIL\",\"message\":\"入账失败\"}");
                        return;
                    }
                    if (StringUtils.hasText(notifyId)) {
                        processedNotifications.put(notifyId, true);
                    }
                }
            }

            out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
        } catch (Exception e) {
            log.error("退款回调处理异常", e);
            out.write("{\"code\":\"FAIL\",\"message\":\"处理失败\"}");
        }
    }

    /**
     * 遍历 DB 配置候选 APIv3 密钥解密退款回调资源（与支付回调 {@code WechatPaymentNotifyHandler} 同口径）。
     */
    private String decryptRefundResource(String ciphertext, String associatedData, String nonce,
                                          List<String> apiV3KeyCandidates) {
        if (apiV3KeyCandidates == null || apiV3KeyCandidates.isEmpty()) {
            return null;
        }
        for (String key : apiV3KeyCandidates) {
            if (!StringUtils.hasText(key)) {
                continue;
            }
            try {
                return WechatPayV3Crypto.decryptAesGcm(ciphertext, associatedData, nonce, key.trim());
            } catch (Exception e) {
                log.debug("退款回调 APIv3 密钥候选解密失败，尝试下一个: {}", e.getMessage());
            }
        }
        return null;
    }

    /**
     * 微信 JSAPI 统一下单并返回 prepay_id、payParams；{@link #getPrepayId} 与 {@link #memberRechargeWechat} 共用。
     * {@code order} 可为 null（仅会员微信充值，不落 {@code t_order}）。
     */
    private R executeWxJsapiPrepay(Order order, String orderNo, String openid, String takeOut,
                                   double paidYuan, String merchantIdInput, String wxDescription) {
        try {
            String merchantId = StringUtils.hasText(merchantIdInput) ? merchantIdInput : "1";
            int totalAmount = (int) Math.round(paidYuan * 100);
            String mchid;
            String notifyUrl;
            String serialNo;
            String pubSerial;
            PrivateKey privateKey;
            PrivateKeySigner signer;
            if ("2".equals(merchantId)) {
                mchid = mchid2;
                privateKey = privateKey2;
                signer = signer2;
                notifyUrl = notifyUrl2;
                serialNo = serialNo2;
                pubSerial = pubSerial2;
            } else {
                mchid = mchid1;
                privateKey = privateKey1;
                signer = signer1;
                notifyUrl = notifyUrl1;
                serialNo = serialNo1;
                pubSerial = pubSerial1;
            }
            String outTradeNo = buildOutTradeNo(orderNo);
            persistLatestOutTradeNo(order, outTradeNo);
            Map<String, Object> requestData = new HashMap<>();
            requestData.put("appid", appid);
            requestData.put("mchid", mchid);
            requestData.put("description", wxDescription != null ? wxDescription : "老肥油边王");
            requestData.put("out_trade_no", outTradeNo);
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX");
            Calendar calendar = Calendar.getInstance();
            calendar.add(Calendar.MINUTE, 2);
            requestData.put("time_expire", sdf.format(calendar.getTime()));
            requestData.put("notify_url", notifyUrl);
            Map<String, Object> amount = new HashMap<>();
            amount.put("total", totalAmount);
            amount.put("currency", "CNY");
            requestData.put("amount", amount);
            Map<String, Object> payer = new HashMap<>();
            payer.put("openid", openid);
            requestData.put("payer", payer);
            String nonceStr = generateNonceStr();
            String timestamp = String.valueOf(System.currentTimeMillis() / 1000);
            String bodyJson = objectMapper.writeValueAsString(requestData);
            String urlPath = "/v3/pay/transactions/jsapi";
            String signature = generatePaymentSignature(
                    "POST", urlPath, timestamp, nonceStr, bodyJson, privateKey);
            String url = "https://api.mch.weixin.qq.com" + urlPath;
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Accept", "application/json");
            headers.set("Authorization", String.format(
                    "WECHATPAY2-SHA256-RSA2048 mchid=\"%s\",nonce_str=\"%s\",timestamp=\"%s\",signature=\"%s\",serial_no=\"%s\"",
                    mchid, nonceStr, timestamp, signature, serialNo));
            headers.set("Wechatpay-Serial", pubSerial);
            HttpEntity<String> requestEntity = new HttpEntity<>(bodyJson, headers);
            String response = restTemplate.postForObject(url, requestEntity, String.class);
            Map<String, Object> responseMap = objectMapper.readValue(response, Map.class);
            log.info("处理订单支付，订单号: {}，商户ID: {}", orderNo, merchantId);
            if (responseMap.containsKey("prepay_id")) {
                String prepayId = (String) responseMap.get("prepay_id");
                Map<String, String> payParams = generatePayParameters(prepayId, appid, signer, privateKey);
                return R.ok().put("prepay_id", prepayId).put("payParams", payParams);
            }
            return R.error("支付失败: " + response);
        } catch (HttpClientErrorException e) {
            String body = e.getResponseBodyAsString();
            if (body != null && body.contains("参数与首次请求时不一致")) {
                log.warn("获取prepay_id 请求重入参数不一致，换新单号返回前端，原单号={} bodySummary={}",
                        orderNo, SafeLogValue.summarize(body));
                if (orderNo != null && !orderNo.isEmpty()) {
                    if (order == null) {
                        if (!isWxRechargeMerchantNo(orderNo)) {
                            return R.error("请稍后再支付");
                        }
                        MemberRecharge row = memberRechargeService.getOne(
                                new QueryWrapper<MemberRecharge>().eq("order_no", orderNo).eq("channel", "wechat").last("LIMIT 1"));
                        if (row != null) {
                            String newNo = generateRechargeOrderNo();
                            memberRechargeService.updateOrderNo(orderNo, newNo);
                            log.info("微信充值单换号: {} -> {}, rechargeId={}", orderNo, newNo, row.getId());
                            return R.ok()
                                    .put("newOrderNo", newNo)
                                    .put("orderId", row.getId())
                                    .put("message", "请使用新订单号重新发起支付");
                        }
                        return R.error("请稍后再支付");
                    }
                    Order orderForClose = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo));
                    if (orderForClose != null) {
                        String newOrderNo = generateOrderNo();
                        Order updated = orderService.replaceOrderNo(orderNo, newOrderNo);
                        if (updated != null) {
                            log.info("已换新订单号: {} -> {}, orderId={}", orderNo, newOrderNo, updated.getId());
                            return R.ok()
                                    .put("newOrderNo", newOrderNo)
                                    .put("orderId", updated.getId())
                                    .put("message", "请使用新订单号重新发起支付");
                        }
                        log.warn("换新订单号失败，订单不存在: {}", orderNo);
                        return R.error("请稍后再支付");
                    }
                }
                return R.error("请稍后再支付");
            }
            log.error("获取prepay_id 微信返回错误 status={} responseSummary={}",
                    e.getStatusCode(), SafeLogValue.summarize(body), e);
            return R.error("支付失败: " + (body != null ? body : e.getMessage()));
        } catch (Exception e) {
            log.error("获取prepay_id异常", e);
            return R.error("支付异常");
        }
    }

    /**
     * C 端会员微信充值：仅写 {@code t_member_recharge}（与 {@code t_order} 无关），单号前缀 RCH；返回与 {@link #getPrepayId} 相同的 prepay_id、payParams。
     * 请求体：openid、amount 或 totalAmount（元，50～10000）；可选 gift_amount / giftAmount（赠送，须与活动档严格一致：200→10、500→50、1000→120、5000→750、10000→2000；不占微信实付）；
     * 可选 takeOut、shop_id、shop_code（与点餐一致）。
     * 若统一下单返回换单（newOrderNo），须用 {@link #getPrepayId} 继续支付，勿重复调用本接口以免重复创单。
     * 支付成功后由 {@link #handlePaymentNotify} 将微信实付入账本金、流水赠送入账赠送金，并同步增加 {@code t_user.balance}（总余额）。
     */
    @PostMapping("/recharge")
    public R memberRechargeWechat(@RequestBody Map<String, String> params, HttpServletRequest request) {
        params = bindAuthenticatedOpenid(params, authenticatedUserOpenid(request));
        if (paymentFacadeProperties.isUseFacade()) {
            return paymentFacadeService.memberRechargeWechat(params, request);
        }
        return paymentMemberRechargeWechat(params, request);
    }

    public R paymentMemberRechargeWechat(Map<String, String> params, HttpServletRequest request) {
        String openid = params != null ? params.get("openid") : null;
        if (!StringUtils.hasText(openid)) {
            return R.error("openid不能为空");
        }
        openid = openid.trim();
        User user = userService.getUserByOpenid(openid);
        if (user == null || user.getId() == null) {
            return R.error("用户未注册");
        }
        String amtStr = null;
        if (params != null) {
            amtStr = params.get("amount");
            if (!StringUtils.hasText(amtStr)) {
                amtStr = params.get("totalAmount");
            }
        }
        if (!StringUtils.hasText(amtStr)) {
            return R.error("充值金额不能为空（amount 或 totalAmount，单位：元）");
        }
        double amountYuan;
        try {
            amountYuan = Double.parseDouble(amtStr.trim());
        } catch (NumberFormatException ex) {
            return R.error("金额格式错误：" + amtStr);
        }
        if (amountYuan < WxRechargeGiftTierValidator.MIN_YUAN || amountYuan > WxRechargeGiftTierValidator.MAX_YUAN) {
            return R.error(String.format("会员充值单笔不得低于%.0f元，且不超过%.0f元",
                    WxRechargeGiftTierValidator.MIN_YUAN, WxRechargeGiftTierValidator.MAX_YUAN));
        }
        double rounded = Math.round(amountYuan * 100) / 100.0;
        String giftStr = null;
        if (params != null) {
            giftStr = params.get("gift_amount");
            if (!StringUtils.hasText(giftStr)) {
                giftStr = params.get("giftAmount");
            }
            if (!StringUtils.hasText(giftStr)) {
                giftStr = params.get("gift");
            }
        }
        double giftYuan = 0d;
        if (StringUtils.hasText(giftStr)) {
            try {
                giftYuan = Double.parseDouble(giftStr.trim());
            } catch (NumberFormatException ex) {
                return R.error("赠送金额格式错误：" + giftStr);
            }
            if (giftYuan < 0d || giftYuan > 9999.99d) {
                return R.error("赠送金额须在 0～9999.99 元之间");
            }
        }
        double giftRounded = Math.round(giftYuan * 100) / 100.0;
        String takeOut = params != null ? params.get("takeOut") : null;
        Integer shopId = resolveChainShop(request,
                ShopChainSupport.parseBodyShopId(params != null ? params.get("shop_id") : null),
                ShopChainSupport.parseBodyShopCode(params != null ? params.get("shop_code") : null));
        R rechargeGuard = paymentOnlineGuardService.checkWechatRecharge(shopId);
        if (rechargeGuard != null) {
            return rechargeGuard;
        }
        String rechargeNo = generateRechargeOrderNo();
        BigDecimal rechargeBd = BigDecimal.valueOf(rounded).setScale(2, RoundingMode.HALF_UP);
        BigDecimal giftBd = BigDecimal.valueOf(giftRounded).setScale(2, RoundingMode.HALF_UP);
        R giftRuleErr = WxRechargeGiftTierValidator.validate(rechargeBd, giftBd);
        if (giftRuleErr != null) {
            return giftRuleErr;
        }
        Long rechargeLogId = memberRechargeService.createPendingWechat(user.getId(), openid, rechargeNo, shopId, rechargeBd, giftBd);
        try {
            R prepay = executeWxJsapiPrepay(null, rechargeNo, openid, takeOut, rounded, "1", "会员账户充值");
            boolean ok = prepay.get("code") != null && Integer.valueOf(0).equals(prepay.get("code"));
            if (!ok) {
                memberRechargeService.markCancelledById(rechargeLogId);
                return prepay;
            }
            if (prepay.get("newOrderNo") != null) {
                return prepay;
            }
            prepay.put("orderNo", rechargeNo);
            if (giftRounded > 0d) {
                prepay.put("giftAmount", giftRounded);
                prepay.put("expectedCreditTotal", rechargeBd.add(giftBd).doubleValue());
            }
            return prepay;
        } catch (RuntimeException ex) {
            memberRechargeService.markCancelledById(rechargeLogId);
            throw ex;
        }
    }

    /**
     * 获取prepay_id接口 - 根据订单的商户ID选择对应的配置
     */
    @PostMapping("/getPrepayId")
    public R getPrepayId(@RequestBody Map<String, String> params, HttpServletRequest request) {
        return getPrepayIdForIdentity(params, authenticatedUserOpenid(request));
    }

    private R getPrepayIdForIdentity(Map<String, String> params, String authenticatedOpenid) {
        params = bindAuthenticatedOpenid(params, authenticatedOpenid);
        // 点餐预支付必须走持久化 JSAPI 尝试；旧内联实现仅保留历史代码，不再作为资金路径回退。
        if (params != null && params.get("orderNo") != null
                && !isWxRechargeMerchantNo(params.get("orderNo"))) {
            return paymentFacadeService.getPrepayId(params);
        }
        if (paymentFacadeProperties.isUseFacade()) return paymentFacadeService.getPrepayId(params);
        String orderNo = params.get("orderNo");
        String openid = params.get("openid");
        String takeOut = params.get("takeOut");
        Long couponId = null;
        String couponIdStr = params.get("coupon_id");
        if (couponIdStr != null && !couponIdStr.trim().isEmpty()) {
            try {
                couponId = Long.parseLong(couponIdStr.trim());
            } catch (NumberFormatException ex) {
                return R.error("优惠券ID格式错误：" + couponIdStr);
            }
        }
        if (orderNo == null || orderNo.isEmpty()) {
            return R.error("订单号不能为空");
        }
        if (openid == null || openid.isEmpty()) {
            return R.error(MiniProgramAuthCodes.LOGIN_EXPIRED, "登录已过期，请重新登录");
        }
        orderNo = orderNo.trim();
        openid = openid.trim();
        Order order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo));
        if (order != null) {
            R prepayGuard = paymentOnlineGuardService.checkWechatPay(order.getShop_id());
            if (prepayGuard != null) {
                return prepayGuard;
            }
        }
        if (order == null) {
            if (!isWxRechargeMerchantNo(orderNo)) {
                return R.error("订单不存在，无法支付");
            }
            MemberRecharge mr = memberRechargeService.getOne(new QueryWrapper<MemberRecharge>()
                    .eq("order_no", orderNo).eq("channel", "wechat").eq("status", "pending").last("LIMIT 1"));
            if (mr == null) {
                return R.error("充值记录不存在或已失效，无法支付");
            }
            R rechargePrepayGuard = paymentOnlineGuardService.checkWechatRecharge(mr.getShop_id());
            if (rechargePrepayGuard != null) {
                return rechargePrepayGuard;
            }
            String mrOpenid = mr.getOpenid() != null ? mr.getOpenid().trim() : "";
            if (!openid.equals(mrOpenid)) {
                return R.error("支付用户与充值记录不一致");
            }
            double paidYuan = mr.getRecharge_amount() != null ? mr.getRecharge_amount().doubleValue() : 0d;
            paidYuan = Math.round(paidYuan * 100) / 100.0;
            if (paidYuan <= 0d) {
                return R.error("充值金额异常，无法支付");
            }
            return executeWxJsapiPrepay(null, orderNo, openid, takeOut, paidYuan, "1", "会员账户充值");
        }
        if ("success".equals(order.getTransac_status())) {
            return R.error("订单已支付");
        }
        if (!"unsettled".equals(order.getTransac_status())) {
            return R.error("订单状态异常，无法支付");
        }
        if (StringUtils.hasText(order.getOpenid()) && !order.getOpenid().trim().equals(openid)) {
            return R.error(403, "支付用户与订单绑定用户不一致");
        }
        R settled = settleOrderPayableAmounts(order, couponId, openid, true);
        Object codeObj = settled.get("code");
        if (codeObj != null && !Integer.valueOf(0).equals(codeObj)) {
            return settled;
        }
        Object paidYuanObj = settled.get("paidYuan");
        double paidYuan = paidYuanObj instanceof Number ? ((Number) paidYuanObj).doubleValue() : 0d;
        if (paidYuan <= 0d) {
            return R.error("折后实付金额异常，无法支付");
        }
        String merchantId = settled.get("merchantId") != null ? settled.get("merchantId").toString() : "";
        String wxDescription = "老肥油边王";
        return executeWxJsapiPrepay(order, orderNo, openid, takeOut, paidYuan, merchantId, wxDescription);
    }

    /**
     * 使用用户钱包全额支付未结账订单：{@code t_user.balance} 为总余额须充足；扣款按 {@code principal_balance} 与 {@code gift_balance} 当前占比以「分」整数拆分（本金份额四舍五入，另一桶为剩余）。
     * <strong>业务限制：</strong>已使用优惠券的订单（请求携带 {@code coupon_id}，或 {@code t_user_coupon} 已绑定本订单号）禁止使用余额支付；
     * 满足夜间九折条件的订单亦禁止使用余额支付（须改用微信支付享九折），余额按券后原价扣款，不叠九折。
     */
    @PostMapping("/payByBalance")
    @Transactional(rollbackFor = Exception.class)
    public R payByBalance(@RequestBody Map<String, String> params, HttpServletRequest request) {
        params = bindAuthenticatedOpenid(params, authenticatedUserOpenid(request));
        // 余额支付属于资金权威路径，不允许通过灰度开关回退到先改订单、后补流水的旧实现。
        if (paymentFacadeService != null) {
            return paymentFacadeService.payByBalance(params);
        }
        String orderNo = params != null ? params.get("orderNo") : null;
        String openid = params != null ? params.get("openid") : null;
        Long couponId = null;
        if (params != null) {
            String couponIdStr = params.get("coupon_id");
            if (couponIdStr != null && !couponIdStr.trim().isEmpty()) {
                try {
                    couponId = Long.parseLong(couponIdStr.trim());
                } catch (NumberFormatException ex) {
                    return R.error("优惠券ID格式错误：" + couponIdStr);
                }
            }
        }
        if (!StringUtils.hasText(orderNo) || !StringUtils.hasText(openid)) {
            return R.error("订单号和openid不能为空");
        }
        orderNo = orderNo.trim();
        openid = openid.trim();
        Object orderLock = paymentOrderLocks.get(orderNo, k -> new Object());
        synchronized (orderLock) {
            Order order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo));
            if (order == null) {
                return R.error("订单不存在");
            }
            R balanceGuard = paymentOnlineGuardService.checkBalancePay(order.getShop_id());
            if (balanceGuard != null) {
                return balanceGuard;
            }
            if ("success".equals(order.getTransac_status())) {
                return R.ok("订单已支付").put("alreadyPaid", true);
            }
            if (!"unsettled".equals(order.getTransac_status())) {
                return R.error("订单状态异常，无法支付");
            }
            if (StringUtils.hasText(order.getOpenid()) && !order.getOpenid().trim().equals(openid)) {
                // 收银台下单（order_channel=cashier）放行：可由任意 C 端用户余额代付；小程序/外卖/AI 下单仅限本人
                boolean cashierOrder = "cashier".equalsIgnoreCase(order.getOrder_channel());
                if (!cashierOrder) {
                    return R.error("订单不一致，请咨询服务员");
                }
            }
            if (couponId != null && couponId > 0L) {
                return R.error("使用优惠券的订单不能使用余额支付，请改用微信支付");
            }
            long couponBoundToOrder = UserCouponMapper.selectCount(
                    new QueryWrapper<UserCoupon>().eq("order_no", orderNo));
            if (couponBoundToOrder > 0L) {
                return R.error("使用优惠券的订单不能使用余额支付，请改用微信支付");
            }
            PayableAmountContext balanceCtx = new PayableAmountContext();
            R balancePrep = fillPayableAmountContext(order, couponId, openid, balanceCtx);
            Object balancePrepCode = balancePrep.get("code");
            if (balancePrepCode != null && !Integer.valueOf(0).equals(balancePrepCode)) {
                return balancePrep;
            }
            if (!balanceCtx.usesCouponForSettlement
                    && paymentNinefoldService.qualifiesForNineFold(
                    PaymentNinefoldService.resolveOrderShopId(order),
                    false, balanceCtx.nineFoldTimeRef, balanceCtx.basePaidYuan, balanceCtx.dineInOrTakeOut)) {
                return R.error("夜间九折优惠订单请使用微信支付，不可使用余额支付");
            }
            R settled = settleOrderPayableAmounts(order, couponId, openid, false);
            Object codeObj = settled.get("code");
            if (codeObj != null && !Integer.valueOf(0).equals(codeObj)) {
                return settled;
            }
            Object py = settled.get("paidYuan");
            double paidYuan = py instanceof Number ? ((Number) py).doubleValue() : 0d;
            if (paidYuan <= 0d) {
                return R.error("折后实付金额异常，无法支付");
            }
            User payer = userService.getUserByOpenid(openid);
            if (payer == null || payer.getId() == null) {
                return R.error("用户不存在");
            }
            BigDecimal payAmt = BigDecimal.valueOf(paidYuan).setScale(2, RoundingMode.HALF_UP);
            BigDecimal principalAvail = payer.getPrincipal_balance() != null ? payer.getPrincipal_balance() : BigDecimal.ZERO;
            BigDecimal giftAvail = payer.getGift_balance() != null ? payer.getGift_balance() : BigDecimal.ZERO;
            // 可用额以本金+赠送金为准（balance 列若历史脏数据为负仍可按实扣）
            BigDecimal totalAvail = principalAvail.add(giftAvail).setScale(2, RoundingMode.HALF_UP);
            if (totalAvail.compareTo(payAmt) < 0) {
                return R.error("余额不足");
            }
            Integer orderShopId = order.getShop_id() != null ? order.getShop_id() : 1;
            if (shopMemberWalletService != null && !shopMemberWalletService.isCrossShopBalanceEnabled(orderShopId)) {
                BigDecimal storeBal = shopMemberWalletService.getAvailableBalanceForShop(payer.getId(), orderShopId);
                if (storeBal.compareTo(payAmt) < 0) {
                    return R.error("本店会员储值余额不足（您在其他门店的充值余额不可跨店使用）");
                }
            }
            int payFen = UserWalletSplitUtil.yuanToFen(payAmt);
            int pFen = UserWalletSplitUtil.yuanToFen(principalAvail);
            int gFen = UserWalletSplitUtil.yuanToFen(giftAvail);
            int[] splitFen;
            try {
                splitFen = UserWalletSplitUtil.splitConsumptionFen(payFen, pFen, gFen);
            } catch (IllegalArgumentException | IllegalStateException ex) {
                return R.error("余额不足");
            }
            BigDecimal deductPrincipal = UserWalletSplitUtil.fenToYuanBd(splitFen[0]);
            BigDecimal deductGift = UserWalletSplitUtil.fenToYuanBd(splitFen[1]);
            if (!userService.subtractBalanceSplitIfEnough(payer.getId(), deductPrincipal, deductGift)) {
                return R.error("余额不足");
            }
            Order latest = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo));
            if (latest == null) {
                userService.addBalanceAndGift(payer.getId(), deductPrincipal, deductGift);
                return R.error("订单不存在");
            }
            if ("success".equals(latest.getTransac_status())) {
                userService.addBalanceAndGift(payer.getId(), deductPrincipal, deductGift);
                return R.error("订单状态已变更，请重试");
            }
            latest.setTransac_status("success");
            logOrder(orderNo, "pay", "openid", openid, latest.getShop_id(), null);
            latest.setTransaction_id(BALANCE_TX_ID_PREFIX + orderNo);
            latest.setPayment_method(PAYMENT_METHOD_BALANCE);
            latest.setPay_openid(openid);
            latest.setPay_time(new Date());
            OrderPayChannelAmounts.applyBalanceWalletSplit(latest,
                    deductPrincipal.doubleValue(), deductGift.doubleValue());
            int channelFenAfter = OrderPayChannelAmounts.totalPayChannelAmountFen(latest);
            if (Math.abs(channelFenAfter - payFen) > 0) {
                log.warn("余额入账后五渠道列合计与应扣总分期不一致: order_no={} channelSumFen={} payFen={}",
                        orderNo, channelFenAfter, payFen);
            }
            if (!StringUtils.hasText(latest.getOpenid())) {
                latest.setOpenid(openid);
            }
            if (!StringUtils.hasText(latest.getMerchantId())) {
                latest.setMerchantId("1");
            }
            orderService.updateById(latest);
            if (shopMemberWalletService != null) {
                shopMemberWalletService.deductAndClearBalance(
                        payer.getId(), orderShopId, deductPrincipal, deductGift, orderNo);
            }
            log.info("event=balance_payment_succeeded");
            runPostPaymentSuccessSideEffects(latest, paidYuan);
            return R.ok().put("paidYuan", paidYuan).put("payment_method", PAYMENT_METHOD_BALANCE);
        }
    }

    /**
     * 余额支付订单的本地退款：按剩余可退金额退回用户钱包（按原单 {@code balance_pay_principal}/{@code balance_pay_gift_wallet} 比例拆分；旧单无记录则全部退回本金），累加 {@code refund_amount}，不调用微信。
     */
    private R refundBalancePaidOrderLocal(Order order, Map<String, Object> params) {
        String orderNo = order.getOrder_no();
        Object orderLock = paymentOrderLocks.get(orderNo, k -> new Object());
        synchronized (orderLock) {
            Order latest = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo));
            if (latest == null) {
                return R.error("订单不存在");
            }
            if (!"success".equals(latest.getTransac_status())) {
                return R.error("仅已支付订单可退款");
            }
            String takeoutRefundBlock = takeoutDeliveryService.getRefundBlockReason(latest);
            if (takeoutRefundBlock != null) {
                return R.error(takeoutRefundBlock);
            }
            if (!isBalancePaymentTransactionId(latest.getTransaction_id())) {
                return R.error("非余额支付订单");
            }
            double paidYuan = (latest.getSett_amount() != null ? latest.getSett_amount() : 0d)
                    + (latest.getService_fee() != null ? latest.getService_fee() : 0d)
                    - (latest.getDiscount_amount() != null ? latest.getDiscount_amount() : 0d);
            if (paidYuan <= 0d) {
                return R.error("订单实付金额异常，无法退款");
            }
            int totalFen = (int) Math.round(paidYuan * 100d);
            int alreadyRefundedFen = (int) Math.round((latest.getRefund_amount() != null ? latest.getRefund_amount() : 0d) * 100d);
            int remainingFen = totalFen - alreadyRefundedFen;
            if (remainingFen <= 0) {
                return R.error("无可退金额");
            }
            int refundFen = remainingFen;
            if (params != null && params.get("refundAmount") != null && StringUtils.hasText(params.get("refundAmount").toString())) {
                try {
                    double refundYuan = Double.parseDouble(params.get("refundAmount").toString().trim());
                    refundFen = (int) Math.round(refundYuan * 100d);
                } catch (NumberFormatException ex) {
                    return R.error("退款金额格式错误");
                }
            }
            if (refundFen <= 0 || refundFen > remainingFen) {
                return R.error("退款金额不合法（需大于0且不超过剩余可退金额）");
            }
            int payBFen = (int) Math.round((latest.getPay_amount_balance() != null ? latest.getPay_amount_balance() : 0d) * 100d);
            int payGFen = (int) Math.round((latest.getPay_amount_gift() != null ? latest.getPay_amount_gift() : 0d) * 100d);
            int paySum = payBFen + payGFen;
            int channelTotalFen = OrderPayChannelAmounts.totalPayChannelAmountFen(latest);
            if (channelTotalFen > 0 && Math.abs(channelTotalFen - remainingFen) > 100) {
                log.warn("余额订单渠道列合计与理论剩余可退差异>1元: order_no={} channelSumFen={} remainingFen={}",
                        orderNo, channelTotalFen, remainingFen);
            }
            if (paySum > 0 && channelTotalFen != paySum) {
                log.warn("余额订单 balance+gift 列与五渠道合计不一致: order_no={} paySumFen={} channelTotalFen={}",
                        orderNo, paySum, channelTotalFen);
            }
            if (channelTotalFen > 0 && refundFen > channelTotalFen) {
                log.warn("余额退款超过五渠道列合计，已截断: order_no={} reqFen={} channelSumFen={}", orderNo, refundFen, channelTotalFen);
                refundFen = channelTotalFen;
            }
            if (refundFen <= 0) {
                return R.error("订单渠道金额不足，无法退款");
            }
            double deltaYuan = Math.round((refundFen / 100.0) * 100d) / 100d;
            String payerOpenid = StringUtils.hasText(latest.getPay_openid())
                    ? latest.getPay_openid().trim()
                    : (latest.getOpenid() != null ? latest.getOpenid().trim() : "");
            if (!StringUtils.hasText(payerOpenid)) {
                return R.error("订单缺少付款用户标识，无法退回余额");
            }
            User u = userService.getUserByOpenid(payerOpenid);
            if (u == null || u.getId() == null) {
                return R.error("用户不存在，无法退回余额");
            }
            BigDecimal refundBd = BigDecimal.valueOf(deltaYuan).setScale(2, RoundingMode.HALF_UP);
            double origPY = latest.getBalance_pay_principal() != null ? latest.getBalance_pay_principal() : 0d;
            double origGY = latest.getBalance_pay_gift_wallet() != null ? latest.getBalance_pay_gift_wallet() : 0d;
            int origPFen = (int) Math.round(origPY * 100d);
            int origGFen = (int) Math.round(origGY * 100d);
            int splitPFen = paySum > 0 ? payBFen : origPFen;
            int splitGFen = paySum > 0 ? payGFen : origGFen;
            boolean credited;
            int[] rf;
            if (splitPFen + splitGFen <= 0) {
                rf = new int[]{refundFen, 0};
                credited = userService.addBalance(u.getId(), refundBd);
            } else {
                rf = UserWalletSplitUtil.splitRefundFen(refundFen, splitPFen, splitGFen);
                credited = userService.addBalanceAndGift(u.getId(),
                        UserWalletSplitUtil.fenToYuanBd(rf[0]),
                        UserWalletSplitUtil.fenToYuanBd(rf[1]));
            }
            if (!credited) {
                return R.error("退回余额失败");
            }
            double prevRefunded = latest.getRefund_amount() != null ? latest.getRefund_amount() : 0d;
            double newRefundTotalYuan = Math.round((prevRefunded + deltaYuan) * 100d) / 100d;
            latest.setRefund_amount(newRefundTotalYuan);
            OrderPayChannelAmounts.applyBalanceRefundFromSplitFen(latest, rf);
            boolean fullRefund = alreadyRefundedFen + refundFen >= totalFen;
            String oldRemark = latest.getRemark() != null ? latest.getRemark() : "";
            String refundTag = (fullRefund ? "【余额退款·全额】" : "【余额退款·部分】")
                    + "本次" + deltaYuan + "元，累计退款" + newRefundTotalYuan + "元";
            if (!oldRemark.contains(refundTag)) {
                latest.setRemark(oldRemark + (StringUtils.hasText(oldRemark) ? "；" : "") + refundTag);
            }
            orderService.updateById(latest);
            log.info("余额支付订单已本地退款: order_no={} refund_yuan={} refund_total_yuan={}", orderNo, deltaYuan, newRefundTotalYuan);
            try {
                InviteService.reconcileFirstOrderInviteRewardOnRefund(latest);
            } catch (Exception ex) {
                log.warn("邀请首单返现退款冲正异常（订单退款已入账）: order_no={}, err={}",
                        orderNo, ex.getMessage(), ex);
            }
            return R.ok()
                    .put("order_no", orderNo)
                    .put("refund_amount", deltaYuan)
                    .put("message", "已退回用户余额");
        }
    }

    public static String buildPaymentSignatureString(String appId, String timestamp,
                                                     String nonceStr, String prepayId) {
        // 注意：每个参数后必须添加 包含 包含\n，包括最后一行
        // 使用StringBuilder确保 确保格式精确，避免多余空格
        StringBuilder signatureStr = new StringBuilder();
        signatureStr.append(appId).append("\n")
                .append(timestamp).append("\n")
                .append(nonceStr).append("\n")
                .append("prepay_id=").append(prepayId).append("\n");
        return signatureStr.toString();
    }
    /**
     * 生成调起支付的参数 - 支持指定商户配置
     */
    private Map<String, String> generatePayParameters(String prepayId, String appid,
                                                      PrivateKeySigner signer, PrivateKey privateKey) throws Exception {
        String nonceStr = generateNonceStr();
        String timestamp = String.valueOf(System.currentTimeMillis() / 1000);

        // 构造签名串
        String signatureString = buildPaymentSignatureString(appid, timestamp, nonceStr, prepayId);

        // 签名
        String paySign;
        if (signer != null) {
            Signer.SignatureResult signatureResult = signer.sign(signatureString.getBytes(StandardCharsets.UTF_8));
            paySign = signatureResult.getSign(); // 获取实际签名值
        } else {
            // 手动签名逻辑
            Signature signature = Signature.getInstance("SHA256withRSA");
            signature.initSign(privateKey);
            signature.update(signatureString.getBytes(StandardCharsets.UTF_8));
            paySign = Base64.getEncoder().encodeToString(signature.sign());
        }

        // 组装调起支付的参数
        Map<String, String> params = new HashMap<>();
        params.put("timeStamp", timestamp);
        params.put("nonceStr", nonceStr);
        params.put("package", "prepay_id=" + prepayId);
        params.put("signType", "RSA");
        params.put("paySign", paySign);

        return params;
    }

    /**
     * 生成新订单号，格式与前端一致：ORD + yyyyMMddHHmmss + 3位随机数（0-999）
     */
    private String generateOrderNo() {
        Calendar cal = Calendar.getInstance();
        String y = String.valueOf(cal.get(Calendar.YEAR));
        String M = padZero(cal.get(Calendar.MONTH) + 1);
        String d = padZero(cal.get(Calendar.DAY_OF_MONTH));
        String H = padZero(cal.get(Calendar.HOUR_OF_DAY));
        String m = padZero(cal.get(Calendar.MINUTE));
        String s = padZero(cal.get(Calendar.SECOND));
        int rand = (int) (Math.random() * 1000);
        return MERCHANT_NO_PREFIX_DINING + y + M + d + H + m + s + rand;
    }

    /** 微信会员充值商户单号（写入 {@code t_member_recharge.order_no}），前缀 RCH（见 {@link #MERCHANT_NO_PREFIX_WX_RECHARGE}） */
    private String generateRechargeOrderNo() {
        Calendar cal = Calendar.getInstance();
        String y = String.valueOf(cal.get(Calendar.YEAR));
        String M = padZero(cal.get(Calendar.MONTH) + 1);
        String d = padZero(cal.get(Calendar.DAY_OF_MONTH));
        String H = padZero(cal.get(Calendar.HOUR_OF_DAY));
        String m = padZero(cal.get(Calendar.MINUTE));
        String s = padZero(cal.get(Calendar.SECOND));
        int rand = (int) (Math.random() * 1000);
        return MERCHANT_NO_PREFIX_WX_RECHARGE + y + M + d + H + m + s + rand;
    }

    private static String padZero(int n) {
        return n < 10 ? "0" + n : String.valueOf(n);
    }

    /**
     * 生成带时间戳的 out_trade_no（订单号_时间戳），保证每次请求唯一且≤32字符。
     */
    private String buildOutTradeNo(String orderNo) {
        if (orderNo == null) orderNo = "";
        long ts = System.currentTimeMillis() % 10000000000L; // 10位数字
        String suffix = "_" + ts;
        if (orderNo.length() + suffix.length() > 32) {
            orderNo = orderNo.substring(0, 32 - suffix.length());
        }
        return orderNo + suffix;
    }

    private void persistLatestOutTradeNo(Order order, String outTradeNo) {
        if (order == null || order.getId() == null || !StringUtils.hasText(outTradeNo)) {
            return;
        }
        // last_out_trade_no 未落库，且实体已移除该字段；保持方法为 no-op 以兼容调用点。
    }

    /**
     * 从微信 out_trade_no 解析业务单号（去掉末尾 _数字 时间戳）。
     * 前缀约定：**ORD**=点餐 {@code t_order.order_no}，**RCH**=微信充值 {@code t_member_recharge.order_no}。
     */
    private String parseOrderNoFromOutTradeNo(String outTradeNo) {
        if (outTradeNo == null) return null;
        int last = outTradeNo.lastIndexOf('_');
        if (last > 0 && last < outTradeNo.length() - 1) {
            String suffix = outTradeNo.substring(last + 1);
            if (suffix.matches("[0-9]+")) {
                return outTradeNo.substring(0, last);
            }
        }
        return outTradeNo;
    }

    /** 商户退款单号 out_refund_no（同商户唯一，长度不超过 64）。 */
    private String buildOutRefundNo(String orderNo) {
        if (orderNo == null) {
            orderNo = MERCHANT_NO_PREFIX_DINING;
        }
        String ts = String.valueOf(System.currentTimeMillis());
        String raw = "RF_" + orderNo + "_" + ts;
        return raw.length() > 64 ? raw.substring(0, 64) : raw;
    }

    private static int jsonNumberToInt(Object value) {
        if (value == null) {
            return 0;
        }
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        try {
            return Integer.parseInt(value.toString().trim());
        } catch (NumberFormatException e) {
            return 0;
        }
    }


    /**
     * 生成微信支付签名 - 支持指定私钥
     */
    private String generatePaymentSignature(String method, String urlPath, String timestamp,
                                            String nonceStr, String body, PrivateKey privateKey) throws Exception {
        // 拼接签名串
        String signatureStr = String.format("%s\n%s\n%s\n%s\n%s\n",
                method, urlPath, timestamp, nonceStr, body);

        // 使用指定商户私钥签名
        Signature sign = Signature.getInstance("SHA256withRSA");
        sign.initSign(privateKey);
        sign.update(signatureStr.getBytes(StandardCharsets.UTF_8));
        return Base64.getEncoder().encodeToString(sign.sign());
    }
    /**
     * 初始化方法 - 加载两个商户的私钥
     */
    @PostConstruct
    public void init() {
        if (!StringUtils.hasText(privateKeyPath1) && !StringUtils.hasText(privateKeyPath2)) {
            log.info("application.yml 未配置微信支付 PEM，线上支付由 payment 模块从 DB 加载商户");
            return;
        }
        try {
            if (StringUtils.hasText(privateKeyPath1)) {
                privateKey1 = loadPrivateKey(privateKeyPath1);
                signer1 = new PrivateKeySigner(serialNo1, privateKey1);
                if (StringUtils.hasText(pubKey1)) {
                    wechatPublicKey1 = loadWechatPublicKey(pubKey1);
                }
                log.info("商户1私钥加载成功");
            }
            if (StringUtils.hasText(privateKeyPath2)) {
                privateKey2 = loadPrivateKey(privateKeyPath2);
                signer2 = new PrivateKeySigner(serialNo2, privateKey2);
                if (StringUtils.hasText(pubKey2)) {
                    wechatPublicKey2 = loadWechatPublicKey(pubKey2);
                }
                log.info("商户2私钥加载成功");
            }
        } catch (Exception e) {
            log.error("初始化签名器失败", e);
            throw new RuntimeException("初始化签名器失败", e);
        }
    }

    /**
     * 加载私钥的通用方法
     */
    private PrivateKey loadPrivateKey(String privateKeyPath) throws Exception {
        InputStream is = null;

        // 处理类路径资源
        if (privateKeyPath.startsWith("classpath:")) {
            String path = privateKeyPath.replace("classpath:", "");
            // 使用类加载器获取资源
            is = getClass().getClassLoader().getResourceAsStream(path);
            if (is == null) {
                throw new FileNotFoundException("私钥文件不存在于类路径: " + path);
            }
        } else {
            // 处理文件系统路径
            File file = new File(privateKeyPath);
            if (!file.exists()) {
                throw new FileNotFoundException("私钥文件不存在: " + privateKeyPath);
            }
            is = new FileInputStream(file);
        }

        // 加载私钥
        return PemUtil.loadPrivateKey(is);
    }

    // 修改公钥加载方法，不依赖PemUtil.loadPublicKey
    private PublicKey loadWechatPublicKey(String pubKey) throws Exception {
        InputStream is = null;
        try {
            // 验证路径配置并获取输入流（保持原有逻辑）
            if (pubKey == null || pubKey.trim().isEmpty()) {
                throw new IllegalArgumentException("公钥路径配置为空，请检查weixin.pubSerial-path");
            }

            if (pubKey.startsWith("classpath:")) {
                String path = pubKey.replace("classpath:", "");
                is = getClass().getResourceAsStream("/" + path);
                if (is == null) {
                    is = Thread.currentThread().getContextClassLoader().getResourceAsStream(path);
                }
                if (is == null) {
                    throw new FileNotFoundException("公钥文件不存在于类路径: " + path);
                }
            } else {
                File pubFile = new File(pubKey);
                if (!pubFile.exists()) {
                    throw new FileNotFoundException("公钥文件不存在: " + pubFile);
                }
                is = new FileInputStream(pubFile);
            }

            // 关键修改：手动解析PEM格式公钥（不依赖SDK的PemUtil）
            BufferedReader reader = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8));
            StringBuilder publicKeyPem = new StringBuilder();
            String line;
            boolean inPublicKeyBlock = false;

            // 读取PEM文件内容，提取公钥部分
            while ((line = reader.readLine()) != null) {
                if (line.contains("-----BEGIN PUBLIC KEY-----")) {
                    inPublicKeyBlock = true;
                    publicKeyPem.append(line); // 不添加\n，保留原始格式
                } else if (line.contains("-----END PUBLIC KEY-----")) {
                    inPublicKeyBlock = false;
                    publicKeyPem.append(line);
                } else if (inPublicKeyBlock) {
                    publicKeyPem.append(line);
                }
            }

            if (publicKeyPem.length() == 0) {
                throw new IOException("公钥文件中未找到有效的PUBLIC KEY块");
            }

            // 使用Java标准库解析公钥
            byte[] publicKeyBytes = Base64.getDecoder().decode(
                    publicKeyPem.toString()
                            .replace("-----BEGIN PUBLIC KEY-----", "")
                            .replace("-----END PUBLIC KEY-----", "")
                            .replaceAll("\\s+", "") // 去除所有空白字符
            );

            X509EncodedKeySpec keySpec = new X509EncodedKeySpec(publicKeyBytes);
            KeyFactory keyFactory = KeyFactory.getInstance("RSA");
            log.info("成功加载微信支付公钥: {}", pubKey);
            return keyFactory.generatePublic(keySpec);


        } finally {
            if (is != null) {
                try {
                    is.close();
                } catch (IOException e) {
                    log.warn("关闭公钥输入流失败", e);
                }
            }
        }
    }


    /**
     * 生成随机字符串
     */
    private String generateNonceStr() {
        String chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        StringBuilder sb = new StringBuilder();
        Random random = new Random();
        for (int i = 0; i < 32; i++) {
            sb.append(chars.charAt(random.nextInt(chars.length())));
        }
        return sb.toString();
    }

    /**
     * 对用户可见的助手正文脱敏：去掉 openid/unionid 等技术词；若正文出现本会话 openid 明文也一并抹掉。
     */
    private String sanitizeAiUserFacingExplanation(String text, String sessionOpenid) {
        if (text == null || text.isEmpty()) {
            return text;
        }
        String s = text.replaceAll("(?i)unionid", "账号");
        s = s.replaceAll("(?i)session_key", "会话信息");
        s = s.replaceAll("(?i)openid", "账号");
        if (sessionOpenid != null && sessionOpenid.length() >= 8 && s.contains(sessionOpenid)) {
            s = s.replace(sessionOpenid, "（已关联）");
        }
        return s;
    }

    /**
     * 解析并移除正文中的 ACTION 协议行，避免编码串直接展示给用户。
     * 协议行示例：
     * - <<<ACTION:add_ai_cart|%7B...%7D>>>
     * - <<<ACTION:scan_table_bind>>>
     */
    private ParsedAiActionResult parseAndStripInlineActions(String text) {
        ParsedAiActionResult result = new ParsedAiActionResult();
        result.explanation = text;
        result.actions = new ArrayList<>();
        if (text == null || text.isEmpty()) {
            return result;
        }
        String[] lines = text.split("\\r?\\n");
        List<String> kept = new ArrayList<>();
        Pattern actionPattern = Pattern.compile("^<<<ACTION:([a-zA-Z0-9_\\-]+)(?:\\|(.+?))?>>>$");
        for (String rawLine : lines) {
            String line = rawLine == null ? "" : rawLine.trim();
            Matcher m = actionPattern.matcher(line);
            if (!m.matches()) {
                kept.add(rawLine);
                continue;
            }
            Map<String, Object> one = new HashMap<>();
            String action = m.group(1);
            String payload = m.group(2);
            one.put("action", action);
            one.put("rawPayload", payload);
            if (payload != null && !payload.trim().isEmpty()) {
                try {
                    String decoded = java.net.URLDecoder.decode(payload, StandardCharsets.UTF_8.name());
                    one.put("decodedPayload", decoded);
                    try {
                        one.put("payload", objectMapper.readValue(decoded, Object.class));
                    } catch (Exception ignoreJson) {
                        one.put("payload", decoded);
                    }
                } catch (Exception decodeErr) {
                    one.put("decodeError", decodeErr.getMessage());
                }
            }
            result.actions.add(one);
        }
        String cleaned = String.join("\n", kept).trim();
        result.explanation = cleaned.isEmpty() ? text : cleaned;
        return result;
    }

    private static class ParsedAiActionResult {
        private String explanation;
        private List<Map<String, Object>> actions;
    }

    /**
     * 自然语言点餐：多轮工具调用 + 正文内 Markdown/伪协议 JSON 解析执行 + 会话 openid/桌号补全，
     * 在递归深度上限内自动纠错直至下单成功或模型输出最终说明（参数仍不全时由模型追问用户）。
     */
    @PostMapping("/ai/chatSuggest")
    public R aiChatSuggest(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        try {
            if (body == null) {
                return R.error("请求体不能为空");
            }
            String openid = body.get("openid") != null ? body.get("openid").toString().trim() : null;
            if (openid == null || openid.isEmpty()) {
                return R.error("openid 不能为空（用于隔离多轮会话）");
            }
            Integer chatShop = null;
            try {
                chatShop = resolveChainShop(request,
                        ShopChainSupport.parseBodyShopId(body.get("shop_id")),
                        ShopChainSupport.parseBodyShopCode(body.get("shop_code")));
            } catch (RuntimeException e) {
                return R.error(e.getMessage());
            }
            if (chatShop != null) {
                try {
                    validateShopOpen(chatShop);
                } catch (RuntimeException e) {
                    return R.error(e.getMessage());
                }
            }
            String table_number = body.get("table_number") != null ? body.get("table_number").toString().trim() : null;
            Object promptObj = body.get("prompt");
            String prompt = promptObj != null ? promptObj.toString().trim() : null;
            if (prompt == null || prompt.isEmpty()) {
                return R.error("prompt 不能为空");
            }
            boolean reset = body.get("reset") instanceof Boolean && (Boolean) body.get("reset");
            if (reset) {
                aiChatMemoryCache.invalidate(openid);
            }

            List<Map<String, Object>> history = aiChatMemoryCache.getIfPresent(openid);
            if (history == null) {
                history = new ArrayList<>();
            } else {
                history = new ArrayList<>(history);
            }

            List<Map<String, Object>> messages = new ArrayList<>();
            Map<String, Object> sys = new HashMap<>();
            sys.put("role", "system");
            sys.put("content", getAiAgentSystemContent());
            messages.add(sys);
            appendAiContextMessage(messages, openid, true);
            messages.addAll(history);

            Map<String, Object> userMsg = new HashMap<>();
            userMsg.put("role", "user");
            String userContent = prompt;
            if (table_number != null && !table_number.isEmpty()) {
                userContent = "当前桌号：" + table_number + "，openid：" + openid + "\n" + prompt;
            }
            // 多轮：避免「推荐完再下单」时模型无视上文、重复索要全套信息
            if (!history.isEmpty()) {
                userContent = appendChatSuggestMultiTurnBridge(userContent, table_number);
            }
            userMsg.put("content", userContent);
            messages.add(userMsg);

            String aiText;
            try {
                AiSuggestSession sess = new AiSuggestSession();
                sess.openid = openid;
                sess.tableNumber = table_number;
                sess.shopId = chatShop;
                AI_SUGGEST_SESSION.set(sess);
                aiText = callAiModelWithMessages(messages, true);
            } finally {
                AI_SUGGEST_SESSION.remove();
            }
            if (aiText == null || aiText.trim().isEmpty()) {
                aiText = "暂时无法生成建议，请稍后重试。";
            }
            aiText = sanitizeAiUserFacingExplanation(aiText, openid);
           

            // 仅保留 user/assistant 文本消息作为多轮上下文，避免工具中间消息导致上下文膨胀
            history.add(userMsg);
            Map<String, Object> assistantMsg = new HashMap<>();
            assistantMsg.put("role", "assistant");
            assistantMsg.put("content", aiText);
            history.add(assistantMsg);
            history = trimAiChatHistory(history, 12); // 最多保留 12 轮（24 条）
            aiChatMemoryCache.put(openid, history);

            Map<String, Object> plan = new HashMap<>();
            plan.put("items", Collections.emptyList());
            plan.put("totalPrice", 0);
            plan.put("perCapitaPrice", 0);
            plan.put("explanation", aiText);
            plan.put("sessionOpenid", openid);
            plan.put("tableNumber", table_number);
            plan.put("shopId", chatShop);
            plan.put("historyRounds", history.size() / 2);
           
            return R.ok().put("plan", plan);
        } catch (Exception e) {
            log.error("AI 自然语言点餐建议异常", e);
            return R.error("智能点餐服务暂不可用，请稍后重试");
        }
    }

    
    /**
     * 通用大模型调用封装。调用前注入统一上下文（用户信息/画像/在售菜单/智能体配置/tools）。
     */
    private String callAiModel(String prompt, boolean enableTools, String openid) {
        if (aiApiUrl == null || aiApiUrl.trim().isEmpty()) {
            return "AI 接口未配置（缺少 ai.api.url），请联系管理员。原始提示：" + prompt;
        }
        try {
            long startTs = System.currentTimeMillis();
            log.info("[AI_CALL] begin enableTools={}, model={}, promptLength={}",
                    enableTools, aiModel, prompt != null ? prompt.length() : 0);
            List<Map<String, Object>> messages = new ArrayList<>();
            Map<String, Object> sys = new HashMap<>();
            sys.put("role", "system");
            sys.put("content", getAiAgentSystemContent());
            messages.add(sys);
            appendAiContextMessage(messages, openid, enableTools);
            Map<String, Object> userMsg = new HashMap<>();
            userMsg.put("role", "user");
            userMsg.put("content", prompt);
            messages.add(userMsg);
            String result = callAiModelWithMessages(messages, enableTools);
            log.info("[AI_CALL] resultSummary={}", SafeLogValue.summarize(result));
            if (result != null) {
                log.info("[AI_CALL] success elapsedMs={}, resultLength={}",
                        System.currentTimeMillis() - startTs, result.length());
                return result;
            }
            log.warn("[AI_CALL] empty-result elapsedMs={}", System.currentTimeMillis() - startTs);
            return "AI 接口返回格式不符合预期";
        } catch (Exception e) {
            log.error("调用 AI 模型失败", e);
            return "调用 AI 模型失败：" + e.getMessage();
        }
    }

    /**
     * 带 messages 和 tools 的请求，若返回 tool_calls 则执行后再请求一轮。
     * @return 最终助手文本内容，若无则 null
     */
    @SuppressWarnings("unchecked")
    private String callAiModelWithMessages(List<Map<String, Object>> messages, boolean enableTools) throws Exception {
        if (enableTools) {
            AI_TOOL_TURN.set(new AiToolTurnTracker());
            try {
                String out = callAiModelWithMessages(messages, enableTools, 0);
                return guardAgainstFakeOrderNarration(out);
            } finally {
                AI_TOOL_TURN.remove();
            }
        }
        return callAiModelWithMessages(messages, false, 0);
    }

    private static boolean isRCodeOk(Object r) {
        if (!(r instanceof R)) {
            return false;
        }
        Object c = ((R) r).get("code");
        if (c == null) {
            return false;
        }
        int v = c instanceof Number ? ((Number) c).intValue() : Integer.parseInt(c.toString().trim());
        return v == 0;
    }

    /**
     * 任一工具失败即停止后续工具调用：
     * - R 且 code != 0 视为失败
     * - Map 且包含 error 视为失败
     */
    private static boolean isToolExecFailed(Object execResult) {
        if (execResult == null) {
            return true;
        }
        if (execResult instanceof R) {
            return !isRCodeOk(execResult);
        }
        if (execResult instanceof Map) {
            Object err = ((Map<?, ?>) execResult).get("error");
            return err != null && !err.toString().trim().isEmpty();
        }
        return false;
    }

    /** 记录本轮查询类工具成功返回的订单号，供防捏造逻辑信任 */
    private void recordTrustedQueryOrderNo(String orderNo) {
        if (orderNo == null) {
            return;
        }
        String n = orderNo.trim();
        if (n.isEmpty()) {
            return;
        }
        AiToolTurnTracker tr = AI_TOOL_TURN.get();
        if (tr == null) {
            return;
        }
        if (tr.trustedOrderNosFromQuery == null) {
            tr.trustedOrderNosFromQuery = new HashSet<>();
        }
        tr.trustedOrderNosFromQuery.add(n);
    }

    private static boolean isOrderNoFromTrustedQuery(AiToolTurnTracker tr, String mentionedNo) {
        if (mentionedNo == null || tr == null || tr.trustedOrderNosFromQuery == null) {
            return false;
        }
        String m = mentionedNo.trim();
        for (String t : tr.trustedOrderNosFromQuery) {
            if (t != null && t.equalsIgnoreCase(m)) {
                return true;
            }
        }
        return false;
    }

    /**
     * 若正文声称下单成功/给出订单号，但本轮未成功执行 create_order 或 add_dishes，或订单号与接口不一致，则拦截捏造。
     * 若订单号为本轮 query_order / get_order_by_table / order_history 等查询成功返回的，视为合法引用。
     */
    private String guardAgainstFakeOrderNarration(String text) {
        if (text == null || text.trim().isEmpty()) {
            return text;
        }
        AiToolTurnTracker tr = AI_TOOL_TURN.get();
        if (tr == null) {
            return text;
        }
        boolean claimsPaidOrCreated = text.contains("下单成功") || text.contains("已下单成功") || text.contains("订单已生成");
        Matcher m = ORDER_NO_MENTION_PATTERN.matcher(text);
        String mentionedNo = m.find() ? m.group(1).trim() : null;

        if (!claimsPaidOrCreated && mentionedNo == null) {
            return text;
        }

        boolean realWriteOk = tr.createOrderOk || tr.addDishesOk;
        boolean orderNoFromQuery = mentionedNo != null && isOrderNoFromTrustedQuery(tr, mentionedNo);

        if (!realWriteOk) {
            // 仅复述本轮查询得到的订单号，无「下单成功」类捏造 → 放行
            if (!claimsPaidOrCreated && orderNoFromQuery) {
                return text;
            }
            if (claimsPaidOrCreated) {
                log.warn("[AI_GUARD] blocked fake order claim: createOrderOk={}, addDishesOk={}, createInvoked={}",
                        tr.createOrderOk, tr.addDishesOk, tr.createOrderInvoked);
                return "【安全提示】智能助手不会在对话里直接下单。请使用文末「加入购物车」按钮，到点餐页确认规格后再结算；不要轻信本段中的下单成功描述。";
            }
            if (mentionedNo != null && !orderNoFromQuery) {
                log.warn("[AI_GUARD] blocked order_no not from write nor query: mentioned={}, createOrderOk={}, addDishesOk={}",
                        mentionedNo, tr.createOrderOk, tr.addDishesOk);
                return "【安全提示】智能助手不会在对话里直接下单。请使用文末「加入购物车」按钮，到点餐页确认规格后再结算；不要轻信本段中的订单号。";
            }
            return text;
        }

        if (mentionedNo != null && tr.serverOrderNo != null && !mentionedNo.equalsIgnoreCase(tr.serverOrderNo.trim())) {
            // 写单成功但文中单号与接口不一致：若与本轮查询结果一致（如先查后写核对），仍放行
            if (isOrderNoFromTrustedQuery(tr, mentionedNo)) {
                return text;
            }
            log.warn("[AI_GUARD] order_no mismatch: text={}, server={}", mentionedNo, tr.serverOrderNo);
            return "【安全提示】回复中的订单号与系统本次下单结果不一致。请以系统为准——订单号：" + tr.serverOrderNo
                    + "。请勿使用文中其它订单号进行支付。";
        }
        return text;
    }

    /**
     * 火山方舟（豆包）等 OpenAI 兼容 Chat Completions，与阿里云 DashScope 的 input/parameters 结构不同。
     */
    private boolean useOpenAiCompatibleChatApi() {
        if (aiApiUrl == null || aiApiUrl.isEmpty()) {
            return false;
        }
        String u = aiApiUrl.toLowerCase(Locale.ROOT);
        return u.contains("volces.com") || u.contains("/v3/chat/completions") || u.contains("/chat/completions");
    }

    /** 解析方舟等返回的 JSON 错误体中的 message，便于直接展示给运维/前端 */
    @SuppressWarnings("unchecked")
    private String extractVolcengineOrGenericApiErrorMessage(String body) {
        if (body == null || body.trim().isEmpty()) {
            return null;
        }
        try {
            Map<String, Object> root = objectMapper.readValue(body, Map.class);
            Object err = root.get("error");
            if (err instanceof Map) {
                Object msg = ((Map<?, ?>) err).get("message");
                if (msg != null) {
                    return msg.toString();
                }
            }
            Object msg2 = root.get("message");
            if (msg2 != null) {
                return msg2.toString();
            }
        } catch (Exception ignored) {
            // 非 JSON
        }
        return body.length() > 500 ? body.substring(0, 500) + "…" : body;
    }

    /**
     * 将方舟/大模型 HTTP 4xx 错误转成面向运维或用户的说明（区分欠费、接入点错误等）。
     */
    private String buildUserFacingAiHttpClientError(boolean ark, String apiMsg) {
        String msg = apiMsg != null ? apiMsg : "";
        String lower = msg.toLowerCase(Locale.ROOT);
        if (lower.contains("overdue balance") || lower.contains("insufficient balance")
                || lower.contains("payment required") || msg.contains("欠费") || msg.contains("余额不足")) {
            return "【火山引擎账号欠费或余额不足】大模型接口已拒绝请求，请到火山引擎控制台「费用中心」充值或结清欠费后再试。"
                    + (msg.isEmpty() ? "" : " 接口说明：" + msg);
        }
        if (ark && (lower.contains("does not exist") || lower.contains("invalidendpoint")
                || lower.contains("not have access"))) {
            return "【方舟配置】请确认：1）ai.model 为推理接入点 ID（ep- 开头），非模型展示名；2）API Key 与接入点同属一账号、同地域。"
                    + (msg.isEmpty() ? "" : " 接口说明：" + msg);
        }
        if (ark) {
            return "【方舟请求失败】"
                    + (msg.isEmpty() ? "请检查接入点、API Key、账号权限及网络。" : "接口说明：" + msg);
        }
        return "【大模型请求失败】" + (msg.isEmpty() ? "请检查 ai.api 配置。" : msg);
    }

    private String callAiModelWithMessages(List<Map<String, Object>> messages, boolean enableTools, int recursionDepth) throws Exception {
        if (recursionDepth > maxAiToolRecursionDepth()) {
            log.warn("[AI_CALL_DETAIL] recursion depth exceeded: {}", recursionDepth);
            return "智能点餐处理中断：工具调用轮次过多，请重试。";
        }
        boolean ark = useOpenAiCompatibleChatApi();
        String model = aiModel != null ? aiModel.trim() : "";
        if (model.isEmpty() && !ark) {
            model = "qwen-plus";
        }
        if (ark && model.isEmpty()) {
            return "【配置错误】使用火山方舟时，请在 application.yml 配置 ai.model，或设置环境变量 ARK_MODEL，"
                    + "值为控制台「推理接入点」的完整 ID（一般以 ep- 开头）。不能使用展示名称如 Doubao-pro-4K。";
        }
        Map<String, Object> payload = new HashMap<>();
        if (ark) {
            payload.put("model", model);
            payload.put("messages", messages);
            if (enableTools) {
                List<Map<String, Object>> tools = filterAiToolsForRecommendAgent(getAiToolDefinitions());
                payload.put("tools", tools);
                payload.put("tool_choice", "auto");
                log.info("[AI_CALL_DETAIL] openAiCompatible=true, toolsCount={}", tools != null ? tools.size() : 0);
            }
        } else {
            payload.put("model", model);
            Map<String, Object> input = new HashMap<>();
            input.put("messages", messages);
            payload.put("input", input);
            Map<String, Object> parameters = new HashMap<>();
            // 显式要求按 message 格式返回，避免不同模型默认返回 text 导致解析失败
            parameters.put("result_format", "message");
            payload.put("parameters", parameters);
            if (enableTools) {
                List<Map<String, Object>> tools = filterAiToolsForRecommendAgent(getAiToolDefinitions());
                payload.put("tools", tools);
                payload.put("tool_choice", "auto");
                log.info("[AI_CALL_DETAIL] toolsEnabled=true, toolsCount={}", tools != null ? tools.size() : 0);
            }
        }

        log.info("[AI_CALL_DETAIL] payload model={}, ark={}, enableTools={}, messageCount={}, depth={}",
                model, ark, enableTools, messages != null ? messages.size() : 0, recursionDepth);

        String json = objectMapper.writeValueAsString(payload);
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        if (aiApiKey != null && !aiApiKey.trim().isEmpty()) {
            headers.set("Authorization", "Bearer " + aiApiKey.trim());
        }
        HttpEntity<String> entity = new HttpEntity<>(json, headers);
        String resp;
        try {
            resp = restTemplate.postForObject(aiApiUrl, entity, String.class);
        } catch (HttpClientErrorException e) {
            String body = e.getResponseBodyAsString();
            log.error("[AI_CALL_DETAIL] HTTP {} responseSummary={}",
                    e.getStatusCode(), SafeLogValue.summarize(body));
            String apiMsg = extractVolcengineOrGenericApiErrorMessage(body);
            return buildUserFacingAiHttpClientError(ark, apiMsg != null ? apiMsg : ("HTTP " + e.getStatusCode()));
        }
        if (resp == null || resp.trim().isEmpty()) {
            log.warn("[AI_CALL_DETAIL] empty response");
            return null;
        }
        log.info("[AI_CALL_DETAIL] rawResponseLength={}", resp.length());
        Map<String, Object> respMap = objectMapper.readValue(resp, Map.class);
        if (respMap.get("request_id") != null) {
            log.info("[AI_CALL_DETAIL] request_id={}", respMap.get("request_id"));
        }
        if (respMap.get("id") != null) {
            log.info("[AI_CALL_DETAIL] response id={}", respMap.get("id"));
        }
        if (respMap.get("error") != null) {
            log.warn("event=ai_provider_error");
        }
        Object outputObj = respMap.get("output");
        // 火山方舟 / OpenAI 兼容：choices 在根上，无 output 包裹
        if (!(outputObj instanceof Map) && respMap.get("choices") instanceof List) {
            outputObj = respMap;
        }
        if (!(outputObj instanceof Map)) {
            log.warn("[AI_CALL_DETAIL] output is not map, keys={}", respMap.keySet());
            return null;
        }
        Map<?, ?> output = (Map<?, ?>) outputObj;
        // 兼容 text-generation 默认返回 output.text 的情况
        Object outputText = output.get("text");
        if (outputText instanceof String && !((String) outputText).trim().isEmpty()) {
            log.info("[AI_CALL_DETAIL] hit output.text branch");
            String text = (String) outputText;
            String handled = tryHandleToolCallsInText(text, messages, enableTools, recursionDepth);
            String result = handled != null ? handled : text;
            return interceptPseudoToolTextBeforeReturn(result, messages, enableTools, recursionDepth, "output.text");
        }
        Object choicesObj = output.get("choices");
        if (!(choicesObj instanceof List) || ((List<?>) choicesObj).isEmpty()) {
            log.warn("[AI_CALL_DETAIL] choices empty, outputKeys={}", output.keySet());
            return null;
        }
        Object firstChoice = ((List<?>) choicesObj).get(0);
        if (!(firstChoice instanceof Map)) {
            return null;
        }
        // 兼容 choices[0].text
        Object choiceText = ((Map<?, ?>) firstChoice).get("text");
        if (choiceText instanceof String && !((String) choiceText).trim().isEmpty()) {
            log.info("[AI_CALL_DETAIL] hit choices[0].text branch");
            String text = (String) choiceText;
            String handled = tryHandleToolCallsInText(text, messages, enableTools, recursionDepth);
            String result = handled != null ? handled : text;
            return interceptPseudoToolTextBeforeReturn(result, messages, enableTools, recursionDepth, "choices[0].text");
        }
        Object msgObj = ((Map<?, ?>) firstChoice).get("message");
        if (!(msgObj instanceof Map)) {
            log.warn("[AI_CALL_DETAIL] choices[0].message missing");
            return null;
        }
        Map<?, ?> message = (Map<?, ?>) msgObj;
        Object content = message.get("content");
        Object toolCallsObj = message.get("tool_calls");

        // 优先使用 message 中的标准 tool_calls 字段
        List<Map<String, Object>> toolCallsToRun = null;
        if (toolCallsObj instanceof List && !((List<?>) toolCallsObj).isEmpty()) {
            toolCallsToRun = (List<Map<String, Object>>) toolCallsObj;
        } else {
            // 多模态/部分模型把 tool_calls 写在 content 里（文本或数组），尝试解析后执行并递归，避免把工具调用当正文返回
            String contentText = aiToolResponseParser.extractTextFromContent(content);
            toolCallsToRun = aiToolResponseParser.parseToolCallsFromText(contentText);
            // 兼容 content 为数组且元素为 {text: "{\"tool_calls\": [...]}"}
            if (toolCallsToRun == null && content instanceof List) {
                for (Object item : (List<?>) content) {
                    if (item instanceof Map) {
                        Object t = ((Map<?, ?>) item).get("text");
                        if (t != null) {
                            List<Map<String, Object>> tcParsed = aiToolResponseParser.parseToolCallsFromText(t.toString());
                            if (tcParsed != null && !tcParsed.isEmpty()) {
                                toolCallsToRun = tcParsed;
                                break;
                            }
                        }
                    }
                }
            }
        }

        if (toolCallsToRun != null && !toolCallsToRun.isEmpty()) {
            // 确保每条 tool_call 都含 function 对象（API 要求），模型有时把 name/arguments 写在顶层
            List<Map<String, Object>> normalizedToolCalls = aiToolResponseParser.normalizeToolCalls(toolCallsToRun);
            log.info("[AI_CALL_DETAIL] toolCallsDetected raw={}, normalized={}",
                    toolCallsToRun.size(), normalizedToolCalls.size());

            List<Map<String, Object>> newMessages = new ArrayList<>(messages);
            // 必须用带齐 id 的 normalizedToolCalls 回传；部分模型返回的 message 缺 id，方舟会报 missing messages.tool_calls.id
            Map<String, Object> assistantReplay = new HashMap<>();
            assistantReplay.put("role", "assistant");
            assistantReplay.put("content", message.get("content"));
            assistantReplay.put("tool_calls", normalizedToolCalls);
            newMessages.add(assistantReplay);

            for (Map<String, Object> tc : normalizedToolCalls) {
                String id = tc.get("id") != null ? tc.get("id").toString() : null;
                Object fnObj = tc.get("function");
                String name = null;
                Map<String, Object> args = new HashMap<>();
                if (fnObj instanceof Map) {
                    Map<?, ?> fn = (Map<?, ?>) fnObj;
                    if (fn.get("name") != null) {
                        name = fn.get("name").toString();
                    }
                    Object argsObj = fn.get("arguments");
                    if (argsObj instanceof Map) {
                        ((Map<?, ?>) argsObj).forEach((k, v) -> args.put(String.valueOf(k), v));
                    } else if (argsObj instanceof String && !((String) argsObj).trim().isEmpty()) {
                        try {
                            Map<?, ?> parsed = objectMapper.readValue((String) argsObj, Map.class);
                            parsed.forEach((k, v) -> args.put(String.valueOf(k), v));
                        } catch (Exception ignored) { }
                    }
                }
                log.info("[AI_TOOL] exec name={}, toolCallId={}, argsKeys={}", name, id, args.keySet());
                Map<String, Object> normalizedArgs = normalizeToolArgs(name, args);
                Object execResult = executeOneToolCall(name, normalizedArgs);
                log.info("[AI_TOOL] done name={}, success={}", name, execResult != null);
                String contentStr = execResult != null ? objectMapper.writeValueAsString(execResult) : "{}";
                Map<String, Object> toolMsg = new HashMap<>();
                toolMsg.put("role", "tool");
                toolMsg.put("content", contentStr);
                toolMsg.put("tool_call_id", id != null ? id : "");
                newMessages.add(toolMsg);
                if (isToolExecFailed(execResult)) {
                    log.warn("[AI_TOOL] stop-after-failure name={}, toolCallId={}", name, id);
                    break;
                }
            }
            log.info("event=ai_followup_prepared");
            return callAiModelWithMessages(newMessages, enableTools, recursionDepth + 1);
        }

        String finalText = aiToolResponseParser.extractTextFromContent(content);
        if (finalText != null && !finalText.isEmpty()) {
            log.info("[AI_CALL_DETAIL] hit final content branch length={}", finalText.length());
            return interceptPseudoToolTextBeforeReturn(finalText, messages, enableTools, recursionDepth, "message.content");
        }
        log.warn("[AI_CALL_DETAIL] no valid content branch matched");
        return null;
    }

    /**
     * 若模型把「正在调用…」「tool_calls: …」等伪工具描述写进正文，则不应原样返回前端：
     * 先尝试从文本解析 tool_calls 并走执行链；解析失败则注入纠正 system 消息再请求一轮。
     */
    private String interceptPseudoToolTextBeforeReturn(String text, List<Map<String, Object>> messages,
                                                       boolean enableTools, int recursionDepth, String resultSource) throws Exception {
        if (text == null || text.trim().isEmpty()) {
            return text;
        }
        // 优先：正文或 ```json``` 代码块内嵌的 {"name":"create_order","arguments":{...}} 也走真实工具链
        if (enableTools && textMayContainEmbeddedToolJson(text)) {
            String handledEarly = tryHandleToolCallsInText(text, messages, enableTools, recursionDepth);
            if (handledEarly != null) {
                return handledEarly;
            }
        }
        if (!enableTools || !looksLikePseudoToolInvocationText(text)) {
            log.info("event=ai_response_ready");
            return text;
        }
        log.warn("event=ai_pseudo_tool_intercepted");
        String handled = tryHandleToolCallsInText(text, messages, enableTools, recursionDepth);
        if (handled != null) {
            return handled;
        }
        if (recursionDepth >= maxAiToolRecursionDepth()) {
            String fallback = "智能助手输出格式异常（含工具调用描述但未正确执行），请简化需求后重试。";
            log.warn("[AI_CALL_INTERCEPT] depth limit, returning fallback");
            log.info("event=ai_fallback_response");
            return fallback;
        }
        List<Map<String, Object>> repairMessages = new ArrayList<>(messages);
        Map<String, Object> repair = new HashMap<>();
        repair.put("role", "system");
        repair.put("content", "【输出纠正】上一条助手回复不符合规范：禁止在用户可见正文中写「正在调用/正在为你生成订单/已调用接口/等待系统返回」等伪进度话术，"
                + "也不得写「tool_calls: …」或仅描述将调用某接口。若需下单或查数据，请只使用协议层标准 tool_calls；"
                + "工具执行完成后，用自然语言直接说明真实结果（成功则给相关返回参数，失败则给错误原因）。");
        repairMessages.add(repair);
        log.info("[AI_CALL_INTERCEPT] injecting repair system message, nextDepth={}", recursionDepth + 1);
        return callAiModelWithMessages(repairMessages, enableTools, recursionDepth + 1);
    }

    private boolean looksLikePseudoToolInvocationText(String text) {
        if (text == null || text.isEmpty()) {
            return false;
        }
        if (text.contains("正在调用")) {
            return true;
        }
        // 伪进度：未真正走 tool_calls 却描写「正在生成订单 / 等待返回 / 已调接口」
        if (text.contains("等待系统返回") || text.contains("等待接口返回")) {
            return true;
        }
        if (text.contains("已调用") && (text.contains("接口") || text.contains("下单") || text.contains("支付"))) {
            return true;
        }
        if (text.contains("正在为你") && (text.contains("生成订单") || text.contains("提交订单") || text.contains("处理中")
                || text.contains("校验") || text.contains("刷新"))) {
            return true;
        }
        if (text.contains("调用下单") || text.contains("调用支付") || text.contains("调用接口")) {
            return true;
        }
        String lower = text.toLowerCase();
        if (lower.contains("tool_calls")) {
            return true;
        }
        // 自然语言里写「调用 get_table_status 工具」类描述
        if (text.contains("调用") && text.contains("工具")
                && (text.contains("get_") || text.contains("list_dishes") || text.contains("create_order")
                || text.contains("table_scan") || text.contains("generateOrderNo"))) {
            return true;
        }
        return false;
    }

    /** 正文中是否可能含有可执行的「单工具 JSON」（含 Markdown 代码块） */
    private boolean textMayContainEmbeddedToolJson(String text) {
        if (text == null || text.isEmpty()) {
            return false;
        }
        if (text.contains("```")) {
            return true;
        }
        String t = text.trim();
        // 模型常把 tool 列表整段输出为 JSON 数组，如 [{"name":"get_order_by_table","arguments":{...}}]
        if (t.startsWith("[") && t.contains("\"name\"") && t.contains("\"arguments\"")) {
            return true;
        }
        if (t.startsWith("{") && t.contains("\"name\"") && t.contains("\"arguments\"")) {
            return true;
        }
        if (text.contains("\"create_order\"") && text.contains("\"arguments\"")) {
            return true;
        }
        if (text.contains("\"add_dishes\"") && text.contains("\"arguments\"")) {
            return true;
        }
        if (text.contains("\"get_order_by_table\"") && text.contains("\"arguments\"")) {
            return true;
        }
        return looksLikePseudoToolInvocationText(text);
    }

    @SuppressWarnings("unchecked")
    private String tryHandleToolCallsInText(String text, List<Map<String, Object>> messages,
                                            boolean enableTools, int recursionDepth) throws Exception {
        if (!enableTools || text == null || text.trim().isEmpty()) {
            return null;
        }
        List<Map<String, Object>> parsed = aiToolResponseParser.parseToolCallsFromText(text);
        if (parsed == null || parsed.isEmpty()) {
            return null;
        }
        List<Map<String, Object>> normalizedToolCalls = aiToolResponseParser.normalizeToolCalls(parsed);
        if (normalizedToolCalls.isEmpty()) {
            return null;
        }
        log.info("[AI_CALL_DETAIL] toolCallsDetectedFromText raw={}, normalized={}",
                parsed.size(), normalizedToolCalls.size());
        List<Map<String, Object>> newMessages = new ArrayList<>(messages);
        Map<String, Object> assistantMsg = new HashMap<>();
        assistantMsg.put("role", "assistant");
        assistantMsg.put("tool_calls", normalizedToolCalls);
        newMessages.add(assistantMsg);
        for (Map<String, Object> tc : normalizedToolCalls) {
            String id = tc.get("id") != null ? tc.get("id").toString() : null;
            Object fnObj = tc.get("function");
            String name = null;
            Map<String, Object> args = new HashMap<>();
            if (fnObj instanceof Map) {
                Map<?, ?> fn = (Map<?, ?>) fnObj;
                if (fn.get("name") != null) {
                    name = fn.get("name").toString();
                }
                Object argsObj = fn.get("arguments");
                if (argsObj instanceof Map) {
                    ((Map<?, ?>) argsObj).forEach((k, v) -> args.put(String.valueOf(k), v));
                } else if (argsObj instanceof String && !((String) argsObj).trim().isEmpty()) {
                    try {
                        Map<?, ?> parsedArgs = objectMapper.readValue((String) argsObj, Map.class);
                        parsedArgs.forEach((k, v) -> args.put(String.valueOf(k), v));
                    } catch (Exception ignored) { }
                }
            }
            log.info("[AI_TOOL] exec(fromText) name={}, toolCallId={}, argsKeys={}", name, id, args.keySet());
            Map<String, Object> normalizedArgs = normalizeToolArgs(name, args);
            Object execResult = executeOneToolCall(name, normalizedArgs);
            String contentStr = execResult != null ? objectMapper.writeValueAsString(execResult) : "{}";
            Map<String, Object> toolMsg = new HashMap<>();
            toolMsg.put("role", "tool");
            toolMsg.put("content", contentStr);
            toolMsg.put("tool_call_id", id != null ? id : "");
            newMessages.add(toolMsg);
            if (isToolExecFailed(execResult)) {
                log.warn("[AI_TOOL] stop-after-failure(fromText) name={}, toolCallId={}", name, id);
                break;
            }
        }
        return callAiModelWithMessages(newMessages, true, recursionDepth + 1);
    }

    /**
     * 工具参数归一化：兼容模型输出的别名字段，统一为后端标准字段名。
     */
    private Map<String, Object> normalizeToolArgs(String toolName, Map<String, Object> args) {
        Map<String, Object> out = args == null ? new HashMap<>() : new HashMap<>(args);
        AiSuggestSession session = AI_SUGGEST_SESSION.get();
        if (session != null && StringUtils.hasText(session.openid) && out.get("openid") == null) {
            out.put("openid", session.openid);
        }
        if (toolName == null) {
            return out;
        }
        if ("get_table_status".equals(toolName)) {
            if (out.get("number") == null) {
                Object v = out.get("table_number");
                if (v == null) v = out.get("tableNumber");
                if (v == null) v = out.get("tableNo");
                if (v == null) v = out.get("table_id");
                if (v == null) v = out.get("tableId");
                if (v != null) out.put("number", v);
            }
        }
        if ("create_order".equals(toolName) || "add_dishes".equals(toolName) || "get_order_by_table".equals(toolName)) {
            if (out.get("table_number") == null) {
                Object v = out.get("tableNumber");
                if (v == null) v = out.get("tableNo");
                if (v == null) v = out.get("table_id");
                if (v == null) v = out.get("tableId");
                if (v != null) out.put("table_number", v);
            }
        }
        if ("create_order".equals(toolName) || "add_dishes".equals(toolName) || "query_order".equals(toolName)
                || "cancel_order".equals(toolName) || "order_notice".equals(toolName)
                || "send_subscribe".equals(toolName) || "get_prepay_id".equals(toolName)
                || "close_pay".equals(toolName)) {
            if (out.get("order_no") == null) {
                Object v = out.get("orderNo");
                if (v != null) out.put("order_no", v);
            }
        }
        if ("create_order".equals(toolName) || "add_dishes".equals(toolName)) {
            normalizeCreateOrderAddDishesArgs(out);
        }
        if ("create_order".equals(toolName)) {
            mergeAiSuggestSessionDefaults(out);
        }
        return out;
    }

    /** 自然语言点餐请求体中的 openid、桌号写入 create_order，避免模型漏传 */
    private void mergeAiSuggestSessionDefaults(Map<String, Object> out) {
        AiSuggestSession s = AI_SUGGEST_SESSION.get();
        if (s == null) {
            return;
        }
        Object openidObj = out.get("openid");
        if (openidObj == null || !StringUtils.hasText(openidObj.toString().trim())) {
            if (StringUtils.hasText(s.openid)) {
                out.put("openid", s.openid.trim());
            }
        }
        Object tn = out.get("table_number");
        String tns = tn == null ? "" : tn.toString().trim();
        if (!StringUtils.hasText(tns) && StringUtils.hasText(s.tableNumber)) {
            out.put("table_number", s.tableNumber.trim());
        }
        Object sid = out.get("shop_id");
        boolean sidEmpty = sid == null
                || (sid instanceof String && !StringUtils.hasText(((String) sid).trim()));
        if (sidEmpty && s.shopId != null) {
            out.put("shop_id", s.shopId);
        }
    }

    /**
     * 下单/加菜参数自我修正：将模型常见别名字段映射为 tools 与 OrderDTO 标准字段，并补全 goods_list 行内缺省（口味、总价）。
     * 与「工具失败后由模型再发起一轮」配合，减少无效重试。
     */
    @SuppressWarnings("unchecked")
    private void normalizeCreateOrderAddDishesArgs(Map<String, Object> out) {
        if (out.get("dineInOrTakeOut") == null) {
            Object v = out.get("dine_in_or_take_out");
            if (v == null) v = out.get("dine_in_type");
            if (v == null) v = out.get("dineInType");
            if (v == null) v = out.get("dineType");
            if (v == null) v = out.get("order_type");
            if (v != null) {
                out.put("dineInOrTakeOut", v.toString().trim());
            }
        }
        if (out.get("number_of_diners") == null) {
            Object v = out.get("people_count");
            if (v == null) v = out.get("peopleCount");
            if (v == null) v = out.get("dine_in_num");
            if (v == null) v = out.get("dineInNum");
            if (v == null) v = out.get("diner_count");
            if (v == null) v = out.get("diners");
            if (v == null) v = out.get("guest_count");
            if (v == null) v = out.get("guests");
            if (v == null) v = out.get("numberOfDiners");
            if (v != null) {
                out.put("number_of_diners", v instanceof Number ? String.valueOf(((Number) v).intValue()) : v.toString().trim());
            }
        } else {
            Object nd = out.get("number_of_diners");
            if (nd instanceof Number) {
                out.put("number_of_diners", String.valueOf(((Number) nd).intValue()));
            }
        }
        // 模型常用 dine_in / take_out / delivery，后端枚举为 堂食 / 打包 / 外卖
        Object dino = out.get("dineInOrTakeOut");
        if (dino != null) {
            String v = dino.toString().trim();
            if ("dine_in".equalsIgnoreCase(v) || "dinein".equalsIgnoreCase(v)) {
                out.put("dineInOrTakeOut", "堂食");
            } else if ("take_out".equalsIgnoreCase(v) || "takeout".equalsIgnoreCase(v)) {
                out.put("dineInOrTakeOut", "打包");
            } else if ("delivery".equalsIgnoreCase(v) || "waimai".equalsIgnoreCase(v) || "外卖".equals(v)) {
                out.put("dineInOrTakeOut", "外卖");
            }
        }
        Object glObj = out.get("goods_list");
        if (!(glObj instanceof List)) {
            return;
        }
        for (Object row : (List<?>) glObj) {
            if (!(row instanceof Map)) {
                continue;
            }
            Map<String, Object> line = (Map<String, Object>) row;
            if (line.get("selectedSpicy") == null) {
                Object spec = line.get("specification");
                if (spec == null) spec = line.get("spec");
                if (spec == null) spec = line.get("spicy");
                if (spec == null) spec = line.get("flavor");
                if (spec != null) {
                    line.put("selectedSpicy", spec instanceof String ? (String) spec : spec.toString());
                }
            }
            if (line.get("total_price") == null) {
                Double unit = aiDoubleArg(line, "unitprice", "unitPrice", "price", "unit_price");
                int qty = aiQuantityInt(line.get("quantity"));
                if (unit != null && qty > 0) {
                    line.put("total_price", Math.round(unit * qty * 100) / 100.0);
                }
            }
            if (line.get("quantity") != null && !(line.get("quantity") instanceof String)) {
                line.put("quantity", line.get("quantity").toString());
            }
            if (line.get("cid") != null && !(line.get("cid") instanceof String)) {
                line.put("cid", line.get("cid").toString());
            }
        }
    }

    private static Double aiDoubleArg(Map<String, Object> m, String... keys) {
        if (m == null || keys == null) {
            return null;
        }
        for (String key : keys) {
            Object v = m.get(key);
            if (v == null) {
                continue;
            }
            if (v instanceof Number) {
                return ((Number) v).doubleValue();
            }
            try {
                return Double.parseDouble(v.toString().trim());
            } catch (NumberFormatException ignored) {
                // next
            }
        }
        return null;
    }

    private static int aiQuantityInt(Object quantity) {
        if (quantity == null) {
            return 0;
        }
        if (quantity instanceof Number) {
            return Math.max(((Number) quantity).intValue(), 0);
        }
        try {
            return Math.max(Integer.parseInt(quantity.toString().trim()), 0);
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    /** 工具参数中取整型，支持 orderId / order_id 等键名 */
    private static Integer aiIntArg(Map<String, Object> args, String... keys) {
        if (args == null || keys == null) {
            return null;
        }
        for (String key : keys) {
            Object v = args.get(key);
            if (v == null) {
                continue;
            }
            if (v instanceof Number) {
                return ((Number) v).intValue();
            }
            try {
                return Integer.parseInt(v.toString().trim());
            } catch (NumberFormatException ignored) {
                // next key
            }
        }
        return null;
    }

    /**
     * 执行单次工具调用，返回可序列化为 JSON 的结果（R 或 Map）。
     */
    private Object executeOneToolCall(String name, Map<String, Object> args) {
        if (name == null || name.isEmpty()) {
            Map<String, Object> errorMap = new HashMap<>();
            errorMap.put("error", "工具名为空");
            return errorMap;
        }
        if (!getAiRecommendToolAllowlist().contains(name)) {
            Map<String, Object> errorMap = new HashMap<>();
            errorMap.put("error", "荐菜助手仅支持「选菜推荐」：已禁止调用工具 " + name
                    + "。请用户在小程序中对推荐结果点击「加入购物车」后进入点餐页完成规格选择与下单。");
            return errorMap;
        }
        try {
            switch (name) {
                case "generateOrderNo": {
                    Map<String, Object> result = new HashMap<>();
                    result.put("order_no", generateOrderNo());
                    return R.ok(result);
                }
                case "get_openid": {
                    Map<String, String> p = new HashMap<>();
                    Object c = args.get("code");
                    if (c == null || c.toString().trim().isEmpty()) {
                        return R.error("code不能为空");
                    }
                    p.put("code", c.toString().trim());
                    return getOpenid(p);
                }
                case "update_user": {
                    if (args.get("openid") == null || args.get("openid").toString().trim().isEmpty()) {
                        return R.error("update_user 需要 openid");
                    }
                    User u = new User();
                    u.setOpenid(args.get("openid").toString().trim());
                    if (args.get("name") != null) {
                        u.setName(args.get("name").toString());
                    }
                    if (args.get("phone") != null) {
                        u.setPhone(args.get("phone").toString());
                    }
                    if (args.get("birthday") != null) {
                        u.setBirthday(args.get("birthday").toString());
                    }
                    return customerProfileService.updateUser(u);
                }
                case "get_official_phone_number": {
                    Map<String, String> p = new HashMap<>();
                    if (args.get("code") == null || args.get("code").toString().trim().isEmpty()) {
                        return R.error("code不能为空");
                    }
                    p.put("code", args.get("code").toString().trim());
                    if (args.get("openid") != null) {
                        p.put("openid", args.get("openid").toString());
                    }
                    if (args.get("invite_code") != null) {
                        p.put("invite_code", args.get("invite_code").toString());
                    }
                    return getOfficialPhoneNumber(p);
                }
                case "table_verify": {
                    String num = args.get("number") != null ? args.get("number").toString().trim() : null;
                    if (num == null || num.isEmpty()) {
                        return R.error("桌号 number 不能为空");
                    }
                    try {
                        return tableVerifyWithShop(num, aiToolShopIdOrDefault(args));
                    } catch (RuntimeException e) {
                        return R.error(e.getMessage());
                    }
                }
                case "get_table_status":
                    return executeGetTableStatus(args);
                case "get_business":
                    return getBusinessForShop(aiToolShopIdOrDefault(args));
                case "calculate_finish_time": {
                    Order od = new Order();
                    Object dine = args.get("dineInOrTakeOut");
                    if (dine != null) {
                        od.setDineInOrTakeOut(dine.toString());
                    }
                    try {
                        return calculateFinishTimeWithShop(od, aiToolShopIdOrDefault(args));
                    } catch (RuntimeException e) {
                        return R.error(e.getMessage());
                    }
                }
                case "list_dishes": {
                    Map<String, Object> map = new HashMap<>();
                    map.put("allDish", getOnSaleMenuForAi(aiToolShopIdOrDefault(args)));
                    return R.ok(map);
                }
                case "list_all_dishes": {
                    List<Category> categoryList = categoryService.list(new QueryWrapper<Category>().orderByAsc("cid"));
                    for (Category category : categoryList) {
                        QueryWrapper<Dish> dq = new QueryWrapper<Dish>().eq("typeId", category.getId()).orderByAsc("sorting");
                        DishCustomerMenuFilters.applyTo(dq);
                        List<Dish> dishList = dishService.list(dq);
                        category.setDishList(dishList);
                    }
                    DishCustomerMenuFilters.dropCategoriesWithNoDishes(categoryList);
                    Map<String, Object> map = new HashMap<>();
                    map.put("allDish", categoryList);
                    return R.ok(map);
                }
                case "create_order": {
                    R co = executeCreateOrder(args);
                    AiToolTurnTracker tr = AI_TOOL_TURN.get();
                    if (tr != null) {
                        tr.createOrderInvoked = true;
                        if (isRCodeOk(co)) {
                            tr.createOrderOk = true;
                            Object ono = co.get("order_no");
                            if (ono != null) {
                                tr.serverOrderNo = ono.toString().trim();
                            }
                        }
                    }
                    return co;
                }
                case "cancel_order":
                    return executeCancelOrder(args);
                case "query_order": {
                    R qr = executeQueryOrder(args);
                    if (AI_TOOL_TURN.get() != null && isRCodeOk(qr)) {
                        Object ord = qr.get("order");
                        if (ord instanceof Order) {
                            String ono = ((Order) ord).getOrder_no();
                            if (StringUtils.hasText(ono)) {
                                recordTrustedQueryOrderNo(ono);
                            }
                        }
                    }
                    return qr;
                }
                
                case "add_dishes": {
                    OrderDTO dto = objectMapper.convertValue(args, OrderDTO.class);
                    if (dto == null) {
                        return R.error("add_dishes 参数解析失败");
                    }
                    R ad = addDishes(dto, null);
                    AiToolTurnTracker trAd = AI_TOOL_TURN.get();
                    if (trAd != null && isRCodeOk(ad)) {
                        trAd.addDishesOk = true;
                        Object ono = args != null ? args.get("order_no") : null;
                        if (ono != null && StringUtils.hasText(ono.toString().trim())) {
                            trAd.serverOrderNo = ono.toString().trim();
                        }
                    }
                    return ad;
                }
                case "get_order_by_table": {
                    String tableNumber = args.get("table_number") != null ? args.get("table_number").toString().trim() : null;
                    String transacStatus = args.get("transac_status") != null ? args.get("transac_status").toString().trim() : null;
                    if (tableNumber == null || tableNumber.isEmpty()) {
                        return R.error("get_order_by_table 需要 table_number");
                    }
                    if (transacStatus == null || transacStatus.isEmpty()) {
                        return R.error("get_order_by_table 需要 transac_status");
                    }
                    try {
                        Integer aiShop = aiToolShopIdOrDefault(args);
                        R gt = getOrderByTableWithShop(tableNumber, transacStatus, aiShop);
                        gt = requireOwnedOrderInResponse(gt, requiredToolOpenid(args), "menu");
                        if (AI_TOOL_TURN.get() != null && isRCodeOk(gt)) {
                            Object menu = gt.get("menu");
                            if (menu instanceof Order) {
                                String ono = ((Order) menu).getOrder_no();
                                if (StringUtils.hasText(ono)) {
                                    recordTrustedQueryOrderNo(ono);
                                }
                            }
                        }
                        return gt;
                    } catch (RuntimeException e) {
                        return R.error(e.getMessage());
                    }
                }
                case "order_history": {
                    R oh = getOrderHistoryByOpenid(args != null ? args : new HashMap<>());
                    if (AI_TOOL_TURN.get() != null && isRCodeOk(oh)) {
                        Object orders = oh.get("orders");
                        if (orders instanceof List) {
                            for (Object item : (List<?>) orders) {
                                if (item instanceof Map) {
                                    Object ono = ((Map<?, ?>) item).get("order_no");
                                    if (ono != null && StringUtils.hasText(ono.toString().trim())) {
                                        recordTrustedQueryOrderNo(ono.toString());
                                    }
                                }
                            }
                        }
                    }
                    return oh;
                }
                case "get_table_info": {
                    String tableNumber = args.get("tableNumber") != null ? args.get("tableNumber").toString().trim() : null;
                    if (tableNumber == null || tableNumber.isEmpty()) {
                        return R.error("get_table_info 需要 tableNumber");
                    }
                    try {
                        String openid = requiredToolOpenid(args);
                        return getTableInfoWithShop(tableNumber, aiToolShopIdOrDefault(args), openid);
                    } catch (RuntimeException e) {
                        return R.error(e.getMessage());
                    }
                }
                case "get_user_info": {
                    String openid = args.get("openid") != null ? args.get("openid").toString().trim() : null;
                    if (openid == null || openid.isEmpty()) {
                        return R.error("get_user_info 需要 openid");
                    }
                    Map<String, String> params = new HashMap<>();
                    params.put("openid", openid);
                    return customerProfileService.getUserInfo(params);
                }
                case "get_available_coupons": {
                    String openid = args.get("openid") != null ? args.get("openid").toString().trim() : null;
                    if (openid == null || openid.isEmpty()) {
                        return R.error("get_available_coupons 需要 openid");
                    }
                    return CouponService.getAvailableCoupons(openid);
                }
                case "get_user_coupons": {
                    String openid = args.get("openid") != null ? args.get("openid").toString().trim() : null;
                    String status = args.get("status") != null ? args.get("status").toString().trim() : null;
                    if (openid == null || openid.isEmpty() || status == null || status.isEmpty()) {
                        return R.error("get_user_coupons 需要 openid 与 status");
                    }
                    return CouponService.getUserCoupons(openid, status);
                }
                case "get_activity_popup_list": {
                    String openid = args.get("openid") != null ? args.get("openid").toString().trim() : null;
                    String type = args.get("type") != null ? args.get("type").toString().trim() : null;
                    if (type == null || type.isEmpty()) {
                        type = "page_activity";
                    }
                    int userType;
                    User user = null;
                    if (openid != null && !openid.isEmpty()) {
                        user = userService.getUserByOpenid(openid);
                    }
                    userType = (user == null) ? 0 : user.getUser_type();
                    Integer popupShopId = null;
                    Object shopArg = args.get("shop_id");
                    if (shopArg instanceof Number) {
                        popupShopId = ((Number) shopArg).intValue();
                    } else if (shopArg != null && StringUtils.hasText(shopArg.toString())) {
                        try {
                            popupShopId = Integer.parseInt(shopArg.toString().trim());
                        } catch (NumberFormatException ignored) {
                        }
                    }
                    if (popupShopId == null) {
                        popupShopId = 1;
                    }
                    List<ActivityPopup> validPopup = activityPopupService.getValidDiningPopupList(
                            1, userType, type, popupShopId);
                    Map<String, Object> result = new HashMap<>();
                    result.put("hasActivity", validPopup != null && !validPopup.isEmpty());
                    result.put("activity", validPopup);
                    return R.ok(result);
                }
                case "order_notice": {
                    Order od = new Order();
                    String on = args.get("order_no") != null ? args.get("order_no").toString().trim() : null;
                    if (on == null || on.isEmpty()) {
                        return R.error("order_notice 需要 order_no");
                    }
                    od.setOrder_no(on);
                    Object n = args.get("notice");
                    if (n instanceof Number) {
                        od.setNotice(((Number) n).intValue());
                    } else if (n != null) {
                        try {
                            od.setNotice(Integer.parseInt(n.toString().trim()));
                        } catch (NumberFormatException e) {
                            od.setNotice(0);
                        }
                    } else {
                        od.setNotice(0);
                    }
                    return notice(od);
                }
                case "order_print_content": {
                    Integer orderId = aiIntArg(args, "orderId", "order_id");
                    if (orderId == null) {
                        return R.error("order_print_content 需要 orderId");
                    }
                    Object t = args.get("type");
                    boolean typeFlag = false;
                    if (t instanceof Boolean) {
                        typeFlag = (Boolean) t;
                    } else if (t != null) {
                        typeFlag = Boolean.parseBoolean(t.toString());
                    }
                    return getPrintContent(orderId, typeFlag);
                }
                case "order_auto_accept_and_print": {
                    Integer orderId = aiIntArg(args, "orderId", "order_id");
                    if (orderId == null) {
                        return R.error("order_auto_accept_and_print 需要 orderId");
                    }
                    return autoAcceptAndPrint(orderId);
                }
                case "get_prepay_id": {
                    Map<String, String> p = new HashMap<>();
                    Object orderNo = args.get("orderNo");
                    if (orderNo == null) {
                        orderNo = args.get("order_no");
                    }
                    if (orderNo == null || orderNo.toString().trim().isEmpty()) {
                        return R.error("get_prepay_id 需要 orderNo");
                    }
                    p.put("orderNo", orderNo.toString().trim());
                    if (args.get("openid") == null || args.get("openid").toString().trim().isEmpty()) {
                        return R.error("get_prepay_id 需要 openid");
                    }
                    p.put("openid", args.get("openid").toString().trim());
                    if (args.get("takeOut") != null) {
                        p.put("takeOut", args.get("takeOut").toString());
                    }
                    if (args.get("totalAmount") != null) {
                        p.put("totalAmount", args.get("totalAmount").toString());
                    }
                    if (args.get("coupon_id") != null) {
                        p.put("coupon_id", args.get("coupon_id").toString());
                    }
                    // 实付与优惠金额以服务端校验为准，不再透传模型/前端的 discount_amount
                    return getPrepayIdForIdentity(p, requiredToolOpenid(args));
                }
                case "query_pay_by_out_trade_no": {
                    String out = args.get("outTradeNo") != null ? args.get("outTradeNo").toString().trim() : null;
                    if (out == null || out.isEmpty()) {
                        return R.error("需要 outTradeNo");
                    }
                    String merchantId = args.get("merchantId") != null ? args.get("merchantId").toString().trim() : null;
                    String openid = args.get("openid") != null ? args.get("openid").toString().trim() : null;
                    if (!StringUtils.hasText(openid)) {
                        return R.error("query_pay_by_out_trade_no 需要 openid");
                    }
                    return queryByOutTradeNoOwned(out, merchantId, openid);
                }
                case "send_subscribe": {
                    Map<String, Object> sub = new HashMap<>();
                    sub.put("openid", args.get("openid"));
                    sub.put("templateId", args.get("templateId"));
                    sub.put("order_no", args.get("order_no"));
                    sub.put("data", args.get("data"));
                    return sendSubscribe(sub);
                }
                case "get_banners":
                    return getEnabledBanners();
                case "coupon_receive": {
                    String openid = args.get("openid") != null ? args.get("openid").toString().trim() : null;
                    if (openid == null || openid.isEmpty()) {
                        return R.error("coupon_receive 需要 openid");
                    }
                    Object cid = args.get("coupon_id");
                    if (cid == null) {
                        return R.error("coupon_receive 需要 coupon_id");
                    }
                    long couponId = cid instanceof Number ? ((Number) cid).longValue() : Long.parseLong(cid.toString().trim());
                    return CouponService.receiveCoupon(openid, couponId);
                }
                case "coupon_available_count": {
                    String openid = args.get("openid") != null ? args.get("openid").toString().trim() : null;
                    if (openid == null || openid.isEmpty()) {
                        return R.error("coupon_available_count 需要 openid");
                    }
                    int cnt = CouponService.getAvailableCouponCount(openid);
                    return R.ok().put("count", cnt);
                }
                case "invite_get_code": {
                    String openid = args.get("openid") != null ? args.get("openid").toString().trim() : null;
                    if (openid == null || openid.isEmpty()) {
                        return R.error(2, "openid不能为空");
                    }
                    com.lanf.dto.R<com.lanf.dto.InviteCodeDTO> sr = InviteService.getInviteCode(openid);
                    if (sr == null) {
                        return R.error(500, "获取邀请码失败");
                    }
                    if (Integer.valueOf(0).equals(sr.getCode()) && sr.getData() != null) {
                        return R.ok().put("invite_code", sr.getData().getInvite_code());
                    }
                    int ec = sr.getCode() != null ? sr.getCode() : 500;
                    String msg = sr.getMsg() != null ? sr.getMsg() : "获取邀请码失败";
                    return R.error(ec, msg);
                }
                case "invite_get_records": {
                    String openid = args.get("openid") != null ? args.get("openid").toString().trim() : null;
                    if (openid == null || openid.isEmpty()) {
                        return R.error(2, "openid不能为空");
                    }
                    com.lanf.dto.R<java.util.List<com.lanf.dto.InviteRecordDTO>> sr = InviteService.getInviteRecords(openid);
                    if (sr != null && Integer.valueOf(0).equals(sr.getCode())) {
                        java.util.List<com.lanf.dto.InviteRecordDTO> list =
                                sr.getData() != null ? sr.getData() : java.util.Collections.emptyList();
                        return R.ok().put("data", list);
                    }
                    int ec = (sr != null && sr.getCode() != null) ? sr.getCode() : 500;
                    String msg = (sr != null && sr.getMsg() != null) ? sr.getMsg() : "获取邀请记录失败";
                    return R.error(ec, msg);
                }
                case "invite_get_reward": {
                    String openid = args.get("openid") != null ? args.get("openid").toString().trim() : null;
                    if (openid == null || openid.isEmpty()) {
                        return R.error(2, "openid不能为空");
                    }
                    com.lanf.dto.R<java.util.List<com.lanf.dto.InviteRecordDTO>> sr = InviteService.getRewardRecords(openid);
                    if (sr != null && Integer.valueOf(0).equals(sr.getCode())) {
                        java.util.List<com.lanf.dto.InviteRecordDTO> list =
                                sr.getData() != null ? sr.getData() : java.util.Collections.emptyList();
                        return R.ok().put("data", list);
                    }
                    int ec = (sr != null && sr.getCode() != null) ? sr.getCode() : 500;
                    String msg = (sr != null && sr.getMsg() != null) ? sr.getMsg() : "获取奖励记录失败";
                    return R.error(ec, msg);
                }
                case "invite_poster": {
                    String code = args.get("code") != null ? args.get("code").toString().trim() : null;
                    if (code == null || code.isEmpty()) {
                        return R.error("邀请码不能为空");
                    }
                    ResponseEntity<Map<String, Object>> entity = inviteController.getInvitePoster(code);
                    if (entity != null && entity.getBody() != null) {
                        return entity.getBody();
                    }
                    return R.error("海报生成失败");
                }
                default:
                    return new HashMap<String, Object>() {{
                        put("error", "未知工具: " + name);
                    }};
            }
        } catch (Exception e) {
            log.warn("工具执行异常: name={}", name, e);
            return new HashMap<String, Object>() {{
                put("error", e.getMessage() != null ? e.getMessage() : "执行异常");
            }};
        }
    }

    /**
     * 返回智能点餐可用的工具定义（供调用大模型时传入 tools 参数）。
     * 前端/中台 GET 此接口拿到列表后，在请求通义千问时带上，模型即可按此生成 tool_calls。
     */
    @GetMapping("/ai/tools")
    public R getAiTools() {
        List<Map<String, Object>> tools = filterAiToolsForRecommendAgent(getAiToolDefinitions());
        return R.ok().put("tools", tools);
    }

    private static final String AI_TOOLS_RESOURCE = "ai-tools.json";
    private static final String AI_AGENT_CONFIG_RESOURCE = "ai-agent-config.json";

    private static final Set<String> DEFAULT_AI_RECOMMEND_TOOL_ALLOWLIST = Collections.unmodifiableSet(new LinkedHashSet<>(
            Arrays.asList("list_dishes", "get_business", "calculate_finish_time")));

    /**
     * 荐菜助手工具白名单，来自 ai-agent-config.json → recommend_agent.tool_allowlist。
     */
    @SuppressWarnings("unchecked")
    private Set<String> getAiRecommendToolAllowlist() {
        Map<String, Object> cfg = getAiAgentConfigMap();
        Object ra = cfg.get("recommend_agent");
        if (!(ra instanceof Map)) {
            return DEFAULT_AI_RECOMMEND_TOOL_ALLOWLIST;
        }
        Object tl = ((Map<?, ?>) ra).get("tool_allowlist");
        if (!(tl instanceof List)) {
            return DEFAULT_AI_RECOMMEND_TOOL_ALLOWLIST;
        }
        Set<String> names = new LinkedHashSet<>();
        for (Object o : (List<?>) tl) {
            if (o != null) {
                String n = o.toString().trim();
                if (!n.isEmpty()) {
                    names.add(n);
                }
            }
        }
        return names.isEmpty() ? DEFAULT_AI_RECOMMEND_TOOL_ALLOWLIST : Collections.unmodifiableSet(names);
    }

    /**
     * 从大模型工具定义列表中筛出荐菜助手可用的条目（与 execute 白名单一致）。
     */
    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> filterAiToolsForRecommendAgent(List<Map<String, Object>> allTools) {
        if (allTools == null || allTools.isEmpty()) {
            return Collections.emptyList();
        }
        Set<String> allow = getAiRecommendToolAllowlist();
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> tool : allTools) {
            if (tool == null) {
                continue;
            }
            Object fn = tool.get("function");
            if (!(fn instanceof Map)) {
                continue;
            }
            Object nm = ((Map<?, ?>) fn).get("name");
            if (nm == null) {
                continue;
            }
            if (allow.contains(nm.toString().trim())) {
                out.add(tool);
            }
        }
        return out;
    }

    /**
     * 从 classpath 的 ai-tools.json 读取工具定义列表（与 docs/openapi 生成的 docs/ai-tools.json 一致，打包时 resources 内有一份）。
     * 读取失败时返回空列表并打日志。
     */
    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> getAiToolDefinitions() {
        try (InputStream is = getClass().getClassLoader().getResourceAsStream(AI_TOOLS_RESOURCE)) {
            if (is == null) {
                log.warn("ai-tools.json 未找到于 classpath: {}", AI_TOOLS_RESOURCE);
                return Collections.emptyList();
            }
            Map<String, Object> root = objectMapper.readValue(is, Map.class);
            Object toolsObj = root.get("tools");
            if (toolsObj instanceof List) {
                List<Map<String, Object>> tools = (List<Map<String, Object>>) toolsObj;
                log.info("[AI_TOOLS] loaded from classpath, count={}", tools.size());
                return tools;
            }
        } catch (Exception e) {
            log.warn("读取 ai-tools.json 失败", e);
        }
        return Collections.emptyList();
    }

    /**
     * 读取智能体配置 JSON（ai-agent-config.json）完整对象，用于作为模型上下文。
     */
    @SuppressWarnings("unchecked")
    private Map<String, Object> getAiAgentConfigMap() {
        try (InputStream is = getClass().getClassLoader().getResourceAsStream(AI_AGENT_CONFIG_RESOURCE)) {
            if (is == null) {
                return Collections.emptyMap();
            }
            Map<String, Object> cfg = objectMapper.readValue(is, Map.class);
            return cfg != null ? cfg : Collections.emptyMap();
        } catch (Exception e) {
            log.warn("读取 ai-agent-config.json 失败", e);
            return Collections.emptyMap();
        }
    }

    /**
     * 从 classpath 的 ai-agent-config.json 读取系统提示词 content。
     * 配置缺失时使用内置兜底文案，避免影响主链路。
     */
    private String getAiAgentSystemContent() {
        try (InputStream is = getClass().getClassLoader().getResourceAsStream(AI_AGENT_CONFIG_RESOURCE)) {
            if (is != null) {
                Map<String, Object> root = objectMapper.readValue(is, Map.class);
                Object content = root.get("content");
                if (content instanceof String && !((String) content).trim().isEmpty()) {
                    return ((String) content).trim();
                }
            } else {
                log.warn("ai-agent-config.json 未找到于 classpath: {}", AI_AGENT_CONFIG_RESOURCE);
            }
        } catch (Exception e) {
            log.warn("读取 ai-agent-config.json 失败", e);
        }
        return "你是「老肥油边王」智能点餐助手。仅处理点餐相关问题，优先使用系统提供的工具，不得编造数据。";
    }

    /**
     * 构建调用前上下文包：openid 用户信息、画像、在售菜品、智能体配置、tools（可选）。
     */
    private Map<String, Object> buildAiContextBundle(String openid, boolean includeTools) {
        Map<String, Object> bundle = new HashMap<>();
        bundle.put("ts", System.currentTimeMillis());
        if (openid != null && !openid.trim().isEmpty()) {
            String oid = openid.trim();
            bundle.put("openid", oid);
            try {
                User user = userService.getUserByOpenid(oid);
                if (user != null) {
                    Map<String, Object> userInfo = new HashMap<>();
                    userInfo.put("id", user.getId());
                    userInfo.put("name", user.getName());
                    userInfo.put("phone", user.getPhone());
                    userInfo.put("points", user.getPoints());
                    userInfo.put("user_type", user.getUser_type());
                    userInfo.put("birthday", user.getBirthday());
                    userInfo.put("openid", user.getOpenid());
                    bundle.put("user_info", userInfo);
                }
            } catch (Exception e) {
                log.warn("event=ai_user_context_failed");
            }
            bundle.put("user_profile", buildUserProfileForAi(oid));
        }
        List<Map<String, Object>> dishBriefList = new ArrayList<>();
        List<Category> onSaleMenu = getOnSaleMenuForAi();
        for (Category c : onSaleMenu) {
            if (c.getDishList() == null) continue;
            for (Dish d : c.getDishList()) {
                Map<String, Object> m = new HashMap<>();
                m.put("id", d.getId());
                m.put("cid", c.getCid());
                m.put("category", c.getLabel());
                m.put("name", d.getName());
                m.put("unitprice", d.getUnitprice());
                m.put("unit", d.getUnit());
                m.put("onsale", d.isOnsale());
                m.put("specification", d.getSpecification());
                m.put("image", d.getImage());
                dishBriefList.add(m);
            }
        }
        bundle.put("on_sale_dishes", dishBriefList);
        bundle.put("agent_config", getAiAgentConfigMap());
        if (includeTools) {
            bundle.put("tools_provided_in_request", Boolean.TRUE);
        }
        return bundle;
    }

    /**
     * 在 messages 开头注入上下文消息，一次性提供给模型。
     */
    private void appendAiContextMessage(List<Map<String, Object>> messages, String openid, boolean includeTools) {
        try {
            Map<String, Object> context = buildAiContextBundle(openid, includeTools);
            Map<String, Object> ctxMsg = new HashMap<>();
            ctxMsg.put("role", "system");
            StringBuilder ctxPrefix = new StringBuilder();
            ctxPrefix.append("以下是本次会话上下文（JSON），请严格基于这些数据作答，不得编造：\n");
            if (includeTools) {
                ctxPrefix.append("【工具调用】请求体顶层 tools 仅为荐菜白名单（list_dishes / get_business / calculate_finish_time）；"
                        + "需要数据时返回标准 tool_calls，勿在正文伪造工具结果。\n");
                ctxPrefix.append("【推荐优先级】若 on_sale_dishes 已完整，优先直接推荐；用户明确要求刷新或缺字段时再 list_dishes。\n");
            }
            ctxPrefix.append(objectMapper.writeValueAsString(context));
            ctxMsg.put("content", ctxPrefix.toString());
            messages.add(ctxMsg);
            log.info("event=ai_context_prepared");
        } catch (Exception e) {
            log.warn("[AI_CONTEXT] inject failed", e);
        }
    }

    /**
     * 多轮点餐：提示模型必须承接上文已讨论的菜品/数量/口味等，仅追问真正缺失项。
     */
    private static String appendChatSuggestMultiTurnBridge(String userContent, String tableNumber) {
        if (userContent == null) {
            return "";
        }
        StringBuilder sb = new StringBuilder(userContent);
        sb.append("\n\n【多轮衔接】请结合本对话中此前的用户与助手消息：");
        sb.append("助手仅做推荐，不代下单；承接上文已讨论的菜名、数量、口味等，用于更新推荐表与文末加入购物车的结构化数据；");
        sb.append("仅对仍不明确的项追问，不要无视上文、从头索要一整套信息。");
        if (tableNumber != null && !tableNumber.trim().isEmpty()) {
            sb.append(" 本条已含桌号，堂食场景下勿再索要桌号。");
        }
        return sb.toString();
    }

    /**
     * 裁剪多轮对话历史，保留最近 N 轮（一轮=1条user+1条assistant）。
     */
    private List<Map<String, Object>> trimAiChatHistory(List<Map<String, Object>> history, int maxRounds) {
        int maxMessages = Math.max(2, maxRounds * 2);
        if (history == null || history.size() <= maxMessages) {
            return history;
        }
        return new ArrayList<>(history.subList(history.size() - maxMessages, history.size()));
    }

    /**
     * AI 工具调用统一执行入口：接收大模型返回的 tool_calls，分发到具体业务。
     */
    @PostMapping("/ai/tools/execute")
    public R executeTools(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        Object tcObj = body.get("tool_calls");
        if (!(tcObj instanceof List)) {
            return R.error("tool_calls 格式错误");
        }
        List<?> toolCalls = (List<?>) tcObj;
        List<Object> results = new ArrayList<>();

        for (Object o : toolCalls) {
            if (!(o instanceof Map)) continue;
            Map<?, ?> call = (Map<?, ?>) o;
            String name = call.get("name") != null ? call.get("name").toString() : null;
            Object argsObj = call.get("arguments");
            Map<String, Object> args = new HashMap<>();
            if (argsObj instanceof Map) {
                ((Map<?, ?>) argsObj).forEach((k, v) -> args.put(String.valueOf(k), v));
            }
            Object authenticatedOpenid = request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID);
            if (authenticatedOpenid != null) {
                args.putIfAbsent("openid", authenticatedOpenid.toString());
            }

            if (name == null || name.isEmpty()) continue;

            results.add(executeOneToolCall(name, args));
        }

        return R.ok().put("results", results);
    }

    /**
     * 工具：根据桌号获取桌台状态（复用 /order/table_status）。
     */
    private R executeGetTableStatus(Map<String, Object> args) {
        String number = null;
        if (args != null) {
            Object n = args.get("number");
            if (n == null) n = args.get("table_number");
            if (n == null) n = args.get("tableNumber");
            if (n != null) number = n.toString().trim();
        }
        log.info("[AI_TOOL] executeGetTableStatus number: {}", number);
        if (number == null || number.isEmpty()) {
            return R.error("桌号不能为空（支持 number/table_number/tableNumber）");
        }
        try {
            return tableStatusWithShop(number, aiToolShopIdOrDefault(args));
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    /**
     * 工具：创建订单（复用 /order/create 的 OrderDTO 流程）。
     */
    private R executeCreateOrder(Map<String, Object> args) {
        try {
            OrderDTO dto = objectMapper.convertValue(args, OrderDTO.class);
            if (dto == null) {
                return R.error("create_order 参数解析失败");
            }
            if (dto.getOpenid() == null || dto.getOpenid().trim().isEmpty()) {
                return R.error("创建订单缺少 openid");
            }
            if (dto.getDineInOrTakeOut() == null || dto.getDineInOrTakeOut().trim().isEmpty()) {
                return R.error("创建订单缺少 dineInOrTakeOut");
            }
            if ("堂食".equals(dto.getDineInOrTakeOut()) &&
                    (dto.getTable_number() == null || dto.getTable_number().trim().isEmpty())) {
                return R.error("堂食必须提供桌号 table_number");
            }
            if (dto.getGoods_list() == null || dto.getGoods_list().isEmpty()) {
                return R.error("创建订单缺少 goods_list");
            }
            if (dto.getNumber_of_diners() == null || dto.getNumber_of_diners().trim().isEmpty()) {
                return R.error("创建订单缺少用餐人数 number_of_diners");
            }
            return create(dto, null);
        } catch (Exception e) {
            log.error("executeCreateOrder 异常", e);
            return R.error("创建订单失败");
        }
    }

    /**
     * 工具：取消订单（复用 /order/cancel 逻辑）。
     */
    private R executeCancelOrder(Map<String, Object> args) {
        String orderNo = args.get("order_no") != null ? args.get("order_no").toString().trim() : null;
        String openid = args.get("openid") != null ? args.get("openid").toString().trim() : null;
        if (orderNo == null || orderNo.isEmpty()) {
            return R.error("取消订单需要 order_no");
        }
        if (openid == null || openid.isEmpty()) {
            return R.error("取消订单需要 openid");
        }
        Map<String, Object> cancelReq = new HashMap<>();
        cancelReq.put("order_no", orderNo);
        cancelReq.put("openid", openid);
        if (args.get("shop_id") != null) {
            cancelReq.put("shop_id", args.get("shop_id"));
        }
        return cancelOrder(cancelReq, null);
    }

    /**
     * 工具：查单（按订单号查询订单及明细）。
     */
    private R executeQueryOrder(Map<String, Object> args) {
        String orderNo = args.get("order_no") != null ? args.get("order_no").toString().trim() : null;
        if (orderNo == null || orderNo.isEmpty()) {
            return R.error("查单需要 order_no");
        }
        Order order = orderService.getOne(new QueryWrapper<Order>()
                .eq("order_no", orderNo).eq("openid", requiredToolOpenid(args)));
        if (order == null) {
            return R.error("订单不存在");
        }
        takeoutDeliveryService.enrichOrder(order);
        List<OrderDetail> details = orderDetailService.list(
                new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
        Map<String, Object> result = new HashMap<>();
        result.put("order", order);
        result.put("orderDetails", details);
        return R.ok(result);
    }

    private String authenticatedUserOpenid(HttpServletRequest request) {
        Object identity = request == null ? null : request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID);
        if (identity == null || !StringUtils.hasText(identity.toString())) {
            throw new IllegalStateException("用户身份缺失");
        }
        return identity.toString().trim();
    }

    private Map<String, String> bindAuthenticatedOpenid(Map<String, String> params, String authenticatedOpenid) {
        Map<String, String> bound = params == null ? new HashMap<>() : new HashMap<>(params);
        bound.put("openid", authenticatedOpenid);
        bound.remove("code");
        bound.remove("wx_code");
        bound.remove("wxCode");
        return bound;
    }

    private String requiredToolOpenid(Map<String, Object> args) {
        Object value = args == null ? null : args.get("openid");
        if (value == null || !StringUtils.hasText(value.toString())) {
            throw new IllegalArgumentException("工具调用缺少 openid");
        }
        return value.toString().trim();
    }

    private R requireOwnedOrderInResponse(R result, String openid, String orderField) {
        if (result == null || !isRCodeOk(result)) {
            return result;
        }
        Object value = result.get(orderField);
        if (value instanceof Order) {
            Order o = (Order) value;
            boolean isOwner = openid != null && openid.equals(o.getOpenid());
            boolean isTableCompanion = "堂食".equals(o.getDineInOrTakeOut())
                    && "unsettled".equals(o.getTransac_status());
            if (!isOwner && !isTableCompanion) {
                return R.error(403, "无权查看该订单");
            }
            return result;
        }
        return R.error(403, "无权查看该订单");
    }

   

    /**
     * 获取 AI 推荐使用的已上架菜单（onsale=true），带短期缓存降低查库压力。
     * 优先使用 AI 会话上下文中的门店；无会话上下文时回退总部菜单。
     */
    private List<Category> getOnSaleMenuForAi() {
        AiSuggestSession sess = AI_SUGGEST_SESSION.get();
        Integer sid = sess != null ? sess.shopId : null;
        return getOnSaleMenuForAi(sid);
    }

    /**
     * 门店维度 AI 菜单（方案 A）：有 shopId 时按门店挂载菜品 + 覆盖列出菜，
     * 缓存 key 含门店维度；无 shopId 时回退总部菜单（与旧行为一致）。
     */
    private List<Category> getOnSaleMenuForAi(Integer shopId) {
        if (shopId == null) {
            return getOnSaleMenuForAiHq();
        }
        final String cacheKey = "onsale_menu_" + shopId;
        List<Category> cached = aiOnSaleMenuCache.getIfPresent(cacheKey);
        if (cached != null) {
            return cached;
        }
        List<DishShop> shopLinks = dishShopMapper.selectList(new QueryWrapper<DishShop>()
                .eq("shop_id", shopId));
        if (shopLinks == null || shopLinks.isEmpty()) {
            List<Category> empty = new ArrayList<>();
            aiOnSaleMenuCache.put(cacheKey, empty);
            return empty;
        }
        Map<Integer, DishShop> meta = shopLinks.stream()
                .filter(l -> l != null && l.getDish_id() != null)
                .collect(Collectors.toMap(DishShop::getDish_id, l -> l, (a, b) -> a));
        List<Dish> allDishes = dishService.list(new QueryWrapper<Dish>().in("id", meta.keySet()));
        DishShopOverrides.apply(allDishes, meta);
        Map<Integer, List<Dish>> byType = new HashMap<>();
        for (Dish d : allDishes) {
            if (d == null || !d.isOnsale()) {
                continue;
            }
            Integer tid = d.getTypeId();
            byType.computeIfAbsent(tid, k -> new ArrayList<>()).add(d);
        }
        List<Category> categoryList = categoryService.list(new QueryWrapper<Category>().orderByAsc("cid"));
        for (Category category : categoryList) {
            category.setDishList(byType.getOrDefault(category.getId(), Collections.emptyList()));
        }
        DishCustomerMenuFilters.dropCategoriesWithNoDishes(categoryList);
        aiOnSaleMenuCache.put(cacheKey, categoryList);
        return categoryList;
    }

    /** 总部菜单（原实现）：供无门店上下文时回退，缓存 key 全局。 */
    private List<Category> getOnSaleMenuForAiHq() {
        final String cacheKey = "onsale_menu";
        List<Category> cached = aiOnSaleMenuCache.getIfPresent(cacheKey);
        if (cached != null) {
            return cached;
        }
        List<Category> categoryList = categoryService.list(new QueryWrapper<Category>().orderByAsc("cid"));
        for (Category category : categoryList) {
            QueryWrapper<Dish> dq = new QueryWrapper<Dish>().eq("typeId", category.getId()).orderByAsc("sorting");
            DishCustomerMenuFilters.applyTo(dq);
            List<Dish> dishList = dishService.list(dq);
            category.setDishList(dishList);
        }
        DishCustomerMenuFilters.dropCategoriesWithNoDishes(categoryList);
        aiOnSaleMenuCache.put(cacheKey, categoryList);
        return categoryList;
    }

    /**
     * 构建用户画像摘要（仅用于 AI 推荐上下文）。
     * 包含：基础信息、可用券数量、近30单消费与偏好（高频菜品/堂食打包偏好/人均区间）。
     */
    private Map<String, Object> buildUserProfileForAi(String openid) {
        Map<String, Object> profile = new HashMap<>();
        profile.put("openid", openid);
        try {
            User user = userService.getUserByOpenid(openid);
            if (user != null) {
                profile.put("nickname", user.getName() != null ? user.getName() : "");
                profile.put("points", user.getPoints());
                profile.put("user_type", user.getUser_type());
                profile.put("birthday", user.getBirthday());
            }
        } catch (Exception e) {
            log.warn("event=ai_profile_failed");
        }
        try {
            int couponCount = CouponService.getAvailableCouponCount(openid);
            profile.put("availableCouponCount", couponCount);
        } catch (Exception e) {
            log.warn("event=ai_coupon_context_failed");
        }
        try {
            Calendar cal = Calendar.getInstance();
            cal.add(Calendar.DAY_OF_YEAR, -90);
            Date since90Days = cal.getTime();
            List<Order> orders = orderService.list(new QueryWrapper<Order>()
                    .eq("openid", openid)
                    .eq("transac_status", "success")
                    .ge("order_time", since90Days)
                    .orderByDesc("order_time")
                    .last("limit 30"));
            profile.put("recentOrderCount", orders.size());
            if (!orders.isEmpty()) {
                int dineInCount = 0;
                int takeOutCount = 0;
                double totalPay = 0d;
                int payCount = 0;
                Map<String, Integer> dishFreq = new HashMap<>();
                for (Order o : orders) {
                    if ("堂食".equals(o.getDineInOrTakeOut())) {
                        dineInCount++;
                    } else if ("打包".equals(o.getDineInOrTakeOut())) {
                        takeOutCount++;
                    }
                    double pay = (o.getSett_amount() != null ? o.getSett_amount() : 0d)
                            + (o.getService_fee() != null ? o.getService_fee() : 0d)
                            - (o.getDiscount_amount() != null ? o.getDiscount_amount() : 0d);
                    totalPay += pay;
                    payCount++;
                    if (o.getId() != null) {
                        List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", o.getId()));
                        for (OrderDetail d : details) {
                            if (d.getName() == null) continue;
                            dishFreq.put(d.getName(), dishFreq.getOrDefault(d.getName(), 0) + 1);
                        }
                    }
                }
                profile.put("dineInPreference", dineInCount >= takeOutCount ? "堂食偏好" : "打包偏好");
                profile.put("avgPaidAmount", payCount > 0 ? Math.round((totalPay / payCount) * 100) / 100.0 : 0d);
                List<String> topDishes = dishFreq.entrySet().stream()
                        .sorted((a, b) -> Integer.compare(b.getValue(), a.getValue()))
                        .limit(5)
                        .map(Map.Entry::getKey)
                        .collect(Collectors.toList());
                profile.put("topDishes", topDishes);
            }
        } catch (Exception e) {
            log.warn("event=ai_order_profile_failed");
        }
        return profile;
    }

    // ---------- payment module bridge (P2) ----------

    public void paymentValidateCoupon(OrderDTO order, boolean isAddDishes) {
        validateCoupon(order, isAddDishes);
    }

    public R paymentFillPayableAmountContext(Order order, Long couponId, String openidForCoupon,
                                             PayableAmountContext ctx) {
        return fillPayableAmountContext(order, couponId, openidForCoupon, ctx);
    }

    public R paymentSettleOrderPayableAmounts(Order order, Long couponId, String openidForCoupon, boolean allowNineFold) {
        return settleOrderPayableAmounts(order, couponId, openidForCoupon, allowNineFold);
    }

    public void paymentRunPostPaymentSuccessSideEffects(Order latestOrder, double paidYuan) {
        paymentSuccessHandler.run(latestOrder, paidYuan);
    }

    public void paymentDoAutoAcceptAndPrint(Order order) {
        doAutoAcceptAndPrint(order);
    }

    public String paymentGeneratePrintContent(Order order, boolean type) {
        return generatePrintContent(order, type);
    }

    public R paymentExecuteWxJsapiPrepay(Order order, String orderNo, String openid, String takeOut,
                                           double paidYuan, String merchantIdInput, String wxDescription) {
        if (paymentFacadeProperties.isUseFacade()) {
            return wechatJsapiChannel.createPrepay(order, orderNo, openid, takeOut,
                    paidYuan, merchantIdInput, wxDescription);
        }
        return executeWxJsapiPrepay(order, orderNo, openid, takeOut, paidYuan, merchantIdInput, wxDescription);
    }

    public String paymentGenerateOrderNo() {
        return generateOrderNo();
    }

    public String paymentGenerateRechargeOrderNo() {
        return generateRechargeOrderNo();
    }
    private void logOrder(String orderNo, String action, String operatorType, String operatorId, Integer shopId, String remark) {
        if (orderLogService == null || orderNo == null || orderNo.isEmpty()) {
            return;
        }
        try {
            OrderLog logRow = new OrderLog();
            logRow.setShop_id(shopId);
            logRow.setOrder_no(orderNo);
            logRow.setAction(action);
            logRow.setOperator_type(operatorType);
            logRow.setOperator_id(operatorId);
            logRow.setRemark(remark);
            orderLogService.save(logRow);
        } catch (Exception e) {
            log.warn("订单日志写入失败 order_no={} action={}: {}", orderNo, action, e.getMessage());
        }
    }
}
