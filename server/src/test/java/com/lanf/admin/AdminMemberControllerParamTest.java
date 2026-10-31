package com.lanf.admin;

import com.lanf.config.GlobalApiExceptionHandler;
import com.lanf.controller.admin.AdminMemberController;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 回归：GET /admin/member/profile 与 /admin/member/consumption 未传必填 phone 时，
 * 应返回「手机号不能为空」业务提示（HTTP 200 + code!=0），而不是走全局兜底 500
 * （服务器处理失败，请稍后重试）。
 * <p>
 * 线上故障 api-1788988159071365-10214：缺参抛 MissingServletRequestParameterException，
 * 无专门异常分支 → @ResponseStatus(500) 兜底。修复为 required=false 后由方法内守卫早退。
 */
public class AdminMemberControllerParamTest {

    private MockMvc mvcWithAdvice() {
        return MockMvcBuilders.standaloneSetup(new AdminMemberController())
                .setControllerAdvice(new GlobalApiExceptionHandler())
                .build();
    }

    @Test
    void profileWithoutPhoneReturnsFriendlyErrorNot500() throws Exception {
        mvcWithAdvice().perform(get("/admin/member/profile"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(500))
                .andExpect(jsonPath("$.msg").value("手机号不能为空"));
    }

    @Test
    void consumptionWithoutPhoneReturnsFriendlyErrorNot500() throws Exception {
        mvcWithAdvice().perform(get("/admin/member/consumption"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(500))
                .andExpect(jsonPath("$.msg").value("手机号不能为空"));
    }
}
