package com.lanf.printing.service;

import com.lanf.printing.model.PrintContext;
import com.lanf.printing.model.PrintTemplateDsl;
import com.lanf.printing.model.PrintDispatchResult;
import com.lanf.printing.model.PrintResolvedPreview;

import java.util.List;

/**
 * 统一打印调度服务接口
 */
public interface PrintDispatcherService {

    /**
     * 业务统一打印入口：依据 (shopId, scenario) 匹配出票规则并派发到对应设备
     * @param shopId 门店 ID
     * @param scenario 场景标识（order, kitchen, serve, shift, refund, label 等）
     * @param context 打印上下文（订单、明细、交接班或自定义内容）
     * @return 生成并执行的打印任务结果列表
     */
    List<PrintDispatchResult> dispatch(int shopId, String scenario, PrintContext context);

    /**
     * 重打指定流水任务
     * @param jobId 打印任务主键 ID
     * @param adminId 操作人 ID
     * @return 重新派发的结果
     */
    PrintDispatchResult reprintJob(long jobId, Integer adminId);

    /**
     * 直接派发自定义文本到指定场景规则设备
     */
    List<PrintDispatchResult> dispatchCustom(int shopId, String scenario, String customContent, Integer adminId);

    /** Resolve real print payloads without sending or recording a print job. */
    List<PrintResolvedPreview> previewExact(int shopId, String scenario, PrintContext context, Long ruleId, Long deviceId);

    /**
     * 设计器预览：与真实打印/精确预览共用同一组装内核；
     * 支持临时 DSL override（templateDsl/templateJson/templateId），临时 DSL 时不要求规则/设备；
     * 未传临时 DSL 时与 previewExact 完全同路径（真实规则），确保预览与真实打印一致。
     */
    List<PrintResolvedPreview> renderPreviewContents(int shopId, String scenario, PrintContext context,
                                                     PrintTemplateDsl dslOverride, Long ruleId, Long deviceId);
}
