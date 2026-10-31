/** 外卖预约配送：营业时段 19:00–次日 02:00，30 分钟一档 */

const SLOT_STEP_MIN = 30;
const OPEN_SERVICE_MIN = 19 * 60;
const CLOSE_SERVICE_MIN = 24 * 60 + 2 * 60;
const DEFAULT_LEAD_MIN = 30;

function pad2(n) {
  return String(n).padStart(2, "0");
}

/** 营业分钟轴上的时刻 → "HH:mm"（0–2 点为次日凌晨） */
export function serviceMinuteToLabel(sm) {
  if (sm < 24 * 60) {
    return `${pad2(Math.floor(sm / 60))}:${pad2(sm % 60)}`;
  }
  const sm2 = sm - 24 * 60;
  return `${pad2(Math.floor(sm2 / 60))}:${pad2(sm2 % 60)}`;
}

/** "HH:mm" → 营业分钟轴 */
export function timeLabelToServiceMinute(label) {
  const [h, m] = String(label).split(":").map(Number);
  if (!Number.isFinite(h) || !Number.isFinite(m)) return NaN;
  if (h >= 19) return h * 60 + m;
  if (h < 3) return (h + 24) * 60 + m;
  return NaN;
}

/** 当前时刻在营业轴上的位置；02:00–19:00 为非营业返回 null */
export function getNowServiceMinute(now = new Date()) {
  const h = now.getHours();
  const mi = now.getMinutes();
  const sm = h * 60 + mi;
  if (h >= 19) return sm;
  if (h < 2) return (h + 24) * 60 + mi;
  return null;
}

/** 营业时段内全部可选时间点 */
export function getAllTakeoutScheduleSlots() {
  const slots = [];
  for (let sm = OPEN_SERVICE_MIN; sm <= CLOSE_SERVICE_MIN; sm += SLOT_STEP_MIN) {
    slots.push(serviceMinuteToLabel(sm));
  }
  return slots;
}

/**
 * 可选预约时间（过滤已过去时段）
 * @param {Date} [now]
 * @param {number} [leadMin] 最早预约须晚于当前 leadMin 分钟
 */
export function getAvailableTakeoutScheduleSlots(now = new Date(), leadMin = DEFAULT_LEAD_MIN) {
  const all = getAllTakeoutScheduleSlots();
  const nowSm = getNowServiceMinute(now);
  if (nowSm === null) {
    return all.slice();
  }
  const cutoff = nowSm + leadMin;
  return all.filter((label) => timeLabelToServiceMinute(label) >= cutoff);
}

/**
 * 将预约时刻解析为具体 Date（用于校验是否已过期）
 * @param {string} label "HH:mm"
 */
export function resolveTakeoutScheduleDateTime(label, now = new Date()) {
  const sm = timeLabelToServiceMinute(label);
  if (!Number.isFinite(sm)) return null;

  const [hh, mm] = String(label).split(":").map(Number);
  const candidate = new Date(now);
  candidate.setSeconds(0, 0);
  candidate.setMilliseconds(0);
  candidate.setHours(hh, mm, 0, 0);

  const refH = now.getHours();
  const nowSm = getNowServiceMinute(now);

  if (hh >= 19) {
    if (refH < 2) {
      candidate.setDate(candidate.getDate() + 1);
    } else if (nowSm !== null && sm <= nowSm) {
      candidate.setDate(candidate.getDate() + 1);
    }
  } else if (refH >= 19) {
    candidate.setDate(candidate.getDate() + 1);
  } else if (refH >= 2 && refH < 19) {
    candidate.setDate(candidate.getDate() + 1);
  }

  if (candidate.getTime() <= now.getTime()) {
    candidate.setDate(candidate.getDate() + 1);
  }
  return candidate;
}

export function formatTakeoutScheduleRemark(label) {
  return label ? `【配送时间】预约配送 ${label}` : "【配送时间】预约配送";
}
