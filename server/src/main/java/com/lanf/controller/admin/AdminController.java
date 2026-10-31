package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Admin;
import com.lanf.entity.AdminRegion;
import com.lanf.entity.AdminRole;
import com.lanf.entity.AdminShop;
import com.lanf.entity.R;
import com.lanf.entity.Role;
import com.lanf.entity.Region;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.mapper.AdminRegionMapper;
import com.lanf.mapper.AdminRoleMapper;
import com.lanf.mapper.AdminShopMapper;
import com.lanf.mapper.RegionMapper;
import com.lanf.mapper.RoleMapper;
import com.lanf.constant.AdminDataScope;
import com.lanf.entity.Shop;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.service.IAdminService;
import com.lanf.service.IShopService;
import com.lanf.security.SecurityAuditService;
import com.lanf.util.AdminNameResolver;
import com.lanf.util.AdminPasswordUtil;
import com.lanf.util.StringUtil;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 管理员 Controller（除登录外均挂在 {@code /admin} 下）。
 * 登录见 {@link AdminLoginController} {@code POST /adminLogin}。权限与契约见 docs/权限设计.md 5.1。
 */
@RestController
@RequestMapping("/admin")
public class AdminController {

    @Autowired
    private IAdminService adminService;
    @Autowired
    private IAdminPermissionService adminPermissionService;
    @Autowired
    private AdminRoleMapper adminRoleMapper;
    @Autowired
    private RoleMapper roleMapper;
    @Autowired
    private AdminShopMapper adminShopMapper;
    @Autowired
    private AdminRegionMapper adminRegionMapper;
    @Autowired
    private RegionMapper regionMapper;
    @Autowired
    private IShopService shopService;
    @Autowired
    private IAdminShopAccessService adminShopAccessService;
    @Autowired
    private SecurityAuditService securityAuditService;
    @Autowired
    private HttpServletRequest currentRequest;

    /**
     * 获取当前登录管理员的权限列表（权限设计 5.1 - 刷新页面后恢复权限）。
     * 请求头：Authorization: Bearer &lt;token&gt;。
     * 成功响应：{ "code": 0, "permissions": ["order:view", ...], "adminId": 1 }。
     * 前端用返回的 permissions 更新 store 即可。
     */
    @GetMapping("/me/permissions")
    public R getMyPermissions(HttpServletRequest request) {
        Object adminIdObj = request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        if (adminIdObj == null) {
            return R.error(401, "未登录或登录已过期");
        }
        Integer adminId = (Integer) adminIdObj;
        Admin currentAdmin = adminService.getById(adminId);
        Set<String> permissions = adminPermissionService.getPermissionCodesByAdminId(adminId);
        Map<String, Object> data = new HashMap<>();
        data.put("permissions", permissions == null ? Collections.emptyList() : permissions.stream().sorted().collect(Collectors.toList()));
        data.put("adminId", adminId);
        data.put("isSuperAdmin", adminShopAccessService.isSuperAdmin(adminId));
        if (currentAdmin != null) {
            data.put("userName", currentAdmin.getUserName());
            data.put("workNo", currentAdmin.getWorkNo());
            data.put("work_no", currentAdmin.getWorkNo());
            data.put("realName", currentAdmin.getRealName());
            data.put("real_name", currentAdmin.getRealName());
            data.put("jobTitle", currentAdmin.getJobTitle());
            data.put("job_title", currentAdmin.getJobTitle());
            String displayName = AdminNameResolver.resolveDisplayName(currentAdmin);
            data.put("name", displayName);
            data.put("displayName", displayName);
        }
        AdminDataScope scope = adminShopAccessService.resolveScope(adminId);
        data.put("scope", scope.name());
        List<Shop> shops = adminShopAccessService.listAccessibleShops(adminId);
        data.put("shops", adminShopAccessService.toShopSummaries(shops));
        data.put("regionIds", adminShopAccessService.listAccessibleRegionIds(adminId));
        return R.ok(data);
    }

