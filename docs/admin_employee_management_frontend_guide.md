# 员工管理体系升级：前端接口调用与 UI/UX 设计规范指南

## 1. 概述与设计原则

本次升级将管理后台与收银系统的账号体系由传统的“单一用户名登录”全面升级为符合现代商业餐饮连锁规范的**“员工档案与责任人体系”**：
1. **身份三元组**：以 **工号 (`work_no`)** 作为员工唯一业务标识，**真实姓名 (`real_name`)** 作为全局操作人责任人，**岗位 (`job_title`)** 作为职务称谓。
2. **平滑演进与向下兼容**：
   - 登录支持工号优先匹配，历史用户名回退兼容；
   - 响应与查询字段全量补齐 `workNo`, `realName`, `jobTitle`, `displayName`；
   - 原取 `userName`/`name`/`adminName` 的旧界面自动无缝回退，不阻断任何现有业务。
3. **全局审计穿透**：当班、交班、钱箱会话、商业日结（Z 报表）、订单操作日志、系统审计日志等所有业务凭据与小票，操作人全面统一展示为**员工真实姓名**（辅以工号/岗位）。

---

## 2. 接口调用规范与数据契约

### 2.1 登录认证接口 (`POST /adminLogin`)
* **接口地址**：`POST /adminLogin`
* **协议与鉴权**：公开接口，无需 Header Token
* **支持格式**：**工号优先**（同时兼容原用户名登录）

#### 请求报文 (Request Body)
```json
{
  "workNo": "EMP1001",
  "password": "yourPassword123"
}
```
> **字段说明**：
> - `workNo`（推荐）：员工工号，如 `EMP1001`；
> - `userName`（兼容）：如果前端传递 `userName`，后端同样自动兼容支持。

#### 响应报文 (Response Body)
```json
{
  "code": 0,
  "msg": "登录成功",
  "token": "eyJhbGciOiJIUzUxMiJ9...",
  "adminId": 12,
  "workNo": "EMP1001",
  "realName": "张晓明",
  "jobTitle": "店长",
  "displayName": "张晓明",
  "name": "张晓明",
  "userName": "zhangxm",
  "scope": "SHOP",
  "shops": [
    {
      "id": 1,
      "code": "S001",
      "name": "老肥烧烤总店"
    }
  ],
  "roles": [
    {
      "roleCode": "store_manager",
      "roleName": "店长"
    }
  ],
  "permissions": [
    "order:view",
    "order:refund",
    "shift:close",
    "daily_close:create",
    "admin:manage"
  ]
}
```

---

### 2.2 恢复会话与权限校验 (`GET /admin/me/permissions`)
* **接口地址**：`GET /admin/me/permissions`
* **请求头**：`Authorization: Bearer <token>`
* **触发时机**：应用初始化加载、页面刷新、路由守卫恢复状态。

#### 响应报文 (Response Body)
```json
{
  "code": 0,
  "data": {
    "adminId": 12,
    "workNo": "EMP1001",
    "realName": "张晓明",
    "jobTitle": "店长",
    "displayName": "张晓明",
    "name": "张晓明",
    "userName": "zhangxm",
    "scope": "SHOP",
    "shops": [
      {
        "id": 1,
        "code": "S001",
        "name": "老肥烧烤总店"
      }
    ],
    "permissions": [
      "order:view",
      "shift:close",
      "daily_close:create"
    ]
  }
}
```

---

### 2.3 员工账号列表与检索 (`GET /admin/administrator/list`)
* **接口地址**：`GET /admin/administrator/list`
* **请求头**：`Authorization: Bearer <token>`
* **查询参数**：
  * `keyword` (string, 可选)：**多字段综合模糊搜索**，支持同时匹配：**工号 (`work_no`)**、**真实姓名 (`real_name`)**、**岗位 (`job_title`)**、**登录名 (`userName`)**；
  * `shopId` (number, 可选)：按门店过滤；
  * `pageNum` (number, 默认 1)；
  * `pageSize` (number, 默认 10)。

