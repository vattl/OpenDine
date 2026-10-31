package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.lanf.dto.AnnouncementSaveDTO;
import com.lanf.entity.Announcement;
import com.lanf.entity.R;
import com.lanf.notify.service.UnifiedNotificationService;
import com.lanf.service.IAnnouncementService;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.AnnouncementDateParser;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 运营后台：门店公告 CRUD（连锁）。
 */
@RestController
@RequestMapping("/admin/announcement")
public class AdminAnnouncementController {

    @Autowired
    private IAnnouncementService announcementService;
    @Autowired
    private HttpServletRequest httpServletRequest;
    @Autowired(required = false)
    private UnifiedNotificationService unifiedNotificationService;

    @GetMapping("/list")
    public R list(@RequestParam(required = false) Integer status) {
        try {
            Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
            List<Announcement> list = announcementService.listForAdmin(sid, status);
            Map<String, Object> res = new HashMap<>();
            res.put("list", list);
            res.put("total", list != null ? list.size() : 0);
            return R.ok(res);
        } catch (Exception e) {
            return R.error("查询失败：" + (e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName()));
        }
    }

    @GetMapping("/get")
    public R get(@RequestParam Long id) {
        if (id == null || id <= 0) {
            return R.error("id 不能为空");
        }
        Announcement row = announcementService.getById(id);
        if (row == null) {
            return R.error("公告不存在");
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (!visibleInAdminList(row, sid)) {
            return R.error(4003, "公告不在当前门店可见范围内");
        }
        return R.ok().put("announcement", row);
    }

    /** 门店上下文下可查看「全店 + 本店」；无门店时可查看任意（HQ） */
    private static boolean visibleInAdminList(Announcement row, Integer resolvedShopId) {
        if (row == null) {
            return false;
        }
        if (resolvedShopId == null) {
            return true;
        }
        return row.getShop_id() == null || resolvedShopId.equals(row.getShop_id());
    }

    @PostMapping("/add")
    @AuditLog(module = "announcement", action = "admin_announcement_add")
    public R add(@RequestBody AnnouncementSaveDTO body) {
        if (body == null) {
            return R.error("参数不能为空");
        }
        if (!StringUtils.hasText(body.getTitle())) {
            return R.error("title 不能为空");
        }
        if (!StringUtils.hasText(body.getContent())) {
            return R.error("content 不能为空");
        }
        Date start;
        Date end;
        try {
            start = AnnouncementDateParser.parse(body.getStartTime());
            end = AnnouncementDateParser.parse(body.getEndTime());
        } catch (RuntimeException e) {
            return R.error(400, e.getMessage() != null ? e.getMessage() : "日期格式错误");
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        Announcement entity = new Announcement();
        entity.setTitle(body.getTitle().trim());
        entity.setContent(body.getContent());
        entity.setSort_order(body.getSortOrder() != null ? body.getSortOrder() : 0);
        entity.setStatus(body.getStatus() != null ? body.getStatus() : 1);
        entity.setStart_time(start);
        entity.setEnd_time(end);
        if (sid != null) {
            entity.setShop_id(sid);
            if (body.getShopId() != null && !body.getShopId().equals(sid)) {
                return R.error(4003, "门店账号仅能创建本店公告");
            }
        } else {
            entity.setShop_id(body.getShopId());
        }
        Date now = new Date();
        entity.setCreated_at(now);
        entity.setUpdated_at(now);
        announcementService.save(entity);
        if (unifiedNotificationService != null) {
            try {
                unifiedNotificationService.publishShopAnnouncementChanged("PUBLISHED", entity);
            } catch (Exception ignore) {
            }
        }
        return R.ok().put("id", entity.getId());
    }

    @PostMapping("/update")
    @AuditLog(module = "announcement", action = "admin_announcement_update", target = "#p0.id")
    public R update(@RequestBody AnnouncementSaveDTO body) {
        if (body == null || body.getId() == null || body.getId() <= 0) {
            return R.error("id 不能为空");
        }
        Announcement existing = announcementService.getById(body.getId());
        if (existing == null) {
            return R.error("公告不存在");
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (!announcementService.canWriteRow(existing, sid)) {
            return R.error(4003, "无权限修改该公告（全部门店公告仅总部上下文可改）");
        }
        if (StringUtils.hasText(body.getTitle())) {
            existing.setTitle(body.getTitle().trim());
        }
        if (body.getContent() != null) {
            existing.setContent(body.getContent());
        }
        if (body.getSortOrder() != null) {
            existing.setSort_order(body.getSortOrder());
        }
        if (body.getStatus() != null) {
            existing.setStatus(body.getStatus());
        }
        if (body.getStartTime() != null || body.getEndTime() != null) {
            try {
                if (body.getStartTime() != null) {
                    existing.setStart_time(AnnouncementDateParser.parse(body.getStartTime()));
                }
                if (body.getEndTime() != null) {
                    existing.setEnd_time(AnnouncementDateParser.parse(body.getEndTime()));
                }
            } catch (RuntimeException e) {
                return R.error(400, e.getMessage() != null ? e.getMessage() : "日期格式错误");
            }
        }
        if (sid == null && body.getShopId() != null) {
            existing.setShop_id(body.getShopId());
        }
        existing.setUpdated_at(new Date());
        announcementService.updateById(existing);
        if (unifiedNotificationService != null) {
            try {
                unifiedNotificationService.publishShopAnnouncementChanged("UPDATED", existing);
            } catch (Exception ignore) {
            }
        }
        return R.ok("更新成功");
    }

    @GetMapping("/delete")
    public R delete(@RequestParam Long id) {
        if (id == null || id <= 0) {
            return R.error("id 不能为空");
        }
        Announcement existing = announcementService.getById(id);
        if (existing == null) {
            return R.error("公告不存在");
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (!announcementService.canWriteRow(existing, sid)) {
            return R.error(4003, "无权限删除该公告");
        }
        announcementService.removeById(id);
        if (unifiedNotificationService != null) {
            try {
                unifiedNotificationService.publishShopAnnouncementChanged("DELETED", existing);
            } catch (Exception ignore) {
            }
        }
        return R.ok("删除成功");
    }
}
