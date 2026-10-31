package com.lanf.service.impl;

import org.junit.jupiter.api.Test;

import java.io.IOException;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class IFeieyunServiceImplTest {

    @Test
    void acceptsSuccessfulFeieBusinessResponse() throws Exception {
        String response = "{\"ret\":0,\"msg\":\"ok\",\"data\":\"print-order-1\"}";
        assertEquals(response, IFeieyunServiceImpl.requireSuccessfulResponse(response));
    }

    @Test
    void rejectsHttp200WithFailedFeieBusinessResponse() {
        IOException error = assertThrows(IOException.class, () ->
                IFeieyunServiceImpl.requireSuccessfulResponse(
                        "{\"ret\":-2,\"msg\":\"printer offline\",\"data\":null}"));
        assertEquals("飞鹅云请求失败(ret=-2): printer offline", error.getMessage());
    }

    @Test
    void rejectsMalformedFeieResponse() {
        assertThrows(IOException.class, () ->
                IFeieyunServiceImpl.requireSuccessfulResponse("gateway ok"));
    }

    @Test
    void acceptsClearQueueSuccessResponse() throws Exception {
        String response = "{\"ret\":0,\"msg\":\"ok\",\"data\":true}";
        assertEquals(response, IFeieyunServiceImpl.requireSuccessfulResponse(response));
    }

    @Test
    void acceptsDeletePrinterSuccessResponse() throws Exception {
        String response = "{\"ret\":0,\"msg\":\"ok\",\"data\":{\"ok\":[\"987654321\"],\"no\":[]}}";
        assertEquals(response, IFeieyunServiceImpl.requireSuccessfulResponse(response));
    }

    @Test
    void acceptsEditPrinterSuccessResponse() throws Exception {
        String response = "{\"ret\":0,\"msg\":\"ok\",\"data\":true}";
        assertEquals(response, IFeieyunServiceImpl.requireSuccessfulResponse(response));
    }
}