#### 响应报文 (Response Body)
```json
{
  "code": 0,
  "data": {
    "list": [
      {
        "id": 12,
        "workNo": "EMP1001",
        "realName": "张晓明",
        "jobTitle": "店长",
        "userName": "zhangxm",
        "phone": "13800138000",
        "email": "zhangxm@example.com",
        "roles": [
          { "roleCode": "store_manager", "roleName": "店长" }
        ],
        "shops": [
          { "id": 1, "name": "老肥烧烤总店" }
        ],
        "createTime": "2026-03-01 10:00:00"
      },
      {
        "id": 15,
        "workNo": "EMP1008",
        "realName": "李芳",
        "jobTitle": "领班收银",
        "userName": "lifang",
        "phone": "13900139000",
        "roles": [
          { "roleCode": "cashier", "roleName": "收银员" }
        ],
        "shops": [
          { "id": 1, "name": "老肥烧烤总店" }
        ]
      }
    ],
    "total": 2
  }
}
```

---

### 2.4 新建员工账号 (`POST /admin/administrator/create`)
* **接口地址**：`POST /admin/administrator/create`
* **请求头**：`Authorization: Bearer <token>`
* **约束规则**：
  - `workNo`（必填，去空处理，全局唯一，已存在时返回 400 错误）；
  - `realName`（必填，员工真实姓名，建议 2~20 字符）；
  - `jobTitle`（选填，常用岗位如店长、副店长、领班、收银员）；
  - `userName`（必填，登录系统识别名）；
  - `password`（必填，初始密码）；
  - `roleIds`（必填，关联的角色 ID 数组）；
  - `shopIds`（选填，授权访问的门店 ID 数组）。

#### 请求报文 (Request Body)
```json
{
  "workNo": "EMP1012",
  "realName": "王强",
  "jobTitle": "前厅收银",
  "userName": "wangqiang",
  "password": "InitialPassword123",
  "phone": "13912345678",
  "roleIds": [2],
  "shopIds": [1]
}
```

#### 异常反馈
* 若工号重复：HTTP 400，`{ "code": 400, "msg": "工号已存在" }`；
* 若用户名重复：HTTP 400，`{ "code": 400, "msg": "账号已存在" }`。

---

### 2.5 编辑员工资料 (`PUT /admin/administrator/{id}`)
* **接口地址**：`PUT /admin/administrator/{id}`
* **请求头**：`Authorization: Bearer <token>`
* **功能**：修改指定员工的工号、真实姓名、岗位，以及重置密码。

#### 请求报文 (Request Body)
```json
{
  "workNo": "EMP1012",
  "realName": "王强",
  "jobTitle": "收银组长",
  "password": "" 
}
```
> **注**：`password` 留空或不传表示保持现有密码不变；若传入非空字符串则重置为新密码。

---

### 2.6 全局业务模块操作人展示映射表

后端已在所有业务实体与视图层完成统一解析，**前端直接取用推荐展示字段即可直接显示员工姓名**：

| 业务场景 | 接口地址 | 推荐展示字段 | 备用回退字段 | 界面渲染场景 |
| :--- | :--- | :--- | :--- | :--- |
| **收银当班** | `GET /cashier/shift/current` | `operator_name` / `opened_by_name` | `admin_name` | 顶部当班条、开班人信息 |
| **交班确认** | `POST /cashier/shift/close` | `closed_by_name` | `operator_name` | 交班小票、交班结算核对单 |
| **钱箱会话** | `GET /cashier/drawer/sessions` | `opened_by_name`, `closed_by_name`, `approved_by_name` | `operator_name` | 钱箱流水、备用金存取、提现核对 |
| **商业日结 (Z报表)** | `GET /admin/daily-close/records` | `operator_name` (日结人), `reviewer_name` (复核人) | `admin_name` | 日结归档列表、商业 Z 报表、打印凭证 |
| **操作审计日志** | `GET /admin/operationLog/list` | `adminName` / `operator_name` | `adminId` | 审计日志“操作人”列 |
| **订单操作日志** | `GET /admin/order/log/{orderId}` | `operator_name` | `adminName` | 订单详情弹窗“操作记录”时间轴 |
| **订单综合列表** | `GET /admin/order/list` | `order_admin_name` | `admin_id` | 订单列表“录单人/接单员”列 |

