// videos.js 안의 인스타그램 게시물 대표 이미지(링크 미리보기용)를 thumbs/ig/<코드>.jpg 로 저장합니다 (GitHub Actions에서 실행)
import fs from "fs";
const src = fs.readFileSync("videos.js", "utf8") + "\n" + (fs.existsSync("remote.txt") ? fs.readFileSync("remote.txt", "utf8") : "");
const codes = [...new Set([...src.matchAll(/instagram\.com\/(?:[\w.]+\/)?(?:reels?|p|tv)\/([\w-]+)/gi)].map(m => m[1]))];
const LOG = [];
for (const code of codes) {
  const out = `thumbs/ig/${code}.jpg`;
  if (fs.existsSync(out)) continue;
  let img = null;
  for (const ua of ["facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)", "Twitterbot/1.0", "Slackbot-LinkExpanding 1.0 (+https://api.slack.com/robots)", "TelegramBot (like TwitterBot)"]) {
    for (const u of [`https://www.instagram.com/p/${code}/`, `https://www.instagram.com/reel/${code}/`]) {
      try {
        const h = await (await fetch(u, { headers: { "User-Agent": ua, "Accept-Language": "ko" } })).text();
        const m = h.match(/property="og:image" content="([^"]+)"/) || h.match(/content="([^"]+)" property="og:image"/);
        LOG.push(`${code} ua=${ua.slice(0, 12)} ${u.includes("/reel/") ? "reel" : "p"} len=${h.length} img=${m ? m[1].slice(0, 60) : "-"}`);
        if (m) { img = m[1].replace(/&amp;/g, "&"); break; }
      } catch (e) { LOG.push(`${code} fail ${e.message}`); }
    }
    if (img) break;
  }
  if (!img) continue;
  const r = await fetch(img);
  if (r.ok) { fs.writeFileSync(out, Buffer.from(await r.arrayBuffer())); LOG.push(`saved ${out}`); } else LOG.push(`${code} img ${r.status}`);
}
console.log(LOG.join("\n"));
