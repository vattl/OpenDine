# Scenario Matrix — WI-077

## Scenarios

| Scenario ID | Category | Description | Preconditions | Inputs / Trigger | Expected Output / State |
|---|---|---|---|---|---|
| SC-01 | 计划单列市精准匹配 | 门店地址位于深圳市南山区 | 门店地址为「广东省深圳市南山区高新科技园南区」 | `TaxBureauResolver.resolve(addr)` | 匹配到「国家税务总局深圳市电子税务局」，URL 为 `https://etax.shenzhen.chinatax.gov.cn/`（不被广东省覆盖） |
| SC-02 | 省份与重点城市匹配 | 门店地址位于广东省广州市 | 门店地址为「广州市天河区天河路123号」 | `TaxBureauResolver.resolve(addr)` | 匹配到「国家税务总局广东省电子税务局」，URL 为 `https://etax.guangdong.chinatax.gov.cn/` |
| SC-03 | 直辖市匹配 | 门店地址位于北京市朝阳区 | 门店地址为「北京市朝阳区建国门外大街1号」 | `TaxBureauResolver.resolve(addr)` | 匹配到「国家税务总局北京市电子税务局」，URL 为 `https://etax.beijing.chinatax.gov.cn/` |
| SC-04 | 计划单列市高优先级 | 门店地址位于浙江省宁波市 | 门店地址为「浙江省宁波市海曙区中山西路」 | `TaxBureauResolver.resolve(addr)` | 匹配到「国家税务总局宁波市电子税务局」，URL 为 `https://etax.ningbo.chinatax.gov.cn/`（优先于浙江省） |
| SC-05 | 空地址安全回退 | 门店地址未填写或为空字符串 | `address = ""` 或 `address = null` | `TaxBureauResolver.resolve(addr)` | 安全回退到「国家税务总局全国统一规范电子税务局」，URL 为 `https://etax.chinatax.gov.cn/` |
| SC-06 | 未知未知偏远地址回退 | 门店地址未包含任何省市行政关键词 | 门店地址为「深山老林未知地段」 | `TaxBureauResolver.resolve(addr)` | 安全回退到「国家税务总局全国统一规范电子税务局」，URL 为 `https://etax.chinatax.gov.cn/` |
| SC-07 | 财务工作台单店开票直达 | 当前选择单店（如深圳店）时点击顶部「打开当地电子税局」 | 选中深圳店 | 点击顶部按钮 | 浏览器新标签页直接打开 `https://etax.shenzhen.chinatax.gov.cn/`，并提示打开对应税局 |
| SC-08 | 财务工作台全部门店清单 | 当前处于「全部门店」模式时点击顶部「打开当地电子税局」 | 处于全部门店汇总 | 点击顶部按钮 | 弹出多门店税局清单对话框，列出各门店对应税局，支持一键单独直达或直达全国统一平台 |
| SC-09 | 发票行内直接开票 | 财务人员在发票表格操作列点击「税局开票」 | 某订单所属门店为北京朝阳店 | 点击行内操作按钮 | 浏览器新标签页直接打开北京电子税局 |
| SC-10 | 开票弹窗资料一键复制 | 财务人员在开票弹窗中点击「一键复制开票资料」 | 顾客提交了企业抬头、税号、银行账号等 | 点击复制按钮 | 格式化拼装资料并写入系统剪贴板，提示「已复制开票资料，可直接在税局系统粘贴」 |