    /**
     * 当前管理员可访问门店分页（用于 HQ 门店量较大时的前端懒加载）。
     * 查询参数：
     * - page: 页码，从 1 开始，默认 1
     * - pageSize: 每页条数，默认 20，最大 200
     * - keyword: 可选，按门店名称/编码包含匹配
     */
    @GetMapping("/me/shops")
    public R getMyShops(HttpServletRequest request,
                        @RequestParam(required = false, defaultValue = "1") Integer page,
                        @RequestParam(required = false, defaultValue = "20") Integer pageSize,
                        @RequestParam(required = false) String keyword) {
        Object adminIdObj = request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        if (adminIdObj == null) {
            return R.error(401, "未登录或登录已过期");
        }
        Integer adminId = (Integer) adminIdObj;
        int p = (page == null || page < 1) ? 1 : page;
        int ps = (pageSize == null || pageSize < 1) ? 20 : Math.min(pageSize, 200);
        String kw = keyword == null ? "" : keyword.trim().toLowerCase();

        List<Shop> all = adminShopAccessService.listAccessibleShops(adminId);
        List<Shop> filtered = all;
        if (!kw.isEmpty()) {
            filtered = all.stream().filter(s -> {
                String name = s.getName() == null ? "" : s.getName().toLowerCase();
                String code = s.getCode() == null ? "" : s.getCode().toLowerCase();
                return name.contains(kw) || code.contains(kw);
            }).collect(Collectors.toList());
        }

        int total = filtered.size();
        int from = Math.min((p - 1) * ps, total);
        int to = Math.min(from + ps, total);
        List<Shop> pageList = filtered.subList(from, to);

        Map<String, Object> data = new HashMap<>();
        List<Integer> regionIds = adminShopAccessService.listAccessibleRegionIds(adminId);
        data.put("scope", adminShopAccessService.resolveScope(adminId).name());
        data.put("regionIds", regionIds);
        if (!regionIds.isEmpty()) {
            List<Region> regions = regionMapper.selectList(new QueryWrapper<Region>().in("id", regionIds).orderByAsc("id"));
            List<Map<String, Object>> regionList = new ArrayList<>();
            for (Region region : regions) {
                Map<String, Object> item = new HashMap<>();
                item.put("id", region.getId());
                item.put("name", region.getName());
                regionList.add(item);
            }
            data.put("regions", regionList);
        } else {
            data.put("regions", Collections.emptyList());
        }
        data.put("list", adminShopAccessService.toShopSummaries(pageList));
        data.put("page", p);
        data.put("pageSize", ps);
        data.put("total", total);
        return R.ok(data);
    }

    /**
     * 修改密码
     * @param admin
     * @return
     */
    @PostMapping("/modifyPassword")
    public R modifyPassword(@RequestBody Admin admin, HttpServletRequest request){
        Object adminIdObj = request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        if (!(adminIdObj instanceof Integer)) {
            return R.error(401, "未登录或登录已过期");
        }
        if (admin == null || StringUtil.isEmpty(admin.getPassword())) {
            return R.error("当前密码不能为空！");
        }
        if(StringUtil.isEmpty(admin.getNewPassword())){
            return R.error("新密码不能为空！");
        }
        Admin current = adminService.getById((Integer) adminIdObj);
        if (current == null || !AdminPasswordUtil.matches(admin.getPassword(), current.getPassword())) {
            return R.error("当前密码错误！");
        }
        Admin update = new Admin();
        update.setId(current.getId());
        update.setPassword(AdminPasswordUtil.encode(admin.getNewPassword()));
        update.setTokenVersion((current.getTokenVersion() == null ? 0 : current.getTokenVersion()) + 1);
        if (!adminService.updateById(update)) {
            return R.error("密码修改失败，请重试");
        }
        securityAuditService.recordPermissionChange(request, "admin_password_changed",
                String.valueOf(current.getId()), null,
                Collections.singletonMap("tokenVersion", update.getTokenVersion()));
        return R.ok();
    }