---

## 3. 前端数据模型与状态管理设计

### 3.1 Flutter / Dart 客户端实现

#### 1) 登录会话实体 (`auth_models.dart`)
```dart
import '../../../core/shop_summary.dart';

class LoginSession {
  const LoginSession({
    required this.token,
    required this.adminId,
    required this.workNo,
    required this.realName,
    required this.jobTitle,
    required this.displayName,
    required this.userName,
    required this.scope,
    required this.permissions,
    required this.shops,
    this.actorName = '',
  });

  final String token;
  final int adminId;
  final String workNo;
  final String realName;
  final String jobTitle;
  final String displayName;
  final String userName;
  final String scope;
  final Set<String> permissions;
  final List<ShopSummary> shops;
  final String actorName;

  /// 格式化操作人标识: "张晓明 [店长]" 或 "张晓明 (EMP1001)"
  String get badgeText => jobTitle.isNotEmpty ? '$displayName [$jobTitle]' : displayName;
  String get fullIdentityText => '$displayName ($workNo) · ${jobTitle.isNotEmpty ? jobTitle : "员工"}';

  factory LoginSession.fromLoginData(Object? data) {
    final map = data is Map ? data.cast<String, Object?>() : <String, Object?>{};
    final rawToken = (map['token'] ?? map['accessToken'] ?? '').toString();
    final cleanToken = rawToken.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
    
    final realName = (map['realName'] ?? '').toString().trim();
    final userName = (map['userName'] ?? map['username'] ?? '').toString().trim();
    final workNo = (map['workNo'] ?? '').toString().trim();
    final jobTitle = (map['jobTitle'] ?? '').toString().trim();
    final displayName = (map['displayName'] ?? map['name'] ?? (realName.isNotEmpty ? realName : userName)).toString().trim();

    return LoginSession(
      token: cleanToken,
      adminId: (map['adminId'] is num) ? (map['adminId'] as num).toInt() : 0,
      workNo: workNo,
      realName: realName,
      jobTitle: jobTitle,
      displayName: displayName.isNotEmpty ? displayName : (userName.isNotEmpty ? userName : '操作员'),
      userName: userName,
      scope: (map['scope'] ?? 'SHOP').toString(),
      permissions: (map['permissions'] as List?)?.map((e) => e.toString()).toSet() ?? {},
      shops: _parseShops(map['shops']),
      actorName: displayName.isNotEmpty ? displayName : userName,
    );
  }

  static List<ShopSummary> _parseShops(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((item) => ShopSummary.fromJson(item)).toList();
  }
}
```

#### 2) 认证仓储层调用 (`auth_repository.dart`)
```dart
Future<LoginSession> login({
  required String workNoOrUsername,
  required String password,
}) async {
  final loginData = await client.post(
    adminLoginEndpoint,
    body: {
      'workNo': workNoOrUsername.trim(),   // 首选工号字段
      'userName': workNoOrUsername.trim(), // 保持向下兼容
      'password': password,
    },
  );
  
  var session = LoginSession.fromLoginData(loginData);
  if (session.token.isEmpty) {
    throw const ApiException('登录失败：未收到有效 Token');
  }

  // 刷新权限与门店列表
  final authedClient = client.copyWith(token: session.token);
  final permissionData = await authedClient.get(adminPermissionsEndpoint);
  return session.merge(permissionData: permissionData);
}
```

---

### 3.2 Web / TypeScript 状态层实现 (Vue Pinia / React Store)

