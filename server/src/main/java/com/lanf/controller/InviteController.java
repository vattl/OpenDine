package com.lanf.controller;

import com.lanf.config.InvitePosterGenerator;
import com.lanf.config.PosterCacheUtil;
import com.lanf.dto.InviteCodeDTO;
import com.lanf.config.InvitePosterSettings;
import com.lanf.dto.InviteRecordDTO;
import com.lanf.entity.R;
import com.lanf.service.InviteService;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.Base64Utils;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 邀请模块接口（与 OpenAPI / FEATURE_LIST 契约一致）
 * - POST /invite/getCode：获取用户专属邀请码，成功 body 含 invite_code
 * - POST /invite/getRecords：邀请记录列表，成功 body 含 code、data（InviteRecordDTO[]）
 * - GET/POST /invite/getReward：奖励列表（注册礼 + 首单余额返现；同邀请可拆两行，见 InviteRecordDTO.reward_row_uid）
 * - GET /invite/poster?code=：根据邀请码生成海报，成功 body 含 posterUrl（Base64）
 */
@RestController
@RequestMapping("/invite")
@RequiredArgsConstructor
public class InviteController {

    private static final Logger logger = LoggerFactory.getLogger(InviteController.class);

    private final InviteService inviteService;
    @Autowired
    private InvitePosterGenerator posterGenerator;
    @Autowired
    private PosterCacheUtil posterCacheUtil;
    @Autowired
    private InvitePosterSettings invitePosterSettings;

    /**
     * 获取用户专属邀请码（契约：requestBody required openid，成功 body 含 invite_code）
     */
    @PostMapping("/getCode")
    public R getInviteCode(@RequestBody Map<String, String> params) {
        String openid = params != null ? params.get("openid") : null;
        if (!StringUtils.hasText(openid)) {
            return R.error(2, "openid不能为空");
        }
        openid = openid.trim();
        com.lanf.dto.R<InviteCodeDTO> sr = inviteService.getInviteCode(openid);
        if (sr == null) {
            return R.error(500, "获取邀请码失败");
        }
        if (Integer.valueOf(0).equals(sr.getCode()) && sr.getData() != null) {
            return R.ok().put("invite_code", sr.getData().getInvite_code());
        }
        int code = sr.getCode() != null ? sr.getCode() : 500;
        String msg = StringUtils.hasText(sr.getMsg()) ? sr.getMsg() : "获取邀请码失败";
        return R.error(code, msg);
    }

    /**
     * 邀请记录列表（契约：requestBody required openid，成功 body 含 code、data（InviteRecordDTO[]））
     */
    @PostMapping("/getRecords")
    public R getInviteRecords(@RequestBody Map<String, String> params) {
        String openid = params != null ? params.get("openid") : null;
        if (!StringUtils.hasText(openid)) {
            return R.error(2, "openid不能为空");
        }
        openid = openid.trim();
        try {
            com.lanf.dto.R<List<InviteRecordDTO>> sr = inviteService.getInviteRecords(openid);
            if (sr != null && Integer.valueOf(0).equals(sr.getCode())) {
                List<InviteRecordDTO> list = sr.getData() != null ? sr.getData() : java.util.Collections.emptyList();
                return R.ok().put("data", list);
            }
            int code = (sr != null && sr.getCode() != null) ? sr.getCode() : 500;
            String msg = (sr != null && StringUtils.hasText(sr.getMsg())) ? sr.getMsg() : "获取邀请记录失败，请稍后重试";
            return R.error(code, msg);
        } catch (Exception e) {
            logger.error("获取邀请记录失败", e);
            return R.error(500, "获取邀请记录失败，请稍后重试");
        }
    }

    /**
     * 获取奖励记录（仅已发放奖励的邀请记录，reward_time 非空，与 t_invite_record 表一致，见 db_diancan.sql）
     * 支持 GET ?openid= 或 POST body { "openid": "string" }
     */
    @GetMapping("/getReward")
    public R getReward(@RequestParam(value = "openid", required = false) String openidGet) {
        String openid = openidGet;
        if (!StringUtils.hasText(openid)) {
            return R.error(2, "openid不能为空");
        }
        openid = openid.trim();
        return invokeGetRewardRecords(openid);
    }

    @PostMapping("/getReward")
    public R getRewardPost(@RequestBody Map<String, String> params) {
        String openid = params != null ? params.get("openid") : null;
        if (!StringUtils.hasText(openid)) {
            return R.error(2, "openid不能为空");
        }
        openid = openid.trim();
        return invokeGetRewardRecords(openid);
    }

