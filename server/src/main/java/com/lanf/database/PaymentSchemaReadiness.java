package com.lanf.database;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import javax.annotation.PostConstruct;
import java.util.List;

/** Refuse startup before payment work is scheduled if the explicit migration is absent. */
@Component("paymentSchemaReadiness")
public class PaymentSchemaReadiness {
    private final JdbcTemplate jdbc;
    public PaymentSchemaReadiness(JdbcTemplate jdbc) { this.jdbc = jdbc; }
    @PostConstruct public void verify() throws Exception {
        List<String> versions = jdbc.queryForList("SELECT checksum FROM t_app_schema_version WHERE version='V007'",String.class);
        if (versions.size()!=1 || !AuditSchemaMigration.checksum().equals(versions.get(0)))
            throw new IllegalStateException("Apply C007 V007 migration with AuditSchemaMigration before starting the server");

        for (String select : new String[]{
                "SELECT shop_id,order_no,idempotency_key,out_refund_no,requested_fen,applied_fen,status FROM t_payment_refund_request WHERE 1=0",
                "SELECT shop_id,order_no,idempotency_key FROM t_payment_refund_guard WHERE 1=0",
                "SELECT shop_id,order_no,session_id,channel,amount_fen,status,expires_at,created_at,updated_at FROM t_cashier_collection_intent WHERE 1=0",
                "SELECT event_id,channel,amount_fen,amount_yuan,timestamp_raw,raw_text,matched_shop_id,matched_order_no,status,remark,created_at FROM t_personal_payment_event WHERE 1=0",
                "SELECT invite_record_id,inviter_user_id,order_no,outstanding_amount,status,attempts,last_error FROM t_invite_reward_clawback WHERE 1=0",
                "SELECT device_id,workflows FROM t_kds_device_workflow WHERE 1=0",
                "SELECT shop_id,order_no,request_id,entry_type,channel,amount_fen,status,business_day,source,trust_level FROM t_payment_ledger WHERE 1=0",
                "SELECT shop_id,order_id,order_no,out_trade_no,merchant_id,amount_fen,code_url,status,trade_state,active_key,expires_at FROM t_wechat_native_payment_attempt WHERE 1=0",
                "SELECT api_v2_key_enc,client_cert_p12_ref FROM t_payment_merchant_config WHERE 1=0",
                "SELECT shop_id,order_id,order_no,out_trade_no,merchant_id,amount_fen,status,trade_state,active_key,terminal_id,client_ip FROM t_wechat_micropay_attempt WHERE 1=0",
                "SELECT shop_id,session_no,terminal_id,drawer_code,state,opening_float_fen,expected_cash_fen,counted_cash_fen,variance_fen FROM t_drawer_session WHERE 1=0",
                "SELECT shop_id,movement_no,drawer_session_id,movement_type,amount_fen,current_balance_fen,operator_id FROM t_cash_movement WHERE 1=0",
                "SELECT drawer_session_id,terminal_id,state,business_day,version FROM t_shift WHERE 1=0",
                "SELECT snapshot_id FROM t_daily_stat WHERE 1=0",
                "SELECT shop_id,business_day,snapshot_no,settle_idempotency_key FROM t_daily_close_snapshot WHERE 1=0"}) jdbc.queryForList(select);
    }
}