```typescript
export interface EmployeeUser {
  adminId: number;
  workNo: string;        // 员工工号: EMP1001
  realName: string;      // 真实姓名: 张晓明
  jobTitle: string;      // 岗位: 店长 / 收银员
  displayName: string;   // 统一展示名称: 张晓明
  userName: string;      // 登录系统名: zhangxm
  scope: 'HQ' | 'SHOP';
  shops: Array<{ id: number; code: string; name: string }>;
  permissions: string[];
}

export const useAuthStore = defineStore('auth', {
  state: () => ({
    token: localStorage.getItem('token') || '',
    user: null as EmployeeUser | null,
  }),
  getters: {
    operatorLabel: (state) => {
      if (!state.user) return '未登录';
      return `${state.user.realName || state.user.userName} (${state.user.workNo || '无工号'})`;
    },
    jobBadge: (state) => state.user?.jobTitle || '员工',
  },
  actions: {
    async login(workNo: string, password: string) {
      const res = await api.post('/adminLogin', { workNo, password });
      this.token = res.token;
      this.user = {
        adminId: res.adminId,
        workNo: res.workNo,
        realName: res.realName,
        jobTitle: res.jobTitle,
        displayName: res.displayName || res.realName || res.userName,
        userName: res.userName,
        scope: res.scope,
        shops: res.shops,
        permissions: res.permissions,
      };
      localStorage.setItem('token', this.token);
      localStorage.setItem('last_work_no', res.workNo);
    }
  }
});
```

---

## 4. UI/UX 界面原型与交互设计规范

### 4.1 登录界面 (Cashier & Admin Login)

#### 🎨 视觉调色板 (Design Tokens)
* **品牌主色**：`#ed3d08`（热烈餐饮红 / 老肥品牌色）
* **背景底色**：`#f5f6f7`
* **主标题文字**：`#2d2d2f` (加粗 18px ~ 24px)
* **副文本与占位提示**：`#848484` (13px ~ 14px)
* **输入框高亮/聚焦边框**：`#ed3d08`
* **岗位标签背景**：`#fff1ed`，标签文字色：`#ed3d08`

#### 📐 ASCII 原型布局
```text
+-------------------------------------------------------------+
|                                                             |
|                   [ 老肥餐饮收银与管理系统 ]                |
|                    门店端工作台 · v2.2                      |
|                                                             |
|       +---------------------------------------------+       |
|       |                                             |       |
|       |  工号登录 / Staff Login                     |       |
|       |                                             |       |
|       |  员工工号                                   |       |
|       |  [ EMP1001                              [v] |       |
|       |  * 支持输入员工工号或系统用户名             |       |
|       |                                             |       |
|       |  登录密码                                   |       |
|       |  [ **********                           (o) |       |
|       |                                             |       |
|       |  [X] 记住工号                [忘记密码/联系店长] |   |
|       |                                             |       |
|       |  +---------------------------------------+  |       |
|       |  |          立即登录 (Enter)             |  |       |
|       |  +---------------------------------------+  |       |
|       |                                             |       |
|       |  (i) 提示：如遇工号未分配，请联系门店管理员创建    |       |
|       +---------------------------------------------+       |
|                                                             |
+-------------------------------------------------------------+
```

#### 交互细节与体验优化
1. **自动聚焦与小键盘支持**：
   - 界面加载后，默认聚焦在“员工工号”输入框；
   - POS 触控机按回车键 (`Enter`) 自动跳转至密码输入框，密码框回车直接触发登录。
2. **历史工号快捷下拉**：
   - 点击工号框右侧下拉按钮 `[v]`，弹出本机曾登录过的工号记忆列表，展示：`EMP1001 (张晓明 - 店长)`，点击即可快速填入。
3. **友好登录反馈**：
   - 登录成功瞬间弹出欢迎轻提示（Toast）：`“欢迎回来，店长 张晓明！”`，随后过渡至收银或管理主台。

---

### 4.2 全局顶部导航栏 & 身份状态胶囊 (Header Identity Capsule)

