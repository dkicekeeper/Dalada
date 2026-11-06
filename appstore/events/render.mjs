// Картинки событий App Store из appstore/events/art/<событие>.html: карточка 1920 × 1080 и страница
// события 1080 × 1920, JPEG без прозрачности. Запуск: node appstore/events/render.mjs first_ice
// (нужен Playwright с Chromium). Результат — appstore/events/<событие>/card.jpg и details.jpg.
import { mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// Playwright — из проекта, из NODE_PATH или из глобальной установки облачного окружения.
const require = createRequire(import.meta.url);
const { chromium } = (() => {
  for (const name of ["playwright", "/opt/node-tools/node_modules/playwright", "/opt/node22/lib/node_modules/playwright"]) {
    try { return require(name); } catch {}
  }
  throw new Error("Нет Playwright: npm i playwright или NODE_PATH=$(npm root -g)");
})();

const here = dirname(fileURLToPath(import.meta.url));
const event = process.argv[2] || "first_ice";
const art = pathToFileURL(join(here, "art", event + ".html")).href;
const out = join(here, event);
mkdirSync(out, { recursive: true });

const browser = await chromium.launch();
for (const [name, width, height] of [["card", 1920, 1080], ["details", 1080, 1920]]) {
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  await page.goto(`${art}?w=${width}&h=${height}`);
  await page.waitForSelector("svg");
  await page.screenshot({ path: join(out, name + ".jpg"), type: "jpeg", quality: 92 });
  await page.close();
  console.log(`${event}/${name}.jpg — ${width} × ${height}`);
}
await browser.close();
