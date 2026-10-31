package com.lanf.integration.amap;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.config.AmapRouteProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/**
 * 高德路径规划：返回起终点间路网距离（公里）。
 */
@Component
public class AmapDirectionClient {

    private static final Logger log = LoggerFactory.getLogger(AmapDirectionClient.class);
    private static final int CONNECT_MS = 8000;
    private static final int READ_MS = 12000;

    private final ObjectMapper mapper = new ObjectMapper();

    @Autowired
    private AmapRouteProperties properties;

    /**
     * @return 路网距离（公里）；失败返回 {@code null}
     */
    public Double routeDistanceKm(double originLng, double originLat, double destLng, double destLat) {
        if (!properties.isRouteDistanceEnabled() || !properties.hasWebKey()) {
            return null;
        }
        String mode = properties.getRouteMode() != null ? properties.getRouteMode().trim().toLowerCase() : "driving";
        try {
            if ("bicycling".equals(mode) || "riding".equals(mode)) {
                return parseBicyclingV4(requestBicycling(originLng, originLat, destLng, destLat));
            }
            return parseDrivingV3(requestDriving(originLng, originLat, destLng, destLat));
        } catch (Exception e) {
            log.warn("高德路径规划失败: {}", e.getMessage());
            return null;
        }
    }

    private String requestDriving(double oLng, double oLat, double dLng, double dLat) throws Exception {
        String origin = oLng + "," + oLat;
        String destination = dLng + "," + dLat;
        String url = "https://restapi.amap.com/v3/direction/driving?origin="
                + enc(origin) + "&destination=" + enc(destination)
                + "&extensions=base&strategy=0&key=" + enc(properties.getWebKey().trim());
        return httpGet(url);
    }

    private String requestBicycling(double oLng, double oLat, double dLng, double dLat) throws Exception {
        String origin = oLng + "," + oLat;
        String destination = dLng + "," + dLat;
        String url = "https://restapi.amap.com/v4/direction/bicycling?origin="
                + enc(origin) + "&destination=" + enc(destination)
                + "&key=" + enc(properties.getWebKey().trim());
        return httpGet(url);
    }

    static Double parseDrivingV3(String json) throws Exception {
        if (json == null || json.isEmpty()) {
            return null;
        }
        JsonNode root = new ObjectMapper().readTree(json);
        if (!"1".equals(text(root, "status"))) {
            return null;
        }
        JsonNode paths = root.path("route").path("paths");
        if (!paths.isArray() || paths.size() == 0) {
            return null;
        }
        String meters = text(paths.get(0), "distance");
        return metersToKm(meters);
    }

    Double parseBicyclingV4(String json) throws Exception {
        if (json == null || json.isEmpty()) {
            return null;
        }
        JsonNode root = mapper.readTree(json);
        if (root.path("errcode").asInt(-1) != 0) {
            return null;
        }
        JsonNode paths = root.path("data").path("paths");
        if (!paths.isArray() || paths.size() == 0) {
            return null;
        }
        JsonNode dist = paths.get(0).get("distance");
        if (dist == null || dist.isNull()) {
            return null;
        }
        double meters = dist.isNumber() ? dist.asDouble() : Double.parseDouble(dist.asText().trim());
        return Math.round(meters / 10d) / 100d;
    }

    private static String text(JsonNode node, String field) {
        if (node == null || node.isMissingNode()) {
            return null;
        }
        JsonNode v = node.get(field);
        if (v == null || v.isNull()) {
            return null;
        }
        return v.asText();
    }

    private static Double metersToKm(String metersStr) {
        if (metersStr == null || metersStr.trim().isEmpty()) {
            return null;
        }
        double meters = Double.parseDouble(metersStr.trim());
        return Math.round(meters / 10d) / 100d;
    }

    private static String enc(String s) throws Exception {
        return URLEncoder.encode(s, StandardCharsets.UTF_8.name());
    }

    private static String httpGet(String urlStr) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(urlStr).openConnection();
        conn.setRequestMethod("GET");
        conn.setConnectTimeout(CONNECT_MS);
        conn.setReadTimeout(READ_MS);
        try {
            int code = conn.getResponseCode();
            java.io.InputStream in = code >= 400 ? conn.getErrorStream() : conn.getInputStream();
            if (in == null) {
                return "";
            }
            StringBuilder sb = new StringBuilder();
            try (BufferedReader br = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
                String line;
                while ((line = br.readLine()) != null) {
                    sb.append(line);
                }
            }
            return sb.toString();
        } finally {
            conn.disconnect();
        }
    }
}