#### 📐 ASCII 原型布局
```text
+-----------------------------------------------------------------------------------------------+
| [LOGO] 老肥烧烤 (总店)    [点餐收银]  [当班交班]  [商业日结]  [员工管理]        2026-10-04 14:15  |
|                                                                                               |
|                                                      +--------------------------------------+ |
|                                                      | (头像) 张晓明 [店长]  EMP1001   [v]  | |
|                                                      +--------------------------------------+ |
+-----------------------------------------------------------------------------------------------+
                                                                  | 点击弹出个人状态浮层
                                                                  v
                                                       +--------------------------------------+
                                                       | 员工姓名：张晓明                      |
                                                       | 员工工号：EMP1001                    |
                                                       | 当前岗位：店长 (全权管理)            |
                                                       | 所属门店：老肥烧烤总店 (S001)        |
                                                       | 当前班次：早班 (已运行 4.5 小时)     |
                                                       | ------------------------------------ |
                                                       | [ 锁定屏幕 ]        [ 申请交班 ]     |
                                                       | [ 退出当前账号 ]                     |
                                                       +--------------------------------------+
```

#### 交互规范
1. **真实姓名突出**：姓名采用 14px / 16px **加粗字体** 展示，岗位使用胶囊 Badge（圆角 4px，浅红底红字），一目了然区分“店长”、“收银员”、“前厅领班”。
2. **多端自适应**：在平板或手机端小屏模式下，自动折叠为 `头像 + 张晓明`，点击浮层展开完整信息。

---

### 4.3 员工管理页面 (Employee Management View)

#### 📐 ASCII 原型布局
```text
+-----------------------------------------------------------------------------------------------+
| 首页 / 系统管理 / 员工管理                                                                     |
|                                                                                               |
| [ 搜索：工号 / 姓名 / 岗位 / 账号...         ]  [ 查询 ]  [ 重置 ]        [ + 新建员工账号 ]   |
+-----------------------------------------------------------------------------------------------+
| 工号     | 员工姓名  | 岗位/职务  | 登录用户名  | 绑定角色  | 所属门店      | 状态  | 操作         |
+----------+-----------+------------+-------------+-----------+---------------+-------+--------------+
| EMP1001  | 张晓明    | [店长]     | zhangxm     | 门店主管  | 老肥烧烤总店  | 正常  | [编辑] [重置] |
| EMP1008  | 李芳      | [收银员]   | lifang      | 收银前厅  | 老肥烧烤总店  | 正常  | [编辑] [重置] |
| EMP1012  | 王强      | [收银组长] | wangqiang   | 收银员    | 老肥烧烤总店  | 正常  | [编辑] [重置] |
+----------+-----------+------------+-------------+-----------+---------------+-------+--------------+
| 共 3 条记录                                                      [ < ]  [ 1 ]  [ > ] 10条/页  |
+-----------------------------------------------------------------------------------------------+
```

#### 📐 新增/编辑员工弹窗设计
```text
+-----------------------------------------------------------+
|  新建员工档案 / 编辑员工信息                              [X] |
+-----------------------------------------------------------+
|                                                           |
|  * 员工工号：                                             |
|  [ EMP1015                                             ]  |
|  (i) 工号为系统唯一标识，用于日常快速登录与操作审计        |
|                                                           |
|  * 真实姓名：                                             |
|  [ 孙立                                                ]  |
|  (i) 必填，后续所有点单、交班、日结单据将打印此姓名        |
|                                                           |
|    岗位称谓：                                             |
|  [ 收银员                                          [v] ]  |
|  (支持选择常用岗位：店长、副店长、领班、收银员，或手动输入) |
|                                                           |
|  * 登录账号 (系统名)：                                    |
|  [ sunli                                               ]  |
|                                                           |
|  * 初始密码 / 重置密码：                                  |
|  [ ****************                                (o) ]  |
|  (编辑时留空表示不修改原密码)                             |
|                                                           |
|  * 权限角色分配：                                         |
|  [X] 收银员角色   [ ] 店长角色   [ ] 财务对账角色         |
|                                                           |
|  * 所属门店授权：                                         |
|  [X] 老肥烧烤总店 (S001)   [ ] 二号直营店 (S002)          |
|                                                           |
| --------------------------------------------------------- |
|                              [  取  消  ]   [ 确认保存 ]  |
+-----------------------------------------------------------+
```