    /**
     * 管理员列表（含角色信息），仅具备 admin:manage 权限可访问；返回项不含密码。
     */
    @GetMapping("/administrator/list")
    public R listAdministrators() {
        List<Admin> admins = adminService.list(new QueryWrapper<Admin>().orderByAsc("id"));
        List<Map<String, Object>> list = new ArrayList<>();
        List<Role> allRoles = roleMapper.selectList(null);
        Map<Integer, Role> roleMap = allRoles.stream().collect(Collectors.toMap(Role::getId, r -> r, (a, b) -> a));
        for (Admin admin : admins) {
            List<AdminRole> arList = adminRoleMapper.selectList(new QueryWrapper<AdminRole>().eq("admin_id", admin.getId()));
            List<Integer> roleIds = arList.stream().map(AdminRole::getRole_id).collect(Collectors.toList());
            List<Map<String, Object>> roleList = roleIds.stream()
                    .map(roleMap::get)
                    .filter(Objects::nonNull)
                    .map(r -> {
                        Map<String, Object> m = new HashMap<>();
                        m.put("id", r.getId());
                        m.put("role_code", r.getRole_code());
                        m.put("role_name", r.getRole_name());
                        return m;
                    })
                    .collect(Collectors.toList());
            Map<String, Object> item = new HashMap<>();
            item.put("id", admin.getId());
            item.put("userName", admin.getUserName());
            item.put("workNo", admin.getWorkNo());
            item.put("work_no", admin.getWorkNo());
            item.put("realName", admin.getRealName());
            item.put("real_name", admin.getRealName());
            item.put("jobTitle", admin.getJobTitle());
            item.put("job_title", admin.getJobTitle());
            String displayName = AdminNameResolver.resolveDisplayName(admin);
            item.put("name", displayName);
            item.put("displayName", displayName);
            item.put("roleIds", roleIds);
            item.put("roles", roleList);
            AdminDataScope scope = adminShopAccessService.resolveScope(admin.getId());
            item.put("scope", scope.name());
            List<Integer> shopIds = listShopIdsByAdminId(admin.getId());
            List<Integer> regionIds = listRegionIdsByAdminId(admin.getId());
            item.put("shopIds", shopIds);
            item.put("regionIds", regionIds);
            List<Shop> shops = shopIds.isEmpty() ? Collections.emptyList() :
                    shopService.list(new QueryWrapper<Shop>().in("id", shopIds).orderByAsc("id"));
            item.put("shops", adminShopAccessService.toShopSummaries(shops));
            list.add(item);
        }
        Map<String, Object> data = new HashMap<>();
        data.put("list", list);
        data.put("total", list.size());
        data.put("allRoles", allRoles.stream().map(r -> {
            Map<String, Object> m = new HashMap<>();
            m.put("id", r.getId());
            m.put("role_code", r.getRole_code());
            m.put("role_name", r.getRole_name());
            return m;
        }).collect(Collectors.toList()));
        return R.ok(data);
    }

    /**
     * 修改指定管理员的角色（权限），仅具备 admin:manage 权限可访问。请求体 roleIds 为空时表示撤销全部权限。
     */
    @PutMapping("/administrator/{id}/roles")
    @Transactional
    public R updateAdministratorRoles(@PathVariable Integer id, @RequestBody Map<String, Object> body) {
        if (id == null) {
            return R.error("管理员ID不能为空");
        }
        Admin admin = adminService.getById(id);
        if (admin == null) {
            return R.error("管理员不存在");
        }
        if (body == null || !(body.get("roleIds") instanceof List)) {
            return R.error("roleIds 必须为数组；传空数组表示撤销全部角色");
        }
        List<Integer> beforeRoleIds = adminRoleMapper.selectList(
                        new QueryWrapper<AdminRole>().eq("admin_id", id)).stream()
                .map(AdminRole::getRole_id).filter(Objects::nonNull).distinct().sorted()
                .collect(Collectors.toList());
        List<Integer> roleIds = parseNumberList(body == null ? null : body.get("roleIds"));
        if (!roleIds.isEmpty()) {
            Integer count = roleMapper.selectCount(new QueryWrapper<Role>().in("id", roleIds));
            if (count == null || count != roleIds.size()) {
                return R.error("部分角色ID不存在，请刷新后重试");
            }
        }
        adminRoleMapper.delete(new QueryWrapper<AdminRole>().eq("admin_id", id));
        for (Integer roleId : roleIds) {
            AdminRole ar = new AdminRole();
            ar.setAdmin_id(id);
            ar.setRole_id(roleId);
            adminRoleMapper.insert(ar);
        }
        securityAuditService.recordPermissionChange(currentRequest, "admin_roles_changed", String.valueOf(id),
                Collections.singletonMap("roleIds", beforeRoleIds),
                Collections.singletonMap("roleIds", roleIds));
        return R.ok();
    }

