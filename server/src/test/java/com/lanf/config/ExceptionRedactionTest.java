package com.lanf.config;

import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessResourceFailureException;
import static org.junit.jupiter.api.Assertions.*;

class ExceptionRedactionTest {
    @Test void databaseDetailsAreNotReturned() {
        com.lanf.entity.R body = new GlobalApiExceptionHandler().onDataAccess(
                new DataAccessResourceFailureException("password=secret /srv/private t_user.balance"));
        assertFalse(body.toString().contains("secret"));
        assertFalse(body.toString().contains("t_user"));
        assertNotNull(body.get("traceId"));
    }
    @Test void unexpectedErrorsAreNotReturned() {
        com.lanf.entity.R body = new GlobalApiExceptionHandler().onUnhandled(new RuntimeException("private-path"));
        assertFalse(body.toString().contains("private-path"));
        assertNotNull(body.get("traceId"));
    }
}
