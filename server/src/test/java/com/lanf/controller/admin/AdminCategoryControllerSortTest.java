package com.lanf.controller.admin;

import com.lanf.entity.Category;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.ICategoryService;
import com.lanf.service.ShopMenuSortService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import javax.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AdminCategoryControllerSortTest {

    private AdminCategoryController controller;
    private ShopMenuSortService sortService;
    private HttpServletRequest request;

    @BeforeEach
    void setUp() {
        controller = new AdminCategoryController();
        sortService = mock(ShopMenuSortService.class);
        request = mock(HttpServletRequest.class);
        ReflectionTestUtils.setField(controller, "categoryService", mock(ICategoryService.class));
        ReflectionTestUtils.setField(controller, "shopMenuSortService", sortService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);
    }

    @Test
    void delegatesSortToCurrentShop() {
        when(request.getAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID)).thenReturn(5);
        when(sortService.sortCategories(5, 3, 1)).thenReturn(category(3));

        R result = controller.sort(sortBody(3, 1));

        assertEquals(0, result.get("code"));
        verify(sortService).sortCategories(5, 3, 1);
    }

    @Test
    void missingShopContextReturnsStableBusinessError() {
        when(sortService.sortCategories(null, 3, 1)).thenThrow(
                new ShopMenuSortService.MenuSortException(4001,
                        "缺少门店上下文，请传 X-Shop-Id 或 X-Shop-Code"));

        R result = controller.sort(sortBody(3, 1));

        assertEquals(4001, result.get("code"));
    }

    private static Category category(int id) {
        Category category = new Category();
        category.setId(id);
        return category;
    }

    private static Map<String, Integer> sortBody(int id, int targetIndex) {
        Map<String, Integer> body = new HashMap<>();
        body.put("id", id);
        body.put("targetIndex", targetIndex);
        return body;
    }
}
