#pragma once
// Single-file web page served by web_portal.h. No external resources: the
// device's LAN may have no Internet access.
#include <pgmspace.h>

static const char WEB_PAGE[] PROGMEM = R"HTML(<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Thiết bị báo ngã</title>
<style>
:root{--bg:#f3f4f6;--card:#fff;--text:#111827;--muted:#6b7280;--line:#e5e7eb;--accent:#2563eb;
--ok:#16a34a;--warn:#d97706;--bad:#dc2626;--chip:#f3f4f6}
@media (prefers-color-scheme:dark){:root{--bg:#0f1115;--card:#181b21;--text:#e5e7eb;--muted:#9ca3af;
--line:#2a2f38;--accent:#60a5fa;--ok:#22c55e;--warn:#f59e0b;--bad:#f87171;--chip:#222730}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif}
main{max-width:720px;margin:0 auto;padding:16px}
header{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:14px}
h1{font-size:19px;margin:0}
h2{font-size:15px;margin:0 0 12px}
.sub{color:var(--muted);font-size:13px}
.pill{display:inline-flex;align-items:center;gap:6px;padding:4px 10px;border-radius:999px;background:var(--card);
border:1px solid var(--line);font-size:13px;white-space:nowrap}
.dot{width:8px;height:8px;border-radius:50%;background:var(--muted)}
.on .dot{background:var(--ok)}.off .dot{background:var(--bad)}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px;margin-bottom:14px}
.alarm{display:none;background:var(--bad);color:#fff;border-radius:14px;padding:16px;margin-bottom:14px;
font-weight:700;font-size:17px;animation:blink 1s infinite}
.alarm small{display:block;font-weight:400;font-size:13px;opacity:.9}
.alarm.still{background:var(--warn);animation:none}
@keyframes blink{50%{opacity:.75}}
.hero{display:flex;align-items:center;gap:16px}
.icon{font-size:52px;line-height:1;width:72px;height:72px;display:grid;place-items:center;border-radius:18px;background:var(--chip)}
.state{font-size:26px;font-weight:700}
.bar{height:6px;background:var(--chip);border-radius:3px;margin-top:8px;overflow:hidden}
.bar i{display:block;height:100%;width:0;background:var(--accent);transition:width .4s}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}
.chips span{padding:5px 11px;border-radius:999px;background:var(--chip);color:var(--muted);font-size:13px}
.chips span.cur{background:var(--accent);color:#fff}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px}
.grid div{background:var(--chip);border-radius:10px;padding:10px}
.grid b{display:block;font-size:15px}
.good{color:var(--ok)}.warn{color:var(--warn)}.bad{color:var(--bad)}
ul{list-style:none;margin:0;padding:0}
li{display:flex;justify-content:space-between;padding:7px 0;border-bottom:1px solid var(--line)}
li:last-child{border:0}
.channel{border:1px solid var(--line);border-radius:12px;padding:12px;margin-bottom:12px}
.row{display:flex;justify-content:space-between;align-items:center;gap:10px}
.switch{position:relative;width:46px;height:26px;flex:none}
.switch input{opacity:0;width:0;height:0}
.switch span{position:absolute;inset:0;background:var(--line);border-radius:13px;transition:.2s;cursor:pointer}
.switch span:before{content:"";position:absolute;width:20px;height:20px;left:3px;top:3px;background:#fff;border-radius:50%;transition:.2s}
.switch input:checked+span{background:var(--ok)}
.switch input:checked+span:before{transform:translateX(20px)}
.switch input:disabled+span{opacity:.4;cursor:not-allowed}
label.f{display:block;font-size:13px;color:var(--muted);margin:10px 0 4px}
textarea{width:100%;min-height:60px;padding:8px 10px;border:1px solid var(--line);border-radius:8px;
background:var(--bg);color:var(--text);font:14px/1.4 ui-monospace,Consolas,monospace;resize:vertical}
textarea:disabled{opacity:.55}
input.num{width:120px;padding:8px 10px;border:1px solid var(--line);border-radius:8px;background:var(--bg);
color:var(--text);font:15px system-ui,sans-serif}
.btns{display:flex;gap:10px;flex-wrap:wrap}
button{border:0;border-radius:9px;padding:10px 16px;font:600 14px system-ui,sans-serif;cursor:pointer}
.primary{background:var(--accent);color:#fff}.secondary{background:var(--chip);color:var(--text)}
button:disabled{opacity:.5;cursor:wait}
#msg{margin-top:10px;font-size:14px;min-height:20px}
.note{font-size:12px;color:var(--warn);margin-top:6px}
.wlink{display:flex;justify-content:space-between;align-items:center;color:var(--text);text-decoration:none}
</style>
</head>
<body>
<main>
<header>
  <div><h1 id="dev">Thiết bị báo ngã</h1><div class="sub" id="ip"></div></div>
  <span class="pill off" id="sync"><span class="dot"></span><span id="syncText">Đang kết nối…</span></span>
</header>

<div class="alarm" id="alarm"></div>

<section class="card">
  <div class="hero">
    <div class="icon" id="icon">⏳</div>
    <div style="flex:1">
      <div class="sub">Trạng thái hiện tại</div>
      <div class="state" id="state">Đang chờ dữ liệu</div>
      <div class="bar"><i id="confBar"></i></div>
      <div class="sub" id="conf">Độ tin cậy —</div>
    </div>
  </div>
  <div class="chips" id="chips"></div>
</section>

<section class="card">
  <h2>Thiết bị</h2>
  <div class="grid">
    <div><span class="sub">Cảm biến</span><b id="imu">—</b></div>
    <div><span class="sub">Hiệu chỉnh</span><b id="cal">—</b></div>
    <div><span class="sub">Pin</span><b id="bat">—</b></div>
    <div><span class="sub">Wi-Fi</span><b id="wifi">—</b></div>
    <div><span class="sub">Thời gian chạy</span><b id="up">—</b></div>
    <div><span class="sub">Cloud</span><b id="cloud">—</b></div>
    <div><span class="sub">Không cử động</span><b id="still">—</b></div>
  </div>
</section>

<section class="card">
  <h2>Hoạt động gần đây</h2>
  <ul id="hist"><li class="sub">Chưa có thay đổi.</li></ul>
</section>

<section class="card">
  <h2>Thông báo cảnh báo</h2>
  <p class="sub" style="margin:-6px 0 12px">Gửi khi phát hiện ngã hoặc người đeo không cử động quá lâu. Nhiều địa chỉ thì cách nhau bằng dấu phẩy hoặc xuống dòng (tối đa <span id="max">5</span>).</p>
  <form id="form">
    <div class="channel">
      <div class="row"><b>Telegram</b>
        <label class="switch"><input type="checkbox" id="tgOn"><span></span></label></div>
      <label class="f" for="chatIds">Chat ID (người dùng, nhóm: số âm, kênh: @ten_kenh)</label>
      <textarea id="chatIds" placeholder="123456789, -1001234567890"></textarea>
      <div class="note" id="tgNote" hidden>Chưa có TELEGRAM_BOT_TOKEN trong secrets.h nên không bật được.</div>
    </div>
    <div class="channel">
      <div class="row"><b>Gmail</b>
        <label class="switch"><input type="checkbox" id="gmOn"><span></span></label></div>
      <label class="f" for="emailTo">Email người nhận</label>
      <textarea id="emailTo" placeholder="nguoithan@gmail.com"></textarea>
      <div class="note" id="gmNote" hidden>Chưa có GMAIL_ADDRESS / GMAIL_APP_PASSWORD trong secrets.h nên không bật được.</div>
    </div>
    <div class="channel">
      <div class="row"><b>Cảnh báo bất động</b></div>
      <label class="f" for="inactiveMin">Gửi cảnh báo khi người đeo không cử động quá (phút, 0 = tắt, tối đa <span id="maxMin">1440</span>)</label>
      <input class="num" type="number" id="inactiveMin" min="0" max="1440" step="1" inputmode="numeric">
      <div class="sub" style="margin-top:6px">Chạm vào thiết bị hoặc cử động sẽ tính lại từ đầu. Khi ngủ, nên đặt dài hơn thời gian nằm yên thường ngày.</div>
    </div>
    <div class="btns">
      <button class="primary" type="submit" id="save">Lưu cài đặt</button>
      <button class="secondary" type="button" id="test" title="Gửi theo cài đặt đã lưu">Gửi tin thử</button>
    </div>
    <div id="msg"></div>
  </form>
</section>

<a class="card wlink" href="/wifi"><span>📶 <b>Wi-Fi</b> <span class="sub">· chọn mạng, kết nối</span></span><span>›</span></a>
</main>

<script>
const A={di_bo:['🚶','Đi bộ'],dung:['🧍','Đứng'],ngoi:['🪑','Ngồi'],nam:['🛌','Nằm'],nga:['⚠️','Có dấu hiệu ngã']};
const $=id=>document.getElementById(id);
$('chips').innerHTML=Object.keys(A).map(k=>'<span data-k="'+k+'">'+A[k][0]+' '+A[k][1]+'</span>').join('');
let fails=0,pending='',pendingN=0,last='',hist=[];

function setText(id,t,cls){const e=$(id);e.textContent=t;e.className=cls||''}
function dur(s){const h=Math.floor(s/3600),m=Math.floor(s%3600/60);return h?h+' giờ '+m+' phút':m?m+' phút '+s%60+' giây':s+' giây'}
function clock(){return new Date().toLocaleTimeString('vi-VN')}

function online(ok){
  const p=$('sync');p.className='pill '+(ok?'on':'off');
  $('syncText').textContent=ok?'Đã đồng bộ · '+clock():'Mất kết nối thiết bị';
}

function track(k){
  if(k!==pending){pending=k;pendingN=0}
  if(++pendingN<2||k===last)return; // Ignore one-poll flickers between classes.
  last=k;hist.unshift([clock(),k]);hist=hist.slice(0,10);
  $('hist').innerHTML=hist.map(h=>'<li><span>'+(A[h[1]]||['',h[1]]).join(' ')+'</span><span class="sub">'+h[0]+'</span></li>').join('');
}

function show(s){
  document.title=s.device+' · '+(A[s.activity]?A[s.activity][1]:'Báo ngã');
  $('dev').textContent=s.device;
  $('ip').textContent=s.ip?'IP '+s.ip:'';
  const a=A[s.activity];
  if(!s.imu){$('icon').textContent='🔌';$('state').textContent='Cảm biến lỗi'}
  else if(!s.model){$('icon').textContent='❗';$('state').textContent='Mô hình lỗi'}
  else if(s.cal==='run'){$('icon').textContent='🎯';$('state').textContent='Đang hiệu chỉnh'}
  else if(!a){$('icon').textContent='⏳';$('state').textContent='Đang chờ dữ liệu'}
  else{$('icon').textContent=a[0];$('state').textContent=a[1];track(s.activity)}
  const c=a&&s.imu?Math.round(s.confidence*100):0;
  $('confBar').style.width=c+'%';
  $('conf').textContent=a&&s.imu?'Độ tin cậy '+c+'%':'Độ tin cậy —';
  document.querySelectorAll('#chips span').forEach(e=>e.className=e.dataset.k===s.activity&&s.imu?'cur':'');
  const al=$('alarm');
  if(s.alarm==='fall'){al.style.display='block';al.innerHTML='🚨 PHÁT HIỆN NGÃ<small>Còi đang kêu. Chạm vào thiết bị để tắt cảnh báo.</small>'}
  else if(s.inactive){al.style.display='block';al.innerHTML='⏸️ KHÔNG CỬ ĐỘNG '+dur(s.stillSec).toUpperCase()+'<small>Đã gửi cảnh báo bất động. Người đeo cử động hoặc chạm vào thiết bị là hết cảnh báo.</small>'}
  else al.style.display='none';
  al.className='alarm'+(s.alarm==='off'&&s.inactive?' still':'');
  setText('imu',s.imu?'Hoạt động':'Lỗi kết nối',s.imu?'good':'bad');
  setText('cal',s.cal==='ok'?'Đã hiệu chỉnh':s.cal==='run'?'Đang chạy…':'Chưa hiệu chỉnh',s.cal==='ok'?'good':'warn');
  if(s.batteryMv<2000)setText('bat','Cắm USB');
  else setText('bat',(s.batteryMv/1000).toFixed(2)+' V'+(s.batteryLow?' · yếu':''),s.batteryLow?'bad':'good');
  setText('wifi',s.rssi?s.rssi+' dBm':'—',s.rssi>-67?'good':s.rssi>-80?'warn':'bad');
  setText('up',dur(s.uptime));
  const cl={ok:['Đã đồng bộ','good'],wait:['Đang kết nối…','warn'],auth:['Sai tài khoản Firebase','bad'],off:['Chưa cấu hình','']}[s.cloud]||['—',''];
  setText('cloud',cl[0],cl[1]);
  setText('still',s.imu?dur(s.stillSec)+(set.inactiveMin>0?' / cảnh báo sau '+set.inactiveMin+' phút':''):'—',s.inactive?'bad':'');
}

async function poll(){
  try{
    const ctl=new AbortController(),t=setTimeout(()=>ctl.abort(),3000);
    const r=await fetch('/api/status',{cache:'no-store',signal:ctl.signal});
    clearTimeout(t);
    if(!r.ok)throw r.status;
    show(await r.json());fails=0;online(true);
  }catch(e){if(++fails>=3)online(false)}
  setTimeout(poll,1000);
}

function msg(t,ok){const m=$('msg');m.textContent=t;m.className=ok?'good':'bad'}
function sync(){
  $('tgOn').disabled=!st.telegramAvailable&&!st.telegramOn;
  $('gmOn').disabled=!st.gmailAvailable&&!st.gmailOn;
  $('tgNote').hidden=st.telegramAvailable;$('gmNote').hidden=st.gmailAvailable;
}
let st={},set={};
async function load(){
  try{
    const r=await fetch('/api/settings',{cache:'no-store'});st=await r.json();set=st;
    $('tgOn').checked=st.telegramOn;$('gmOn').checked=st.gmailOn;
    $('chatIds').value=st.chatIds;$('emailTo').value=st.emailTo;$('max').textContent=st.maxItems;
    $('inactiveMin').value=st.inactiveMin;$('inactiveMin').max=st.maxInactiveMin;$('maxMin').textContent=st.maxInactiveMin;sync();
  }catch(e){msg('Không tải được cài đặt, đang thử lại…');setTimeout(load,3000)}
}

async function post(url,body){
  const r=await fetch(url,{method:'POST',headers:{'X-Requested-With':'fetch'},body});
  let j={};try{j=await r.json()}catch(e){j={msg:'Lỗi '+r.status}}
  return [r.ok,j.msg||''];
}

$('form').onsubmit=async e=>{
  e.preventDefault();$('save').disabled=true;
  const b=new URLSearchParams({telegramOn:$('tgOn').checked?1:0,gmailOn:$('gmOn').checked?1:0,
    chatIds:$('chatIds').value,emailTo:$('emailTo').value,inactiveMin:$('inactiveMin').value.trim()});
  try{const [ok,t]=await post('/api/settings',b);msg(t,ok);if(ok)await load()}
  catch(err){msg('Không gửi được tới thiết bị.')}
  $('save').disabled=false;
};
$('test').onclick=async()=>{
  $('test').disabled=true;
  try{const [ok,t]=await post('/api/test',new URLSearchParams());msg(t,ok)}
  catch(err){msg('Không gửi được tới thiết bị.')}
  setTimeout(()=>$('test').disabled=false,3000);
};
load();poll();
</script>
</body>
</html>
)HTML";
