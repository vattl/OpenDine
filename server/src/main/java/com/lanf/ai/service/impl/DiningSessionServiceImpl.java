package com.lanf.ai.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.ai.dto.*;
import com.lanf.ai.entity.DiningSession;
import com.lanf.ai.entity.DiningSessionMember;
import com.lanf.ai.entity.MealPlan;
import com.lanf.ai.mapper.DiningSessionMapper;
import com.lanf.ai.mapper.DiningSessionMemberMapper;
import com.lanf.ai.mapper.MealPlanMapper;
import com.lanf.ai.service.IAiMenuAdapterService;
import com.lanf.ai.service.IDiningSessionService;
import com.lanf.ai.solver.LexicographicalMealSolver;
import com.lanf.ai.solver.SolverInput;
import com.lanf.ai.solver.SolverResult;
import com.lanf.common.ApiException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;

@Slf4j
@Service
public class DiningSessionServiceImpl implements IDiningSessionService {

    @Autowired
    private DiningSessionMapper sessionMapper;

    @Autowired
    private DiningSessionMemberMapper memberMapper;

    @Autowired
    private MealPlanMapper mealPlanMapper;

    @Autowired
    private IAiMenuAdapterService menuAdapterService;

    @Autowired
    private LexicographicalMealSolver mealSolver;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    @Transactional(rollbackFor = Exception.class)
    public DiningSession createSession(CreateDiningSessionDTO dto) {
        if (dto == null) {
            throw new ApiException(400, "BAD_REQUEST", "会话创建参数不能为空");
        }
        int partySize = (dto.getParty_size() != null && dto.getParty_size() > 0) ? dto.getParty_size() : 2;
        if (partySize > 20) {
            throw new ApiException(400, "PARTY_SIZE_EXCEEDED", "用餐人数不能超过20人");
        }
        int budgetFen = (dto.getBudget_fen() != null && dto.getBudget_fen() > 0) ? dto.getBudget_fen() : 10000;

        String sessionId = "sess_" + UUID.randomUUID().toString().replace("-", "").substring(0, 16);
        DiningSession session = new DiningSession();
        session.setSession_id(sessionId);
        Integer resolvedShopId = dto.getShop_id() != null ? dto.getShop_id() : (dto.getStore_id() != null ? dto.getStore_id() : 1);
        session.setShop_id(resolvedShopId);
        session.setTable_number(dto.getTable_number() != null ? dto.getTable_number() : "A01");
        session.setParty_size(partySize);
        session.setBudget_fen(budgetFen);
        session.setCurrency(dto.getCurrency() != null ? dto.getCurrency() : "CNY");
        session.setDining_mode(dto.getDining_mode() != null ? dto.getDining_mode() : "dine_in");
        session.setInclude_drinks(Boolean.TRUE.equals(dto.getInclude_drinks()) ? 1 : 0);
        session.setStrategy(dto.getStrategy() != null ? dto.getStrategy() : "balanced");
        session.setRevision(1);
        session.setStatus("COLLECTING");

        if (dto.getTable_goals() != null && !dto.getTable_goals().isEmpty()) {
            try {
                session.setTable_goals(objectMapper.writeValueAsString(dto.getTable_goals()));
            } catch (Exception ignored) {}
        }

        // 默认会话2小时有效期
        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.HOUR_OF_DAY, 2);
        session.setExpires_at(cal.getTime());
        session.setCreated_at(new Date());
        session.setUpdated_at(new Date());

        sessionMapper.insert(session);

        // 初始化成员卡片
        List<DinerMemberDTO> memberDTOs = dto.getMembers();
        if (memberDTOs == null || memberDTOs.isEmpty()) {
            memberDTOs = new ArrayList<>();
            for (int i = 1; i <= partySize; i++) {
                DinerMemberDTO m = new DinerMemberDTO();
                m.setDiner_id("P" + i);
                m.setAlias("顾客" + i);
                m.setIs_non_spicy(false);
                m.setPortion_target("normal");
                m.setJoin_shared_dishes(true);
                memberDTOs.add(m);
            }
        }

