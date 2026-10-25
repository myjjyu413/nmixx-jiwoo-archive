// videos.js 안의 틱톡 영상 표지 이미지를 thumbs/tt/<영상ID>.jpg 로 저장합니다 (GitHub Actions에서 실행)
import fs from "fs";
const src = fs.readFileSync("videos.js", "utf8");
const ids = [...new Set([...src.matchAll(/tiktok\.com\/@[\w.\-]+\/video\/(\d+)/g)].map(m => m[1]))];
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";
async function coverUrl(id, url) {
  try {
    const j = await (await fetch("https://www.tiktok.com/oembed?url=" + encodeURIComponent(url), { headers: { "User-Agent": UA } })).json();
    if (j.thumbnail_url) return j.thumbnail_url;
  } catch (e) { console.log("oembed fail", id, e.message); }
  try {
    const h = await (await fetch(url, { headers: { "User-Agent": UA, "Accept-Language": "ko" } })).text();
    const m = h.match(/"(?:originCover|cover|dynamicCover)":"(https:[^"]+)"/);
    if (m) return JSON.parse('"' + m[1] + '"');
    const og = h.match(/property="og:image" content="([^"]+)"/);
    if (og) return og[1].replace(/&amp;/g, "&");
  } catch (e) { console.log("page fail", id, e.message); }
  return null;
}
for (const id of ids) {
  const out = `thumbs/tt/${id}.jpg`;
  if (fs.existsSync(out)) continue;
  const url = (src.match(new RegExp(`https://www\\.tiktok\\.com/@[\\w.\\-]+/video/${id}`)) || [])[0];
  const c = await coverUrl(id, url);
  if (!c) { console.log("no cover", id); continue; }
  const r = await fetch(c, { headers: { "User-Agent": UA, Referer: "https://www.tiktok.com/" } });
  if (!r.ok) { console.log("img fail", id, r.status); continue; }
  fs.writeFileSync(out, Buffer.from(await r.arrayBuffer()));
  console.log("saved", out);
}
