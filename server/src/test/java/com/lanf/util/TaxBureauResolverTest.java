package com.lanf.util;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("TaxBureauResolver 税务局门户精准解析测试")
class TaxBureauResolverTest {

    @Test
    @DisplayName("SC-01: 深圳计划单列市精准匹配（优先于广东省）")
    void resolve_shenzhen_matchesShenzhenTaxBureau() {
        TaxBureauResolver.TaxBureauInfo info =
                TaxBureauResolver.resolve("广东省深圳市南山区高新科技园南区创智大厦");
        assertNotNull(info);
        assertEquals("深圳", info.getRegion());
        assertEquals("国家税务总局深圳市电子税务局", info.getName());
        assertEquals("https://etax.shenzhen.chinatax.gov.cn/", info.getUrl());
    }

    @Test
    @DisplayName("SC-04: 宁波计划单列市精准匹配（优先于浙江省）")
    void resolve_ningbo_matchesNingboTaxBureau() {
        TaxBureauResolver.TaxBureauInfo info =
                TaxBureauResolver.resolve("浙江省宁波市海曙区中山西路123号");
        assertNotNull(info);
        assertEquals("宁波", info.getRegion());
        assertEquals("国家税务总局宁波市电子税务局", info.getName());
        assertEquals("https://etax.ningbo.chinatax.gov.cn/", info.getUrl());
    }

    @Test
    @DisplayName("SC-04-2: 大连/青岛/厦门等计划单列市精准匹配")
    void resolve_otherSinglePlanningCities() {
        TaxBureauResolver.TaxBureauInfo dalian =
                TaxBureauResolver.resolve("辽宁省大连市中山区人民路10号");
        assertEquals("大连", dalian.getRegion());
        assertEquals("https://etax.dalian.chinatax.gov.cn/", dalian.getUrl());

        TaxBureauResolver.TaxBureauInfo qingdao =
                TaxBureauResolver.resolve("山东省青岛市市南区香港中路88号");
        assertEquals("青岛", qingdao.getRegion());
        assertEquals("https://etax.qingdao.chinatax.gov.cn/", qingdao.getUrl());

        TaxBureauResolver.TaxBureauInfo xiamen =
                TaxBureauResolver.resolve("福建省厦门市思明区湖滨南路66号");
        assertEquals("厦门", xiamen.getRegion());
        assertEquals("https://etax.xiamen.chinatax.gov.cn/", xiamen.getUrl());
    }

    @Test
    @DisplayName("SC-03: 直辖市（北京、上海、天津、重庆）精准匹配")
    void resolve_municipalities() {
        TaxBureauResolver.TaxBureauInfo beijing =
                TaxBureauResolver.resolve("北京市朝阳区建国门外大街1号国贸大厦");
        assertEquals("北京", beijing.getRegion());
        assertEquals("https://etax.beijing.chinatax.gov.cn/", beijing.getUrl());

        TaxBureauResolver.TaxBureauInfo shanghai =
                TaxBureauResolver.resolve("上海市黄浦区南京东路888号恒基大厦");
        assertEquals("上海", shanghai.getRegion());
        assertEquals("https://etax.shanghai.chinatax.gov.cn/", shanghai.getUrl());

        TaxBureauResolver.TaxBureauInfo tianjin =
                TaxBureauResolver.resolve("天津市和平区南京路80号");
        assertEquals("天津", tianjin.getRegion());
        assertEquals("https://etax.tianjin.chinatax.gov.cn/", tianjin.getUrl());

        TaxBureauResolver.TaxBureauInfo chongqing =
                TaxBureauResolver.resolve("重庆市渝中区解放碑时代广场");
        assertEquals("重庆", chongqing.getRegion());
        assertEquals("https://etax.chongqing.chinatax.gov.cn/", chongqing.getUrl());
    }

    @Test
    @DisplayName("SC-02: 省份与省内地级市匹配（广东广州、浙江杭州、江苏苏州等）")
    void resolve_provincesAndCities() {
        TaxBureauResolver.TaxBureauInfo guangzhou =
                TaxBureauResolver.resolve("广州市天河区天河路123号");
        assertEquals("广东", guangzhou.getRegion());
        assertEquals("国家税务总局广东省电子税务局", guangzhou.getName());
        assertEquals("https://etax.guangdong.chinatax.gov.cn/", guangzhou.getUrl());

        TaxBureauResolver.TaxBureauInfo hangzhou =
                TaxBureauResolver.resolve("杭州市西湖区文三路398号");
        assertEquals("浙江", hangzhou.getRegion());
        assertEquals("https://etax.zhejiang.chinatax.gov.cn/", hangzhou.getUrl());

        TaxBureauResolver.TaxBureauInfo suzhou =
                TaxBureauResolver.resolve("江苏省苏州市姑苏区平江路1号");
        assertEquals("江苏", suzhou.getRegion());
        assertEquals("https://etax.jiangsu.chinatax.gov.cn/", suzhou.getUrl());

        TaxBureauResolver.TaxBureauInfo chengdu =
                TaxBureauResolver.resolve("四川省成都市锦江区春熙路8号");
        assertEquals("四川", chengdu.getRegion());
        assertEquals("https://etax.sichuan.chinatax.gov.cn/", chengdu.getUrl());
    }

    @Test
    @DisplayName("SC-05: 空地址与空字符串安全回退到国家统一规范电子税务局总入口")
    void resolve_nullOrEmptyAddress_returnsNationalDefault() {
        TaxBureauResolver.TaxBureauInfo infoNull = TaxBureauResolver.resolve(null);
        assertNotNull(infoNull);
        assertEquals("全国", infoNull.getRegion());
        assertEquals("https://etax.chinatax.gov.cn/", infoNull.getUrl());

        TaxBureauResolver.TaxBureauInfo infoEmpty = TaxBureauResolver.resolve("   ");
        assertNotNull(infoEmpty);
        assertEquals("全国", infoEmpty.getRegion());
        assertEquals("https://etax.chinatax.gov.cn/", infoEmpty.getUrl());
    }

    @Test
    @DisplayName("SC-06: 未知非行政区划地址优雅回退到国家统一规范电子税务局总入口")
    void resolve_unknownAddress_returnsNationalDefault() {
        TaxBureauResolver.TaxBureauInfo info = TaxBureauResolver.resolve("深山老林桃花源88号");
        assertNotNull(info);
        assertEquals("全国", info.getRegion());
        assertEquals("https://etax.chinatax.gov.cn/", info.getUrl());
    }
}