        for (DinerMemberDTO m : memberDTOs) {
            DiningSessionMember member = new DiningSessionMember();
            member.setSession_id(sessionId);
            member.setDiner_id(m.getDiner_id() != null ? m.getDiner_id() : "P1");
            member.setAlias(m.getAlias());
            member.setIs_non_spicy(Boolean.TRUE.equals(m.getIs_non_spicy()) ? 1 : 0);
            member.setPortion_target(m.getPortion_target() != null ? m.getPortion_target() : "normal");
            member.setJoin_shared_dishes(m.getJoin_shared_dishes() == null || m.getJoin_shared_dishes() ? 1 : 0);
            member.setCreated_at(new Date());

            if (m.getDisliked_ingredients() != null) {
                try {
                    member.setDisliked_ingredients(objectMapper.writeValueAsString(m.getDisliked_ingredients()));
                } catch (Exception ignored) {}
            }
            if (m.getVerified_allergens() != null) {
                try {
                    member.setVerified_allergens(objectMapper.writeValueAsString(m.getVerified_allergens()));
                } catch (Exception ignored) {}
            }
            if (m.getFitness_goals() != null) {
                try {
                    member.setFitness_goals(objectMapper.writeValueAsString(m.getFitness_goals()));
                } catch (Exception ignored) {}
            }
            memberMapper.insert(member);
        }

