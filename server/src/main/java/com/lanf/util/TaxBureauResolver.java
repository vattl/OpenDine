package com.lanf.util;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * 国家电子税务局门户解析器
 * 根据门店地址匹配国家税务总局及各省市（含计划单列市）官方电子税务局开票入口。
 */
public class TaxBureauResolver {

    private static final TaxBureauInfo DEFAULT_TAX_BUREAU = new TaxBureauInfo(
            "全国",
            "国家税务总局全国统一规范电子税务局",
            "https://etax.chinatax.gov.cn/"
    );

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class TaxBureauInfo implements Serializable {
        private static final long serialVersionUID = 1L;
        /** 税区或行政区简称 */
        private String region;
        /** 官方电子税务局全称 */
        private String name;
        /** 官方电子税局登录/开票入口 URL */
        private String url;
    }

    private static class RegionRule {
        final String region;
        final String name;
        final String url;
        final List<String> keywords;

        RegionRule(String region, String name, String url, String... keywords) {
            this.region = region;
            this.name = name;
            this.url = url;
            this.keywords = Collections.unmodifiableList(Arrays.asList(keywords));
        }

        boolean matches(String text) {
            if (text == null) return false;
            for (String kw : keywords) {
                if (text.contains(kw)) {
                    return true;
                }
            }
            return false;
        }
    }

    private static final List<RegionRule> RULES = new ArrayList<>();

