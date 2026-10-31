package com.lanf.service;

import java.io.IOException;

/**
 * 飞鹅云打印服务。
 *
 * <p>自 v1.2.223 起，本接口只保留「显式凭据」变体：所有 apiUrl / user / ukey 均要求由调用方
 * 从 {@code t_printing_device.connection_json}（或经统一调度器）传入，不再支持门店配置
 * （t_shop_printer_config）与全局配置（feieyun.*）兜底解析。</p>
 */
public interface IFeieyunService {

    /**
     * 使用指定凭据打印 — Open_printMsg
     */
    String printWithCredential(String apiUrl, String user, String ukey,
                               String sn, String content, int times) throws IOException;

    /**
     * 使用指定凭据打印标签 — Open_printLabelMsg
     */
    String printLabelMsgWithCredential(String apiUrl, String user, String ukey,
                                       String sn, String content, int times) throws IOException;

    /**
     * 使用指定凭据查询订单状态 — Open_queryOrderState
     */
    String queryOrderStateWithCredential(String apiUrl, String user, String ukey,
                                         String orderId) throws IOException;

    /**
     * 使用指定凭据查询打印机状态 — Open_queryPrinterStatus
     */
    String queryPrinterStatusWithCredential(String apiUrl, String user, String ukey,
                                            String sn) throws IOException;

    /**
     * 使用指定凭据添加打印机 — Open_printerAddlist
     */
    String addPrinterWithCredential(String apiUrl, String user, String ukey, String snList) throws IOException;

    /**
     * 使用指定凭据删除打印机 — Open_printerDelList
     */
    String deletePrinterWithCredential(String apiUrl, String user, String ukey, String snList) throws IOException;

    /**
     * 使用指定凭据清空打印机待打印队列 — Open_delPrinterSqs
     */
    String clearPrintQueueWithCredential(String apiUrl, String user, String ukey, String sn) throws IOException;
}
