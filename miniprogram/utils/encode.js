/**
 * 步骤1：pt函数 - UTF-16字符串 → UTF-8字节数组（前端原版）
 */
const pt = function(e) {
  var t, n, a = [];
  t = e.length;
  for (var i = 0; i < t; i++) {
    n = e.charCodeAt(i);
    if (n >= 65536 && n <= 1114111) {
      a.push(n >> 18 & 7 | 240);
      a.push(n >> 12 & 63 | 128);
      a.push(n >> 6 & 63 | 128);
      a.push(63 & n | 128);
    } else if (n >= 2048 && n <= 65535) {
      a.push(n >> 12 & 15 | 224);
      a.push(n >> 6 & 63 | 128);
      a.push(63 & n | 128);
    } else if (n >= 128 && n <= 2047) {
      a.push(n >> 6 & 31 | 192);
      a.push(63 & n | 128);
    } else {
      a.push(255 & n);
    }
  }
  return a;
};

/**
 * 步骤2：lt函数 - 自定义异或加密（前端原版）
 */
const lt = function(e, t) {
  const n = t.length;
  const a = e.length;
  const i = new Uint8Array(a);
  for (let r = 0; r < a; r++) {
    const o = (a - r) % n;
    const c = t.charCodeAt(o) ^ ~("string" === typeof e ? e.charCodeAt(r) : e[r]);
    i[r] = c;
  }
  return i;
};

/**
 * 步骤3：ht函数 - 手工Base64编码（前端原版，紧凑写法）
 */
const ht = function(e) {
  let o = "";
  const c = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  const u = new Uint8Array(e);
  const s = u.byteLength;
  const d = s % 3;
  const p = s - d;
  let l = 0;
  let t, n, a, i, r;

  for (; l < p; l += 3) {
    r = u[l] << 16 | u[l + 1] << 8 | u[l + 2];
    t = (16515072 & r) >> 18;
    n = (258048 & r) >> 12;
    a = (4032 & r) >> 6;
    i = 63 & r;
    o += c[t] + c[n] + c[a] + c[i];
  }

  if (1 === d) {
    r = u[p];
    t = (252 & r) >> 2;
    n = (3 & r) << 4;
    o += c[t] + c[n] + "==";
  } else if (2 === d) {
    r = u[p] << 8 | u[p + 1];
    t = (64512 & r) >> 10;
    n = (1008 & r) >> 4;
    a = (15 & r) << 2;
    o += c[t] + c[n] + c[a] + "=";
  }

  return o;
};

/**
 * 完整加密函数（修复字符串序列化问题）
 * @param {string|object} plainData - 明文（字符串/对象，字符串直接使用，不做JSON.stringify）
 * @param {string} key - 加密密钥
 * @returns {string} 最终Base64字符串
 */
export const encryptFull = function(plainData) {
  try {
    // 关键修复：纯字符串直接使用，不做JSON.stringify（避免多引号）
    const inputStr = typeof plainData === "string" ? plainData : JSON.stringify(plainData);
	const key = "riegh^ee:w0fok5je5eeS{eecaes1nep";

    // 2. pt：UTF-16字符串 → UTF-8字节数组
    const ptResult = pt(inputStr);
    // 3. lt：异或加密 → Uint8数组
    const ltResult = lt(ptResult, key);
    // 4. ht：Base64编码 → 最终结果
    const htResult = ht(ltResult);
    return htResult;
  } catch (e) {
    console.error("加密失败：", e);
    throw e; // 抛出错误让调用方处理
  }
};

/**
 * 测试函数（可选，用于验证加密逻辑正确性）
 */
export const testEncrypt = function() {
  const plainE = {
    app_id: 'your_parking_app_id',
    plate: '粤A00000',
    token: 'test_token_placeholder',
    identity: 'test_identity_placeholder'
  };
  const key = "test_parking_key_placeholder";
  try {
    const encryptedStr = encryptFull(plainE, key);
    console.log("✅ 加密测试结果：", encryptedStr);
    console.log("预期结果参考：5vX/ve228sXV+PP/+A==");
    return encryptedStr;
  } catch (err) {
    console.error("❌ 加密测试失败：", err);
    return null;
  }
};