package com.lanf.filter;

import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;

/**
 * 对 JSON 请求包装为可重复读取，供拦截器和控制器共享 body。
 */
@Component
public class RequestBodyCacheFilter extends OncePerRequestFilter {

    @org.springframework.beans.factory.annotation.Value("${app.http.max-json-bytes:1048576}")
    private int maxJsonBytes = 1048576;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String contentType = request.getContentType();
        boolean jsonBody = contentType != null && contentType.toLowerCase().contains("application/json");
        if (jsonBody) {
            CachedBodyHttpServletRequest cached;
            try {
                cached = new CachedBodyHttpServletRequest(request, maxJsonBytes);
            } catch (CachedBodyHttpServletRequest.BodyTooLargeException ex) {
                response.setStatus(413);
                response.setContentType("application/json;charset=UTF-8");
                response.getWriter().write("{\"code\":413,\"msg\":\"请求体超过大小限制\"}");
                return;
            }
            filterChain.doFilter(cached, response);
            return;
        }
        filterChain.doFilter(request, response);
    }
}
