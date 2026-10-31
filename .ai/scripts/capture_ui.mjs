#!/usr/bin/env node
/** Capture a deterministic full-page UI screenshot using Playwright.
 *
 * Usage:
 *   node .ai/scripts/capture_ui.mjs --url http://localhost:3000/page \
 *     --out production.png --width 1440 --height 900
 *
 * Requires Playwright in the target project:
 *   npm install -D playwright
 */
import fs from 'node:fs';
import process from 'node:process';

function arg(name, fallback = undefined) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : fallback;
}

const url = arg('url');
const out = arg('out', 'screenshot.png');
const width = Number(arg('width', '1440'));
const height = Number(arg('height', '900'));
const waitFor = arg('wait-for', 'networkidle');
const delay = Number(arg('delay', '0'));
const fullPage = arg('full-page', 'true') !== 'false';
const colorScheme = arg('color-scheme', 'light');

if (!url) {
  console.error('ERROR: --url is required');
  process.exit(2);
}

let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch (e) {
  console.error('ERROR: Playwright is required. Install it in the target project: npm install -D playwright');
  process.exit(2);
}

const browser = await chromium.launch({ headless: true });
try {
  const context = await browser.newContext({
    viewport: { width, height },
    colorScheme,
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  await page.goto(url, { waitUntil: waitFor, timeout: 60_000 });
  if (delay > 0) await page.waitForTimeout(delay);
  // Disable animations/transitions to reduce noisy diffs.
  await page.addStyleTag({ content: `
    *, *::before, *::after {
      animation-duration: 0s !important;
      animation-delay: 0s !important;
      transition-duration: 0s !important;
      caret-color: transparent !important;
    }
  `});
  await page.screenshot({ path: out, fullPage });
  fs.writeFileSync(`${out}.meta.json`, JSON.stringify({ url, width, height, fullPage, colorScheme }, null, 2));
  console.log(out);
  await context.close();
} finally {
  await browser.close();
}
