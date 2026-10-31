package com.lanf.ai.service;

import com.lanf.ai.dto.CreateDiningSessionDTO;
import com.lanf.ai.dto.MealPlanAdjustDTO;
import com.lanf.ai.dto.MealPlanResponseDTO;
import com.lanf.ai.dto.UpdateDiningSessionDTO;
import com.lanf.ai.entity.DiningSession;
import com.lanf.ai.entity.DiningSessionMember;

import java.util.List;

public interface IDiningSessionService {

    DiningSession createSession(CreateDiningSessionDTO dto);

    DiningSession getSession(String sessionId);

    List<DiningSessionMember> getSessionMembers(String sessionId);

    DiningSession updateSession(String sessionId, UpdateDiningSessionDTO dto);

    MealPlanResponseDTO solveMealPlan(String sessionId, String strategy);

    MealPlanResponseDTO adjustMealPlan(String planId, MealPlanAdjustDTO patchDTO);
}
