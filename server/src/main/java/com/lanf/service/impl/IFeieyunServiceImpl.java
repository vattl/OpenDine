package com.lanf.service.impl;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.service.IFeieyunService;
import org.apache.commons.codec.digest.DigestUtils;
import org.apache.http.HttpEntity;
import org.apache.http.NameValuePair;
import org.apache.http.client.config.RequestConfig;
import org.apache.http.client.entity.UrlEncodedFormEntity;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.message.BasicNameValuePair;
import org.apache.http.util.EntityUtils;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

/**
 * 飞鹅云打印服务实现。
 *
 * <p>凭据一律由调用方传入（apiUrl / user / ukey），本类不再依赖门店配置表
 * （t_shop_printer_config）或全局配置（feieyun.*），保证设备参数单一来源为
 * {@code t_printing_device.connection_json}。</p>
 */
@Service
public class IFeieyunServiceImpl implements IFeieyunService {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    @Override
    public String printWithCredential(String apiUrl, String user, String ukey,
                                      String sn, String content, int times) throws IOException {
        List<NameValuePair> params = new ArrayList<>();
        if (!StringUtils.hasText(sn)) {
            throw new IOException("打印机 SN 不能为空");
        }
        params.add(new BasicNameValuePair("sn", sn));
        params.add(new BasicNameValuePair("content", content));
        params.add(new BasicNameValuePair("times", String.valueOf(times)));
        params.add(new BasicNameValuePair("apiname", "Open_printMsg"));

        return sendRequest(params, apiUrl, user, ukey);
    }

    @Override
    public String printLabelMsgWithCredential(String apiUrl, String user, String ukey,
                                              String sn, String content, int times) throws IOException {
        List<NameValuePair> params = new ArrayList<>();
        if (!StringUtils.hasText(sn)) {
            throw new IOException("打印机 SN 不能为空");
        }
        params.add(new BasicNameValuePair("sn", sn));
        params.add(new BasicNameValuePair("content", content));
        params.add(new BasicNameValuePair("times", String.valueOf(times)));
        params.add(new BasicNameValuePair("apiname", "Open_printLabelMsg"));

        return sendRequest(params, apiUrl, user, ukey);
    }

    @Override
    public String queryOrderStateWithCredential(String apiUrl, String user, String ukey,
                                                String orderId) throws IOException {
        List<NameValuePair> params = new ArrayList<>();
        params.add(new BasicNameValuePair("orderid", orderId));
        params.add(new BasicNameValuePair("apiname", "Open_queryOrderState"));

        return sendRequest(params, apiUrl, user, ukey);
    }

    @Override
    public String queryPrinterStatusWithCredential(String apiUrl, String user, String ukey,
                                                   String sn) throws IOException {
        List<NameValuePair> params = new ArrayList<>();
        params.add(new BasicNameValuePair("sn", sn));
        params.add(new BasicNameValuePair("apiname", "Open_queryPrinterStatus"));

        return sendRequest(params, apiUrl, user, ukey);
    }

    @Override
    public String addPrinterWithCredential(String apiUrl, String user, String ukey,
                                           String snList) throws IOException {
        List<NameValuePair> params = new ArrayList<>();
        params.add(new BasicNameValuePair("printerContent", snList));
        params.add(new BasicNameValuePair("apiname", "Open_printerAddlist"));

        return sendRequest(params, apiUrl, user, ukey);
    }

    @Override
    public String deletePrinterWithCredential(String apiUrl, String user, String ukey,
                                              String snList) throws IOException {
        List<NameValuePair> params = new ArrayList<>();
        params.add(new BasicNameValuePair("snlist", snList));
        params.add(new BasicNameValuePair("apiname", "Open_printerDelList"));

        return sendRequest(params, apiUrl, user, ukey);
    }

    @Override
    public String clearPrintQueueWithCredential(String apiUrl, String user, String ukey,
                                                String sn) throws IOException {
        List<NameValuePair> params = new ArrayList<>();
        params.add(new BasicNameValuePair("sn", sn));
        params.add(new BasicNameValuePair("apiname", "Open_delPrinterSqs"));

        return sendRequest(params, apiUrl, user, ukey);
    }

    private String sendRequest(List<NameValuePair> params, String apiUrl, String user, String ukey) throws IOException {
        if (!StringUtils.hasText(user) || !StringUtils.hasText(ukey)) {
            throw new IOException("飞鹅云凭据缺失(user/ukey为空)，请先在打印设备中配置飞鹅云参数");
        }
        if (!StringUtils.hasText(apiUrl)) {
            throw new IOException("飞鹅云接口地址未配置，请在打印设备的 connection 中配置 url/apiUrl");
        }

        // 添加公共参数
        String stime = String.valueOf(System.currentTimeMillis() / 1000);
        params.add(0, new BasicNameValuePair("user", user));
        params.add(1, new BasicNameValuePair("stime", stime));
        params.add(2, new BasicNameValuePair("sig", generateSignature(user, ukey, stime)));

        // 创建HTTP客户端和请求
        RequestConfig requestConfig = RequestConfig.custom()
                .setSocketTimeout(30000)
                .setConnectTimeout(30000)
                .build();

        try (CloseableHttpClient httpClient = HttpClients.custom()
                .setDefaultRequestConfig(requestConfig)
                .build()) {

            HttpPost post = new HttpPost(apiUrl);
            post.setEntity(new UrlEncodedFormEntity(params, "utf-8"));

            try (CloseableHttpResponse response = httpClient.execute(post)) {
                int stateCode = response.getStatusLine().getStatusCode();
                if (stateCode == 200) {
                    HttpEntity entity = response.getEntity();
                    String body = entity != null ? EntityUtils.toString(entity) : null;
                    return requireSuccessfulResponse(body);
                } else {
                    throw new IOException("HTTP request failed with status code: " + stateCode);
                }
            }
        }
    }

    static String requireSuccessfulResponse(String responseBody) throws IOException {
        if (!StringUtils.hasText(responseBody)) {
            throw new IOException("飞鹅云返回为空");
        }
        try {
            JsonNode root = OBJECT_MAPPER.readTree(responseBody);
            JsonNode ret = root != null ? root.get("ret") : null;
            if (ret == null || !ret.isNumber()) {
                throw new IOException("飞鹅云返回格式不合法");
            }
            if (ret.asInt() != 0) {
                JsonNode msg = root.get("msg");
                String message = msg != null && !msg.isNull() ? msg.asText() : "未知错误";
                throw new IOException("飞鹅云请求失败(ret=" + ret.asInt() + "): " + message);
            }
            return responseBody;
        } catch (IOException e) {
            throw e;
        } catch (Exception e) {
            throw new IOException("飞鹅云返回格式不合法", e);
        }
    }

    private static String generateSignature(String user, String ukey, String stime) {
        return DigestUtils.sha1Hex(user + ukey + stime);
    }
}
