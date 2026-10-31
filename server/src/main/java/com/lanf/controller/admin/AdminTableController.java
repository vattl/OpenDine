package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.alibaba.fastjson.JSON;
import com.alibaba.fastjson.JSONObject;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.PageBean;
import com.lanf.entity.R;
import com.lanf.entity.Table;
import com.lanf.entity.User;
import com.lanf.properties.WeixinProperties;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITableService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.IUserService;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.DateUtil;
import com.lanf.util.HttpClientUtil;
import com.lanf.util.TableStatusAmountCalculator;
import org.apache.http.HttpResponse;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClientBuilder;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.*;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.HashSet;

/**
 * 桌号管理
 */
@RestController
@RequestMapping("/admin/table")
public class AdminTableController {

    @Autowired
    private ITableService tableService;

    @Autowired
    private IOrderService orderService;

    @Autowired
    private IOrderDetailService orderDetailService;

    @Autowired
    private IUserService userService;

    @Autowired
    private ITakeoutDeliveryService takeoutDeliveryService;

    @Autowired
    private WeixinProperties weixinProperties;

    @Autowired
    HttpClientUtil httpClientUtil;
    @Autowired
    private HttpServletRequest httpServletRequest;

    @Value("${qrcodeImgsFilePath}")
    private String qrcodeImgsFilePath;

    /**
     * 添加
     * @param table
     * @return
     */
    @PostMapping("/add")
    @AuditLog(module = "table", action = "admin_table_add", target = "#p0.id")
    public R add(@RequestBody Table table){
        if (table == null || table.getNumber() == null || table.getNumber().trim().isEmpty()) {
            return R.error("桌号不能为空");
        }
        table.setNumber(table.getNumber().trim());

        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (shopId != null) {
            table.setShop_id(shopId);
        }

        QueryWrapper<Table> qw = new QueryWrapper<Table>().eq("number", table.getNumber());
        if (table.getShop_id() != null) {
            qw.eq("shop_id", table.getShop_id());
        }
        if (tableService.count(qw) > 0) {
            return R.error("桌号 " + table.getNumber() + " 已存在");
        }

        if (table.getArea_code() != null && !table.getArea_code().trim().isEmpty()) {
            table.setArea_code(table.getArea_code().trim());
            if (table.getArea_name() == null || table.getArea_name().trim().isEmpty()) {
                if ("box".equalsIgnoreCase(table.getArea_code())) {
                    table.setArea_name("特色包厢");
                } else if ("patio".equalsIgnoreCase(table.getArea_code())) {
                    table.setArea_name("露天外摆");
                } else {
                    table.setArea_name("大厅散座");
                }
            } else {
                table.setArea_name(table.getArea_name().trim());
            }
        } else {
            table.setArea_code("hall");
            table.setArea_name("大厅散座");
        }

        try {
            String token = this.getAccessToken();
            if (token != null && !token.trim().isEmpty()) {
                table.setQrcode(genQrCodeImage(token, table.getNumber(), table.getShop_id()));
            }
        } catch (Exception e) {
            // 离线环境或未配置微信凭证时容错，不阻断桌台创建
        }

        table.setStatus(0);
        if(tableService.save(table)){
            return R.ok("添加成功");
        }else {
            return R.error("添加失败");
        }

    }

    /**
     * 修改桌台信息（桌号、所属区域等）
     * @param table
     * @return
     */
    @PostMapping("/update")
    @AuditLog(module = "table", action = "admin_table_update", target = "#p0.id")
    public R update(@RequestBody Table table) {
        if (table == null || table.getId() == null) {
            return R.error("桌台ID不能为空");
        }
        Table existing = tableService.getById(table.getId());
        if (existing == null) {
            return R.error("桌台不存在");
        }
        R err = assertTableInCurrentShop(existing);
        if (err != null) {
            return err;
        }

        if (table.getNumber() != null && !table.getNumber().trim().isEmpty()
                && !table.getNumber().trim().equals(existing.getNumber())) {
            String newNumber = table.getNumber().trim();
            QueryWrapper<Table> qw = new QueryWrapper<Table>()
                    .eq("number", newNumber)
                    .ne("id", existing.getId());
            if (existing.getShop_id() != null) {
                qw.eq("shop_id", existing.getShop_id());
            }
            if (tableService.count(qw) > 0) {
                return R.error("桌号 " + newNumber + " 已存在");
            }
            existing.setNumber(newNumber);
        }

        if (table.getArea_code() != null && !table.getArea_code().trim().isEmpty()) {
            existing.setArea_code(table.getArea_code().trim());
            if (table.getArea_name() != null && !table.getArea_name().trim().isEmpty()) {
                existing.setArea_name(table.getArea_name().trim());
            } else {
                if ("box".equalsIgnoreCase(table.getArea_code())) {
                    existing.setArea_name("特色包厢");
                } else if ("patio".equalsIgnoreCase(table.getArea_code())) {
                    existing.setArea_name("露天外摆");
                } else {
                    existing.setArea_name("大厅散座");
                }
            }
        }

        if (tableService.updateById(existing)) {
            return R.ok("修改成功");
        } else {
            return R.error("修改失败");
        }
    }