    private R invokeGetRewardRecords(String openid) {
        try {
            com.lanf.dto.R<List<InviteRecordDTO>> sr = inviteService.getRewardRecords(openid);
            if (sr != null && Integer.valueOf(0).equals(sr.getCode())) {
                List<InviteRecordDTO> list = sr.getData() != null ? sr.getData() : java.util.Collections.emptyList();
                return R.ok().put("data", list);
            }
            int code = (sr != null && sr.getCode() != null) ? sr.getCode() : 500;
            String msg = (sr != null && StringUtils.hasText(sr.getMsg())) ? sr.getMsg() : "获取奖励记录失败";
            return R.error(code, msg);
        } catch (Exception e) {
            logger.error("获取奖励记录失败", e);
            return R.error(500, "获取奖励记录失败，请稍后重试");
        }
    }

    /**
     * 根据邀请码生成海报（契约：GET /invite/poster?code=，成功 body 含 posterUrl（Base64），400 邀请码为空，500 海报生成失败）
     * 错误响应与统一约定一致：body 含 code、msg
     */
    @GetMapping("/poster")
    public ResponseEntity<Map<String, Object>> getInvitePoster(@RequestParam(value = "code", required = false) String code) {
        final String IMAGE_FORMAT = "jpg";
        final String CONTENT_TYPE = IMAGE_FORMAT.equalsIgnoreCase("jpg")
                ? MediaType.IMAGE_JPEG_VALUE
                : MediaType.IMAGE_PNG_VALUE;

        if (!StringUtils.hasText(code)) {
            logger.warn("poster: code参数为空");
            Map<String, Object> err = new HashMap<>();
            err.put("code", 2);
            err.put("msg", "邀请码不能为空");
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(err);
        }
        code = code.trim();

        try {
            byte[] posterBytes = posterCacheUtil.getPosterCache(code);
            if (posterBytes == null) {
                posterBytes = posterGenerator.generatePoster(
                        invitePosterSettings.getBackground().getPath(),
                        code,
                        invitePosterSettings.getQr().getX(),
                        invitePosterSettings.getQr().getY(),
                        invitePosterSettings.getQr().getSize(),
                        IMAGE_FORMAT);
                if (posterBytes == null || posterBytes.length == 0) {
                    logger.error("poster: 海报生成结果为空, code={}", code);
                    Map<String, Object> err = new HashMap<>();
                    err.put("code", 500);
                    err.put("msg", "海报生成失败");
                    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(err);
                }
                posterCacheUtil.setPosterCache(code, posterBytes);
                logger.debug("poster: 生成并缓存成功, code={}, length={}", code, posterBytes.length);
            }

            String base64Str = Base64Utils.encodeToString(posterBytes);
            String posterUrl = "data:" + CONTENT_TYPE + ";base64," + base64Str;
            Map<String, Object> result = new HashMap<>();
            result.put("code", 0);
            result.put("posterUrl", posterUrl);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            logger.error("poster: 海报生成异常, code={}", code, e);
            Map<String, Object> err = new HashMap<>();
            err.put("code", 500);
            err.put("msg", "海报生成失败");
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(err);
        }
    }

    /**
     * 备选接口：直接返回图片二进制（Content-Type: image/jpeg）
     */
    @GetMapping("/poster/alt")
    public ResponseEntity<byte[]> getInvitePosterAlt(@RequestParam(value = "code", required = false) String code) {
        if (!StringUtils.hasText(code)) {
            return ResponseEntity.badRequest().build();
        }
        final String IMAGE_FORMAT = "jpg";
        code = code.trim();
        try {
            byte[] posterBytes = posterGenerator.generatePoster(
                    invitePosterSettings.getBackground().getPath(),
                    code,
                    invitePosterSettings.getQr().getX(),
                    invitePosterSettings.getQr().getY(),
                    invitePosterSettings.getQr().getSize(),
                    IMAGE_FORMAT);
            if (posterBytes == null || posterBytes.length == 0) {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
            }
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.IMAGE_JPEG);
            headers.setContentLength(posterBytes.length);
            return new ResponseEntity<>(posterBytes, headers, HttpStatus.OK);
        } catch (Exception e) {
            logger.error("poster/alt: 生成异常, code={}", code, e);
            return new ResponseEntity<>(HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }
}