    static {
        // 1. 计划单列市（必须优先于所在省份匹配，拥有独立国家税务局直属权限）
        RULES.add(new RegionRule("深圳", "国家税务总局深圳市电子税务局", "https://etax.shenzhen.chinatax.gov.cn/",
                "深圳"));
        RULES.add(new RegionRule("大连", "国家税务总局大连市电子税务局", "https://etax.dalian.chinatax.gov.cn/",
                "大连"));
        RULES.add(new RegionRule("青岛", "国家税务总局青岛市电子税务局", "https://etax.qingdao.chinatax.gov.cn/",
                "青岛"));
        RULES.add(new RegionRule("宁波", "国家税务总局宁波市电子税务局", "https://etax.ningbo.chinatax.gov.cn/",
                "宁波"));
        RULES.add(new RegionRule("厦门", "国家税务总局厦门市电子税务局", "https://etax.xiamen.chinatax.gov.cn/",
                "厦门"));

        // 2. 直辖市
        RULES.add(new RegionRule("北京", "国家税务总局北京市电子税务局", "https://etax.beijing.chinatax.gov.cn/",
                "北京", "朝阳区", "海淀区", "西城区", "东城区", "丰台区", "昌平区", "通州区", "大兴区", "顺义区"));
        RULES.add(new RegionRule("上海", "国家税务总局上海市电子税务局", "https://etax.shanghai.chinatax.gov.cn/",
                "上海", "浦东新区", "黄浦区", "徐汇区", "静安区", "长宁区", "普陀区", "虹口区", "杨浦区", "闵行区"));
        RULES.add(new RegionRule("天津", "国家税务总局天津市电子税务局", "https://etax.tianjin.chinatax.gov.cn/",
                "天津", "和平区", "南开区", "河西区", "河东区", "滨海新区"));
        RULES.add(new RegionRule("重庆", "国家税务总局重庆市电子税务局", "https://etax.chongqing.chinatax.gov.cn/",
                "重庆", "渝中区", "江北区", "渝北区", "沙坪坝", "九龙坡", "南岸区"));

        // 3. 各省及主要地级市
        RULES.add(new RegionRule("广东", "国家税务总局广东省电子税务局", "https://etax.guangdong.chinatax.gov.cn/",
                "广东", "广州", "东莞", "佛山", "中山", "珠海", "惠州", "江门", "汕头", "湛江", "肇庆", "清远", "潮州", "韶关", "梅州", "茂名", "阳江", "揭阳", "汕尾", "河源", "云浮"));
        RULES.add(new RegionRule("浙江", "国家税务总局浙江省电子税务局", "https://etax.zhejiang.chinatax.gov.cn/",
                "浙江", "杭州", "温州", "嘉兴", "湖州", "绍兴", "金华", "衢州", "舟山", "台州", "丽水"));
        RULES.add(new RegionRule("江苏", "国家税务总局江苏省电子税务局", "https://etax.jiangsu.chinatax.gov.cn/",
                "江苏", "南京", "苏州", "无锡", "常州", "南通", "扬州", "镇江", "泰州", "盐城", "淮安", "连云港", "宿迁", "徐州"));
        RULES.add(new RegionRule("山东", "国家税务总局山东省电子税务局", "https://etax.shandong.chinatax.gov.cn/",
                "山东", "济南", "烟台", "潍坊", "淄博", "威海", "临沂", "德州", "聊城", "滨州", "菏泽", "泰安", "日照", "枣庄", "济宁", "东营"));
        RULES.add(new RegionRule("福建", "国家税务总局福建省电子税务局", "https://etax.fujian.chinatax.gov.cn/",
                "福建", "福州", "泉州", "漳州", "莆田", "宁德", "南平", "三明", "龙岩"));
        RULES.add(new RegionRule("四川", "国家税务总局四川省电子税务局", "https://etax.sichuan.chinatax.gov.cn/",
                "四川", "成都", "绵阳", "德阳", "宜宾", "南充", "泸州", "达州", "乐山", "凉山", "广元", "遂宁", "内江", "眉山", "广安", "资阳", "攀枝花", "雅安", "巴中", "阿坝", "甘孜"));
        RULES.add(new RegionRule("湖北", "国家税务总局湖北省电子税务局", "https://etax.hubei.chinatax.gov.cn/",
                "湖北", "武汉", "襄阳", "宜昌", "荆州", "黄冈", "孝感", "荆门", "十堰", "黄石", "咸宁", "随州", "恩施", "仙桃", "潜江", "天门", "神农架"));
        RULES.add(new RegionRule("湖南", "国家税务总局湖南省电子税务局", "https://etax.hunan.chinatax.gov.cn/",
                "湖南", "长沙", "株洲", "湘潭", "衡阳", "岳阳", "常德", "郴州", "益阳", "永州", "怀化", "娄底", "邵阳", "张家界", "湘西"));
        RULES.add(new RegionRule("河南", "国家税务总局河南省电子税务局", "https://etax.henan.chinatax.gov.cn/",
                "河南", "郑州", "洛阳", "南阳", "许昌", "周口", "新乡", "安阳", "驻马店", "信阳", "开封", "商丘", "焦作", "平顶山", "濮阳", "漯河", "鹤壁", "三门峡", "济源"));
        RULES.add(new RegionRule("河北", "国家税务总局河北省电子税务局", "https://etax.hebei.chinatax.gov.cn/",
                "河北", "石家庄", "保定", "唐山", "廊坊", "邯郸", "沧州", "邢台", "秦皇岛", "张家口", "承德", "衡水", "雄安"));
        RULES.add(new RegionRule("陕西", "国家税务总局陕西省电子税务局", "https://etax.shaanxi.chinatax.gov.cn/",
                "陕西", "西安", "咸阳", "宝鸡", "渭南", "榆林", "汉中", "延安", "安康", "商洛", "铜川"));
        RULES.add(new RegionRule("安徽", "国家税务总局安徽省电子税务局", "https://etax.anhui.chinatax.gov.cn/",
                "安徽", "合肥", "芜湖", "蚌埠", "阜阳", "滁州", "安庆", "马鞍山", "六安", "宿州", "亳州", "淮南", "淮北", "铜陵", "黄山", "池州", "宣城"));
        RULES.add(new RegionRule("江西", "国家税务总局江西省电子税务局", "https://etax.jiangxi.chinatax.gov.cn/",
                "江西", "南昌", "赣州", "九江", "宜春", "吉安", "上饶", "抚州", "萍乡", "景德镇", "新余", "鹰潭"));
        RULES.add(new RegionRule("辽宁", "国家税务总局辽宁省电子税务局", "https://etax.liaoning.chinatax.gov.cn/",
                "辽宁", "沈阳", "鞍山", "抚顺", "本溪", "丹东", "锦州", "营口", "阜新", "辽阳", "盘锦", "铁岭", "朝阳", "葫芦岛"));
        RULES.add(new RegionRule("吉林", "国家税务总局吉林省电子税务局", "https://etax.jilin.chinatax.gov.cn/",
                "吉林", "长春", "吉林市", "四平", "通化", "白城", "辽源", "松原", "白山", "延边"));
        RULES.add(new RegionRule("黑龙江", "国家税务总局黑龙江省电子税务局", "https://etax.heilongjiang.chinatax.gov.cn/",
                "黑龙江", "哈尔滨", "大庆", "齐齐哈尔", "牡丹江", "佳木斯", "绥化", "鸡西", "双鸭山", "伊春", "七台河", "鹤岗", "黑河", "大兴安岭"));
        RULES.add(new RegionRule("广西", "国家税务总局广西壮族自治区电子税务局", "https://etax.guangxi.chinatax.gov.cn/",
                "广西", "南宁", "桂林", "柳州", "玉林", "百色", "钦州", "贵港", "北海", "梧州", "防城港", "崇左", "来宾", "贺州", "河池"));
        RULES.add(new RegionRule("海南", "国家税务总局海南省电子税务局", "https://etax.hainan.chinatax.gov.cn/",
                "海南", "海口", "三亚", "儋州", "琼海", "文昌", "万宁", "东方", "澄迈"));
        RULES.add(new RegionRule("贵州", "国家税务总局贵州省电子税务局", "https://etax.guizhou.chinatax.gov.cn/",
                "贵州", "贵阳", "遵义", "毕节", "六盘水", "安顺", "铜仁", "黔东南", "黔南", "黔西南"));
        RULES.add(new RegionRule("云南", "国家税务总局云南省电子税务局", "https://etax.yunnan.chinatax.gov.cn/",
                "云南", "昆明", "曲靖", "玉溪", "昭通", "保山", "丽江", "普洱", "临沧", "大理", "红河", "楚雄", "文山", "西双版纳", "德宏"));
        RULES.add(new RegionRule("山西", "国家税务总局山西省电子税务局", "https://etax.shanxi.chinatax.gov.cn/",
                "山西", "太原", "大同", "运城", "长治", "晋中", "临汾", "吕梁", "晋城", "阳泉", "朔州", "忻州"));
        RULES.add(new RegionRule("内蒙古", "国家税务总局内蒙古自治区电子税务局", "https://etax.neimenggu.chinatax.gov.cn/",
                "内蒙古", "呼和浩特", "包头", "鄂尔多斯", "赤峰", "通辽", "呼伦贝尔", "巴彦淖尔", "乌兰察布", "乌海", "兴安", "锡林郭勒", "阿拉善"));
        RULES.add(new RegionRule("甘肃", "国家税务总局甘肃省电子税务局", "https://etax.gansu.chinatax.gov.cn/",
                "甘肃", "兰州", "天水", "白银", "平凉", "庆阳", "定西", "武威", "张掖", "酒泉", "嘉峪关", "陇南", "金昌", "临夏", "甘南"));
        RULES.add(new RegionRule("青海", "国家税务总局青海省电子税务局", "https://etax.qinghai.chinatax.gov.cn/",
                "青海", "西宁", "海东", "海北", "海南州", "黄南", "果洛", "玉树", "海西"));
        RULES.add(new RegionRule("宁夏", "国家税务总局宁夏回族自治区电子税务局", "https://etax.ningxia.chinatax.gov.cn/",
                "宁夏", "银川", "石嘴山", "吴忠", "固原", "中卫"));
        RULES.add(new RegionRule("新疆", "国家税务总局新疆维吾尔自治区电子税务局", "https://etax.xinjiang.chinatax.gov.cn/",
                "新疆", "乌鲁木齐", "昌吉", "伊犁", "喀什", "阿克苏", "巴音郭楞", "克拉玛依", "和田", "塔城", "阿勒泰", "吐鲁番", "哈密", "克孜勒苏", "博尔塔拉"));
        RULES.add(new RegionRule("西藏", "国家税务总局西藏自治区电子税务局", "https://etax.xizang.chinatax.gov.cn/",
                "西藏", "拉萨", "日喀则", "昌都", "林芝", "山南", "那曲", "阿里"));
    }

    /**
     * 根据门店详细地址精准解析对应的国家电子税务局门户信息
     *
     * @param address 门店详细地址或区域文本
     * @return 对应的电子税局门户信息；若地址为空或无法识别则回退至国家统一电子税务局
     */
    public static TaxBureauInfo resolve(String address) {
        if (address == null || address.trim().isEmpty()) {
            return DEFAULT_TAX_BUREAU;
        }
        String cleanAddr = address.trim();
        for (RegionRule rule : RULES) {
            if (rule.matches(cleanAddr)) {
                return new TaxBureauInfo(rule.region, rule.name, rule.url);
            }
        }
        return DEFAULT_TAX_BUREAU;
    }

    /**
     * 获取国家统一规范电子税务局总入口
     */
    public static TaxBureauInfo getDefaultTaxBureau() {
        return DEFAULT_TAX_BUREAU;
    }
}