    /**
     * 覆盖管理员数据范围绑定（门店/区域）。
     * 说明：
     * 1) 仅维护显式绑定关系（t_admin_shop / t_admin_region）；
     * 2) 若管理员为 HQ（显式 super_admin 角色）则拒绝修改，避免与 HQ 语义冲突。
     */
    @PutMapping("/administrator/{id}/shops")
    @Transactional
    public R updateAdministratorScope(@PathVariable Integer id, @RequestBody Map<String, Object> body) {
        if (id == null) {
            return R.error("管理员ID不能为空");
        }
        Admin admin = adminService.getById(id);
        if (admin == null) {
            return R.error("管理员不存在");
        }
        if (adminShopAccessService.isHeadquartersAdmin(id)) {
            return R.error("总部管理员不支持修改门店/区域范围");
        }
        if (body == null || !(body.get("shopIds") instanceof List)
                || !(body.get("regionIds") instanceof List)) {
            return R.error("shopIds 和 regionIds 必须为数组；传空数组表示清空对应范围");
        }
        List<Integer> shopIds = parseNumberList(body == null ? null : body.get("shopIds"));
        List<Integer> regionIds = parseNumberList(body == null ? null : body.get("regionIds"));
        List<Integer> beforeShopIds = listShopIdsByAdminId(id);
        List<Integer> beforeRegionIds = listRegionIdsByAdminId(id);

        if (!shopIds.isEmpty()) {
            Integer count = shopService.count(new QueryWrapper<Shop>().in("id", shopIds));
            if (count == null || count != shopIds.size()) {
                return R.error("部分门店ID不存在，请刷新后重试");
            }
        }
        if (!regionIds.isEmpty()) {
            Integer count = regionMapper.selectCount(new QueryWrapper<Region>().in("id", regionIds));
            if (count == null || count != regionIds.size()) {
                return R.error("部分区域ID不存在，请刷新后重试");
            }
        }

        adminShopMapper.delete(new QueryWrapper<AdminShop>().eq("admin_id", id));
        adminRegionMapper.delete(new QueryWrapper<AdminRegion>().eq("admin_id", id));

        for (Integer shopId : shopIds) {
            AdminShop link = new AdminShop();
            link.setAdmin_id(id);
            link.setShop_id(shopId);
            adminShopMapper.insert(link);
        }
        for (Integer regionId : regionIds) {
            AdminRegion link = new AdminRegion();
            link.setAdmin_id(id);
            link.setRegion_id(regionId);
            adminRegionMapper.insert(link);
        }
        Map<String, Object> before = new LinkedHashMap<>();
        before.put("shopIds", beforeShopIds);
        before.put("regionIds", beforeRegionIds);
        Map<String, Object> after = new LinkedHashMap<>();
        after.put("shopIds", shopIds);
        after.put("regionIds", regionIds);
        securityAuditService.recordPermissionChange(currentRequest, "admin_scope_changed",
                String.valueOf(id), before, after);
        return R.ok();
    }

