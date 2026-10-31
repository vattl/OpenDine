package com.lanf.kds;

/**
 * 流转批次队列状态（与 {@link KdsWorkflowQueue} 对齐，done 表示已传菜归档）。
 */
public final class KdsFlowBatchStatus {

    public static final String PENDING_PREP = "pending_prep";
    public static final String PENDING_COOK = "pending_cook";
    public static final String READY_SERVE = "ready_serve";
    public static final String DONE = "done";
    public static final String VOID = "void";

    private KdsFlowBatchStatus() {
    }
}
