package com.lanf.printing.service;

import com.lanf.printing.model.UnifiedPrintRequest;
import com.lanf.printing.model.UnifiedPrintResponse;

/**
 * 统一出票与补打调度服务接口
 */
public interface UnifiedPrintService {

    /**
     * 统一出票调度
     *
     * @param request 出票请求参数
     * @param operatorAdminId 操作人管理员 ID (可选)
     * @param shopIdContext 门店上下文 ID (可选)
     * @return 统一调度响应结果
     */
    UnifiedPrintResponse dispatch(UnifiedPrintRequest request, Integer operatorAdminId, Integer shopIdContext);
}