    /**
     * 创建新管理员账号，并可选择同时绑定角色（权限）。
     * 仅具备 admin:manage 权限的管理员可调用。
     */
    @PostMapping("/administrator/create")
    @Transactional
    public R createAdministrator(@RequestBody Map<String, Object> body) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        String userName = body.get("userName") != null ? body.get("userName").toString().trim() : null;
        String password = body.get("password") != null ? body.get("password").toString().trim() : null;
        if (StringUtil.isEmpty(userName)) {
            return R.error("用户名不能为空");
        }
        if (StringUtil.isEmpty(password)) {
            return R.error("密码不能为空");
        }
        Admin exists = adminService.getOne(new QueryWrapper<Admin>().eq("userName", userName));
        if (exists != null) {
            return R.error("用户名已存在");
        }
        List<Integer> roleIds = parseNumberList(body.get("roleIds"));
        if (!roleIds.isEmpty()) {
            Integer count = roleMapper.selectCount(new QueryWrapper<Role>().in("id", roleIds));
            if (count == null || count != roleIds.size()) {
                return R.error("部分角色ID不存在，请刷新后重试");
            }
        }
        String workNo = body.get("workNo") != null ? body.get("workNo").toString().trim()
                : (body.get("work_no") != null ? body.get("work_no").toString().trim() : null);
        String realName = body.get("realName") != null ? body.get("realName").toString().trim()
                : (body.get("real_name") != null ? body.get("real_name").toString().trim() : null);
        String jobTitle = body.get("jobTitle") != null ? body.get("jobTitle").toString().trim()
                : (body.get("job_title") != null ? body.get("job_title").toString().trim() : null);

        if (StringUtils.hasText(workNo)) {
            Admin existingWorkNo = adminService.getOne(new QueryWrapper<Admin>().eq("work_no", workNo));
            if (existingWorkNo != null) {
                return R.error("工号已存在");
            }
        }

        Admin admin = new Admin();
        admin.setUserName(userName);
        admin.setPassword(AdminPasswordUtil.encode(password));
        admin.setWorkNo(workNo);
        admin.setRealName(realName);
        admin.setJobTitle(jobTitle);
        adminService.save(admin);

