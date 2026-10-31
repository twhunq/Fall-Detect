#pragma once
// Wi-Fi page (/wifi), served by web_portal.h: works like a phone's Wi-Fi
// screen. Networks are scanned when the page opens; tapping one asks for the
// password when needed and joins it; the result (connected / wrong password /
// not found) is shown. Also the landing page of the setup hotspot.
#include <pgmspace.h>

static const char WIFI_PAGE[] PROGMEM = R"HTML(<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Wi-Fi · Thiết bị báo ngã</title>
<style>
:root{--bg:#f2f2f7;--card:#fff;--text:#111827;--muted:#6b7280;--line:#e5e7eb;--accent:#2563eb;--ok:#16a34a;--bad:#dc2626}
@media (prefers-color-scheme:dark){:root{--bg:#000;--card:#1c1c1e;--text:#f3f4f6;--muted:#9ca3af;--line:#2c2c2e;--accent:#60a5fa;--ok:#22c55e;--bad:#f87171}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.4 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;-webkit-tap-highlight-color:transparent}
main{max-width:560px;margin:0 auto;padding:12px 16px 32px}
a{color:var(--accent);text-decoration:none}
h1{font-size:28px;margin:10px 4px 0}
.label{display:flex;justify-content:space-between;align-items:center;color:var(--muted);font-size:13px;text-transform:uppercase;letter-spacing:.3px;margin:22px 14px 6px}
.list{background:var(--card);border-radius:12px;overflow:hidden}
.item{display:flex;align-items:center;gap:10px;width:100%;min-height:50px;padding:10px 14px;border:0;border-bottom:1px solid var(--line);
background:none;color:inherit;font:inherit;text-align:left;cursor:pointer}
.item:last-child{border-bottom:0}
.check{width:18px;color:var(--accent);font-weight:700;flex:none}
.name{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.sub{font-size:13px;color:var(--muted)}
.icons{display:flex;gap:8px;align-items:center;color:var(--muted);flex:none}
.bars{display:inline-flex;align-items:flex-end;gap:2px;height:14px}
.bars i{width:3px;border-radius:1px;background:var(--line)}.bars i.on{background:var(--text)}
.empty{padding:14px;color:var(--muted)}
.note{font-size:13px;color:var(--muted);margin:10px 14px}
.banner{background:var(--card);border-radius:12px;padding:12px 14px;margin-top:14px;font-size:14px}
.spin{display:inline-block;width:16px;height:16px;border:2px solid var(--line);border-top-color:var(--accent);border-radius:50%;animation:r 1s linear infinite}
.spin.big{width:40px;height:40px;border-width:3px}
@keyframes r{to{transform:rotate(360deg)}}
.sheet{position:fixed;inset:0;z-index:5;display:flex;align-items:flex-end;justify-content:center;background:rgba(0,0,0,.45)}
.sheet[hidden]{display:none}
.panel{width:100%;max-width:560px;background:var(--card);border-radius:16px 16px 0 0;padding:20px 16px calc(20px + env(safe-area-inset-bottom))}
@media (min-width:600px){.sheet{align-items:center}.panel{border-radius:16px}}
.panel h2{font-size:18px;margin:0 0 6px;text-align:center;overflow-wrap:anywhere}
.panel p{margin:0 0 14px;text-align:center;color:var(--muted);font-size:14px;overflow-wrap:anywhere}
.panel input[type=text],.panel input[type=password]{width:100%;margin-top:8px;padding:12px;border:1px solid var(--line);border-radius:10px;background:var(--bg);color:var(--text);font:16px system-ui,sans-serif}
.chk{display:flex;align-items:center;gap:8px;margin-top:10px;font-size:14px;color:var(--muted)}
.row{display:flex;gap:10px;margin-top:16px}
.b{flex:1;border:0;border-radius:10px;padding:12px;font:600 16px system-ui,sans-serif;cursor:pointer}
.pri{background:var(--accent);color:#fff}.sec{background:var(--bg);color:var(--text)}
.b:disabled{opacity:.45}
.mini{flex:none;padding:6px 12px;font-size:14px}
.center{text-align:center}.big{font-size:44px;line-height:1.2}
.good{color:var(--ok)}.bad{color:var(--bad)}
</style>
</head>
<body>
<main>
<a href="/">‹ Trang chính</a>
<h1>Wi-Fi</h1>
<div class="banner" id="ap" hidden></div>
<div class="label"><span>Đang kết nối</span></div>
<div class="list" id="cur"><div class="empty">Đang tải…</div></div>
<div class="label"><span>Mạng khả dụng</span><span id="scanSt"></span></div>
<div class="list" id="nets"><div class="empty">Đang quét…</div></div>
<div class="label"><span>Mạng đã lưu</span></div>
<div class="list" id="saved"><div class="empty">—</div></div>
<p class="note">Thiết bị chỉ dùng được Wi-Fi 2,4 GHz. Mạng được lưu khi kết nối thành công (tối đa <span id="max">3</span>); khi mất mạng, thiết bị tự thử lại các mạng đã lưu.</p>
</main>
<div class="sheet" id="sheet" hidden><div class="panel" id="panel"></div></div>
<script>
const $=id=>document.getElementById(id);
const esc=t=>String(t).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const REASON={15:'Sai mật khẩu.',202:'Sai mật khẩu.',204:'Sai mật khẩu.',
  201:'Không tìm thấy mạng (ở ngoài vùng sóng hoặc là mạng 5 GHz).',0:'Mạng không phản hồi, hết thời gian chờ.'};
let W=null,scan=[],scanning=false,busy=false;

function bars(r){const n=r>-60?4:r>-70?3:r>-80?2:1;
  return '<span class="bars">'+[5,8,11,14].map((h,i)=>'<i style="height:'+h+'px"'+(i<n?' class="on"':'')+'></i>').join('')+'</span>'}
async function api(url){const r=await fetch(url,{cache:'no-store'});if(!r.ok)throw r.status;return r.json()}
async function post(body){
  const r=await fetch('/api/wifi',{method:'POST',headers:{'X-Requested-With':'fetch'},body:new URLSearchParams(body)});
  let j={};try{j=await r.json()}catch(e){}
  return [r.ok,j.msg||('Lỗi '+r.status)];
}

function render(){
  if(!W)return;
  $('max').textContent=W.max;
  $('ap').hidden=!W.ap;
  if(W.ap)$('ap').innerHTML='📡 Thiết bị đang phát Wi-Fi cài đặt <b>'+esc(W.apName)+'</b>'+(W.apLocked?' (mật khẩu = mật khẩu trang web)':'')+
    '. Chọn mạng nhà bạn bên dưới; khi đã vào mạng, điểm phát này sẽ tự tắt.';
  $('cur').innerHTML=W.connected
    ?'<div class="item"><span class="check">✓</span><span class="name">'+esc(W.connected)+'<div class="sub">IP '+esc(W.ip)+' · '+W.rssi+' dBm</div></span><span class="icons">'+bars(W.rssi)+'</span></div>'
    :'<div class="empty">Chưa kết nối mạng nào.</div>';
  const saved=new Set(W.networks.map(n=>n.ssid));
  const rows=scan.filter(n=>n.ssid!==W.connected).map(n=>'<button class="item" data-s="'+esc(n.ssid)+'" data-o="'+(n.open?1:0)+'">'+
    '<span class="check"></span><span class="name">'+esc(n.ssid)+(saved.has(n.ssid)?'<div class="sub">Đã lưu</div>':'')+'</span>'+
    '<span class="icons">'+(n.open?'':'🔒')+bars(n.rssi)+'</span></button>');
  if(!rows.length)rows.push('<div class="empty">'+(scanning?'Đang quét…':'Không thấy mạng nào.')+'</div>');
  rows.push('<button class="item" id="other"><span class="check"></span><span class="name">Mạng khác…</span></button>');
  $('nets').innerHTML=rows.join('');
  document.querySelectorAll('[data-s]').forEach(b=>b.onclick=()=>{
    const s=b.dataset.s;
    if(b.dataset.o==='1'||saved.has(s))connect(s,'');else askPass(s);
  });
  $('other').onclick=other;
  $('saved').innerHTML=W.networks.length?W.networks.map(n=>'<div class="item"><span class="check">'+(n.ssid===W.connected?'✓':'')+'</span>'+
    '<span class="name">'+esc(n.ssid)+'</span><button class="b sec mini" data-f="'+esc(n.ssid)+'">Quên</button></div>').join('')
    :'<div class="empty">Chưa lưu mạng nào.</div>';
  document.querySelectorAll('[data-f]').forEach(b=>b.onclick=async()=>{
    const s=b.dataset.f;
    if(!confirm('Quên mạng “'+s+'”?'+(s===W.connected?' Thiết bị sẽ ngắt khỏi mạng này ngay.':'')))return;
    try{await post({action:'forget',ssid:s})}catch(e){}
    load();
  });
}

async function load(){try{W=await api('/api/wifi');render()}catch(e){}}

async function doScan(){
  if(scanning||busy)return;
  scanning=true;$('scanSt').innerHTML='<span class="spin"></span>';
  let url='/api/wifi/scan?fresh=1';
  for(let i=0;i<15;i++){
    try{const j=await api(url);if(!j.scanning){if(!j.error)scan=j.list;break}}catch(e){break}
    url='/api/wifi/scan';await sleep(1000);
  }
  scanning=false;
  $('scanSt').innerHTML='<a href="#" id="rescan">Quét lại</a>';
  $('rescan').onclick=e=>{e.preventDefault();doScan()};
  render();
}

function sheet(html){$('panel').innerHTML=html;$('sheet').hidden=false}
function closeSheet(){$('sheet').hidden=true;busy=false}

function askPass(ssid){
  sheet('<h2>Nhập mật khẩu cho “'+esc(ssid)+'”</h2>'+
    '<input id="pw" type="password" placeholder="Mật khẩu" autocomplete="current-password" maxlength="64">'+
    '<label class="chk"><input type="checkbox" id="sh"> Hiện mật khẩu</label>'+
    '<div class="row"><button class="b sec" id="cx">Hủy</button><button class="b pri" id="go" disabled>Kết nối</button></div>');
  const pw=$('pw');
  pw.oninput=()=>{$('go').disabled=pw.value.length<8};
  pw.onkeydown=e=>{if(e.key==='Enter'&&!$('go').disabled)$('go').click()};
  $('sh').onchange=()=>{pw.type=$('sh').checked?'text':'password'};
  $('cx').onclick=closeSheet;
  $('go').onclick=()=>connect(ssid,pw.value);
  setTimeout(()=>pw.focus(),50);
}

function other(){
  sheet('<h2>Mạng khác</h2><p>Mạng ẩn hoặc không có trong danh sách</p>'+
    '<input id="ss" type="text" placeholder="Tên Wi-Fi" maxlength="32" autocapitalize="off" spellcheck="false">'+
    '<input id="pw" type="password" placeholder="Mật khẩu (để trống nếu mạng mở)" maxlength="64">'+
    '<div class="row"><button class="b sec" id="cx">Hủy</button><button class="b pri" id="go" disabled>Kết nối</button></div>');
  const ok=()=>{$('go').disabled=!$('ss').value.trim()||($('pw').value.length>0&&$('pw').value.length<8)};
  $('ss').oninput=ok;$('pw').oninput=ok;
  $('cx').onclick=closeSheet;
  $('go').onclick=()=>connect($('ss').value.trim(),$('pw').value);
  setTimeout(()=>$('ss').focus(),50);
}

function result(state,ssid,text){
  const icon=state===true?'<div class="big good">✓</div>':state===false?'<div class="big bad">✕</div>':'<div class="big">📶</div>';
  const title=state===true?'Đã kết nối':state===false?'Không kết nối được':'Thiết bị đang chuyển mạng';
  sheet('<div class="center">'+icon+'</div><h2>'+title+'</h2><p>'+esc(ssid)+'<br>'+text+'</p>'+
    '<div class="row"><button class="b pri" id="done">'+(state===false?'Thử lại':'Xong')+'</button></div>');
  $('done').onclick=()=>{closeSheet();if(state===false)askPass(ssid);else{load();doScan()}};
}

async function connect(ssid,pass){
  busy=true;
  sheet('<div class="center"><span class="spin big"></span></div><h2>Đang kết nối…</h2><p>'+esc(ssid)+'</p>');
  let ok,msg;
  try{[ok,msg]=await post({action:'connect',ssid,pass})}catch(e){ok=false;msg='Không gửi được tới thiết bị.'}
  if(!ok)return result(false,ssid,esc(msg));
  const host=W&&W.host?W.host:'baonga';
  for(let t0=Date.now(),lost=0;Date.now()-t0<35000;){
    await sleep(1500);
    try{
      W=await api('/api/wifi');lost=0;
      const a=W.attempt;
      if(a.ssid===ssid&&a.state==='ok')
        return result(true,ssid,'Mở trang thiết bị tại <b>http://'+esc(W.ip)+'/</b> hoặc http://'+esc(host)+'.local khi điện thoại cùng mạng này.');
      if(a.ssid===ssid&&a.state==='fail')return result(false,ssid,REASON[a.reason]||('Lỗi Wi-Fi '+a.reason+'.'));
    }catch(e){
      if(++lost>=4)return result(null,ssid,'Điện thoại đã mất liên lạc với thiết bị, thường là vì thiết bị vừa vào mạng mới. '+
        'Kết nối điện thoại vào “'+esc(ssid)+'” rồi mở http://'+esc(host)+'.local');
    }
  }
  result(false,ssid,'Hết thời gian chờ.');
}

load().then(doScan);
setInterval(()=>{if(!busy)load()},5000);
setInterval(()=>{if(!busy)doScan()},30000);
</script>
</body>
</html>
)HTML";
