// Плоская картинка иконки из файла Icon Composer: фон из icon.json + слои из Assets/ (сзади вперёд).
// Стекло (блики, тени) рисует сама iOS — здесь его нет. Нужна, чтобы обновить PNG в AppIcon.appiconset
// (запасная иконка, страница App Store, og.png сайта) и посмотреть иконку в маленьком размере.
//
//   node docs/05-release/icon/render.mjs <AppIcon.icon> <выходная папка>
//
// Пишет icon-light.png и icon-dark.png (1024 × 1024, без прозрачности) и preview.png — иконка на
// светлом и тёмном домашнем экране в размерах 60, 40 и 29 pt. Использует Playwright с Chromium.
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import fs from 'fs';
import path from 'path';

const [iconDir, outDir] = process.argv.slice(2);
if (!iconDir || !outDir) {
  console.error('node render.mjs <AppIcon.icon> <выходная папка>');
  process.exit(1);
}
fs.mkdirSync(outDir, { recursive: true });
const icon = JSON.parse(fs.readFileSync(path.join(iconDir, 'icon.json'), 'utf8'));

// «srgb:0.1,0.2,0.3,1.0» → rgba(…)
const color = (value) => {
  const [, comps] = value.split(':');
  const [r, g, b, a] = comps.split(',').map(Number);
  return `rgba(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)}, ${a ?? 1})`;
};

const background = (fill) => {
  if (fill.solid) return color(fill.solid);
  const [c1, c2] = fill['linear-gradient'];
  const o = fill.orientation ?? { start: { x: 0.5, y: 0 }, stop: { x: 0.5, y: 1 } };
  const angle = (Math.atan2(o.stop.x - o.start.x, -(o.stop.y - o.start.y)) * 180) / Math.PI;
  const from = Math.round(o.start.y * 100);
  const to = Math.round(o.stop.y * 100);
  return `linear-gradient(${angle}deg, ${color(c1)} ${from}%, ${color(c2)} ${to}%)`;
};

const fillFor = (appearance) =>
  (icon['fill-specializations'] ?? []).find((s) => s.appearance === appearance)?.value ?? icon.fill;

// Сзади вперёд: в icon.json первая группа и первый слой — передние.
const layers = [...icon.groups]
  .reverse()
  .filter((g) => !g.hidden)
  .flatMap((g) => [...g.layers].reverse().filter((l) => !l.hidden))
  .map((l) => {
    const svg = fs.readFileSync(path.join(iconDir, 'Assets', l['image-name']));
    return { src: 'data:image/svg+xml;base64,' + svg.toString('base64'), opacity: l.opacity ?? 1 };
  });

const art = (appearance, size) => `
  <div style="position:relative;width:${size}px;height:${size}px;overflow:hidden;background:${background(fillFor(appearance))}">
    ${layers.map((l) => `<img src="${l.src}" style="position:absolute;inset:0;width:100%;height:100%;opacity:${l.opacity}">`).join('')}
  </div>`;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
for (const appearance of ['light', 'dark']) {
  await page.setContent(`<html><body style="margin:0">${art(appearance, 1024)}</body></html>`);
  await page.waitForTimeout(200);
  await page.screenshot({ path: path.join(outDir, `icon-${appearance}.png`), omitBackground: false });
}

const tile = (appearance, pt) =>
  `<div style="border-radius:${pt * 3 * 0.2237}px;overflow:hidden;width:${pt * 3}px;height:${pt * 3}px">
     <div style="transform:scale(${(pt * 3) / 1024});transform-origin:0 0">${art(appearance, 1024)}</div></div>`;
const row = (appearance, bg, fg) => `
  <div style="display:flex;gap:40px;align-items:center;padding:40px;background:${bg};border-radius:40px">
    ${[60, 40, 29].map((pt) => tile(appearance, pt)).join('')}
    <span style="font:32px -apple-system,Helvetica,Arial;color:${fg}">Dalada</span>
  </div>`;
await page.setViewportSize({ width: 900, height: 700 });
await page.setContent(`<html><body style="margin:0;padding:40px;background:#f2f2f7;display:flex;flex-direction:column;gap:40px">
  ${row('light', 'linear-gradient(135deg,#d9e7f7,#f7e6d9)', '#1c1c1e')}
  ${row('dark', 'linear-gradient(135deg,#0b0b12,#1d2233)', '#fff')}
</body></html>`);
await page.waitForTimeout(200);
await page.screenshot({ path: path.join(outDir, 'preview.png'), fullPage: true });
await browser.close();
console.log('готово:', outDir);
