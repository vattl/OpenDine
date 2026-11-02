import 'package:flutter/foundation.dart';

/// 微信订阅消息场景与模板配置实体
@immutable
class SubscribeSceneTemplate {
  const SubscribeSceneTemplate({
    this.id,
    required this.sceneCode,
    required this.templateId,
    required this.title,
    this.triggerPoint = 'SUBMIT_ORDER',
    this.isActive = 1,
    this.paramMappingJson,
    this.remark,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String sceneCode;
  final String templateId;
  final String title;
  final String triggerPoint;
  final int isActive;
  final String? paramMappingJson;
  final String? remark;
  final String? createdAt;
  final String? updatedAt;

  bool get active => isActive == 1;

  SubscribeSceneTemplate copyWith({
    int? id,
    String? sceneCode,
    String? templateId,
    String? title,
    String? triggerPoint,
    int? isActive,
    String? paramMappingJson,
    String? remark,
    String? createdAt,
    String? updatedAt,
  }) {
    return SubscribeSceneTemplate(
      id: id ?? this.id,
      sceneCode: sceneCode ?? this.sceneCode,
      templateId: templateId ?? this.templateId,
      title: title ?? this.title,
      triggerPoint: triggerPoint ?? this.triggerPoint,
      isActive: isActive ?? this.isActive,
      paramMappingJson: paramMappingJson ?? this.paramMappingJson,
      remark: remark ?? this.remark,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory SubscribeSceneTemplate.fromJson(Map<String, dynamic> json) {
    return SubscribeSceneTemplate(
      id: (json['id'] as num?)?.toInt(),
      sceneCode: json['scene_code']?.toString() ?? json['sceneCode']?.toString() ?? '',
      templateId: json['template_id']?.toString() ?? json['templateId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      triggerPoint: json['trigger_point']?.toString() ?? json['triggerPoint']?.toString() ?? 'SUBMIT_ORDER',
      isActive: (json['is_active'] as num?)?.toInt() ?? (json['isActive'] as num?)?.toInt() ?? 1,
      paramMappingJson: json['param_mapping_json']?.toString() ?? json['paramMappingJson']?.toString(),
      remark: json['remark']?.toString(),
      createdAt: json['created_at']?.toString() ?? json['createdAt']?.toString(),
      updatedAt: json['updated_at']?.toString() ?? json['updatedAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'scene_code': sceneCode,
      'template_id': templateId,
      'title': title,
      'trigger_point': triggerPoint,
      'is_active': isActive,
      if (paramMappingJson != null) 'param_mapping_json': paramMappingJson,
      if (remark != null) 'remark': remark,
    };
  }
}

/// 微信订阅消息下发审计日志实体
@immutable
class SubscribeSendLog {
  const SubscribeSendLog({
    this.id,
    this.bizNo,
    required this.openid,
    required this.sceneCode,
    required this.templateId,
    required this.sendStatus,
    this.errcode,
    this.errmsg,
    this.quotaBefore,
    this.quotaAfter,
    this.durationMs,
    this.payloadSummary,
    this.createdAt,
  });

  final int? id;
  final String? bizNo;
  final String openid;
  final String sceneCode;
  final String templateId;
  final String sendStatus;
  final int? errcode;
  final String? errmsg;
  final int? quotaBefore;
  final int? quotaAfter;
  final int? durationMs;
  final String? payloadSummary;
  final String? createdAt;

  bool get isSuccess => sendStatus == 'SUCCESS';
  bool get isFailed => sendStatus == 'FAILED';
  bool get isSkipped => sendStatus == 'SKIPPED_NO_QUOTA';

  factory SubscribeSendLog.fromJson(Map<String, dynamic> json) {
    return SubscribeSendLog(
      id: (json['id'] as num?)?.toInt(),
      bizNo: json['biz_no']?.toString() ?? json['bizNo']?.toString(),
      openid: json['openid']?.toString() ?? '',
      sceneCode: json['scene_code']?.toString() ?? json['sceneCode']?.toString() ?? '',
      templateId: json['template_id']?.toString() ?? json['templateId']?.toString() ?? '',
      sendStatus: json['send_status']?.toString() ?? json['sendStatus']?.toString() ?? '',
      errcode: (json['errcode'] as num?)?.toInt(),
      errmsg: json['errmsg']?.toString(),
      quotaBefore: (json['quota_before'] as num?)?.toInt() ?? (json['quotaBefore'] as num?)?.toInt(),
      quotaAfter: (json['quota_after'] as num?)?.toInt() ?? (json['quotaAfter'] as num?)?.toInt(),
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? (json['durationMs'] as num?)?.toInt(),
      payloadSummary: json['payload_summary']?.toString() ?? json['payloadSummary']?.toString(),
      createdAt: json['created_at']?.toString() ?? json['createdAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (bizNo != null) 'biz_no': bizNo,
      'openid': openid,
      'scene_code': sceneCode,
      'template_id': templateId,
      'send_status': sendStatus,
      if (errcode != null) 'errcode': errcode,
      if (errmsg != null) 'errmsg': errmsg,
      if (quotaBefore != null) 'quota_before': quotaBefore,
      if (quotaAfter != null) 'quota_after': quotaAfter,
      if (durationMs != null) 'duration_ms': durationMs,
      if (payloadSummary != null) 'payload_summary': payloadSummary,
      if (createdAt != null) 'created_at': createdAt,
    };
  }
}
