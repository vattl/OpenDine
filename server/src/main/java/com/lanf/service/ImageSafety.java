package com.lanf.service;

import org.springframework.web.multipart.MultipartFile;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.MemoryCacheImageInputStream;
import java.awt.image.BufferedImage;
import java.io.*;
import java.nio.file.*;
import java.util.Iterator;
import java.util.UUID;

/** Bounded reads and header validation before raster allocation. */
public final class ImageSafety {
    private ImageSafety() {}

    public static byte[] readBounded(InputStream input, int maxBytes) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int count;
        while ((count = input.read(buffer, 0, Math.min(buffer.length, maxBytes - out.size() + 1))) != -1) {
            if (count > maxBytes - out.size()) throw new IOException("图片文件超过大小限制");
            out.write(buffer, 0, count);
        }
        return out.toByteArray();
    }

    public static BufferedImage decode(byte[] bytes, long maxPixels, boolean avatar) throws IOException {
        try (MemoryCacheImageInputStream input = new MemoryCacheImageInputStream(new ByteArrayInputStream(bytes))) {
            Iterator<ImageReader> readers = ImageIO.getImageReaders(input);
            if (!readers.hasNext()) throw new IOException("图片格式无效");
            ImageReader reader = readers.next();
            try {
                String format = reader.getFormatName();
                if (avatar && !"JPEG".equalsIgnoreCase(format) && !"PNG".equalsIgnoreCase(format))
                    throw new IOException("头像仅支持 JPEG 或 PNG");
                reader.setInput(input, true, true);
                int width = reader.getWidth(0), height = reader.getHeight(0);
                if (width <= 0 || height <= 0 || (long) width * height > maxPixels)
                    throw new IOException("图片像素超过限制");
                return reader.read(0);
            } finally { reader.dispose(); }
        }
    }

    public static String storeAvatar(MultipartFile file, String directory) throws IOException {
        if (file == null || file.isEmpty()) throw new IOException("上传文件不能为空");
        if (directory == null || directory.trim().isEmpty()) throw new IOException("头像目录未配置");
        if (file.getSize() > 5 * 1024 * 1024) throw new IOException("头像超过 5 MiB 限制");
        BufferedImage image;
        try (InputStream input = file.getInputStream()) {
            image = decode(readBounded(input, 5 * 1024 * 1024), 8_000_000, true);
        }
        Path root = Paths.get(directory).toAbsolutePath().normalize();
        Files.createDirectories(root);
        String name = UUID.randomUUID().toString() + ".png";
        Path target = root.resolve(name);
        try {
            if (!ImageIO.write(image, "png", target.toFile())) throw new IOException("图片编码失败");
        } catch (IOException ex) {
            Files.deleteIfExists(target);
            throw ex;
        } finally { image.flush(); }
        return "/image/avatar/" + name;
    }
}
