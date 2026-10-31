package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.SubscribeSceneTemplate;
import com.lanf.entity.SubscribeSendLog;
import com.lanf.entity.UserSubscribeQuota;
import com.lanf.mapper.SubscribeSceneTemplateMapper;
import com.lanf.mapper.SubscribeSendLogMapper;
import com.lanf.mapper.UserSubscribeQuotaMapper;
import com.lanf.service.IWechatSubscribeQuotaService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.*;

@Slf4j
@Service
public class WechatSubscribeQuotaServiceImpl implements IWechatSubscribeQuotaService {

    @Autowired(required = false)
    private SubscribeSceneTemplateMapper sceneTemplateMapper;

    @Autowired(required = false)
    private UserSubscribeQuotaMapper quotaMapper;

    @Autowired(required = false)
    private SubscribeSendLogMapper sendLogMapper;

    @Override
    public Map<String, Object> getPromptDecision(String openid, String sceneCode) {
        Map<String, Object> out = new LinkedHashMap<>();
        if (!StringUtils.hasText(openid)) {
            out.put("need_prompt", false);
            out.put("reason", "OPENID_REQUIRED");
            out.put("tmpl_ids", Collections.emptyList());
            return out;
        }

        // 1. 获取目标场景列表（启用中）
        QueryWrapper<SubscribeSceneTemplate> qw = new QueryWrapper<SubscribeSceneTemplate>().eq("is_active", 1);
        if (StringUtils.hasText(sceneCode)) {
            qw.eq("scene_code", sceneCode.trim());
        }
        List<SubscribeSceneTemplate> scenes = sceneTemplateMapper != null ? sceneTemplateMapper.selectList(qw) : Collections.emptyList();
        if (scenes.isEmpty()) {
            out.put("need_prompt", false);
            out.put("reason", "NO_ACTIVE_SCENES");
            out.put("tmpl_ids", Collections.emptyList());
            return out;
        }

        // 2. 查询用户各场景已有的配额记录
        List<UserSubscribeQuota> userQuotas = quotaMapper != null
                ? quotaMapper.selectList(new QueryWrapper<UserSubscribeQuota>().eq("openid", openid.trim()))
                : Collections.emptyList();
        Map<String, UserSubscribeQuota> quotaMap = new HashMap<>();
        for (UserSubscribeQuota q : userQuotas) {
            if (q != null && q.getScene_code() != null) {
                quotaMap.put(q.getScene_code(), q);
            }
        }

        List<String> promptTmplIds = new ArrayList<>();
        List<Map<String, Object>> sceneDecisions = new ArrayList<>();
        boolean anyNeedPrompt = false;

        for (SubscribeSceneTemplate st : scenes) {
            String sc = st.getScene_code();
            String tmplId = st.getTemplate_id();
            UserSubscribeQuota uq = quotaMap.get(sc);

            int quota = (uq != null && uq.getAvailable_quota() != null) ? uq.getAvailable_quota() : 0;
            int banStatus = (uq != null && uq.getBan_status() != null) ? uq.getBan_status() : 0;

            Map<String, Object> item = new LinkedHashMap<>();
            item.put("scene_code", sc);
            item.put("template_id", tmplId);
            item.put("title", st.getTitle());
            item.put("available_quota", quota);

            if (quota > 0) {
                // 已有额度，无需打扰
                item.put("need_prompt", false);
                item.put("reason", "HAS_AVAILABLE_QUOTA");
            } else if (banStatus == 1) {
                // 用户已永久拒绝
                item.put("need_prompt", false);
                item.put("reason", "USER_PERMANENTLY_DECLINED");
            } else {
                // 额度为0，需要引导用户授权
                item.put("need_prompt", true);
                item.put("reason", "QUOTA_EXHAUSTED");
                anyNeedPrompt = true;
                if (StringUtils.hasText(tmplId) && !promptTmplIds.contains(tmplId.trim())) {
                    promptTmplIds.add(tmplId.trim());
                }
            }
            sceneDecisions.add(item);
        }

        // 微信规定一次最多支持 3 个模板 ID
        if (promptTmplIds.size() > 3) {
            promptTmplIds = promptTmplIds.subList(0, 3);
        }

        out.put("need_prompt", anyNeedPrompt);
        out.put("tmpl_ids", promptTmplIds);
        out.put("scene_decisions", sceneDecisions);
        return out;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> reportAuthResult(String openid, String sceneCode, Map<String, String> authResults) {
        Map<String, Object> out = new LinkedHashMap<>();
        if (!StringUtils.hasText(openid) || authResults == null || authResults.isEmpty()) {
            out.put("status", "IGNORED");
            out.put("message", "openid 或 authResults 不能为空");
            return out;
        }

        // 建立 template_id 到 scene_code 映射
        Map<String, String> tmplToScene = new HashMap<>();
        if (sceneTemplateMapper != null) {
            List<SubscribeSceneTemplate> list = sceneTemplateMapper.selectList(new QueryWrapper<SubscribeSceneTemplate>().eq("is_active", 1));
            for (SubscribeSceneTemplate s : list) {
                if (s != null && s.getTemplate_id() != null && s.getScene_code() != null) {
                    tmplToScene.put(s.getTemplate_id().trim(), s.getScene_code());
                }
            }
        }

        int acceptTotal = 0;
        int rejectTotal = 0;

        for (Map.Entry<String, String> entry : authResults.entrySet()) {
            String tmplId = entry.getKey() != null ? entry.getKey().trim() : "";
            String result = entry.getValue() != null ? entry.getValue().trim().toLowerCase(Locale.ROOT) : "";

            if (!StringUtils.hasText(tmplId)) continue;

            String resolvedScene = StringUtils.hasText(sceneCode) ? sceneCode.trim() : tmplToScene.get(tmplId);
            if (!StringUtils.hasText(resolvedScene)) {
                resolvedScene = "COMMON";
            }

            if ("accept".equals(result)) {
                if (quotaMapper != null) {
                    quotaMapper.recordAccept(openid.trim(), resolvedScene, tmplId);
                }
                acceptTotal++;
                log.info("[subscribe-quota] Recorded accept for openid={}, scene={}, tmpl={}", openid, resolvedScene, tmplId);
            } else if ("reject".equals(result)) {
                if (quotaMapper != null) {
                    quotaMapper.recordReject(openid.trim(), resolvedScene, tmplId, 0);
                }
                rejectTotal++;
                log.info("[subscribe-quota] Recorded reject for openid={}, scene={}, tmpl={}", openid, resolvedScene, tmplId);
            } else if ("ban".equals(result)) {
                if (quotaMapper != null) {
                    quotaMapper.recordReject(openid.trim(), resolvedScene, tmplId, 1);
                }
                rejectTotal++;
                log.warn("[subscribe-quota] User permanently banned subscribe for openid={}, scene={}, tmpl={}", openid, resolvedScene, tmplId);
            }
        }

        out.put("status", "SUCCESS");
        out.put("accepted", acceptTotal);
        out.put("rejected", rejectTotal);
        out.put("quotas", getUserQuotaSummary(openid));
        return out;
    }

    @Override
    public boolean hasAvailableQuota(String openid, String sceneCode) {
        if (!StringUtils.hasText(openid) || !StringUtils.hasText(sceneCode) || quotaMapper == null) {
            return false;
        }
        UserSubscribeQuota q = quotaMapper.selectOne(new QueryWrapper<UserSubscribeQuota>()
                .eq("openid", openid.trim())
                .eq("scene_code", sceneCode.trim()));
        return q != null && q.getAvailable_quota() != null && q.getAvailable_quota() > 0;
    }

    @Override
    public SubscribeSceneTemplate getActiveTemplateByScene(String sceneCode) {
        if (!StringUtils.hasText(sceneCode) || sceneTemplateMapper == null) {
            return null;
        }
        return sceneTemplateMapper.selectOne(new QueryWrapper<SubscribeSceneTemplate>()
                .eq("scene_code", sceneCode.trim())
                .eq("is_active", 1));
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void handleSendResult(String openid, String sceneCode, String templateId,
                                  int errcode, String errmsg, String bizNo,
                                  long durationMs, String payloadSummary) {
        int quotaBefore = 0;
        int quotaAfter = 0;

        if (quotaMapper != null && StringUtils.hasText(openid) && StringUtils.hasText(sceneCode)) {
            UserSubscribeQuota cur = quotaMapper.selectOne(new QueryWrapper<UserSubscribeQuota>()
                    .eq("openid", openid.trim())
                    .eq("scene_code", sceneCode.trim()));
            if (cur != null && cur.getAvailable_quota() != null) {
                quotaBefore = cur.getAvailable_quota();
            }

            if (errcode == 0) {
                // 发送成功，配额递减
                quotaMapper.decrementQuota(openid.trim(), sceneCode.trim());
                quotaAfter = Math.max(0, quotaBefore - 1);
            } else if (errcode == 43101) {
                // 43101: 用户拒绝或额度耗尽，自动自愈校准配额归零
                quotaMapper.resetQuotaToZero(openid.trim(), sceneCode.trim());
                quotaAfter = 0;
                log.warn("[subscribe-quota] Errcode 43101 received for openid={}, reset quota to 0", openid);
            } else {
                quotaAfter = quotaBefore;
            }
        }

        // 落盘审计日志
        if (sendLogMapper != null) {
            try {
                SubscribeSendLog sendLog = new SubscribeSendLog();
                sendLog.setBiz_no(bizNo);
                sendLog.setOpenid(openid);
                sendLog.setScene_code(sceneCode);
                sendLog.setTemplate_id(templateId);
                sendLog.setSend_status(errcode == 0 ? "SUCCESS" : "FAILED");
                sendLog.setErrcode(errcode);
                sendLog.setErrmsg(errmsg != null && errmsg.length() > 250 ? errmsg.substring(0, 250) : errmsg);
                sendLog.setQuota_before(quotaBefore);
                sendLog.setQuota_after(quotaAfter);
                sendLog.setDuration_ms(durationMs);
                sendLog.setPayload_summary(payloadSummary != null && payloadSummary.length() > 500 ? payloadSummary.substring(0, 500) : payloadSummary);
                sendLog.setCreated_at(new Date());
                sendLogMapper.insert(sendLog);
            } catch (Exception e) {
                log.error("[subscribe-quota] Record send log failed: {}", e.getMessage());
            }
        }
    }

    @Override
    public Map<String, Object> getUserQuotaSummary(String openid) {
        Map<String, Object> out = new LinkedHashMap<>();
        if (!StringUtils.hasText(openid) || quotaMapper == null) {
            return out;
        }
        List<UserSubscribeQuota> list = quotaMapper.selectList(new QueryWrapper<UserSubscribeQuota>()
                .eq("openid", openid.trim()));
        for (UserSubscribeQuota q : list) {
            if (q != null && q.getScene_code() != null) {
                Map<String, Object> detail = new LinkedHashMap<>();
                detail.put("template_id", q.getTemplate_id());
                detail.put("available_quota", q.getAvailable_quota() != null ? q.getAvailable_quota() : 0);
                detail.put("accept_count", q.getAccept_count() != null ? q.getAccept_count() : 0);
                detail.put("reject_count", q.getReject_count() != null ? q.getReject_count() : 0);
                detail.put("ban_status", q.getBan_status() != null && q.getBan_status() == 1);
                detail.put("last_authorized_at", q.getLast_authorized_at());
                detail.put("last_sent_at", q.getLast_sent_at());
                out.put(q.getScene_code(), detail);
            }
        }
        return out;
    }

    @Override
    public List<SubscribeSceneTemplate> listSceneTemplates() {
        if (sceneTemplateMapper == null) return Collections.emptyList();
        return sceneTemplateMapper.selectList(new QueryWrapper<SubscribeSceneTemplate>().orderByAsc("id"));
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public boolean saveOrUpdateSceneTemplate(SubscribeSceneTemplate template) {
        if (template == null || !StringUtils.hasText(template.getScene_code()) || sceneTemplateMapper == null) {
            return false;
        }
        SubscribeSceneTemplate exist = sceneTemplateMapper.selectOne(new QueryWrapper<SubscribeSceneTemplate>()
                .eq("scene_code", template.getScene_code().trim()));
        if (exist != null) {
            template.setId(exist.getId());
            template.setUpdated_at(new Date());
            return sceneTemplateMapper.updateById(template) > 0;
        } else {
            template.setCreated_at(new Date());
            template.setUpdated_at(new Date());
            return sceneTemplateMapper.insert(template) > 0;
        }
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public boolean deleteSceneTemplate(String sceneCode) {
        if (!StringUtils.hasText(sceneCode) || sceneTemplateMapper == null) {
            return false;
        }
        return sceneTemplateMapper.delete(new QueryWrapper<SubscribeSceneTemplate>()
                .eq("scene_code", sceneCode.trim())) > 0;
    }

    @Override
    public List<SubscribeSendLog> listSendLogs(String bizNo, String openid, String sceneCode, String status, int limit) {
        if (sendLogMapper == null) return Collections.emptyList();
        QueryWrapper<SubscribeSendLog> qw = new QueryWrapper<SubscribeSendLog>().orderByDesc("id");
        if (StringUtils.hasText(bizNo)) {
            qw.eq("biz_no", bizNo.trim());
        }
        if (StringUtils.hasText(openid)) {
            qw.eq("openid", openid.trim());
        }
        if (StringUtils.hasText(sceneCode)) {
            qw.eq("scene_code", sceneCode.trim());
        }
        if (StringUtils.hasText(status)) {
            qw.eq("send_status", status.trim().toUpperCase(Locale.ROOT));
        }
        int l = limit > 0 && limit <= 200 ? limit : 50;
        qw.last("LIMIT " + l);
        return sendLogMapper.selectList(qw);
    }
}
