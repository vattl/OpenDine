package com.lanf.service;

import com.lanf.config.ImageServeProperties;
import com.lanf.controller.OrderController;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.util.ReflectionTestUtils;
import java.nio.file.*;
import java.io.IOException;
import static org.junit.jupiter.api.Assertions.*;

class ImageSafetyTest {
    @TempDir Path directory;
    private byte[] png(int width, int height) throws Exception {
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        javax.imageio.ImageIO.write(new java.awt.image.BufferedImage(width,height,java.awt.image.BufferedImage.TYPE_INT_RGB),"png",out);
        return out.toByteArray();
    }
    @Test void validAvatarIsReencodedWithServerExtension() throws Exception {
        String url = ImageSafety.storeAvatar(new MockMultipartFile("avatar","bad.php","application/octet-stream",png(10,10)),directory.toString());
        assertTrue(url.endsWith(".png"));
        assertNotNull(javax.imageio.ImageIO.read(directory.resolve(url.substring(url.lastIndexOf('/')+1)).toFile()));
    }
    @Test void dimensionsAreCheckedBeforeDecode() throws Exception {
        byte[] data = png(20,20);
        assertThrows(IOException.class, () -> ImageSafety.decode(data,100,true));
    }
    @Test void repeatedThumbnailUsesCachedBytes() throws Exception {
        Files.write(directory.resolve("valid.png"),png(200,100));
        ImageFileServeService service = new ImageFileServeService(new ImageServeProperties());
        ReflectionTestUtils.setField(service,"dishImgsFilePath",directory.toString()); service.initRoots();
        ImageFileServeService.ServedImage result = service.serve("/image/dish/valid.png",100);
        assertSame(result,service.serve("/image/dish/valid.png",100));
        assertEquals(100,javax.imageio.ImageIO.read(new java.io.ByteArrayInputStream(result.bytes)).getWidth());
    }
    @Test void corruptRasterIsRejectedBeforeServing() throws Exception {
        Files.write(directory.resolve("bad.png"), "not-an-image".getBytes("UTF-8"));
        ImageFileServeService service = new ImageFileServeService(new ImageServeProperties());
        ReflectionTestUtils.setField(service,"dishImgsFilePath",directory.toString());
        service.initRoots();
        assertThrows(IOException.class, () -> service.serve("/image/dish/bad.png",100));
    }
    @Test void oversizedOriginalCannotBypassLimitWithoutResize() throws Exception {
        Files.write(directory.resolve("huge.jpg"), new byte[10 * 1024 * 1024 + 1]);
        ImageFileServeService service = new ImageFileServeService(new ImageServeProperties());
        ReflectionTestUtils.setField(service,"dishImgsFilePath",directory.toString());
        service.initRoots();
        assertThrows(IOException.class, () -> service.serve("/image/dish/huge.jpg",null));
    }
    @Test void avatarRejectsForgedExtension() {
        CustomerProfileService controller = new CustomerProfileService();
        ReflectionTestUtils.setField(controller,"avatarImgsFilePath",directory.toString());
        MockMultipartFile file = new MockMultipartFile("avatar","photo.png","image/png",new byte[]{1,2,3});
        assertThrows(Exception.class, () -> ReflectionTestUtils.invokeMethod(controller,"uploadAvatarFile",file));
    }
}
