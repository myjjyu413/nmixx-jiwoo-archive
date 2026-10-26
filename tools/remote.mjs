// 사이트에서 추가한 영상(Supabase) 주소를 remote.txt 로 받아 와요 → 썸네일 스크립트가 함께 읽어요
import fs from "fs";
const URL = "https://hzcsaitzhzmwlhtrcsad.supabase.co/rest/v1/rpc/vid_list";
const KEY = "sb_publishable_sMVbjoFS0VwINLiA0lH29A_i4wjCANG";
try {
  const r = await fetch(URL, { method: "POST", headers: { "Content-Type": "application/json", apikey: KEY, Authorization: "Bearer " + KEY }, body: "{}" });
  const j = await r.json();
  fs.writeFileSync("remote.txt", ((j && j.adds) || []).map(a => a.url).join("\n"));
  console.log("remote urls:", ((j && j.adds) || []).length);
} catch (e) { console.log("remote fail", e.message); fs.writeFileSync("remote.txt", ""); }
