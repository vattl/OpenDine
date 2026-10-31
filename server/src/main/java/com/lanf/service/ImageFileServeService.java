package com.lanf.service;

import com.lanf.config.ImageServeProperties;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import javax.annotation.PostConstruct;
import javax.imageio.ImageIO;
import java.awt.Graphics2D;
import java.awt.Image;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 解析 /image/{category}/** 到磁盘路径，并按 q 生成缩放图字节。
 */
@Service
public class ImageFileServeService {

    private final ImageServeProperties props;
    private final java.util.concurrent.Semaphore decoders = new java.util.concurrent.Semaphore(2);
    private final com.github.benmanes.caffeine.cache.Cache<String, ServedImage> thumbnails =
            com.github.benmanes.caffeine.cache.Caffeine.newBuilder()
                    .maximumWeight(32L * 1024 * 1024)
                    .weigher((String key, ServedImage value) -> value.bytes.length)
                    .expireAfterAccess(10, java.util.concurrent.TimeUnit.MINUTES).build();
    private Map<String, Path> categoryRoots = new LinkedHashMap<>();

    @Value("${qrcodeImgsFilePath:/www/wwwroot/qrcodeImgs/}")
    private String qrcodeImgsFilePath;
    @Value("${dishImgsFilePath:/www/wwwroot/dishImgs/}")
    private String dishImgsFilePath;
    @Value("${ImgsFilePath:/www/wwwroot/upload/images/}")
    private String imgsFilePath;
    @Value("${avatarImgsFilePath:/www/wwwroot/upload/avatar/}")
    private String avatarImgsFilePath;
    @Value("${activateImgsFilePath:/www/wwwroot/upload/advertising/}")
    private String advertisingImgsFilePath;
    @Value("${offlineCollectImgsFilePath:/www/wwwroot/upload/offline-collect/}")
    private String offlineCollectImgsFilePath;

    public ImageFileServeService(ImageServeProperties props) {
        this.props = props;
    }

    @PostConstruct
    public void initRoots() {
        categoryRoots = new LinkedHashMap<>();
        putRoot("qrcode", qrcodeImgsFilePath);
        putRoot("dish", dishImgsFilePath);
        putRoot("img", imgsFilePath);
        putRoot("avatar", avatarImgsFilePath);
        putRoot("advertising", advertisingImgsFilePath);
        putRoot("offline-collect", offlineCollectImgsFilePath);
    }

    private void putRoot(String category, String dir) {
        if (!StringUtils.hasText(dir)) {
            return;
        }
        Path p = Paths.get(dir.trim()).toAbsolutePath().normalize();
        categoryRoots.put(category, p);
    }

    public static class ServedImage {
        public final byte[] bytes;
        public final MediaType mediaType;
        public final boolean resized;

        public ServedImage(byte[] bytes, MediaType mediaType, boolean resized) {
            this.bytes = bytes;
            this.mediaType = mediaType;
            this.resized = resized;
        }
    }

    /**
     * @param requestUri 如 /image/dish/foo.jpg（不含 query）
     */
    public ServedImage serve(String requestUri, Integer q) throws IOException {
        Path file = resolveFile(requestUri);
        if (file == null || !Files.isRegularFile(file)) {
            return null;
        }
        if (Files.size(file) > 10L * 1024 * 1024) throw new IOException("图片超过 10 MiB 限制");
        String ext = extension(file.getFileName().toString());
        MediaType mt = mediaTypeForExt(ext);
        if (!props.isResizeEnabled() || q == null || q <= 0 || !isRasterImage(ext) || "gif".equals(ext)) {
            return new ServedImage(readImage(file), mt, false);
        }
        int width = clampQ(q);
        String key = file.toString() + ":" + Files.getLastModifiedTime(file) + ":" + Files.size(file) + ":" + width;
        try {
            return thumbnails.get(key, ignored -> {
                try { return resize(file, ext, width); }
                catch (IOException ex) { throw new java.io.UncheckedIOException(ex); }
            });
        } catch (java.io.UncheckedIOException ex) { throw ex.getCause(); }
    }

    private byte[] readImage(Path file) throws IOException {
        try (java.io.InputStream input = Files.newInputStream(file)) {
            return ImageSafety.readBounded(input, 10 * 1024 * 1024);
        }
    }

    private ServedImage resize(Path file, String ext, int width) throws IOException {
        if (!decoders.tryAcquire()) throw new IOException("图片处理繁忙，请稍后重试");
        BufferedImage src = null, dst = null;
        try {
            byte[] original = readImage(file);
            src = ImageSafety.decode(original, 16_000_000, false);
            if (src.getWidth() <= width) return new ServedImage(original, mediaTypeForExt(ext), false);
            int height = Math.max(1, (int) Math.round((double) src.getHeight() * width / src.getWidth()));
            boolean png = "png".equals(ext);
            dst = new BufferedImage(width, height, png ? BufferedImage.TYPE_INT_ARGB : BufferedImage.TYPE_INT_RGB);
            Graphics2D g = dst.createGraphics();
            try {
                g.setRenderingHint(java.awt.RenderingHints.KEY_INTERPOLATION, java.awt.RenderingHints.VALUE_INTERPOLATION_BILINEAR);
                g.drawImage(src, 0, 0, width, height, null);
            } finally { g.dispose(); }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            if (!ImageIO.write(dst, png ? "png" : "jpg", out)) throw new IOException("图片编码失败");
            return new ServedImage(out.toByteArray(), png ? MediaType.IMAGE_PNG : MediaType.IMAGE_JPEG, true);
        } finally {
            if (src != null) src.flush();
            if (dst != null) dst.flush();
            decoders.release();
        }
    }

    private int clampQ(int q) {
        int max = props.getMaxQ() > 0 ? props.getMaxQ() : 1200;
        int min = props.getMinQ() > 0 ? props.getMinQ() : 1;
        return Math.min(max, Math.max(min, q));
    }

    /**
     * /image/{category}/relative/path.jpg
     */
    public Path resolveFile(String requestUri) throws IOException {
        if (!StringUtils.hasText(requestUri) || !requestUri.startsWith("/image/")) {
            return null;
        }
        String rest = requestUri.substring("/image/".length());
        int slash = rest.indexOf('/');
        if (slash <= 0) {
            return null;
        }
        String category = rest.substring(0, slash);
        String relative = rest.substring(slash + 1);
        if (!StringUtils.hasText(relative) || relative.contains("..")) {
            return null;
        }
        Path root = categoryRoots.get(category);
        if (root == null) {
            return null;
        }
        Path resolved = root.resolve(relative.replace('\\', '/')).normalize();
        if (!resolved.startsWith(root)) {
            return null;
        }
        if (Files.exists(resolved) && !resolved.toRealPath().startsWith(root.toRealPath())) return null;
        return resolved;
    }

    private static boolean isRasterImage(String ext) {
        return "jpg".equals(ext) || "jpeg".equals(ext) || "png".equals(ext) || "gif".equals(ext) || "bmp".equals(ext);
    }

    private static String extension(String filename) {
        int i = filename.lastIndexOf('.');
        if (i < 0) {
            return "";
        }
        return filename.substring(i + 1).toLowerCase();
    }

    private static MediaType mediaTypeForExt(String ext) {
        if ("png".equals(ext)) {
            return MediaType.IMAGE_PNG;
        }
        if ("gif".equals(ext)) {
            return MediaType.parseMediaType("image/gif");
        }
        if ("webp".equals(ext)) {
            return MediaType.parseMediaType("image/webp");
        }
        return MediaType.IMAGE_JPEG;
    }
}
