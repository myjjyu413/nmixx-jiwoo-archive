// videos.js 안의 X(트위터) 게시물 영상 표지를 thumbs/x/<글번호>.jpg 로 저장합니다 (GitHub Actions에서 실행)
import fs from "fs";
const src = fs.readFileSync("videos.js", "utf8");
const ids = [...new Set([...src.matchAll(/(?:x|twitter)\.com\/[\w]+\/status\/(\d+)/gi)].map(m => m[1]))];
if (process.env.XTEST) ids.push(...process.env.XTEST.split(","));
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";
const token = id => ((Number(id) / 1e15) * Math.PI).toString(36).replace(/(0+|\.)/g, "");
const LOG = [];
for (const id of ids) {
  const out = `thumbs/x/${id}.jpg`;
  if (fs.existsSync(out)) continue;
  try {
    const r = await fetch(`https://cdn.syndication.twimg.com/tweet-result?id=${id}&token=${token(id)}&lang=ko`, { headers: { "User-Agent": UA } });
    const j = await r.json();
    const v = j.video?.poster || j.mediaDetails?.[0]?.media_url_https || j.photos?.[0]?.url;
    LOG.push(`${id} status=${r.status} poster=${v || "-"} text=${(j.text || "").slice(0, 40)}`);
    if (!v) continue;
    const img = await fetch(v, { headers: { "User-Agent": UA } });
    if (!img.ok) { LOG.push(`${id} img ${img.status}`); continue; }
    fs.writeFileSync(out, Buffer.from(await img.arrayBuffer()));
    LOG.push(`saved ${out}`);
  } catch (e) { LOG.push(`${id} fail ${e.message}`); }
}
console.log(LOG.join("\n"));
if (process.env.XTEST) fs.writeFileSync("thumbs/x/_log.txt", LOG.join("\n"));
