package com.lanf.ai.service;

import com.lanf.ai.dto.CreateOrderDraftDTO;
import com.lanf.ai.dto.SubmitAiOrderDTO;
import com.lanf.ai.entity.OrderDraft;
import com.lanf.entity.Order;

public interface IOrderDraftService {

    OrderDraft createDraft(CreateOrderDraftDTO dto);

    OrderDraft validateDraft(String draftId);

    Order submitOrder(SubmitAiOrderDTO dto);
}
