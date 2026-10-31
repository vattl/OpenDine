/**
 * 余额展示：整数（含 .00）不显示小数；有小数时固定两位（如 100.5 → 100.50）。
 * @param {unknown} value 元
 * @returns {string}
 */
export function formatBalanceForDisplay(value) {
  if (value == null || value === "") return "0";
  const n = Number(value);
  if (!Number.isFinite(n)) return "0";
  const cents = Math.round(n * 100);
  const sign = cents < 0 ? -1 : 1;
  const abs = Math.abs(cents);
  if (abs % 100 === 0) {
    const whole = sign * Math.trunc(abs / 100);
    return String(whole);
  }
  const whole = Math.trunc(abs / 100);
  const frac = abs % 100;
  return (sign < 0 ? "-" : "") + whole + "." + String(frac).padStart(2, "0");
}
