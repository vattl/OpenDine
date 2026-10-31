package com.lanf.controller.admin;

import com.lanf.entity.Banner;
import com.lanf.entity.R;
import com.lanf.config.ApiPermissionMapping;
import com.lanf.service.IBannerService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AdminOrderControllerBannerTest {

    @Mock
    private IBannerService bannerService;

    private AdminOrderController controller;

    @BeforeEach
    void setUp() {
        controller = new AdminOrderController();
        ReflectionTestUtils.setField(controller, "bannerService", bannerService);
    }

    @Test
    void updateBannerUsesPathIdAndPersistsEditableFields() {
        Banner existing = new Banner();
        existing.setId(3);
        when(bannerService.getById(3)).thenReturn(existing);
        when(bannerService.updateBannerInfo(argThat(banner ->
                banner.getId() == 3
                        && "new.png".equals(banner.getImage())
                        && "/campaign".equals(banner.getUrl())
                        && banner.getStatus() == 0
                        && "bottom".equals(banner.getType())))).thenReturn(true);

        Banner update = new Banner();
        update.setId(99);
        update.setImage("new.png");
        update.setUrl("/campaign");
        update.setStatus(0);
        update.setType("bottom");

        R response = controller.updateBanner(3, update);

        assertEquals(0, response.get("code"));
        verify(bannerService).updateBannerInfo(update);
        assertEquals(3, update.getId());
    }

    @Test
    void updateBannerRejectsMissingBanner() {
        when(bannerService.getById(404)).thenReturn(null);

        R response = controller.updateBanner(404, new Banner());

        assertEquals(404, response.get("code"));
    }

    @Test
    void updateBannerRejectsUnsupportedStatusWithoutWriting() {
        Banner existing = new Banner();
        existing.setId(3);
        when(bannerService.getById(3)).thenReturn(existing);
        Banner update = new Banner();
        update.setStatus(2);

        R response = controller.updateBanner(3, update);

        assertEquals(400, response.get("code"));
        verify(bannerService, never()).updateBannerInfo(update);
    }

    @Test
    void bannerUpdateRouteRequiresBannerManagePermission() {
        assertEquals(
                "banner:manage",
                ApiPermissionMapping.getRequiredPermission("/admin/order/update_banners/3"));
    }
}
