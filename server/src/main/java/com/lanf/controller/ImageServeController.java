package com.lanf.controller;

import com.lanf.service.ImageFileServeService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.util.concurrent.TimeUnit;

/**
 * 图片资源：原路径访问；带 {@code q} 时服务端按宽度等比缩放后返回（如 {@code /image/dish/a.jpg?q=300}）。
 */
@RestController
public class ImageServeController {

    @Autowired
    private ImageFileServeService imageFileServeService;

    @GetMapping("/image/**")
    public ResponseEntity<byte[]> serveImage(HttpServletRequest request,
                                             @RequestParam(value = "q", required = false) Integer q) {
        String uri = request.getRequestURI();
        if (!StringUtils.hasText(uri)) {
            return ResponseEntity.notFound().build();
        }
        try {
            ImageFileServeService.ServedImage img = imageFileServeService.serve(uri, q);
            if (img == null || img.bytes == null || img.bytes.length == 0) {
                return ResponseEntity.notFound().build();
            }
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(img.mediaType);
            headers.setCacheControl(CacheControl.maxAge(7, TimeUnit.DAYS).cachePublic());
            if (img.resized) {
                headers.add("X-Image-Resized", "1");
            }
            return new ResponseEntity<>(img.bytes, headers, HttpStatus.OK);
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }
}
