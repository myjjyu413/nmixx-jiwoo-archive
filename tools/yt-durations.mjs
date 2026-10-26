// 숏폼 유튜브 영상 길이 확인 (수동 실행용)
import fs from "fs";
const w={};new Function("window",fs.readFileSync("videos.js","utf8"))(w);
const cat=process.env.CAT||"숏폼";
const list=w.VIDEOS.filter(v=>v.category===cat).map(v=>[(v.url.match(/(?:youtu\.be\/|v=|shorts\/)([\w-]{11})/)||[])[1],v.title]).filter(x=>x[0]);
const out=[];let i=0;
async function one([id,t]){for(let k=0;k<3;k++){try{const r=await fetch("https://www.youtube.com/watch?v="+id,{headers:{"accept-language":"ko-KR,ko;q=0.9","user-agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36","cookie":"CONSENT=YES+1"}});const h=await r.text();const m=h.match(/"lengthSeconds":"(\d+)"/);if(m)return out.push([id,+m[1],t]);}catch(e){}await new Promise(r=>setTimeout(r,1500));}out.push([id,-1,t]);}
await Promise.all(Array.from({length:6},async()=>{while(i<list.length)await one(list[i++]);}));
out.sort((a,b)=>b[1]-a[1]);
console.log("DUR_START");for(const x of out)console.log(JSON.stringify(x));console.log("DUR_END");
