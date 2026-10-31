<template>
    <view class="ai-chat-page">
      <view class="top-bar">
        <view class="top-bar-inner">
          <view class="table-hint" v-if="tableDisplay">
            <text class="table-label">当前桌号</text>
            <text class="table-value">{{ tableDisplay }}</text>
          </view>
          <view class="table-hint table-hint--weak" v-else>
            <text>未绑定桌号 · 可先对话推荐</text>
          </view>
          <button class="btn-new-chat" size="mini" :disabled="sending || !canSend" @click="onNewChat">新对话</button>
        </view>
      </view>
  
      <scroll-view
        class="msg-scroll"
        scroll-y
        :scroll-into-view="scrollIntoView"
        scroll-with-animation
        :show-scrollbar="false"
        :enable-flex="true"
      >
        <view class="msg-list">
          <view
            v-for="m in messages"
            :key="m.id"
            :id="'msg-' + m.id"
            class="msg-row"
            :class="m.role === 'user' ? 'msg-row--user' : 'msg-row--assistant'"
          >
            <view v-if="m.role === 'assistant'" class="avatar ai-avatar">AI</view>
            <view class="bubble-wrap">
              <view v-if="m.role === 'user'" class="bubble bubble--user">
                <text class="bubble-text bubble-text--user" selectable>{{ m.text }}</text>
              </view>
              <view v-else class="bubble bubble--ai">
                <view v-if="m.loginHint" class="login-hint-bubble">
                  <text class="bubble-text bubble-text--ai" selectable>{{ m.text }}</text>
                  <button class="btn-login-inline" @tap="goLogin">去登录</button>
                </view>
                <template v-else>
                  <view v-if="m.planMeta && m.planMeta.length" class="plan-meta">
                    <view v-for="(chip, mi) in m.planMeta" :key="mi" class="plan-meta-chip">
                      <text class="plan-meta-label">{{ chip.label }}</text>
                      <text class="plan-meta-value">{{ chip.value }}</text>
                    </view>
                  </view>
                  <view class="ai-main-block">
                    <text v-if="m.text" class="bubble-text bubble-text--ai ai-bubble-main" selectable>{{ m.text }}</text>
                  </view>
                  <view v-if="m.dishes && m.dishes.length" class="ai-dish-list">
                    <view
                      v-for="(d, di) in m.dishes"
                      :key="dishCardKey(d, di)"
                      class="ai-dish-card-wrap"
                      :class="{ 'ai-dish-card-wrap--zero': dishSliderQty(d) === 0 }"
                    >
                      <view class="classif-goods ai-dish-card" @tap="onDishCardTap(d)">
                        <view class="goods-image">
                          <image
                            class="real-img dish-card-cover"
                            :src="dishImageDisplaySrc(d)"
                            mode="aspectFill"
                            lazy-load
                          />
                        </view>
                        <view class="goods-Price">
                          <view class="goods-name">
                            <text class="Bold">{{ d.name }}</text>
                            <text class="Thinning">{{ d.subLabel || ' ' }}</text>
                          </view>
                          <view class="unit-price" v-if="d.priceText">
                            <text class="Symbol">¥</text>
                            <text class="Unitprice">{{ d.priceMain }}</text>
                            <text class="unit" v-if="d.priceUnitSuffix">{{ d.priceUnitSuffix }}</text>
                          </view>
                        </view>
                        <view class="dish-card-qty" v-if="d.qtyText || d.subtotalText">
                          <text v-if="d.qtyText" class="dish-qty-line">{{ d.qtyText }}</text>
                          <text v-if="d.subtotalText" class="dish-sub-line">{{ d.subtotalText }}</text>
                        </view>
                      </view>
                      <view class="dish-card-stepper-row" @tap.stop>
                        <text v-if="dishLineSubtotalDisplay(d)" class="dish-card-stepper-sub">{{ dishLineSubtotalDisplay(d) }}</text>
                        <view class="dish-card-stepper-ctrl">
                          <view
                            class="stepper-btn"
                            :class="{ 'stepper-btn--disabled': dishSliderQty(d) <= 0 }"
                            @tap="onDishSliderDelta(m, di, -1)"
                          >−</view>
                          <text class="stepper-val">{{ dishSliderQty(d) }}</text>
                          <view
                            class="stepper-btn"
                            :class="{ 'stepper-btn--disabled': dishSliderQty(d) >= 99 }"
                            @tap="onDishSliderDelta(m, di, 1)"
                          >+</view>
                          <text class="stepper-del" @tap="onDishRemoveFromBubble(m, di)">删除</text>
                        </view>
                      </view>
                    </view>
                  </view>
                  <view
                    v-for="(btn, abi) in assistantActionButtons(m)"
                    :key="abi"
                    class="ai-action-below-text"
                  >
                    <button
                      class="btn-action-inline"
                      :disabled="btn.needSendGuard && (sending || !canSend)"
                      @tap="runAssistantAction(btn.key, btn.payload, m)"
                    >
                      {{ btn.label }}
                    </button>
                  </view>
                </template>
              </view>
              <view v-if="m.role === 'assistant' && m.ts && !m.loginHint" class="msg-meta">{{ m.ts }}</view>
            </view>
            <view v-if="m.role === 'user'" class="avatar user-avatar">
              <image
                v-if="userAvatarUrl"
                class="user-avatar-img"
                :src="userAvatarUrl"
                mode="aspectFill"
              />
              <text v-else class="user-avatar-fallback">我</text>
            </view>
          </view>
  
          <view v-if="sending" id="msg-typing" class="msg-row msg-row--assistant">
            <view class="avatar ai-avatar">AI</view>
            <view class="bubble-wrap">
              <view class="bubble bubble--ai bubble--typing">
                <text class="typing-tip">正在思考中</text>
                <text class="dot">·</text>
                <text class="dot">·</text>
                <text class="dot">·</text>
                
              </view>
            </view>
          </view>
  
          <view class="scroll-bottom-pad" id="chat-anchor"></view>
        </view>
      </scroll-view>
  
      <view class="footer-area">
        <view class="quick-panel" :class="{ 'quick-panel--open': showQuickSuggest }">
          <view class="quick-panel-inner">
            <view class="quick-panel-title">推荐说法</view>
            <view
              v-for="(q, i) in quickPrompts"
              :key="i"
              class="quick-panel-item"
              :class="{ 'quick-panel-item--disabled': sending || !canSend }"
              @tap="onPickQuick(q)"
            >
              {{ q }}
            </view>
          </view>
        </view>
        <view class="composer-wrap">
          <view class="composer">
            <textarea
              class="composer-input"
              v-model="inputText"
              :maxlength="800"
              :disabled="sending || !canSend"
              placeholder="例如：3 个人，不太辣，预算 200 元以内…"
              :show-confirm-bar="false"
              :cursor-spacing="24"
              :adjust-position="true"
              auto-height
              @focus="onComposerFocus"
              @blur="onComposerBlur"
              @confirm="onSend"
            />
            <button class="send-btn" type="primary" :disabled="sending || !canSend || !inputTrimmed" @click="onSend">
              {{ sending ? '发送中' : '发送' }}
            </button>
          </view>
          <text class="composer-ai-footnote">内容由AI生成</text>
        </view>
      </view>
    </view>
  </template>
  
  <script>
  import { requestUtil, getBaseUrl } from '../../utils/requestUtil.js';
  import { subscribeMenuCatalogChanged } from '../../utils/menuCatalogSocket.js';
  import { DISH_CACHE_KEY, DISH_CACHE_TIME_KEY } from '../../config/perf.js';
  import { dishSoldOut, normalizeSoldOut } from '../../utils/dishSale.js';
  import { staticUrl } from '../../utils/staticAssetUrl.js';
  import { dishImageUrlList } from '../../utils/imageUrl.js';
  
  const app = getApp();
  
  const STORAGE_PREFIX = 'ai_order_chat_v2_';
  const MAX_STORED_MESSAGES = 100;
  /** 无菜品图或地址无效时的占位（与模板原 placeholder 一致） */
  const DEFAULT_DISH_IMAGE = staticUrl('images/default-avatar.png');
  
  function storageKey(openid) {
    return STORAGE_PREFIX + (openid || 'guest');
  }

  /** 与 chatSuggestResetOnce 同步：切换 tab 时页面可能被重建，仅内存会丢 */
  function pendingResetStorageKey(openid) {
    return STORAGE_PREFIX + 'pending_reset_' + (openid || 'guest');
  }
  
  function nowTimeStr() {
    const d = new Date();
    const h = d.getHours();
    const mi = d.getMinutes();
    return `${String(h).padStart(2, '0')}:${String(mi).padStart(2, '0')}`;
  }
  
  function formatMoney(n) {
    const num = Number(n);
    if (Number.isNaN(num)) return String(n);
    const s = num.toFixed(2);
    return s.replace(/\.00$/, '').replace(/(\.\d)0$/, '$1');
  }

  /** 菜品卡片数量条：已存 sliderQty / quantity / qtyText 解析，默认 1 */
  function parseSliderQtyFromDish(d) {
    if (!d || typeof d !== 'object') return 1;
    if (d.sliderQty != null && d.sliderQty !== '') {
      const n = Math.round(Number(d.sliderQty));
      if (Number.isFinite(n)) return Math.min(99, Math.max(0, n));
    }
    const num = d.quantity != null ? d.quantity : d.count;
    if (num != null && num !== '') {
      const n = Math.round(Number(num));
      if (Number.isFinite(n)) return Math.min(99, Math.max(0, n));
    }
    if (d.qtyText) {
      const hit = String(d.qtyText).match(/(\d+)/);
      if (hit) {
        const n = parseInt(hit[1], 10);
        if (Number.isFinite(n)) return Math.min(99, Math.max(0, n));
      }
    }
    return 1;
  }
  
  function buildPlanMetaChips(plan) {
    if (!plan || typeof plan !== 'object') return null;
    const chips = [];
    if (plan.perCapitaPrice != null && plan.perCapitaPrice !== '') {
      const p = Number(plan.perCapitaPrice);
      if (!Number.isNaN(p) && p > 0) chips.push({ label: '人均', value: `￥${formatMoney(p)}` });
    }
    const planTableNumber = plan.table_number != null ? plan.table_number : plan.tableNumber;
    if (planTableNumber != null && String(planTableNumber).trim() !== '') {
      chips.push({ label: '桌号', value: String(planTableNumber).trim() });
    }
    if (plan.totalPrice != null && plan.totalPrice !== '' && Number(plan.totalPrice) > 0) {
      chips.push({ label: '总价', value: `￥${formatMoney(plan.totalPrice)}` });
    }
    return chips.length ? chips : null;
  }
  
  function isStructuredChatPlan(plan) {
    if (!plan || typeof plan !== 'object') return false;
    return (
      Object.prototype.hasOwnProperty.call(plan, 'explanation') ||
      Object.prototype.hasOwnProperty.call(plan, 'totalPrice') ||
      Object.prototype.hasOwnProperty.call(plan, 'items') ||
      Object.prototype.hasOwnProperty.call(plan, 'historyRounds') ||
      Object.prototype.hasOwnProperty.call(plan, 'perCapitaPrice')
    );
  }
  
  function pickStr(o, keys) {
    for (let i = 0; i < keys.length; i++) {
      const v = o[keys[i]];
      if (typeof v === 'string' && v.trim()) return v.trim();
    }
    return '';
  }
  
  function parseTableRow(line) {
    if (line == null || typeof line !== 'string') return null;
    const t = line.trim();
    if (!t.includes('|')) return null;
    let cells = t.split('|').map((c) => c.trim());
    if (cells.length >= 2 && cells[0] === '') cells = cells.slice(1);
    if (cells.length >= 1 && cells[cells.length - 1] === '') cells = cells.slice(0, -1);
    return cells.length >= 2 ? cells : null;
  }
  
  function isMarkdownSeparatorRow(cells) {
    if (!cells || cells.length < 2) return false;
    return cells.every((c) => {
      const t = String(c).replace(/\s/g, '');
      return /^:?-{2,}:?$/.test(t);
    });
  }
  
  function normalizeTableRow(cells, colCount) {
    const out = [];
    for (let i = 0; i < colCount; i++) {
      out.push(cells[i] != null ? String(cells[i]) : '');
    }
    return out;
  }
  
  function parseExplanationSegments(raw) {
    if (raw == null || raw === '') return [];
    if (typeof raw !== 'string') return [{ type: 'text', text: String(raw) }];
    const lines = raw.split(/\n/);
    const segments = [];
    const textBuffer = [];
    let i = 0;
  
    function flushText() {
      if (!textBuffer.length) return;
      const t = textBuffer.join('\n');
      textBuffer.length = 0;
      if (t.trim()) segments.push({ type: 'text', text: t });
    }
  
    while (i < lines.length) {
      const row0 = parseTableRow(lines[i]);
      const row1 = i + 1 < lines.length ? parseTableRow(lines[i + 1]) : null;
      if (row0 && row1 && isMarkdownSeparatorRow(row1)) {
        flushText();
        let colCount = row0.length;
        i += 2;
        const rows = [];
        while (i < lines.length) {
          const cells = parseTableRow(lines[i]);
          if (!cells || cells.length < 2) break;
          colCount = Math.max(colCount, cells.length);
          rows.push(cells);
          i += 1;
        }
        const headers = normalizeTableRow(row0, colCount);
        const normRows = rows.map((r) => normalizeTableRow(r, colCount));
        segments.push({ type: 'table', headers, rows: normRows });
        continue;
      }
      textBuffer.push(lines[i]);
      i += 1;
    }
    flushText();
    if (!segments.length) return [{ type: 'text', text: raw }];
    return segments;
  }
  
  function filterRenderableSegments(segments) {
    if (!Array.isArray(segments)) return [];
    return segments.filter((s) => {
      if (!s || typeof s !== 'object') return false;
      if (s.type === 'table') return Array.isArray(s.headers) && s.headers.length > 0;
      if (s.type === 'text') return typeof s.text === 'string' && s.text.trim().length > 0;
      return false;
    });
  }
  
  function headerIndex(headers, re) {
    const i = headers.findIndex((h) => re.test(String(h).trim()));
    return i;
  }

  /**
   * 非真实图片：占位文案、横杠等（有合法图片扩展名或 http(s) 的视为真资源）
   */
  function isNonImagePlaceholderText(s) {
    const t = String(s || '').trim();
    if (!t) return true;
    if (/^https?:\/\//i.test(t)) return false;
    if (/\.(jpe?g|png|gif|webp|bmp|svg)(?:\?.*)?$/i.test(t)) return false;
    if (/^\/?image\/dish\//i.test(t.replace(/\\/g, '/'))) return false;
    const c = t.replace(/\s/g, '');
    if (/^[-—–_/\\.]+$/.test(c)) return true;
    if (/^(n\/a|none|null|noimage)$/i.test(c)) return true;
    if (/暂无/.test(c) && /图/.test(c)) return true;
    if (/^(无图|缺图|无照片|没有图|未配图|无)$/.test(c)) return true;
    return false;
  }

  /** 表格单元格里的图：支持纯 URL/路径，或 ![](url) / [text](url) */
  function normalizeTableImageCell(raw) {
    const s = raw == null ? '' : String(raw).trim();
    if (!s) return '';
    const mdImg = s.match(/^!\[[^\]]*\]\(([^)]+)\)\s*$/);
    if (mdImg) {
      const inner = String(mdImg[1] || '').trim();
      return isNonImagePlaceholderText(inner) ? '' : inner;
    }
    const mdLink = s.match(/^\[[^\]]*\]\(([^)]+)\)\s*$/);
    if (mdLink) {
      const inner = String(mdLink[1] || '').trim();
      return isNonImagePlaceholderText(inner) ? '' : inner;
    }
    const angle = s.match(/^<([^>\s]+)>\s*$/);
    if (angle) {
      const inner = String(angle[1] || '').trim();
      return isNonImagePlaceholderText(inner) ? '' : inner;
    }
    const plain = s;
    return isNonImagePlaceholderText(plain) ? '' : plain;
  }
  
  /** Markdown 表格列 → 菜品卡片（与点餐页字段对齐，便于展示） */
  function tableSegmentToDishes(seg) {
    if (!seg || seg.type !== 'table' || !Array.isArray(seg.headers) || !Array.isArray(seg.rows)) return [];
    const headers = seg.headers.map((h) => String(h).trim());
    const nameIdx = (() => {
      const i = headerIndex(headers, /菜品|名称|菜名|品名/);
      return i >= 0 ? i : 0;
    })();
    const typeIdx = headerIndex(headers, /类型|分类|品类/);
    const specIdx = headerIndex(headers, /规格|口味|做法/);
    const qtyIdx = headerIndex(headers, /数量|份数/);
    const priceIdx = headerIndex(headers, /单价|价格|预估/);
    const subIdx = headerIndex(headers, /小计/);
    const imageIdx = headerIndex(
      headers,
      /图片|菜品图|主图|封面|配图|示意图|照片|缩略图|图链|image|pic|photo|thumb|url|cover|img/i
    );
  
    return seg.rows
      .map((row, ri) => {
        const get = (idx) => (idx >= 0 && row[idx] != null ? String(row[idx]).trim() : '');
        const name = get(nameIdx);
        if (!name) return null;
        const type = typeIdx >= 0 ? get(typeIdx) : '';
        const spec = specIdx >= 0 ? get(specIdx) : '';
        const qty = qtyIdx >= 0 ? get(qtyIdx) : '';
        const priceRaw = priceIdx >= 0 ? get(priceIdx) : '';
        const subRaw = subIdx >= 0 ? get(subIdx) : '';
        const imageRaw = imageIdx >= 0 ? normalizeTableImageCell(get(imageIdx)) : '';
        const subLabel = [type, spec].filter(Boolean).join(' · ');
        const { priceText, priceMain, priceUnitSuffix } = splitPriceDisplay(priceRaw);
        const subtotalText = normalizeSubtotalDisplay(subRaw);
        let sliderQty = 1;
        if (qty) {
          const digits = String(qty).replace(/[^\d]/g, '');
          if (digits) {
            const n = parseInt(digits, 10);
            if (Number.isFinite(n)) sliderQty = Math.min(99, Math.max(0, n));
          }
        }
        return enrichDishCard({
          id: `t-${ri}`,
          name,
          subLabel,
          qtyText: qty,
          priceText,
          priceMain,
          priceUnitSuffix,
          subtotalText,
          image: imageRaw,
          dishId: null,
          sliderQty,
        });
      })
      .filter(Boolean);
  }
  
  /** 展示用：拆 「12 元」 / 「¥12」 → 主数字 + 单位后缀 */
  function splitPriceDisplay(raw) {
    if (!raw || !String(raw).trim()) return { priceText: '', priceMain: '', priceUnitSuffix: '' };
    const s = String(raw).trim().replace(/\s+/g, '');
    const yuan = s.replace(/元$/, '').replace(/^¥/, '').replace(/^￥/, '');
    const m = yuan.match(/^([\d.]+)(.*)$/);
    if (!m) return { priceText: raw, priceMain: yuan, priceUnitSuffix: /元/.test(s) ? '元' : '' };
    return {
      priceText: raw,
      priceMain: m[1],
      priceUnitSuffix: m[2] || (/元/.test(s) ? '元' : ''),
    };
  }
  
  function normalizeSubtotalDisplay(raw) {
    if (!raw || !String(raw).trim()) return '';
    const s = String(raw).trim();
    if (/小计|¥|￥/.test(s)) return s;
    return `小计 ${s}`;
  }
  
  function enrichDishCard(card) {
    if (!card.priceMain && card.priceText) {
      const sp = splitPriceDisplay(card.priceText);
      return { ...card, ...sp };
    }
    return card;
  }
  
  function normalizePlanItemToCard(item, idx) {
    if (item == null) return null;
    if (typeof item === 'string') {
      return enrichDishCard({
        id: `s-${idx}`,
        name: item,
        subLabel: ' ',
        qtyText: '',
        priceText: '',
        priceMain: '',
        priceUnitSuffix: '',
        subtotalText: '',
        image: '',
        dishId: null,
        sliderQty: 1,
      });
    }
    if (typeof item !== 'object') return null;
    const name =
      item.name || item.dish_name || item.title || item.dishName || pickStr(item, ['label']) || '推荐菜品';
    const type = item.type || item.category || '';
    const spec = item.spec || item.sku || item.norm || '';
    const num = item.quantity != null ? item.quantity : item.count;
    const unit = item.unit || '';
    const unitPrice =
      item.unitprice != null ? item.unitprice : item.unitPrice != null ? item.unitPrice : item.price;
    const subtotal = item.subtotal != null ? item.subtotal : item.lineTotal;
    const image = item.image || item.image_url || item.popup_image || '';
    const dishId = item.id != null ? item.id : item.dish_id != null ? item.dish_id : item.did != null ? item.did : item.dishId;
    const subLabel = [type, spec].filter(Boolean).join(' · ') || ' ';
    const qtyText = num != null && num !== '' ? `×${num}${unit ? unit : ''}` : '';
    let priceMain = '';
    let priceUnitSuffix = '元';
    let priceText = '';
    if (unitPrice != null && unitPrice !== '') {
      priceMain = formatMoney(unitPrice);
      priceText = `¥${priceMain}`;
    }
    const subtotalText =
      subtotal != null && subtotal !== '' ? `小计 ¥${formatMoney(subtotal)}` : '';
    let sliderQty = 1;
    if (num != null && num !== '') {
      const n = Math.round(Number(num));
      if (Number.isFinite(n)) sliderQty = Math.min(99, Math.max(0, n));
    }
    return enrichDishCard({
      id: String(dishId != null ? dishId : `p-${idx}`),
      name: String(name),
      subLabel,
      qtyText,
      priceText,
      priceMain,
      priceUnitSuffix: priceMain ? priceUnitSuffix : '',
      subtotalText,
      image: image ? String(image) : '',
      dishId: dishId != null ? dishId : null,
      sliderQty,
    });
  }
  
  function normalizeItemsFromPlan(items) {
    if (!Array.isArray(items) || !items.length) return [];
    return items.map((it, i) => normalizePlanItemToCard(it, i)).filter(Boolean);
  }

  /**
   * 从 src[i] 起截取完整 JSON 对象或数组（仅识别标准双引号字符串，避免与 ACTION 的 >>> 截断冲突）。
   */
  function extractJsonValueStartingAt(src, i) {
    if (src == null || i < 0 || i >= src.length) return null;
    let p = i;
    while (p < src.length && /\s/.test(src[p])) p++;
    if (p >= src.length) return null;
    const start = p;
    const first = src[p];
    if (first !== '{' && first !== '[') {
      const end = src.indexOf('>>>', p);
      return end === -1 ? String(src.slice(p)).trim() : String(src.slice(p, end)).trim();
    }
    const stack = [];
    stack.push(first === '{' ? '}' : ']');
    let inStr = false;
    let esc = false;
    for (let j = p + 1; j < src.length; j++) {
      const ch = src[j];
      if (inStr) {
        if (esc) {
          esc = false;
          continue;
        }
        if (ch === '\\') {
          esc = true;
          continue;
        }
        if (ch === '"') inStr = false;
        continue;
      }
      if (ch === '"') {
        inStr = true;
        continue;
      }
      const top = stack[stack.length - 1];
      if (ch === '{') {
        stack.push('}');
        continue;
      }
      if (ch === '[') {
        stack.push(']');
        continue;
      }
      if (ch === '}' || ch === ']') {
        if (ch !== top) continue;
        stack.pop();
        if (stack.length === 0) return src.slice(start, j + 1);
      }
    }
    return null;
  }

  /** 从整段原文中提取 ACTION:add_ai_cart 后的 JSON（解决正则非贪婪在首个 >>> 截断导致 JSON 不完整）。 */
  function extractBracketPayloadForActionKey(src, actionKey) {
    if (!src || !actionKey) return null;
    const escKey = String(actionKey).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const re = new RegExp(`<<<\\s*ACTION\\s*[:：]\\s*${escKey}\\s*[|｜]\\s*`, 'gi');
    let m;
    while ((m = re.exec(src)) !== null) {
      const from = m.index + m[0].length;
      const chunk = extractJsonValueStartingAt(src, from);
      if (chunk) return String(chunk).trim();
    }
    return null;
  }

  /** 多种方式解析购物车 JSON（后端/LM 常见变体）。 */
  function tryParseAiCartJsonString(s) {
    let t = String(s == null ? '' : s).replace(/^\uFEFF/, '').trim();
    if (!t) return null;
    const tryOne = (x) => {
      try {
        return JSON.parse(x);
      } catch (e) {
        return null;
      }
    };
    const repairSelectedSpicyJsonString = (x) => {
      if (!x || typeof x !== 'string') return x;
      // 兼容后端/模型返回：selectedSpicy 被写成 "{"辣度":"不辣"}"（内层引号未转义，导致 JSON.parse 失败）
      return x.replace(/"selectedSpicy":"\{([\s\S]*?)\}"/g, (_, inner) => {
        const escaped = String(inner).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
        return `"selectedSpicy":"{${escaped}}"`;
      });
    };
    const tried = new Set();
    const queue = [t];
    while (queue.length > 0) {
      const cur = String(queue.shift() || '').trim();
      if (!cur || tried.has(cur)) continue;
      tried.add(cur);

      let data = tryOne(cur);
      if (data != null) return data;
      const repaired = repairSelectedSpicyJsonString(cur);
      if (repaired && repaired !== cur) {
        data = tryOne(repaired);
        if (data != null) return data;
        queue.push(repaired);
      }

      const fenced = cur.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim();
      if (fenced && fenced !== cur) queue.push(fenced);

      if ((cur.startsWith('"') && cur.endsWith('"')) || (cur.startsWith("'") && cur.endsWith("'"))) {
        const inner = cur
          .slice(1, -1)
          .replace(/\\n/g, '\n')
          .replace(/\\"/g, '"')
          .replace(/\\'/g, "'");
        if (inner) queue.push(inner);
      }

      // 兼容 URL 编码被编码多次的场景（最多连解 3 次）
      let dec = cur;
      for (let i = 0; i < 3; i++) {
        try {
          const next = decodeURIComponent(dec.replace(/\+/g, ' '));
          if (!next || next === dec) break;
          dec = next.trim();
          if (dec) queue.push(dec);
        } catch (e) {
          break;
        }
      }
    }
    return null;
  }
  
  function actionPayloadToString(payload) {
    if (payload == null) return '';
    if (typeof payload === 'string') return payload;
    try {
      return JSON.stringify(payload);
    } catch (e) {
      return String(payload);
    }
  }
  
  /**
   * 解析 <<<ACTION:key>>> 或 <<<ACTION:key|payload>>>，支持同条消息多个标签。
   * 通用能力：后端可用 send_prompt|用户要点发的完整句子，客户端无需为新文案发版。
   */
  function parseAssistantActions(rawText) {
    const src = rawText == null ? '' : String(rawText);
    const normalized = src.replace(/↵/g, '\n').replace(/＜＜＜/g, '<<<').replace(/＞＞＞/g, '>>>');
    const re = /<<<\s*ACTION\s*[:：]\s*([a-zA-Z0-9_:-]+)(?:\s*[|｜]\s*([\s\S]*?))?\s*>>>/gi;
    const actions = [];
    let m;
    while ((m = re.exec(normalized)) !== null) {
      const key = String(m[1] || '').trim().toLowerCase();
      const payload = m[2] == null ? '' : String(m[2]).trim();
      if (key) actions.push({ key, payload });
    }
    for (let ai = 0; ai < actions.length; ai++) {
      if (actions[ai].key !== 'add_ai_cart') continue;
      const fixed = extractBracketPayloadForActionKey(normalized, 'add_ai_cart');
      if (fixed) actions[ai].payload = fixed;
    }
    const text = normalized
      .replace(/<<<\s*ACTION\s*[:：]\s*[a-zA-Z0-9_:-]+(?:\s*[|｜]\s*[\s\S]*?)?\s*>>>/gi, '')
      .replace(/[ \t]*\n[ \t]*/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    return { text, actions };
  }

  /** @deprecated 请用 parseAssistantActions；保留兼容旧调用 */
  function parseAssistantAction(rawText) {
    const { text, actions } = parseAssistantActions(rawText);
    return {
      text,
      action: actions[0]?.key || '',
      actions,
      actionPayload: actions[0]?.payload || '',
    };
  }

  function normalizeCachedMessage(msg) {
    if (!msg || typeof msg !== 'object') return msg;
    if (msg.role !== 'assistant' || msg.loginHint) return msg;
    const raw = msg.text == null ? '' : String(msg.text);
    let actions =
      Array.isArray(msg.actions) && msg.actions.length
        ? msg.actions.map((x) => ({
            key: String(x.key || '').trim().toLowerCase(),
            payload: actionPayloadToString(x.payload),
          }))
        : null;
    const parsed = parseAssistantActions(raw);
    const text = actions ? raw : parsed.text;
    if (!actions) actions = parsed.actions;
    const action = String(msg.action || '').trim().toLowerCase() || actions[0]?.key || '';
    const actionPayload =
      msg.actionPayload != null ? String(msg.actionPayload) : actions[0]?.payload || '';
    const dishesNorm = Array.isArray(msg.dishes)
      ? msg.dishes.map((d) => ({
          ...d,
          sliderQty:
            d.sliderQty != null && d.sliderQty !== ''
              ? Math.min(99, Math.max(0, Math.round(Number(d.sliderQty))))
              : parseSliderQtyFromDish(d),
        }))
      : msg.dishes;
    return { ...msg, text, action, actionPayload, actions, dishes: dishesNorm };
  }

  /**
   * AI 气泡内嵌按钮：仅当 key 在此注册时渲染；新能力优先用 send_prompt，或发版增加条目。
   */
  const ASSISTANT_ACTION_DEFS = {
    scan_table_bind: {
      label: '扫一扫绑定桌号',
      needSendGuard: false,
      run(vm) {
        vm.scanAndBindTable();
      },
    },
    confirm_place_order: {
      label: '确认下单',
      needSendGuard: true,
      run(vm) {
        vm.inputText = '确认下单';
        vm.$nextTick(() => vm.onSend());
      },
    },
    /** 后端：<<<ACTION:send_prompt|要自动发出的用户话术>>> */
    send_prompt: {
      labelFromPayload: true,
      needSendGuard: true,
      run(vm, payload) {
        const t = String(payload || '').trim();
        if (!t) return;
        vm.inputText = t;
        vm.$nextTick(() => vm.onSend());
      },
    },
    /** 后端：<<<ACTION:add_ai_cart|JSON>>>，JSON 为数组或 { items: [...] } */
    add_ai_cart: {
      label: '加入购物车',
      needSendGuard: false,
      run(vm, payload, extraSources, options) {
        vm.applyAiCartPayload(payload, Array.isArray(extraSources) ? extraSources : [], options || {});
      },
    },
  };
  
  /** AI 回复 → 气泡文案（去掉表格段）+ 菜品卡片（优先 plan.items，否则解析 explanation 中的表格） */
  function assistantBubbleAndDishes(plan) {
    const planMeta = buildPlanMetaChips(plan);
    const empty = { text: '暂无具体建议，请换个说法试试。', dishes: [], planMeta, action: '', actions: [] };
  
    if (plan == null || plan === '') return empty;
    if (typeof plan === 'string') {
      const segments = filterRenderableSegments(parseExplanationSegments(plan));
      const text = segments.filter((s) => s.type === 'text').map((s) => s.text.trim()).join('\n\n').trim();
      let dishes = [];
      const tableSeg = segments.find((s) => s.type === 'table');
      if (tableSeg) dishes = tableSegmentToDishes(tableSeg);
      const parsed = parseAssistantActions(text || plan.trim());
      return {
        text: parsed.text,
        dishes,
        planMeta: null,
        action: parsed.actions[0]?.key || '',
        actions: parsed.actions,
      };
    }
    if (typeof plan !== 'object') {
      const parsed = parseAssistantActions(String(plan));
      return {
        text: parsed.text,
        dishes: [],
        planMeta,
        action: parsed.actions[0]?.key || '',
        actions: parsed.actions,
      };
    }
  
    let explanation = typeof plan.explanation === 'string' ? plan.explanation : '';
    if (!explanation.trim() && isStructuredChatPlan(plan)) {
      explanation =
        pickStr(plan, ['summary', 'reply', 'message', 'content', 'text', 'suggestion', 'description']) || '';
    }
  
    const segments = filterRenderableSegments(parseExplanationSegments(explanation || ''));
    const textParts = segments.filter((s) => s.type === 'text').map((s) => s.text.trim()).filter(Boolean);
    let bubbleText = textParts.join('\n\n').trim();
  
    let dishes = normalizeItemsFromPlan(plan.items);
    if (!dishes.length) {
      const tableSeg = segments.find((s) => s.type === 'table');
      if (tableSeg) dishes = tableSegmentToDishes(tableSeg);
    }
  
    if (!bubbleText && dishes.length) {
      bubbleText = '为您推荐以下菜品，可在菜单中加购：';
    }
    if (!bubbleText && !dishes.length) {
      if (isStructuredChatPlan(plan)) {
        try {
          const slim = {};
          Object.keys(plan).forEach((k) => {
            if (k !== 'sessionOpenid') slim[k] = plan[k];
          });
          bubbleText = JSON.stringify(slim, null, 2);
        } catch (e) {
          bubbleText = '暂无可展示内容';
        }
      } else {
        bubbleText = explanation.trim() || '暂无可展示内容';
      }
    }
  
    const parsed = parseAssistantActions(bubbleText);
    return {
      text: parsed.text,
      dishes,
      planMeta,
      action: parsed.actions[0]?.key || '',
      actions: parsed.actions,
    };
  }
  
  export default {
    data() {
      return {
        /** 仅用于写入 shopping_cart 缓存（与点餐页合并），本页不展示购物车 */
        shopping_card: [],
        messages: [],
        msgId: 0,
        inputText: '',
        sending: false,
        scrollIntoView: '',
        canSend: false,
        table_number: '',
        inputFocused: false,
        /** 点此「新对话」后为 true；下一次 chatSuggest 附带 reset:true，仅当接口返回 code===0 后置为 false */
        chatSuggestResetOnce: false,
        quickPrompts: [
          '3 个人，不太辣，预算 200 以内',
          '两人宵夜，有什么推荐',
          '招牌菜有哪些，各来一份攻略',
          '确认下单',
        ],
        /** 用户头像 URL（与 globalData / 本地 userInfo 同步） */
        userAvatarUrl: '',
      };
    },
    computed: {
      inputTrimmed() {
        return (this.inputText || '').trim();
      },
      tableDisplay() {
        return this.table_number && String(this.table_number).trim() ? String(this.table_number).trim() : '';
      },
      showQuickSuggest() {
        if (!this.canSend || this.sending) return false;
        if (!this.inputFocused) return false;
        const t = this.inputText;
        return t == null || t.length === 0;
      },
    },
    onLoad() {
      // onLoad 即同步本地台号缓存，避免首次进入顶部桌号为空
      this.table_number = String(app.getStorageWithExpiry('table_number') || '').trim();
      this.syncPendingSuggestResetFromStorage();
      this.syncLoginUi();
      this._unsubMenuCatalog = subscribeMenuCatalogChanged((payload) => {
        if (!payload || payload.type !== 'dish_catalog_changed') return;
        try {
          wx.removeStorageSync(DISH_CACHE_KEY);
          wx.removeStorageSync(DISH_CACHE_TIME_KEY);
        } catch (e) {}
      });
    },
    onUnload() {
      if (this._unsubMenuCatalog) {
        this._unsubMenuCatalog();
        this._unsubMenuCatalog = null;
      }
    },
    onShow() {
      if (typeof app.guardToQueueIfReview === 'function') {
        app.guardToQueueIfReview();
      }
      this.refreshTable();
      this.syncPendingSuggestResetFromStorage();
      this.syncLoginUi();
    },
    methods: {
      dishCardKey(d, di) {
        return d && d.id != null ? `dish-${d.id}` : `dish-i-${di}`;
      },
      syncCartFromStorage() {
        try {
          const raw = wx.getStorageSync('shopping_cart');
          this.shopping_card = Array.isArray(raw) ? raw : [];
        } catch (e) {
          this.shopping_card = [];
        }
      },
      /** 与首页 shopping_Cart 合并规则一致；不联动 goods/itemize（AI 页无菜单树） */
      shopping_Cart(arr) {
        if (!arr || arr.quantity <= 0) {
          if (arr && arr.id != null && arr.id !== '') this.removeFromShoppingCart(arr.id);
          return;
        }
        if (!arr.onsale) return;
        if (dishSoldOut(arr)) return;
        if (!Array.isArray(this.shopping_card)) this.shopping_card = [];
        if (this.shopping_card.length === 0) {
          this.shopping_card.push(arr);
        } else {
          const itemindex = this.shopping_card.findIndex((item) => item.id == arr.id);
          if (itemindex === -1) {
            this.shopping_card.push(arr);
          } else {
            const sameSpicyIndex = this.shopping_card.findIndex(
              (item) => item.id === arr.id && item.selectedSpicy === arr.selectedSpicy
            );
            if (sameSpicyIndex !== -1) {
              this.$set(
                this.shopping_card[sameSpicyIndex],
                'quantity',
                this.shopping_card[sameSpicyIndex].quantity + arr.quantity
              );
              this.$set(
                this.shopping_card[sameSpicyIndex],
                'total_price',
                this.shopping_card[sameSpicyIndex].total_price + arr.total_price
              );
            } else {
              this.shopping_card.push(arr);
            }
          }
        }
        wx.setStorageSync('shopping_cart', this.shopping_card);
        this.sortShoppingCart();
      },
      sortShoppingCart() {
        if (!Array.isArray(this.shopping_card)) return;
        this.shopping_card.sort((a, b) => {
          const cidA = parseInt(a.index, 10);
          const cidB = parseInt(b.index, 10);
          if (cidA !== cidB) return cidA - cidB;
          const indexA = parseInt(a.good_index, 10);
          const indexB = parseInt(b.good_index, 10);
          return indexA - indexB;
        });
        this.$forceUpdate();
      },
      removeFromShoppingCart(id) {
        if (!Array.isArray(this.shopping_card)) return;
        const itemIndex = this.shopping_card.findIndex((item) => item.id === id);
        if (itemIndex !== -1) this.shopping_card.splice(itemIndex, 1);
        wx.setStorageSync('shopping_cart', this.shopping_card);
      },
      normalizeAiCartRow(it) {
        if (!it || typeof it !== 'object') return null;
        const id = it.id != null ? it.id : it.dishId;
        if (id == null || id === '') return null;
        const quantity = Math.max(1, Number(it.quantity) || 1);
        const rawPrice = it.unitprice != null ? it.unitprice : it.unit_price;
        let unitprice = rawPrice == null || rawPrice === '' ? 0 : Number(rawPrice);
        if (Number.isNaN(unitprice) || unitprice < 0) return null;
        const name = String(it.name || it.title || '商品').trim() || '商品';
        let image = it.image != null ? String(it.image).trim() : '';
        if (image) {
          image = image.replace(/^\/?image\/dish\//i, '');
        }
        const unit = it.unit != null && String(it.unit).trim() ? String(it.unit).trim() : '份';
        const cid = it.cid != null ? String(it.cid) : '';
        const good_index = it.good_index != null ? Number(it.good_index) : 0;
        const index = it.index != null ? Number(it.index) : 0;
        let selectedSpicy = it.selectedSpicy;
        if (selectedSpicy && typeof selectedSpicy === 'object') {
          try {
            selectedSpicy = JSON.stringify(selectedSpicy);
          } catch (e) {
            selectedSpicy = '{}';
          }
        } else if (selectedSpicy == null || selectedSpicy === '') {
          selectedSpicy = '{}';
        } else {
          selectedSpicy = String(selectedSpicy);
        }
        const onsale = it.onsale !== false;
        const sold_out = normalizeSoldOut(it.sold_out);
        return {
          image,
          name,
          unitprice,
          quantity,
          unit,
          total_price: unitprice * quantity,
          id,
          cid,
          index,
          good_index,
          onsale,
          sold_out,
          selectedSpicy,
        };
      },
      applyAiCartPayload(raw, extraSources = [], options = {}) {
        this.syncCartFromStorage();
        const quantityOverrides = options && options.quantityOverrides ? options.quantityOverrides : null;
        const extras = Array.isArray(extraSources) ? extraSources : [];
        const directObjects = [];
        const candidates = [];
        const pushCand = (x) => {
          if (x == null) return;
          if (Array.isArray(x) || (typeof x === 'object' && x !== null)) {
            directObjects.push(x);
            const s = actionPayloadToString(x).trim();
            if (s) candidates.push(s);
            return;
          }
          const t = String(x).trim();
          if (t) candidates.push(t);
        };
        pushCand(raw);
        for (let ei = 0; ei < extras.length; ei++) pushCand(extras[ei]);
        if (!candidates.length && !directObjects.length) {
          wx.showToast({ title: '购物车数据为空', icon: 'none' });
          return;
        }

        let data = null;
        for (let oi = 0; oi < directObjects.length; oi++) {
          const obj = directObjects[oi];
          if (Array.isArray(obj)) {
            data = obj;
            break;
          }
          if (obj && Array.isArray(obj.items)) {
            data = obj;
            break;
          }
        }
        for (let ci = 0; ci < candidates.length; ci++) {
          if (data != null) break;
          const cand = candidates[ci];
          data = tryParseAiCartJsonString(cand);
          if (data != null) break;
          const bracket = extractBracketPayloadForActionKey(cand, 'add_ai_cart');
          if (bracket) {
            data = tryParseAiCartJsonString(bracket);
            if (data != null) break;
          }
        }
        if (data == null) {
          for (let ei = 0; ei < extras.length; ei++) {
            const src = extras[ei];
            const text = typeof src === 'string' ? src : actionPayloadToString(src);
            const bracket = extractBracketPayloadForActionKey(text, 'add_ai_cart');
            if (!bracket) continue;
            data = tryParseAiCartJsonString(bracket);
            if (data != null) break;
          }
        }
        if (data == null) {
          const debugCandidates = candidates.slice(0, 5).map((c) => String(c).slice(0, 300));
          const debugExtras = extras.slice(0, 3).map((x) => {
            const text = typeof x === 'string' ? x : actionPayloadToString(x);
            return String(text).slice(0, 300);
          });
          const debugInfo = {
            rawType: typeof raw,
            rawPreview: (typeof raw === 'string' ? raw : actionPayloadToString(raw)).slice(0, 500),
            directObjectsCount: directObjects.length,
            candidateCount: candidates.length,
            candidatesPreview: debugCandidates,
            extrasCount: extras.length,
            extrasPreview: debugExtras,
          };
          console.error('[ai-add-cart] payload parse failed', {
            ...debugInfo,
          });
          try {
            console.error('[ai-add-cart] payload parse failed detail=' + JSON.stringify(debugInfo));
          } catch (e) {
            console.error('[ai-add-cart] payload parse failed detail stringify failed');
          }
          wx.showToast({ title: '购物车数据格式错误', icon: 'none' });
          return;
        }
        const items = Array.isArray(data) ? data : data && Array.isArray(data.items) ? data.items : null;
        if (!items || !items.length) {
          wx.showToast({ title: '没有可加入的商品', icon: 'none' });
          return;
        }
        // 产品要求：AI 加入购物车前先清空旧购物车，按当前方案整体覆盖。
        this.shopping_card = [];
        wx.removeStorageSync('shopping_cart');
        const sumQty = (card) =>
          !Array.isArray(card) ? 0 : card.reduce((s, x) => s + (Number(x.quantity) || 0), 0);
        const prevSum = sumQty(this.shopping_card);
        let attempted = 0;
        let validRows = 0;
        for (let i = 0; i < items.length; i++) {
          const row = this.normalizeAiCartRow(items[i]);
          if (!row) continue;
          if (quantityOverrides) {
            const byId = row.id != null ? quantityOverrides.byId && quantityOverrides.byId[String(row.id)] : null;
            const byName = row.name ? quantityOverrides.byName && quantityOverrides.byName[String(row.name).trim()] : null;
            const q = byId != null ? Number(byId) : (byName != null ? Number(byName) : NaN);
            if (Number.isFinite(q)) {
              const fixedQ = Math.max(0, Math.min(99, Math.round(q)));
              row.quantity = fixedQ;
              row.total_price = row.unitprice * fixedQ;
            }
          }
          if (!(Number(row.quantity) > 0)) continue;
          validRows++;
          attempted++;
          this.shopping_Cart(row);
        }
        const nextSum = sumQty(this.shopping_card);
        if (!validRows) {
          wx.showToast({ title: '商品字段不完整（缺少id/价格/数量）', icon: 'none' });
          return;
        }
        if (nextSum <= prevSum) {
          wx.showToast({ title: '加入失败：商品可能已下架或售罄', icon: 'none' });
          return;
        }
        const addedQty = nextSum - prevSum;
        wx.showToast({ title: `已加入购物车（+${addedQty}）`, icon: 'success' });
        wx.switchTab({ url: '/pages/home-page/page' });
      },
      dishImageSrc(d) {
        if (!d || !d.image) return '';
        const img = String(d.image).trim();
        if (!img || isNonImagePlaceholderText(img)) return '';
        return dishImageUrlList(img);
      },
      /** 无图或地址为空时用本地默认图 */
      dishImageDisplaySrc(d) {
        const u = this.dishImageSrc(d);
        return u && String(u).trim() ? u : DEFAULT_DISH_IMAGE;
      },
      refreshTable() {
        const n = app.getStorageWithExpiry('table_number');
        this.table_number = n != null && n !== '' ? String(n) : '';
      },
      persistHistory() {
        const openid = app.globalData.openid || wx.getStorageSync('openid');
        if (!openid || !this.canSend) return;
        try {
          const payload = {
            msgId: this.msgId,
            messages: this.messages.filter((m) => !m.loginHint).slice(-MAX_STORED_MESSAGES),
            savedAt: Date.now(),
          };
          wx.setStorageSync(storageKey(openid), JSON.stringify(payload));
        } catch (e) {
          console.warn('ai_order_chat persist', e);
        }
      },
      loadHistory() {
        const openid = app.globalData.openid || wx.getStorageSync('openid');
        if (!openid) return false;
        try {
          const raw = wx.getStorageSync(storageKey(openid));
          if (!raw) return false;
          const data = typeof raw === 'string' ? JSON.parse(raw) : raw;
          if (!data || !Array.isArray(data.messages) || data.messages.length === 0) return false;
          this.messages = data.messages.map((m) => normalizeCachedMessage(m));
          this.msgId =
            typeof data.msgId === 'number' && data.msgId > 0
              ? data.msgId
              : this.messages.reduce((max, x) => Math.max(max, x.id || 0), 0);
          return true;
        } catch (e) {
          console.warn('ai_order_chat load', e);
          return false;
        }
      },
      clearHistoryStorage() {
        const openid = app.globalData.openid || wx.getStorageSync('openid');
        if (!openid) return;
        try {
          wx.removeStorageSync(storageKey(openid));
        } catch (e) {}
      },
      /** 从本地恢复「新对话待带 reset」标记，避免 tab 重建后仍为 false */
      syncPendingSuggestResetFromStorage() {
        const openid = app.globalData.openid || wx.getStorageSync('openid');
        if (!openid) {
          this.chatSuggestResetOnce = false;
          return;
        }
        try {
          this.chatSuggestResetOnce = wx.getStorageSync(pendingResetStorageKey(openid)) === '1';
        } catch (e) {
          this.chatSuggestResetOnce = false;
        }
      },
      persistPendingSuggestReset(on) {
        const openid = app.globalData.openid || wx.getStorageSync('openid');
        if (!openid) return;
        const k = pendingResetStorageKey(openid);
        try {
          if (on) wx.setStorageSync(k, '1');
          else wx.removeStorageSync(k);
        } catch (e) {}
        this.chatSuggestResetOnce = !!on;
      },
      syncLoginUi() {
        if (this.sending) return;
        this.refreshUserAvatar();
        const openid = app.globalData.openid || wx.getStorageSync('openid');
        if (!openid) {
          this.canSend = false;
          this.pushLoginHintMessage();
          return;
        }
        if (!this.canSend) {
          this.enterLoggedInChat();
        }
      },
      /** 用户头像：支持 https 全路径，或后端相对路径如 /image/avatar/xxx.jpeg */
      resolveUserAvatarUrl(raw) {
        if (raw == null || !String(raw).trim()) return '';
        const s = String(raw).trim();
        if (/^https?:\/\//i.test(s)) return s;
        const base = String(getBaseUrl() || '').replace(/\/$/, '');
        if (!base) return s;
        const path = s.replace(/\\/g, '/').replace(/^\//, '');
        return `${base}/${path}`;
      },
      refreshUserAvatar() {
        const openid = app.globalData.openid || wx.getStorageSync('openid');
        if (!openid) {
          this.userAvatarUrl = '';
          return;
        }
        const u = app.globalData.userInfo || wx.getStorageSync('userInfo') || {};
        const raw = u && u.avatar != null ? String(u.avatar).trim() : '';
        this.userAvatarUrl = raw ? this.resolveUserAvatarUrl(raw) : '';
      },
      pushLoginHintMessage() {
        if (this.messages.some((m) => m.loginHint)) return;
        this.messages.push({
          id: this.nextMsgId(),
          role: 'assistant',
          loginHint: true,
          text: '您尚未登录。智能点餐需要微信授权登录后使用，点击下方按钮前往「我的」完成登录。',
          ts: nowTimeStr(),
        });
        this.$nextTick(() => this.scrollToBottom());
      },
      enterLoggedInChat() {
        this.canSend = true;
        this.messages = this.messages.filter((m) => !m.loginHint);
        if (this.messages.length === 0) {
          if (this.loadHistory()) {
            this.$nextTick(() => this.scrollToBottom());
            return;
          }
        }
        this.msgId = this.messages.reduce((max, m) => Math.max(max, m.id || 0), 0);
        if (this.messages.length === 0) {
          this.pushAssistantPayload({
            text: '您好，我是老肥油边王智能点餐助手。告诉我人数、口味偏好和预算，我会结合在售菜单给您点餐建议。',
            dishes: [],
            planMeta: null,
          });
        }
        this.$nextTick(() => this.scrollToBottom());
      },
      goLogin() {
        wx.switchTab({ url: '/pages/my/my' });
      },
      nextMsgId() {
        this.msgId += 1;
        return this.msgId;
      },
      pushAssistantPayload({ text, dishes = [], planMeta = null, action = '', actions: incomingActions = null }) {
        let t = text == null ? '' : String(text);
        let actions =
          Array.isArray(incomingActions) && incomingActions.length
            ? incomingActions.map((x) => ({
                key: String(x.key || '').trim().toLowerCase(),
                payload: actionPayloadToString(x.payload),
              }))
            : null;
        let a = String(action || '').trim().toLowerCase();
        if (Array.isArray(actions) && actions.length) {
          const beforeStrip = t;
          const stripped = parseAssistantActions(t);
          t = stripped.text;
          for (let aj = 0; aj < actions.length; aj++) {
            if (actions[aj].key !== 'add_ai_cart') continue;
            const fixed = extractBracketPayloadForActionKey(beforeStrip, 'add_ai_cart');
            if (fixed) actions[aj].payload = fixed;
          }
          if (!a) a = actions[0]?.key || '';
        } else {
          const parsed = parseAssistantActions(t);
          t = parsed.text;
          actions = parsed.actions;
          if (!a && actions.length) a = actions[0].key;
          if (!actions.length && a) actions = [{ key: a, payload: '' }];
        }
        const row = {
          id: this.nextMsgId(),
          role: 'assistant',
          text: t,
          action: a,
          actionPayload: actions[0]?.payload || '',
          actions,
          dishes: Array.isArray(dishes)
            ? dishes.map((d) => {
                const o = { ...d };
                if (o.sliderQty == null || o.sliderQty === '') {
                  o.sliderQty = parseSliderQtyFromDish(o);
                } else {
                  o.sliderQty = Math.min(99, Math.max(0, Math.round(Number(o.sliderQty))));
                }
                return o;
              })
            : [],
          planMeta: Array.isArray(planMeta) && planMeta.length ? planMeta : null,
          ts: nowTimeStr(),
        };
        this.messages.push(row);
        this.messages = this.messages.slice();
        this.persistHistory();
        this.$nextTick(() => this.scrollToBottom());
      },
      pushUser(text) {
        const row = {
          id: this.nextMsgId(),
          role: 'user',
          text: text == null ? '' : String(text),
        };
        this.messages.push(row);
        this.messages = this.messages.slice();
        this.persistHistory();
      },
      /**
       * 滚到底部锚点。先清空再赋值，避免 scroll-into-view 值不变时不滚动；多次延迟适配「正在输入」与菜品图撑高。
       */
      scrollToBottom() {
        const anchor = 'chat-anchor';
        const snap = () => {
          this.scrollIntoView = '';
          this.$nextTick(() => {
            this.scrollIntoView = anchor;
          });
        };
        snap();
        setTimeout(snap, 100);
        setTimeout(snap, 420);
      },
      onComposerFocus() {
        if (this._quickBlurTimer) {
          clearTimeout(this._quickBlurTimer);
          this._quickBlurTimer = null;
        }
        this.inputFocused = true;
      },
      onComposerBlur() {
        if (this._quickBlurTimer) clearTimeout(this._quickBlurTimer);
        this._quickBlurTimer = setTimeout(() => {
          this.inputFocused = false;
          this._quickBlurTimer = null;
        }, 220);
      },
      onPickQuick(q) {
        if (this.sending || !this.canSend) return;
        if (this._quickBlurTimer) {
          clearTimeout(this._quickBlurTimer);
          this._quickBlurTimer = null;
        }
        this.inputText = q;
        this.inputFocused = false;
      },
      onDishCardTap(d) {
        wx.switchTab({ url: '/pages/home-page/page' });
      },
      dishSliderQty(d) {
        return parseSliderQtyFromDish(d);
      },
      dishLineSubtotalDisplay(d) {
        const q = this.dishSliderQty(d);
        const u = Number(d && d.priceMain);
        if (!Number.isFinite(u) || u < 0 || !Number.isFinite(q) || q <= 0) return '';
        return `小计 ¥${formatMoney(u * q)}`;
      },
      onDishSliderDelta(m, di, delta) {
        const mi = this.messages.findIndex((x) => x.id === m.id);
        if (mi < 0 || !this.messages[mi].dishes || !this.messages[mi].dishes[di]) return;
        const row = this.messages[mi].dishes[di];
        const cur = this.dishSliderQty(row);
        const next = Math.max(0, Math.min(99, cur + delta));
        this.$set(this.messages[mi].dishes[di], 'sliderQty', next);
        this.messages = this.messages.slice();
        this.persistHistory();
      },
      onDishRemoveFromBubble(m, di) {
        const mi = this.messages.findIndex((x) => x.id === m.id);
        if (mi < 0 || !this.messages[mi].dishes) return;
        const next = this.messages[mi].dishes.filter((_, idx) => idx !== di);
        this.$set(this.messages[mi], 'dishes', next);
        this.messages = this.messages.slice();
        this.persistHistory();
      },
      assistantActionButtons(m) {
        if (!m || m.role !== 'assistant' || m.loginHint) return [];
        const raw =
          Array.isArray(m.actions) && m.actions.length
            ? m.actions
            : m.action
              ? [{ key: m.action, payload: m.actionPayload || '' }]
              : [];
        const out = [];
        for (let i = 0; i < raw.length; i++) {
          const key = String(raw[i].key || '').trim().toLowerCase();
          const payload = actionPayloadToString(raw[i].payload);
          const def = ASSISTANT_ACTION_DEFS[key];
          if (!def) continue;
          let label = def.label;
          if (def.labelFromPayload) {
            const p = payload.trim();
            label = p ? (p.length > 12 ? `${p.slice(0, 12)}…` : p) : '发送';
          }
          out.push({
            key,
            payload,
            label,
            needSendGuard: !!def.needSendGuard,
          });
        }
        // 「确认下单」固定显示在最后一行，其它按钮保持原有顺序
        return out.sort((a, b) => {
          const aLast = a.key === 'confirm_place_order' ? 1 : 0;
          const bLast = b.key === 'confirm_place_order' ? 1 : 0;
          return aLast - bLast;
        });
      },
      runAssistantAction(key, payload, msg) {
        const k = String(key || '').trim().toLowerCase();
        const def = ASSISTANT_ACTION_DEFS[k];
        if (!def) return;
        if (def.needSendGuard && (this.sending || !this.canSend)) return;
        if (k === 'add_ai_cart' && msg && msg.role === 'assistant') {
          const extras = [];
          if (msg.text) extras.push(msg.text);
          const hit = (msg.actions || []).find((x) => String(x.key || '').trim().toLowerCase() === 'add_ai_cart');
          if (hit && hit.payload != null && String(hit.payload).trim()) extras.push(hit.payload);
          const quantityOverrides = { byId: {}, byName: {} };
          if (Array.isArray(msg.dishes)) {
            msg.dishes.forEach((d) => {
              const qty = this.dishSliderQty(d);
              if (!Number.isFinite(qty)) return;
              if (d && d.dishId != null && d.dishId !== '') quantityOverrides.byId[String(d.dishId)] = qty;
              if (d && d.id != null && d.id !== '') quantityOverrides.byId[String(d.id)] = qty;
              if (d && d.name) quantityOverrides.byName[String(d.name).trim()] = qty;
            });
          }
          def.run(this, payload, extras, { quantityOverrides });
          return;
        }
        def.run(this, payload);
      },
      scanAndBindTable() {
        app.scanCode({
          onSuccess: (res) => {
            const raw = [res && res.path, res && res.result].filter(Boolean).join(' ');
            const hit = String(raw).match(/(?:number|table_number)=(\d+)/i) || String(raw).match(/\b(\d{1,6})\b/);
            if (!hit) {
              wx.showToast({ title: '未识别到桌号', icon: 'none' });
              return;
            }
            const table = String(hit[1]);
            this.table_number = table;
            wx.setStorageSync('table_number', table);
            app.setStorageWithExpiry('table_number', table);
            wx.showToast({ title: `已绑定桌号 ${table}`, icon: 'none' });
            // 让 AI 接着用已绑定桌号继续给下一步建议（复用 onSend）
            this.inputText = '已扫码绑定桌号';
            this.$nextTick(() => this.onSend());
          },
          onFail: () => {
            wx.showToast({ title: '未完成扫码', icon: 'none' });
          },
        });
      },
      async onSend() {
        const prompt = this.inputTrimmed;
        if (!prompt || this.sending || !this.canSend) return;
        const openid = app.globalData.openid || wx.getStorageSync('openid');
        if (!openid) return;
  
        this.pushUser(prompt);
        this.inputText = '';
        this.sending = true;
        this.$nextTick(() => {
          this.scrollToBottom();
        });
  
        try {
          this.refreshTable();
          this.syncPendingSuggestResetFromStorage();
          const withReset = this.chatSuggestResetOnce === true;
          const data = await requestUtil({
            url: '/order/ai/chatSuggest',
            method: 'post',
            data: {
              openid,
              prompt,
              table_number: this.tableDisplay || undefined,
              ...(withReset ? { reset: true } : {}),
            },
            timeout: 120000,
            showLoading: false,
          });
  
          if (!data) {
            this.pushAssistantPayload({ text: '服务暂时无响应，请稍后重试。', dishes: [], planMeta: null });
            return;
          }
          if (data.code !== 0) {
            this.pushAssistantPayload({ text: data.msg || '请求失败', dishes: [], planMeta: null });
            return;
          }
          const { text, dishes, planMeta, action, actions } = assistantBubbleAndDishes(data.plan);
          this.pushAssistantPayload({ text, dishes, planMeta, action, actions });
          this.persistPendingSuggestReset(false);
        } catch (e) {
          console.error('chatSuggest', e);
          this.pushAssistantPayload({ text: '网络异常，请检查连接后重试。', dishes: [], planMeta: null });
        } finally {
          this.sending = false;
          this.$nextTick(() => {
            this.scrollToBottom();
          });
        }
      },
      onNewChat() {
        if (this.sending) return;
        wx.showModal({
          title: '开始新对话',
          content: '将清空服务端与您当前账号的多轮会话上下文，并清除本机聊天记录。',
          success: (r) => {
            if (!r.confirm) return;
            const openid = app.globalData.openid || wx.getStorageSync('openid');
            if (!openid) {
              wx.showToast({ title: '请先登录', icon: 'none' });
              return;
            }
            this.clearHistoryStorage();
            this.messages = [];
            this.msgId = 0;
            this.persistPendingSuggestReset(true);
            this.refreshTable();
            this.pushAssistantPayload({
              text: '您好，我是老肥油边王智能点餐助手。告诉我人数、口味偏好和预算，我会结合在售菜单给您点餐建议。',
              dishes: [],
              planMeta: null,
            });
            this.$nextTick(() => this.scrollToBottom());
          },
        });
      },
    },
  };
  </script>
  
  <style scoped>
  .ai-chat-page {
    display: flex;
    flex-direction: column;
    height: 100vh;
    background: linear-gradient(180deg, #fff5f0 0%, #f7f8fa 32%, #f0f2f5 100%);
    box-sizing: border-box;
  }
  
  .top-bar {
    flex-shrink: 0;
    padding: 16rpx 24rpx 8rpx;
    background: rgba(255, 255, 255, 0.92);
    border-bottom: 1rpx solid #eee;
  }

  .top-bar-inner {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16rpx;
  }
  
  .table-hint {
    flex: 1;
    min-width: 0;
    font-size: 24rpx;
    color: #333;
    line-height: 1.4;
  }
  
  .table-hint--weak {
    color: #888;
  }
  
  .table-label {
    color: #999;
    margin-right: 8rpx;
  }
  
  .table-value {
    font-weight: 600;
    color: #e10606;
  }
  
  .btn-new-chat {
    flex-shrink: 0;
    margin: 0;
    padding: 0 20rpx;
    font-size: 24rpx;
    line-height: 52rpx;
    height: 52rpx;
    background: #fff;
    color: #e10606;
    border: 1rpx solid #e10606;
    border-radius: 28rpx;
  }
  
  .msg-scroll {
    flex: 1;
    min-height: 0;
    padding: 16rpx 0 0;
  }
  
  .msg-list {
    padding: 0 20rpx 24rpx;
  }
  
  .msg-row {
    display: flex;
    align-items: flex-start;
    margin-bottom: 24rpx;
  }
  
  .msg-row--user {
    justify-content: flex-end;
  }
  
  .msg-row--assistant {
    justify-content: flex-start;
  }
  
  .avatar {
    width: 64rpx;
    height: 64rpx;
    border-radius: 50%;
    font-size: 22rpx;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    font-weight: 700;
  }
  
  .ai-avatar {
    margin-right: 12rpx;
    background: linear-gradient(135deg, #ff5117, #e10606);
    color: #fff;
  }
  
  .user-avatar {
    margin-left: 12rpx;
    background: #e8e8e8;
    color: #555;
    overflow: hidden;
    padding: 0;
  }

  .user-avatar-img {
    width: 100%;
    height: 100%;
    border-radius: 50%;
    display: block;
  }

  .user-avatar-fallback {
    font-size: 22rpx;
    font-weight: 700;
  }
  
  .bubble-wrap {
    max-width: 72%;
    min-width: 0;
  }
  
  .msg-row--assistant .bubble-wrap {
    max-width: 88%;
  }
  
  .bubble {
    border-radius: 20rpx;
    padding: 20rpx 24rpx;
    word-break: break-word;
  }
  
  .bubble--user {
    background: linear-gradient(135deg, #ff5117, #e10606);
    color: #fff;
    border-bottom-right-radius: 6rpx;
  }
  
  .bubble--ai {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    min-width: 0;
    background: #fff;
    color: #222;
    border: 1rpx solid #f0f0f0;
    box-shadow: 0 4rpx 16rpx rgba(0, 0, 0, 0.06);
    border-bottom-left-radius: 6rpx;
  }
  
  .login-hint-bubble {
    width: 100%;
  }
  
  .btn-login-inline {
    margin-top: 20rpx;
    width: 100%;
    height: 72rpx;
    line-height: 72rpx;
    font-size: 28rpx;
    border-radius: 14rpx;
    background: linear-gradient(90deg, #ff5117, #e10606);
    color: #fff;
    border: none;
    padding: 0;
  }
  
  .btn-login-inline::after {
    border: none;
  }
  
  .ai-main-block {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    width: 100%;
    min-width: 0;
  }

  .ai-action-below-text {
    align-self: flex-start;
    width: auto;
    max-width: 100%;
    margin-top: 20rpx;
    box-sizing: border-box;
  }

  .btn-action-inline {
    width: auto;
    margin: 0;
    height: 64rpx;
    line-height: 64rpx;
    padding: 0 28rpx;
    border-radius: 14rpx;
    background: #fff5f0;
    color: #d63a00;
    border: 1rpx solid #ffd2bf;
    font-size: 26rpx;
    box-sizing: border-box;
  }

  .btn-action-inline::after {
    border: none;
  }
  
  .bubble--typing {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6rpx;
  }
  
  .dot {
    animation: blink 1.2s infinite;
    font-size: 36rpx;
    line-height: 1;
    color: #e10606;
  }
  
  .dot:nth-child(2) {
    animation-delay: 0.2s;
  }
  
  .dot:nth-child(3) {
    animation-delay: 0.4s;
  }
  
  @keyframes blink {
    0%,
    80%,
    100% {
      opacity: 0.25;
    }
    40% {
      opacity: 1;
    }
  }
  
  .typing-tip {
    width: 100%;
    font-size: 24rpx;
    color: #888;
    margin-top: 8rpx;
  }
  
  .bubble-text {
    font-size: 28rpx;
    line-height: 1.55;
    white-space: pre-wrap;
  }
  
  .bubble-text--user {
    color: #fff;
  }
  
  .bubble-text--ai {
    color: #222;
  }
  
  .ai-bubble-main {
    display: block;
    width: 100%;
    box-sizing: border-box;
  }
  
  .plan-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 12rpx;
    margin-bottom: 16rpx;
  }
  
  .plan-meta-chip {
    display: inline-flex;
    align-items: center;
    padding: 8rpx 16rpx;
    background: #fff5f0;
    border: 1rpx solid #ffd0bf;
    border-radius: 10rpx;
    font-size: 22rpx;
    line-height: 1.3;
  }
  
  .plan-meta-label {
    color: #999;
    margin-right: 8rpx;
  }
  
  .plan-meta-value {
    color: #c53000;
    font-weight: 600;
  }
  
  /* —— 点餐页 classif-goods 同款结构（略收窄边距以适配聊天气泡） —— */
  .ai-dish-list {
    margin-top: 16rpx;
    width: 100%;
    padding: 8rpx 0 4rpx;
  }
  
  .ai-dish-card-wrap {
    margin-bottom: 16rpx;
    border: 1rpx solid #f0f0f0;
    border-radius: 14rpx;
    background: #fffdfc;
    box-sizing: border-box;
    overflow: hidden;
  }

  .ai-dish-card-wrap:last-child {
    margin-bottom: 0;
  }

  .ai-dish-card-wrap--zero .ai-dish-card {
    opacity: 0.55;
  }

  .ai-dish-card {
    height: auto;
    min-height: 150rpx;
    padding: 16rpx 14rpx;
    box-sizing: border-box;
    margin-bottom: 0;
    border: none;
    border-radius: 0;
    background: transparent;
  }

  .dish-card-stepper-row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 12rpx;
    padding: 12rpx 20rpx 16rpx;
    border-top: 1rpx solid #f2f2f2;
    background: #fffdfb;
  }

  .dish-card-stepper-sub {
    font-size: 24rpx;
    color: #e10606;
    font-weight: 600;
    flex: 1;
    min-width: 0;
  }

  .dish-card-stepper-ctrl {
    display: flex;
    align-items: center;
    gap: 16rpx;
  }

  .stepper-btn {
    width: 56rpx;
    height: 56rpx;
    line-height: 54rpx;
    text-align: center;
    font-size: 34rpx;
    color: #333;
    background: #f0f0f0;
    border-radius: 12rpx;
    font-weight: 500;
  }

  .stepper-btn--disabled {
    opacity: 0.35;
    pointer-events: none;
  }

  .stepper-val {
    min-width: 48rpx;
    text-align: center;
    font-size: 30rpx;
    font-weight: 600;
    color: #333;
  }

  .stepper-del {
    font-size: 26rpx;
    color: #999;
    padding: 8rpx 4rpx;
    margin-left: 4rpx;
  }
  
  .classif-goods {
    display: flex;
    justify-content: space-between;
    align-items: stretch;
    padding: 20rpx;
    min-height: 150rpx;
    font-size: 30rpx;
    
  }
  
  .goods-image {
    position: relative;
    width: 150rpx;
    height: 150rpx;
    flex-shrink: 0;
  }
  
  .placeholder-img {
    width: 100%;
    height: 100%;
    background-color: #f5f5f5;
    border-radius: 10rpx;
  }
  
  .real-img {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    border-radius: 10rpx;
  }

  .dish-card-cover {
    background-color: #f5f5f5;
  }
  
  .goods-Price {
    flex: 1;
    position: relative;
    padding: 4rpx 18rpx 2rpx;
    min-width: 0;
  }
  
  .goods-Price text {
    display: block;
  }
  
  .goods-name {
    display: flex;
    flex-direction: column;
    position: relative;
    top: 0;
    padding-right: 8rpx;
  }
  
  .goods-name text:nth-child(1) {
    padding-bottom: 9rpx;
  }
  
  .unit-price {
    position: absolute;
    bottom: 0;
    display: flex;
    align-items: baseline;
  }
  
  .Bold {
    font-weight: 550;
    font-size: 28rpx;
  }
  
  .Thinning {
    font-size: 22rpx;
    color: #999;
  }
  
  .Symbol {
    font-size: 20rpx;
    color: #e60909;
  }
  
  .Unitprice {
    font-weight: 550;
    font-size: 28rpx;
    color: #e60909;
  }
  
  .unit {
    font-size: 22rpx;
    color: #999;
    margin-left: 4rpx;
  }
  
  .dish-card-qty {
    flex-shrink: 0;
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    justify-content: center;
    padding-left: 12rpx;
    max-width: 160rpx;
  }
  
  .dish-qty-line {
    font-size: 24rpx;
    color: #666;
    margin-bottom: 8rpx;
  }
  
  .dish-sub-line {
    font-size: 24rpx;
    color: #e10606;
    font-weight: 600;
  }
  
  .msg-meta {
    font-size: 22rpx;
    color: #bbb;
    margin-top: 8rpx;
    text-align: left;
  }
  
  .scroll-bottom-pad {
    min-height: 24rpx;
    height: 32rpx;
  }
  
  .footer-area {
    flex-shrink: 0;
    background: #fff;
    /* tabBar 页内容区已在 tab 之上，勿再叠一整段 safe-area，否则留白过大 */
    padding-bottom: 8rpx;
  }
  
  .quick-panel {
    max-height: 0;
    overflow: hidden;
    opacity: 0;
    transform: translateY(16rpx);
    transition: max-height 0.3s cubic-bezier(0.33, 1, 0.68, 1), opacity 0.22s ease, transform 0.28s ease;
    border-top: 1rpx solid transparent;
    box-sizing: border-box;
  }
  
  .quick-panel--open {
    max-height: 520rpx;
    opacity: 1;
    transform: translateY(0);
    border-top-color: #eee;
  }
  
  .quick-panel-inner {
    max-height: 520rpx;
    overflow-y: auto;
    padding: 12rpx 20rpx 16rpx;
    box-sizing: border-box;
  }
  
  .quick-panel-title {
    font-size: 24rpx;
    color: #999;
    margin-bottom: 12rpx;
  }
  
  .quick-panel-item {
    font-size: 26rpx;
    color: #333;
    padding: 18rpx 20rpx;
    margin-bottom: 12rpx;
    background: #f7f8fa;
    border-radius: 12rpx;
    border: 1rpx solid #eee;
  }
  
  .quick-panel-item:last-child {
    margin-bottom: 0;
  }
  
  .quick-panel-item--disabled {
    opacity: 0.45;
  }
  
  .composer-wrap {
    border-top: 1rpx solid #eee;
    background: #fff;
  }

  .composer {
    display: flex;
    align-items: flex-end;
    padding: 12rpx 20rpx 4rpx;
    gap: 16rpx;
  }

  .composer-ai-footnote {
    display: block;
    padding: 0 24rpx 6rpx;
    font-size: 22rpx;
    line-height: 1.4;
    color: #999;
    text-align: center;
  }
  .composer-input {
    flex: 1;
    min-height: 72rpx;
    max-height: 200rpx;
    padding: 16rpx 20rpx;
    font-size: 28rpx;
    line-height: 1.4;
    background: #f5f5f5;
    border-radius: 16rpx;
    box-sizing: border-box;
  }
  
  .send-btn {
    flex-shrink: 0;
    margin: 0;
    padding: 0 28rpx;
    height: 72rpx;
    line-height: 72rpx;
    font-size: 28rpx;
    border-radius: 16rpx;
    background: linear-gradient(90deg, #ff5117, #e10606);
  }
  
  .send-btn::after {
    border: none;
  }
  
  </style>
  