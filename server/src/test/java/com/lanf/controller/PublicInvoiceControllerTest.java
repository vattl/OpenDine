package com.lanf.controller;

import com.lanf.entity.R;
import com.lanf.service.IOrderInvoiceService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.CrossOrigin;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class PublicInvoiceControllerTest {

    private MockMvc mockMvc;

    @Mock
    private IOrderInvoiceService orderInvoiceService;

    @InjectMocks
    private PublicInvoiceController publicInvoiceController;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.initMocks(this);
        mockMvc = MockMvcBuilders.standaloneSetup(publicInvoiceController).build();
    }

    @Test
    void controllerHasCrossOriginAnnotation() {
        CrossOrigin crossOrigin = PublicInvoiceController.class.getAnnotation(CrossOrigin.class);
        assertNotNull(crossOrigin, "PublicInvoiceController 必须具备 @CrossOrigin 注解以彻底防止跨域拦截");
    }

    @Test
    void getInvoiceInfo_allCandidateRoutesSupported() throws Exception {
        Map<String, Object> data = new HashMap<>();
        data.put("orderNo", "ORD20261028001");
        data.put("invoiceAmount", 128.50);
        data.put("invoiceStatus", "PENDING_SCAN");

        when(orderInvoiceService.getInvoiceInfoForPublic(eq("ORD20261028001"), any(), eq("token_valid_123")))
                .thenReturn(R.ok().put("code", 200).put("data", data));

        String[] routes = new String[]{
                "/public/invoice/info",
                "/api/invoice/info",
                "/order/invoice/public/info"
        };

        for (String route : routes) {
            mockMvc.perform(get(route)
                            .param("orderNo", "ORD20261028001")
                            .param("token", "token_valid_123")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.code").value(200))
                    .andExpect(jsonPath("$.data.orderNo").value("ORD20261028001"))
                    .andExpect(jsonPath("$.data.invoiceAmount").value(128.50));
        }
    }

    @Test
    void getInvoiceInfo_missingToken_returns400BadRequest() throws Exception {
        mockMvc.perform(get("/public/invoice/info")
                        .param("orderNo", "ORD20261028001")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isBadRequest());
    }

    @Test
    void submitInvoice_allCandidateRoutesSupported() throws Exception {
        when(orderInvoiceService.submitInvoiceTitleFromCustomer(
                eq("ORD20261028001"), any(), eq("token_valid_123"), eq("COMPANY"),
                eq("北京老肥家餐饮管理有限公司"), eq("91110108MA00000000"),
                eq("finance@laofei.com"), any()))
                .thenReturn(R.ok("提交成功").put("code", 200));

        String requestJson = "{" +
                "\"orderNo\":\"ORD20261028001\"," +
                "\"token\":\"token_valid_123\"," +
                "\"titleType\":\"COMPANY\"," +
                "\"buyerTitle\":\"北京老肥家餐饮管理有限公司\"," +
                "\"buyerTaxNo\":\"91110108MA00000000\"," +
                "\"buyerEmail\":\"finance@laofei.com\"" +
                "}";

        String[] routes = new String[]{
                "/public/invoice/submit",
                "/api/invoice/submit",
                "/order/invoice/public/submit"
        };

        for (String route : routes) {
            mockMvc.perform(post(route)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(requestJson))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.code").value(200));
        }
    }

    @Test
    void submitInvoice_missingToken_returns401() throws Exception {
        String requestJson = "{" +
                "\"orderNo\":\"ORD20261028001\"," +
                "\"titleType\":\"COMPANY\"," +
                "\"buyerTitle\":\"北京老肥家餐饮管理有限公司\"" +
                "}";

        mockMvc.perform(post("/public/invoice/submit")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(401));
    }
}