        return session;
    }

    @Override
    public DiningSession getSession(String sessionId) {
        if (sessionId == null) return null;
        DiningSession session = sessionMapper.selectOne(new QueryWrapper<DiningSession>().eq("session_id", sessionId));
        if (session != null && session.getExpires_at() != null && session.getExpires_at().before(new Date())) {
            session.setStatus("EXPIRED");
        }
        return session;
    }

    @Override
    public List<DiningSessionMember> getSessionMembers(String sessionId) {
        if (sessionId == null) return Collections.emptyList();
        return memberMapper.selectList(new QueryWrapper<DiningSessionMember>().eq("session_id", sessionId));
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public DiningSession updateSession(String sessionId, UpdateDiningSessionDTO dto) {
        DiningSession session = getSession(sessionId);
        if (session == null) {
            throw new ApiException(404, "SESSION_NOT_FOUND", "点餐会话不存在: " + sessionId);
        }
        if ("EXPIRED".equals(session.getStatus())) {
            throw new ApiException(400, "SESSION_EXPIRED", "点餐会话已失效");
        }

        // 乐观锁版本并发校验
        if (dto.getExpected_revision() != null && !dto.getExpected_revision().equals(session.getRevision())) {
            throw new ApiException(409, "CONCURRENT_CONFLICT", "会话已被其他人修改，请刷新后重试 (Expected revision: " + dto.getExpected_revision() + ", Current: " + session.getRevision() + ")");
        }

        if (dto.getBudget_fen() != null && dto.getBudget_fen() > 0) {
            session.setBudget_fen(dto.getBudget_fen());
        }
        if (dto.getParty_size() != null && dto.getParty_size() > 0) {
            session.setParty_size(dto.getParty_size());
        }
        if (dto.getStrategy() != null) {
            session.setStrategy(dto.getStrategy());
        }
        if (dto.getTable_goals() != null) {
            try {
                session.setTable_goals(objectMapper.writeValueAsString(dto.getTable_goals()));
            } catch (Exception ignored) {}
        }

        session.setRevision(session.getRevision() + 1);
        session.setUpdated_at(new Date());
        sessionMapper.updateById(session);

        // 如果传了 members，做全量/增量同步
        if (dto.getMembers() != null && !dto.getMembers().isEmpty()) {
            memberMapper.delete(new QueryWrapper<DiningSessionMember>().eq("session_id", sessionId));
            for (DinerMemberDTO m : dto.getMembers()) {
                DiningSessionMember member = new DiningSessionMember();
                member.setSession_id(sessionId);
                member.setDiner_id(m.getDiner_id());
                member.setAlias(m.getAlias());
                member.setIs_non_spicy(Boolean.TRUE.equals(m.getIs_non_spicy()) ? 1 : 0);
                member.setPortion_target(m.getPortion_target() != null ? m.getPortion_target() : "normal");
                member.setJoin_shared_dishes(m.getJoin_shared_dishes() == null || m.getJoin_shared_dishes() ? 1 : 0);
                member.setCreated_at(new Date());

                if (m.getDisliked_ingredients() != null) {
                    try {
                        member.setDisliked_ingredients(objectMapper.writeValueAsString(m.getDisliked_ingredients()));
                    } catch (Exception ignored) {}
                }
                if (m.getVerified_allergens() != null) {
                    try {
                        member.setVerified_allergens(objectMapper.writeValueAsString(m.getVerified_allergens()));
                    } catch (Exception ignored) {}
                }
                if (m.getFitness_goals() != null) {
                    try {
                        member.setFitness_goals(objectMapper.writeValueAsString(m.getFitness_goals()));
                    } catch (Exception ignored) {}
                }
                memberMapper.insert(member);
            }
        }

        return session;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public MealPlanResponseDTO solveMealPlan(String sessionId, String strategy) {
        DiningSession session = getSession(sessionId);
        if (session == null) {
            throw new ApiException(404, "SESSION_NOT_FOUND", "点餐会话不存在: " + sessionId);
        }

        List<DiningSessionMember> members = getSessionMembers(sessionId);
        AiMenuSnapshotDTO menuSnapshot = menuAdapterService.getStoreMenuSnapshot(session.getShop_id());

        if (menuSnapshot == null || menuSnapshot.getItems() == null || menuSnapshot.getItems().isEmpty()) {
            MealPlanResponseDTO err = new MealPlanResponseDTO();
            err.setSession_id(sessionId);
            err.setFeasible(false);
            Map<String, Object> conflict = new LinkedHashMap<>();
            conflict.put("status", "REQUIRES_MENU_DATA");
            conflict.put("message", "尚未连接门店真实菜单数据，无法生成可下单报价");
            err.setConflict_details(conflict);
            return err;
        }

        // 构造求解输入
        SolverInput input = new SolverInput();
        input.setParty_size(session.getParty_size());
        input.setBudget_fen(session.getBudget_fen());
        input.setStrategy(strategy != null ? strategy : session.getStrategy());
        input.setMenu_version(menuSnapshot.getMenu_version());
        input.setMenu_items(menuSnapshot.getItems());

        if (session.getTable_goals() != null) {
            try {
                input.setTable_goals(objectMapper.readValue(session.getTable_goals(), new TypeReference<List<String>>() {}));
            } catch (Exception ignored) {}
        }

        List<DinerMemberDTO> memberDTOs = new ArrayList<>();
        for (DiningSessionMember m : members) {
            DinerMemberDTO dto = new DinerMemberDTO();
            dto.setDiner_id(m.getDiner_id());
            dto.setAlias(m.getAlias());
            dto.setIs_non_spicy(m.getIs_non_spicy() != null && m.getIs_non_spicy() == 1);
            dto.setPortion_target(m.getPortion_target());
            dto.setJoin_shared_dishes(m.getJoin_shared_dishes() == null || m.getJoin_shared_dishes() == 1);
            if (m.getDisliked_ingredients() != null) {
                try {
                    dto.setDisliked_ingredients(objectMapper.readValue(m.getDisliked_ingredients(), new TypeReference<List<String>>() {}));
                } catch (Exception ignored) {}
            }
            if (m.getVerified_allergens() != null) {
                try {
                    dto.setVerified_allergens(objectMapper.readValue(m.getVerified_allergens(), new TypeReference<List<String>>() {}));
                } catch (Exception ignored) {}
            }
            if (m.getFitness_goals() != null) {
                try {
                    dto.setFitness_goals(objectMapper.readValue(m.getFitness_goals(), new TypeReference<List<String>>() {}));
                } catch (Exception ignored) {}
            }
            memberDTOs.add(dto);
        }
        input.setMembers(memberDTOs);

        // 调用确定性求解器
        SolverResult solved = mealSolver.solve(input);

        String planId = "plan_" + UUID.randomUUID().toString().replace("-", "").substring(0, 16);
        MealPlan planEntity = new MealPlan();
        planEntity.setPlan_id(planId);
        planEntity.setSession_id(sessionId);
        planEntity.setRevision(session.getRevision());
        planEntity.setMenu_version(menuSnapshot.getMenu_version());
        planEntity.setStrategy(solved.getStrategy());
        planEntity.setFeasible(solved.isFeasible() ? 1 : 0);
        planEntity.setPrice_total_fen(solved.getPrice_total_fen());
        planEntity.setRemaining_budget_fen(solved.getRemaining_budget_fen());
        planEntity.setCreated_at(new Date());

        try {
            planEntity.setLine_items_json(objectMapper.writeValueAsString(solved.getLine_items()));
            planEntity.setAllocation_matrix_json(objectMapper.writeValueAsString(solved.getAllocation_summary()));
            planEntity.setScore_details_json(objectMapper.writeValueAsString(solved.getScore_details()));
            planEntity.setExplanation_cards_json(objectMapper.writeValueAsString(solved.getExplanation_cards()));
            if (solved.getConflict_details() != null) {
                planEntity.setConflict_details_json(objectMapper.writeValueAsString(solved.getConflict_details()));
            }
        } catch (Exception e) {
            log.error("Serialize meal plan error: {}", e.getMessage());
        }

        mealPlanMapper.insert(planEntity);

        // 更新 session 活跃方案
        if (solved.isFeasible()) {
            session.setActive_plan_id(planId);
            session.setStatus("PROPOSED");
            sessionMapper.updateById(session);
        }

        // 构造响应 DTO
        MealPlanResponseDTO resp = new MealPlanResponseDTO();
        resp.setPlan_id(planId);
        resp.setSession_id(sessionId);
        resp.setRevision(session.getRevision());
        resp.setMenu_version(menuSnapshot.getMenu_version());
        resp.setPrice_total_fen(solved.getPrice_total_fen());
        resp.setRemaining_budget_fen(solved.getRemaining_budget_fen());
        resp.setFeasible(solved.isFeasible());
        resp.setStrategy(solved.getStrategy());
        resp.setLine_items(solved.getLine_items());
        resp.setAllocation_summary(solved.getAllocation_summary());
        resp.setScore_details(solved.getScore_details());
        resp.setConflict_details(solved.getConflict_details());
        resp.setExplanation_cards(solved.getExplanation_cards());
        return resp;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public MealPlanResponseDTO adjustMealPlan(String planId, MealPlanAdjustDTO patchDTO) {
        MealPlan oldPlan = mealPlanMapper.selectOne(new QueryWrapper<MealPlan>().eq("plan_id", planId));
        if (oldPlan == null) {
            throw new ApiException(404, "PLAN_NOT_FOUND", "未找到对应配餐方案: " + planId);
        }

        DiningSession session = getSession(oldPlan.getSession_id());
        if (session == null) {
            throw new ApiException(404, "SESSION_NOT_FOUND", "对应点餐会话不存在");
        }

        // 解析补丁并递增 revision
        if (patchDTO != null) {
            if (patchDTO.getBudget_delta_fen() != null) {
                session.setBudget_fen(session.getBudget_fen() + patchDTO.getBudget_delta_fen());
            }

            // 自然语言补丁解析：如「再便宜20元」「不要牛肉」
            String text = patchDTO.getNatural_language_patch();
            if (text != null && !text.trim().isEmpty()) {
                if (text.contains("便宜") || text.contains("降预算") || text.contains("减少")) {
                    // 尝试匹配数字
                    if (text.contains("20") || text.contains("二十")) {
                        session.setBudget_fen(Math.max(1000, session.getBudget_fen() - 2000));
                    } else if (text.contains("30")) {
                        session.setBudget_fen(Math.max(1000, session.getBudget_fen() - 3000));
                    }
                }
                if (text.contains("不要牛肉") || text.contains("不吃牛肉")) {
                    List<DiningSessionMember> members = getSessionMembers(session.getSession_id());
                    if (!members.isEmpty()) {
                        DiningSessionMember m1 = members.get(0);
                        List<String> dislikes = new ArrayList<>();
                        if (m1.getDisliked_ingredients() != null) {
                            try {
                                dislikes = objectMapper.readValue(m1.getDisliked_ingredients(), new TypeReference<List<String>>() {});
                            } catch (Exception ignored) {}
                        }
                        if (!dislikes.contains("牛肉")) {
                            dislikes.add("牛肉");
                            try {
                                m1.setDisliked_ingredients(objectMapper.writeValueAsString(dislikes));
                                memberMapper.updateById(m1);
                            } catch (Exception ignored) {}
                        }
                    }
                }
            }
        }

        session.setRevision(session.getRevision() + 1);
        session.setUpdated_at(new Date());
        sessionMapper.updateById(session);

        // 重新调用求解器生成新方案
        return solveMealPlan(session.getSession_id(), session.getStrategy());
    }
}