        if (!roleIds.isEmpty()) {
            for (Integer roleId : roleIds) {
                AdminRole ar = new AdminRole();
                ar.setAdmin_id(admin.getId());
                ar.setRole_id(roleId);
                adminRoleMapper.insert(ar);
            }
        }
        List<Integer> shopIds = parseNumberList(body.get("shopIds"));
        if (!shopIds.isEmpty()) {
            for (Integer shopId : shopIds) {
                AdminShop as = new AdminShop();
                as.setAdmin_id(admin.getId());
                as.setShop_id(shopId);
                adminShopMapper.insert(as);
            }
        }
        Map<String, Object> afterDetails = new LinkedHashMap<>();
        afterDetails.put("roleIds", roleIds);
        afterDetails.put("shopIds", shopIds);
        securityAuditService.recordPermissionChange(currentRequest, "administrator_created",
                String.valueOf(admin.getId()), null, afterDetails);
        R ok = R.ok();
        ok.put("id", admin.getId());
        return ok;
    }

    /**
     * 更新管理员/员工基本资料（工号、姓名、岗位、可选重置密码）。
     * 仅具备 admin:manage 权限可访问。
     */
    @PutMapping("/administrator/{id}")
    @Transactional
    public R updateAdministrator(@PathVariable Integer id, @RequestBody Map<String, Object> body) {
        if (id == null) {
            return R.error("管理员ID不能为空");
        }
        Admin admin = adminService.getById(id);
        if (admin == null) {
            return R.error("管理员不存在");
        }
        if (body == null) {
            return R.error("请求体不能为空");
        }
        String workNo = body.get("workNo") != null ? body.get("workNo").toString().trim()
                : (body.get("work_no") != null ? body.get("work_no").toString().trim() : null);
        String realName = body.get("realName") != null ? body.get("realName").toString().trim()
                : (body.get("real_name") != null ? body.get("real_name").toString().trim() : null);
        String jobTitle = body.get("jobTitle") != null ? body.get("jobTitle").toString().trim()
                : (body.get("job_title") != null ? body.get("job_title").toString().trim() : null);
        String password = body.get("password") != null ? body.get("password").toString().trim() : null;

        if (StringUtils.hasText(workNo)) {
            Admin existingWorkNo = adminService.getOne(new QueryWrapper<Admin>().eq("work_no", workNo).ne("id", id));
            if (existingWorkNo != null) {
                return R.error("工号已存在");
            }
            admin.setWorkNo(workNo);
        } else if (body.containsKey("workNo") || body.containsKey("work_no")) {
            admin.setWorkNo(null);
        }

        if (body.containsKey("realName") || body.containsKey("real_name")) {
            admin.setRealName(realName);
        }
        if (body.containsKey("jobTitle") || body.containsKey("job_title")) {
            admin.setJobTitle(jobTitle);
        }
        if (StringUtils.hasText(password)) {
            admin.setPassword(AdminPasswordUtil.encode(password));
            admin.setTokenVersion((admin.getTokenVersion() == null ? 0 : admin.getTokenVersion()) + 1);
        }
        adminService.updateById(admin);
        securityAuditService.recordPermissionChange(currentRequest, "administrator_updated",
                String.valueOf(admin.getId()), null, body);
        return R.ok();
    }

    /**
     * 删除管理员/员工账号。
     * 仅具备 admin:manage 权限可访问。
     */
    @DeleteMapping("/administrator/{id}")
    @Transactional
    public R deleteAdministrator(@PathVariable Integer id,
                                 @RequestParam(defaultValue = "false") boolean confirm) {
        if (id == null) {
            return R.error("管理员ID不能为空");
        }
        Integer currentAdminId = currentAdminId();
        if (currentAdminId != null && currentAdminId.equals(id)) {
            return R.error("安全保护：不能删除当前正在登录的账号");
        }
        Admin admin = adminService.getById(id);
        if (admin == null) {
            return R.error("管理员不存在");
        }
        if (!confirm) {
            return R.error(400, "删除操作需要确认（confirm=true）");
        }
        adminRoleMapper.delete(new QueryWrapper<AdminRole>().eq("admin_id", id));
        adminShopMapper.delete(new QueryWrapper<AdminShop>().eq("admin_id", id));
        if (adminRegionMapper != null) {
            adminRegionMapper.delete(new QueryWrapper<AdminRegion>().eq("admin_id", id));
        }
        adminService.removeById(id);
        Map<String, Object> before = new LinkedHashMap<>();
        before.put("id", admin.getId());
        before.put("userName", admin.getUserName());
        before.put("workNo", admin.getWorkNo());
        before.put("realName", admin.getRealName());
        securityAuditService.recordPermissionChange(currentRequest, "administrator_deleted",
                String.valueOf(id), before, null);
        return R.ok("员工账号已删除");
    }

    private Integer currentAdminId() {
        Object adminId = currentRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        return adminId instanceof Integer ? (Integer) adminId : null;
    }

    private List<Integer> parseNumberList(Object obj) {
        List<Integer> list = new ArrayList<>();
        if (!(obj instanceof List)) {
            return list;
        }
        for (Object o : (List<?>) obj) {
            if (o instanceof Number) {
                list.add(((Number) o).intValue());
            }
        }
        return list.stream().distinct().collect(Collectors.toList());
    }

    private List<Integer> listShopIdsByAdminId(Integer adminId) {
        if (adminId == null) {
            return Collections.emptyList();
        }
        List<AdminShop> links = adminShopMapper.selectList(new QueryWrapper<AdminShop>().eq("admin_id", adminId));
        return links.stream().map(AdminShop::getShop_id).filter(Objects::nonNull).distinct().collect(Collectors.toList());
    }

    private List<Integer> listRegionIdsByAdminId(Integer adminId) {
        if (adminId == null) {
            return Collections.emptyList();
        }
        List<AdminRegion> links = adminRegionMapper.selectList(new QueryWrapper<AdminRegion>().eq("admin_id", adminId));
        return links.stream().map(AdminRegion::getRegion_id).filter(Objects::nonNull).distinct().collect(Collectors.toList());
    }

}
