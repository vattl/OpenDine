/// WS 握手：移动端/桌面优先 Header 鉴权（RT3-09），与 REST `X-Kds-Device-Token` 一致。
/// Web 端见 [kds_ws_connect_web.dart]（浏览器仅支持 query token）。
const kKdsDeviceTokenHeader = 'X-Kds-Device-Token';
