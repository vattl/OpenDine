// src/utils/decrypt.js
/**
 * 反向pt函数（UTF-8字节数组 → UTF-16字符串）
 * @param {Array} e - UTF-8字节数组
 * @returns {string} UTF-16字符串
 */
const reversePt = function(e) {
  var t = "", n = 0, a, i, r, o;
  for (; n < e.length; ) {
    a = e[n];
    if (a < 128)
      t += String.fromCharCode(a),
      n++;
    else if (a >= 192 && a < 224)
      i = e[n + 1],
      r = ((a & 31) << 6) | (i & 63),
      t += String.fromCharCode(r),
      n += 2;
    else if (a >= 224 && a < 240)
      i = e[n + 1],
      r = e[n + 2],
      o = ((a & 15) << 12) | ((i & 63) << 6) | (r & 63),
      t += String.fromCharCode(o),
      n += 3;
    else if (a >= 240 && a < 248)
      i = e[n + 1],
      r = e[n + 2],
      o = e[n + 3],
      c = ((a & 7) << 18) | ((i & 63) << 12) | ((r & 63) << 6) | (o & 63),
      t += String.fromCharCode(c),
      n += 4;
    else
      n++;
  }
  return t;
};

/**
 * 反向lt函数（异或解密）
 * @param {Uint8Array} e - 加密后的Uint8数组
 * @param {string} t - 解密密钥
 * @returns {Array} 解密后的UTF-8字节数组
 */
const reverseLt = function(e, t) {
  var n = t.length, a = e.length, i = [], r, o, c;
  for (var l = 0; l < a; l++) {
    r = (a - l) % n;
    o = t.charCodeAt(r);
    c = ~(e[l] ^ o);
    i.push(c & 255);
  }
  return i;
};

/**
 * 反向ht函数（手工Base64解码）
 * @param {string} e - Base64加密字符串
 * @returns {Uint8Array} 解码后的Uint8数组
 */
const reverseHt = function(e) {
  var t, n, a, i, r, o = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
      c = e.replace(/=/g, ""), l = c.length, u = [], s = 0, d = 0;
  for (; s < l; ) {
    t = o.indexOf(c.charAt(s)) << 18 | o.indexOf(c.charAt(s + 1)) << 12 | o.indexOf(c.charAt(s + 2)) << 6 | o.indexOf(c.charAt(s + 3));
    n = (t & 16711680) >> 16;
    a = (t & 65280) >> 8;
    i = t & 255;
    u[d++] = n;
    if (s + 2 < l) u[d++] = a;
    if (s + 3 < l) u[d++] = i;
    s += 4;
  }
  return new Uint8Array(u);
};

/**
 * 完整解密函数（支持纯字符串/对象）
 * @param {string} encryptedStr - 加密后的Base64字符串
 * @param {string} key - 解密密钥
 * @returns {string|object} 解密后的明文
 */
export const decryptFull = function(encryptedStr, key) {
  try {
    // 1. Base64解码 → Uint8数组
    const htReverse = reverseHt(encryptedStr);
    // 2. 异或解密 → UTF-8字节数组
    const ltReverse = reverseLt(htReverse, key);
    // 3. UTF-8字节数组 → UTF-16字符串
    const jsonStr = reversePt(ltReverse);
    
    // 尝试解析JSON，失败则返回原字符串
    try {
      return JSON.parse(jsonStr);
    } catch (err) {
      return jsonStr;
    }
  } catch (e) {
    console.error("解密失败：", e);
    throw e; // 抛出错误让调用方处理
  }
};

// 测试函数（可选，用于验证）
export const testDecrypt = () => {
  const encryptedStr = "vrj3zvXx9vOvtbig+7Wtq6yrrbGYr7jmuPar5OT6p+nnoLiTpqiqo7yttrOv/OrB9f64vo716vyrovyn8qH8vv2trJnzrrjr";
  const key = "riegh^ee:w0fok5je5eeS{eecaes1nep";
  try {
    const decryptedRes = decryptFull(encryptedStr, key);
    console.log("✅ 解密测试成功：", decryptedRes);
    return decryptedRes;
  } catch (err) {
    console.error("❌ 解密测试失败：", err);
    return null;
  }
};