    /**
     * 删除
     * @param id
     * @return
     */
    @GetMapping("/delete")
    public R delete(Integer id){
        if (id == null) {
            return R.error("桌台ID不能为空");
        }
        Table t = tableService.getById(id);
        if (t == null) {
            return R.error("桌台不存在");
        }
        R err = assertTableInCurrentShop(t);
        if (err != null) {
            return err;
        }
        if (t.getStatus() != null && t.getStatus() != 0) {
            return R.error("该桌台当前在使用中，请先结账或清台后再删除");
        }
        boolean removed = tableService.removeById(id);
        if (removed) {
            deleteQrcodeFileIfExists(t);
        }
        return R.ok();
    }

    /**
     * 清台：若该桌关联订单处于未结账状态则不允许清台。
     */
    @PostMapping("/open")
    @AuditLog(module = "table", action = "admin_table_open")
    public R open(@RequestBody Map<String, Object> body) {
        return R.error(410, "该接口已弃用，请使用 /cashier/table/open");
    }

    @GetMapping("/out")
    public R out(Integer id){
        return R.error(410, "该接口已弃用，请使用 /cashier/table/clear");
    }

    /**
     * 获取或生成桌台微信小程序码（返回 PNG 二进制图）
     * 入参：number（桌号）或 id（桌台ID）
     */
    @GetMapping("/qrcode")
    public ResponseEntity<byte[]> getTableQrcode(@RequestParam(name = "number", required = false) String number,
                                                 @RequestParam(name = "id", required = false) Integer id) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        QueryWrapper<Table> qw = new QueryWrapper<>();
        if (id != null) {
            qw.eq("id", id);
        } else if (number != null && !number.trim().isEmpty()) {
            qw.eq("number", number.trim());
        } else {
            return ResponseEntity.badRequest().build();
        }
        if (shopId != null) {
            qw.eq("shop_id", shopId);
        }
        Table table = tableService.getOne(qw);
        if (table == null) {
            return ResponseEntity.notFound().build();
        }

        // 1. 如果已有图片且本地文件存在，直接读取
        if (table.getQrcode() != null && !table.getQrcode().trim().isEmpty()) {
            String fileName = table.getQrcode().trim();
            int slash = Math.max(fileName.lastIndexOf('/'), fileName.lastIndexOf('\\'));
            if (slash >= 0 && slash < fileName.length() - 1) {
                fileName = fileName.substring(slash + 1);
            }
            File file = new File(qrcodeImgsFilePath, fileName);
            if (file.exists() && file.length() > 0) {
                try {
                    byte[] bytes = java.nio.file.Files.readAllBytes(file.toPath());
                    return ResponseEntity.ok()
                            .header(HttpHeaders.CONTENT_TYPE, MediaType.IMAGE_PNG_VALUE)
                            .body(bytes);
                } catch (IOException e) {
                    e.printStackTrace();
                }
            }
        }

