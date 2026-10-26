// 유튜브 영상 썸네일을 작게 줄여서 thumbs/yt/<영상ID>.webp 로 저장해요 (GitHub Actions에서 실행)
// 사이트는 이 파일을 먼저 쓰고, 없으면 유튜브 썸네일을 그대로 불러와요.
import fs from "fs";
import sharp from "sharp";
const src = fs.readFileSync("videos.js", "utf8") + "\n" + (fs.existsSync("remote.txt") ? fs.readFileSync("remote.txt", "utf8") : "");
const ids = [...new Set([...src.matchAll(/(?:youtu\.be\/|youtube\.com\/(?:watch\?v=|shorts\/|embed\/|live\/))([\w-]{11})/g)].map(m => m[1]))];
fs.mkdirSync("thumbs/yt", { recursive: true });
const todo = ids.filter(id => !fs.existsSync(`thumbs/yt/${id}.webp`));
console.log("youtube ids:", ids.length, "new:", todo.length);
async function get(id) {
  for (const q of ["maxresdefault", "sddefault", "hqdefault", "mqdefault"]) {
    try {
      const r = await fetch(`https://i.ytimg.com/vi/${id}/${q}.jpg`);
      if (!r.ok) continue;
      const b = Buffer.from(await r.arrayBuffer());
      const m = await sharp(b).metadata();
      if (m.width <= 120) continue; // 없는 썸네일 자리 이미지
      return b;
    } catch (e) {}
  }
  return null;
}
let i = 0, saved = 0;
await Promise.all(Array.from({ length: 8 }, async () => {
  while (i < todo.length) {
    const id = todo[i++];
    const b = await get(id);
    if (!b) { console.log("no thumb", id); continue; }
    // 16:9 로 가운데를 잘라서(위아래 검은 띠 제거) 640x360 으로
    await sharp(b).resize(640, 360, { fit: "cover", position: "centre" }).webp({ quality: 72 }).toFile(`thumbs/yt/${id}.webp`);
    saved++;
  }
}));
console.log("saved", saved);
