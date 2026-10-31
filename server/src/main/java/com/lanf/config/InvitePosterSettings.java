package com.lanf.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * 邀请海报默认配置（背景图与二维码位置），来自 invite.poster.* 配置项。
 * 支持通过后台接口动态修改（仅在内存中生效，重启后以配置文件为准）。
 */
@Configuration
@ConfigurationProperties(prefix = "invite.poster")
public class InvitePosterSettings {

    private Background background = new Background();
    private Qr qr = new Qr();

    public Background getBackground() {
        return background;
    }

    public void setBackground(Background background) {
        this.background = background;
    }

    public Qr getQr() {
        return qr;
    }

    public void setQr(Qr qr) {
        this.qr = qr;
    }

    public static class Background {
        /** 背景图路径（本地绝对路径/网络URL） */
        private String path;

        public String getPath() {
            return path;
        }

        public void setPath(String path) {
            this.path = path;
        }
    }

    public static class Qr {
        /** 二维码X坐标（距左侧像素） */
        private int x;
        /** 二维码Y坐标（距顶部像素） */
        private int y;
        /** 二维码尺寸（像素，正方形） */
        private int size;

        public int getX() {
            return x;
        }

        public void setX(int x) {
            this.x = x;
        }

        public int getY() {
            return y;
        }

        public void setY(int y) {
            this.y = y;
        }

        public int getSize() {
            return size;
        }

        public void setSize(int size) {
            this.size = size;
        }
    }
}

