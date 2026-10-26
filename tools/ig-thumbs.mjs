// videos.js 안의 인스타그램 게시물 표지 이미지를 thumbs/ig/<코드>.jpg 로 저장합니다 (GitHub Actions에서 실행)
import fs from "fs";
const src = fs.readFileSync("videos.js", "utf8");
const codes = [...new Set([...src.matchAll(/instagram\.com\/(?:[\w.]+\/)?(?:reels?|p|tv)\/([\w-]+)/gi)].map(m => m[1]))];
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";
const LOG=[];const log=(...a)=>{console.log(...a);LOG.push(a.join(" "));};
const dec = s => s.replace(/\\u0026/g, "&").replace(/&amp;/g, "&").replace(/\\\//g, "/");
async function cover(code) {
  for (const u of [`https://www.instagram.com/p/${code}/embed/captioned/`, `https://www.instagram.com/reel/${code}/embed/`, `https://www.instagram.com/p/${code}/`]) {
    try {
      const h = await (await fetch(u, { headers: { "User-Agent": UA, "Accept-Language": "ko,en" } })).text();
      let m = h.match(/class="EmbeddedMediaImage"[^>]*src="([^"]+)"/) || h.match(/<img[^>]+class="EmbeddedMediaImage"[^>]+>/);
      if (m && m[1]) return dec(m[1]);
      m = h.match(/"display_url":"([^"]+)"/) || h.match(/"thumbnail_src":"([^"]+)"/) || h.match(/property="og:image" content="([^"]+)"/);
      if (m) return dec(m[1]);
      log("no image in", u, h.length, JSON.stringify(h.slice(0,300)));
    } catch (e) { log("fail", u, e.message); }
  }
  return null;
}
for (const code of codes) {
  const out = `thumbs/ig/${code}.jpg`;
  if (fs.existsSync(out)) continue;
  const c = await cover(code);
  if (!c) { log("no cover", code); continue; }
  const r = await fetch(c, { headers: { "User-Agent": UA, Referer: "https://www.instagram.com/" } });
  if (!r.ok) { log("img fail", code, r.status); continue; }
  fs.writeFileSync(out, Buffer.from(await r.arrayBuffer()));
  log("saved", out);
}

fs.writeFileSync("thumbs/ig/_log.txt", LOG.join("\n"));