        // 2. 否则向微信获取生成小程序码并持久化
        try {
            String token = this.getAccessToken();
            if (token != null && !token.trim().isEmpty()) {
                String newFileName = genQrCodeImage(token, table.getNumber(), table.getShop_id());
                if (newFileName != null) {
                    table.setQrcode(newFileName);
                    tableService.updateById(table);
                    File file = new File(qrcodeImgsFilePath, newFileName);
                    if (file.exists() && file.length() > 0) {
                        byte[] bytes = java.nio.file.Files.readAllBytes(file.toPath());
                        return ResponseEntity.ok()
                                .header(HttpHeaders.CONTENT_TYPE, MediaType.IMAGE_PNG_VALUE)
                                .body(bytes);
                    }
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return ResponseEntity.status(500).build();
    }

    /**
     * 获取桌台状态（B 端）：可按桌号或订单号查询；订单号会先在当前门店内解析桌号。
     */
    @GetMapping("/status")
    public R status(@RequestParam(name = "number", required = false) String number,
                    @RequestParam(name = "orderNo", required = false) String orderNo,
                    @RequestParam(name = "order_no", required = false) String orderNoSnake) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        String tableNumber = trimToNull(number);
        String camelOrderNo = trimToNull(orderNo);
        String snakeOrderNo = trimToNull(orderNoSnake);
        if (camelOrderNo != null && snakeOrderNo != null && !camelOrderNo.equals(snakeOrderNo)) {
            return R.error("orderNo 与 order_no 不一致");
        }
        String requestedOrderNo = camelOrderNo != null ? camelOrderNo : snakeOrderNo;
        Order requestedOrder = null;
        if (requestedOrderNo != null) {
            QueryWrapper<Order> orderQuery = new QueryWrapper<Order>()
                    .eq("order_no", requestedOrderNo);
            if (shopId != null) {
                orderQuery.eq("shop_id", shopId);
            }
            requestedOrder = orderService.getOne(orderQuery.last("LIMIT 1"));
            if (requestedOrder == null) {
                return R.error("订单不存在");
            }
            String orderTableNumber = trimToNull(requestedOrder.getTable_number());
            if (tableNumber != null && !tableNumber.equals(orderTableNumber)) {
                return R.error("订单号与桌号不匹配");
            }
            if (tableNumber == null) {
                tableNumber = orderTableNumber;
            }
        }

        QueryWrapper<Table> q = new QueryWrapper<Table>().orderByAsc("number");
        if (shopId != null) {
            q.eq("shop_id", shopId);
        }
        if (tableNumber != null) {
            q.eq("number", tableNumber);
        }
        List<Table> tableList = requestedOrderNo != null && tableNumber == null
                ? Collections.emptyList()
                : tableService.list(q);
        Map<String, Object> resultMap = new HashMap<>();
        resultMap.put("tableList", tableList);
        resultMap.put("total", tableList.size());
        Table table = tableList.isEmpty() ? null : tableList.get(0);
        List<Order> orderList = null;
        if (requestedOrder != null) {
            if ("unsettled".equals(requestedOrder.getTransac_status()) && tableNumber != null) {
                orderList = listUnsettledTableOrders(tableNumber, shopId);
                if (!containsOrderNo(orderList, requestedOrder.getOrder_no())) {
                    orderList = Collections.singletonList(requestedOrder);
                }
            } else {
                orderList = Collections.singletonList(requestedOrder);
            }
        } else if (tableNumber != null && table != null) {
            // A merged table can own multiple orders. The table order_no is only a compatibility pointer.
            orderList = listUnsettledTableOrders(table.getNumber(), shopId);
            // 已结账待清台（status=2）：无论是否存在未结订单，都把该桌最近一笔已结订单
            // 并入返回，保证“收款自动到账 / 退菜”之后收银端进入桌台仍能看到账单明细，
            // 而不是退回空点单。优先用 table.order_no 指针，其次按桌号回退查最近已结单。
            if (Integer.valueOf(2).equals(table.getStatus())) {
                String pointerNo = trimToNull(table.getOrder_no());
                Order settledOrder = null;
                if (pointerNo != null) {
                    QueryWrapper<Order> pointerQuery = new QueryWrapper<Order>()
                            .eq("order_no", pointerNo);
                    if (shopId != null) {
                        pointerQuery.eq("shop_id", shopId);
                    }
                    settledOrder = orderService.getOne(pointerQuery.last("LIMIT 1"));
                }
                if (settledOrder == null) {
                    QueryWrapper<Order> fallbackQuery = new QueryWrapper<Order>()
                            .eq("table_number", table.getNumber())
                            .ne("transac_status", "unsettled")
                            .orderByDesc("id");
                    if (shopId != null) {
                        fallbackQuery.eq("shop_id", shopId);
                    }
                    settledOrder = orderService.getOne(fallbackQuery.last("LIMIT 1"));
                }
                if (settledOrder != null
                        && !containsOrderNo(orderList, settledOrder.getOrder_no())) {
                    List<Order> merged = new ArrayList<>(orderList);
                    merged.add(settledOrder);
                    orderList = merged;
                }
            }
        }

        if (orderList != null) {
            List<Map<String, Object>> amountAudits = new ArrayList<>();
            double tablePayable = 0d;
            enrichMemberPhones(orderList);
            for (Order order : orderList) {
                takeoutDeliveryService.enrichOrder(order);
                List<OrderDetail> goodsList = orderDetailService.list(
                    new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
                order.setGoods_list(goodsList);
                TableStatusAmountCalculator.Result amount = TableStatusAmountCalculator.calculate(order, goodsList);
                tablePayable += amount.getPayableAmount();
                Map<String, Object> audit = amount.toMap();
                audit.put("order_no", order.getOrder_no());
                audit.put("table_number", tableNumber);
                amountAudits.add(audit);
            }
            tablePayable = Math.round(tablePayable * 100d) / 100d;
            if (table != null && (requestedOrder == null
                    || "unsettled".equals(requestedOrder.getTransac_status())
                    || requestedOrder.getOrder_no().equals(trimToNull(table.getOrder_no())))) {
                table.setAmount(tablePayable);
            }
            resultMap.put("orderList", orderList);
            resultMap.put("amountAudits", amountAudits);
            if (amountAudits.size() == 1) {
                resultMap.put("amountAudit", amountAudits.get(0));
            } else {
                Map<String, Object> aggregateAudit = new LinkedHashMap<>();
                aggregateAudit.put("table_number", tableNumber);
                aggregateAudit.put("order_count", orderList.size());
                aggregateAudit.put("payable_amount", tablePayable);
                aggregateAudit.put("calculation_source", "all_current_table_orders");
                resultMap.put("amountAudit", aggregateAudit);
            }
        }
        return R.ok(resultMap);
    }

    public R status(String number) {
        return status(number, null, null);
    }

    private List<Order> listUnsettledTableOrders(String tableNumber, Integer shopId) {
        QueryWrapper<Order> activeQuery = new QueryWrapper<Order>()
                .eq("table_number", tableNumber)
                .eq("transac_status", "unsettled")
                .orderByAsc("id");
        if (shopId != null) {
            activeQuery.eq("shop_id", shopId);
        }
        return orderService.list(activeQuery);
    }

    private static String trimToNull(String value) {
        if (value == null || value.trim().isEmpty()) {
            return null;
        }
        return value.trim();
    }

    private static boolean containsOrderNo(List<Order> orders, String orderNo) {
        if (orders == null || orderNo == null) {
            return false;
        }
        for (Order order : orders) {
            if (order != null && orderNo.equals(order.getOrder_no())) {
                return true;
            }
        }
        return false;
    }

    private void enrichMemberPhones(List<Order> orders) {
        if (userService == null || orders == null || orders.isEmpty()) {
            return;
        }
        Set<String> openids = new HashSet<>();
        for (Order order : orders) {
            if (order != null && order.getOpenid() != null
                    && !order.getOpenid().trim().isEmpty()) {
                openids.add(order.getOpenid().trim());
            }
        }
        if (openids.isEmpty()) {
            return;
        }
        List<User> users = userService.list(
                new QueryWrapper<User>()
                        .select("openid", "phone")
                        .in("openid", openids));
        Map<String, String> phoneByOpenid = new HashMap<>();
        for (User user : users) {
            if (user != null && user.getOpenid() != null
                    && user.getPhone() != null
                    && !user.getPhone().trim().isEmpty()) {
                phoneByOpenid.put(user.getOpenid().trim(), user.getPhone().trim());
            }
        }
        for (Order order : orders) {
            if (order != null && order.getOpenid() != null) {
                order.setMember_phone(phoneByOpenid.get(order.getOpenid().trim()));
            }
        }
    }

    /**
     * 分页显示
     * @param pageBean
     * @return
     */
    @RequestMapping("/list")
    public R list(@RequestBody PageBean pageBean){
        if(pageBean == null || pageBean.getStart() <= 0){
            Map<String,Object> resultMap;
            resultMap = getAllTables();
            return R.ok(resultMap);
        }
        Map<String,Object> map=new HashMap<>();
        map.put("start",pageBean.getStart());
        map.put("pageSize",pageBean.getPageSize());
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (shopId != null) {
            map.put("shop_id", shopId);
        }
        List<Table> list=tableService.list(map);
        Long total =tableService.getTotal(map);
        Map<String,Object> resultMap=new HashMap<>();
        resultMap.put("tableList",list);
        resultMap.put("total",total);
        return R.ok(resultMap);
    }
    public Map<String,Object> getAllTables(){
        // 不传递分页参数，获取全部数据
        Map<String, Object> m = new HashMap<>();
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (shopId != null) {
            m.put("shop_id", shopId);
        }
        List<Table> tableList = tableService.list(m);
        Map<String,Object> resultMap=new HashMap<>();
        resultMap.put("tableList", tableList);
        // 仍然返回total字段，保持与前端数据结构一致
        resultMap.put("total", tableList.size());
        return resultMap;
    }


    public String getAccessToken(){
        String url="https://api.weixin.qq.com/cgi-bin/token" + "?grant_type=client_credential&appid=" + weixinProperties.getAppid()+ "&secret=" + weixinProperties.getSecret();
        System.out.println(url);
        String token = httpClientUtil.sendHttpGet(url);
        JSONObject jsonObject = JSON.parseObject(token);
        return jsonObject.get("access_token").toString();
    }

    /**
     * 小程序扫码入口 path：桌号 + 门店绑定（query：number、shop_id）
     */
    private String genQrCodeImage(String accessToken, String table, Integer shopId) {
        Map<String, Object> body = new HashMap<>();
        String path = "pages/index/index?number=" + table;
        if (shopId != null) {
            path += "&shop_id=" + shopId;
        }
        body.put("path", path);
        String url="https://api.weixin.qq.com/wxa/getwxacode?access_token="+accessToken;
        try {
            ByteArrayInputStream bis = new ByteArrayInputStream(getWechatQrcodeByHttpClient(url,body));
            BufferedImage image = ImageIO.read(bis);
            String newFileName=table+"_"+DateUtil.getCurrentDateStr()+".png";
            File output = new File(qrcodeImgsFilePath+newFileName);
            ImageIO.write(image, "png", output);
            return newFileName;
        } catch (IOException e) {
            e.printStackTrace();
        }
        return null;
    }

    private  byte[] getWechatQrcodeByHttpClient(String url, Map<String, Object> body) {
        CloseableHttpClient httpClient = HttpClientBuilder.create().build();
        HttpPost httpPost = new HttpPost(url);
        try {
            StringEntity entity = new StringEntity(JSONObject.toJSONString(body));
            entity.setContentType("image/png");
            httpPost.setEntity(entity);
            HttpResponse response = httpClient.execute(httpPost);
            try (InputStream inputStream = response.getEntity().getContent();
                 ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[1024];
                int len = -1;
                while ((len = inputStream.read(buffer)) != -1) {
                    out.write(buffer, 0, len);
                }
                return out.toByteArray();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return null;
    }

    private R assertTableInCurrentShop(Table table) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null || table == null) {
            return null;
        }
        if (table.getShop_id() != null && !table.getShop_id().equals(sid)) {
            return R.error(4003, "桌台不属于当前门店");
        }
        return null;
    }

    private void deleteQrcodeFileIfExists(Table table) {
        if (table == null || table.getQrcode() == null || table.getQrcode().trim().isEmpty()) {
            return;
        }
        String qrcodeValue = table.getQrcode().trim();
        String fileName = qrcodeValue;
        int slash = Math.max(qrcodeValue.lastIndexOf('/'), qrcodeValue.lastIndexOf('\\'));
        if (slash >= 0 && slash < qrcodeValue.length() - 1) {
            fileName = qrcodeValue.substring(slash + 1);
        }
        File file = new File(qrcodeImgsFilePath, fileName);
        if (file.exists()) {
            file.delete();
        }
    }

}