#### 表单校验规则 (Validation Rules)
1. **`workNo`（工号）**：必填，正则 `^[a-zA-Z0-9_\-]+$`（建议长度 3~20 位，不允许包含空格、特殊符号），失焦即触发重复性校验。
2. **`realName`（真实姓名）**：必填，2~20 个字符。
3. **`jobTitle`（岗位）**：提供快捷下拉（店长、副店长、领班、收银员、服务员），同时允许自定义输入。
4. **`userName`（登录用户名）**：必填，英文字母开头，4~20 位。

---

### 4.4 核心业务场景展示升级细节

#### 1) 收银当班与交班确认弹窗
```text
+----------------------------------------------------+
| 当班交班结算确认                               [X] |
+----------------------------------------------------+
| 门店名称：老肥烧烤总店 (S001)                      |
| 当班班次：20261004-早班                            |
| 开班人员：张晓明 (EMP1001 · 店长)                  |
| 交班操作人：李芳 (EMP1008 · 收银员)                |
| -------------------------------------------------- |
| 钱箱备用金：￥500.00                               |
| 现金应结金额：￥1,820.00                           |
| 移动支付金额：￥9,640.00                           |
| -------------------------------------------------- |
|                       [ 打印交班单并登出 ]         |
+----------------------------------------------------+
```

#### 2) 商业日结 Z 报表界面与热敏小票
* **屏幕端**：
  - 关账记录表头：“关账人：**张晓明**（店长） | 审核人：**王强**（财务）”
* **80mm 热敏打印小票模板**：
  ```text
  ------------------------------------------------
                 老肥烧烤 · 营业日结单 (Z-Report)
  ------------------------------------------------
  日结日期: 2026-10-04 02:00:15
  门店名称: 老肥烧烤总店
  关 账 人: 张晓明 [店长] (EMP1001)
  复 核 人: 王强 [财务总监]
  ------------------------------------------------
  营业总额: ￥24,580.00
  实收总计: ￥23,120.00
  ------------------------------------------------
  ```

#### 3) 系统操作日志与订单日志
* **操作日志列表**：
  - “操作人”列统一渲染：
    `张晓明`（第一行，粗体）
    `EMP1001 · 店长`（第二行，浅灰色 12px 小字）
* **订单详情日志流**：
  - `14:20:05` **张晓明**（店长） 退菜【烤生蚝 x 2】，退款金额 ￥36.00
  - `14:35:10` **李芳**（收银员） 结账买单，实收 ￥188.00

---

## 5. 前端改造任务清单 (Frontend Tasks)

| 阶段 | 模块 | 核心工作 | 涉及前端文件参考 |
| :--- | :--- | :--- | :--- |
| **阶段 1** | **数据层与契约** | ① 扩展 `LoginSession` 实体，加入 `workNo`, `realName`, `jobTitle`；<br>② `login` API 请求优先携带 `workNo`。 | `auth_models.dart`<br>`auth_repository.dart`<br>`auth_store.ts` |
| **阶段 2** | **登录页面** | ① 登录框输入提示改为“员工工号 / 账号”；<br>② 本地存储记忆历史工号；<br>③ 登录成功弹出“欢迎，[岗位] [姓名]”反馈。 | `cashier_login_page.dart`<br>`login.vue` |
| **阶段 3** | **框架壳层** | ① 顶部 Header 状态栏增加员工姓名与岗位 Tag 胶囊；<br>② 点击弹出包含工号与门店的员工个人卡片。 | `cashier_shell_page.dart`<br>`header.vue` |
| **阶段 4** | **员工管理** | ① 员工列表表格增加“工号”、“姓名”、“岗位”三列；<br>② 搜索框支持按工号与姓名筛选；<br>③ 新增/编辑弹窗提供工号校验与排重处理。 | `employee_list_view.dart`<br>`admin_users.vue` |
| **阶段 5** | **业务对齐** | ① 检查交班、日结、操作日志，将原 `admin_name`/`adminId` 统一绑定为 `operator_name`/`realName`。 | `shift_dialog.dart`<br>`daily_close_view.dart`<br>`log_table.vue` |
