#!/usr/bin/env python3
"""Manga FX v2 for Raisin Kidd: the Grapes-of-Wrath title/SFX shown in TWO fonts
(Rye = the game's Western display face; Permanent Marker = a free Ink-Free-style
hand-drawn face), PLUS the Five-Point Exploding Gumdrop finishing-move effect.
Self-contained HTML, additive/normal 2D-canvas (frost_bolts-style, mobile-safe).

Usage: python3 tools/gen_manga_fx_v2.py <out_path.html>
"""
import pathlib, sys
OUT = pathlib.Path(sys.argv[1])

HTML = r"""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Manga FX v2 — fonts + finisher</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Rye&family=Permanent+Marker&display=swap" rel="stylesheet">
<style>
 body{margin:0;background:#0b0713;color:#e8def7;font-family:system-ui,sans-serif}
 .wrap{max-width:1000px;margin:0 auto;padding:20px}
 h2{color:#ffd98a;margin:14px 0 4px} .lead{color:#cbb6ea;font-size:14px;line-height:1.5;margin-bottom:14px}
 .sec{border-top:2px solid #3a2a4f;margin-top:20px;padding-top:6px}
 .grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}
 .card{background:#140e22;border:2px solid #3a2a4f;border-radius:12px;padding:10px;text-align:center}
 .card.rye{border-color:#e8a23a} .card.hand{border-color:#4aa6e8} .card.full{grid-column:span 2;border-color:#e84d86}
 canvas{width:100%;border-radius:8px;display:block;background:#000}
 .cn{font-size:15px;color:#ffd98a;margin-top:8px} .cd{font-size:12px;color:#cbb6ea;margin-top:3px;line-height:1.4}
 b{color:#ffd23f}
</style></head><body><div class="wrap">
<h2>Grapes of Wrath — pick the lettering font</h2>
<div class="lead">Same FX, two faces. The speed-lines / burst-lines / slash-streaks are unchanged (font-independent) — this is just the <b>title card + onomatopoeia SFX</b> in <b>Rye</b> (orange — the game's Western display font) vs a <b>hand-drawn marker font</b> (blue — Permanent Marker, a free Ink-Free-style face). Tell me which, or mix (e.g. Rye title + hand-drawn SFX).</div>
<div class="grid">
 <div class="card rye"><canvas id="c_seq_rye" width="340" height="230"></canvas><div class="cn">Full sequence — Rye</div></div>
 <div class="card hand"><canvas id="c_seq_hand" width="340" height="230"></canvas><div class="cn">Full sequence — hand-drawn</div></div>
 <div class="card rye"><canvas id="c_sfx_rye" width="340" height="180"></canvas><div class="cn">SFX pops — Rye</div></div>
 <div class="card hand"><canvas id="c_sfx_hand" width="340" height="180"></canvas><div class="cn">SFX pops — hand-drawn</div></div>
</div>
<div class="sec">
<h2>Five-Point Raisin Exploding Gumdrop — the finishing move</h2>
<div class="lead">The lose-screen finisher: a rapid <b>five-point strike</b> → <b>five gumdrop pips count down</b> 5→1 → a comic candy <b>KA-BLOOM!</b> burst (no gore — bursts into candy) → <b>DEFEATED</b>. Family-friendly. (SFX shown in the hand-drawn font; final font follows your pick above.)</div>
<div class="grid">
 <div class="card full"><canvas id="c_fin" width="700" height="250"></canvas><div class="cn">FULL finisher sequence</div><div class="cd">strike → countdown → KA-BLOOM → DEFEATED</div></div>
 <div class="card"><canvas id="c_pips" width="340" height="180"></canvas><div class="cn">Gumdrop countdown (close-up)</div></div>
 <div class="card"><canvas id="c_pop" width="340" height="180"></canvas><div class="cn">The candy burst (close-up)</div></div>
</div></div>
</div>
<script>
var FONT_RYE="'Rye', serif", FONT_HAND="'Permanent Marker', cursive";
var WORDS=['DON!','ZUSH!','BA-DOON!','KRA-KOW!','FWASH!','POW!'];
var COLS=['#ff4d9d','#ffa23a','#b06be8','#ffd23f','#ff6b4d'];
var PIP=['255,77,157','255,162,58','176,107,232','255,210,63','107,214,107'];
function rnd(s){ s=Math.sin(s*127.1)*43758.5453; return s-Math.floor(s); }
function lerp(a,b,t){return a+(b-a)*t;} function easeIn(t){return t*t;} function easeOut(t){return 1-(1-t)*(1-t);}
function bg(ctx,W,H){ var g=ctx.createLinearGradient(0,0,0,H); g.addColorStop(0,'#2a1530'); g.addColorStop(1,'#140a1e'); ctx.fillStyle=g; ctx.fillRect(0,0,W,H); }
function focusLines(ctx,W,H,t,conv,col){ var cx=W/2,cy=H/2,R=Math.max(W,H)*0.78,N=46; ctx.save(); ctx.translate(cx,cy); ctx.rotate(t*0.05);
  for(var i=0;i<N;i++){ var a=i/N*6.283, inner=lerp(R*0.6,16,easeIn(conv))*(0.8+0.4*rnd(i)); ctx.lineWidth=rnd(i*3)>0.7?3.4:1.2; ctx.strokeStyle='rgba('+col+','+(0.22+0.5*rnd(i*5))+')'; ctx.beginPath(); ctx.moveTo(Math.cos(a)*R,Math.sin(a)*R); ctx.lineTo(Math.cos(a)*inner,Math.sin(a)*inner); ctx.stroke(); } ctx.restore();
  if(conv>0.8){ var f=(conv-0.8)/0.2, rg=ctx.createRadialGradient(cx,cy,0,cx,cy,60*f+8); rg.addColorStop(0,'rgba(255,255,255,'+(f*0.9)+')'); rg.addColorStop(1,'rgba(255,255,255,0)'); ctx.fillStyle=rg; ctx.fillRect(0,0,W,H); } }
function burstLines(ctx,W,H,t,prog,col){ var cx=W/2,cy=H/2,R=Math.max(W,H)*0.85*easeOut(prog),N=42; ctx.save(); ctx.translate(cx,cy); ctx.rotate(t*0.03);
  for(var i=0;i<N;i++){ var a=i/N*6.283+rnd(i)*0.05, inner=12+rnd(i*2)*18; ctx.lineWidth=rnd(i*3)>0.6?3.6:1.4; ctx.strokeStyle='rgba('+col+','+((1-prog)*0.9*(0.4+0.6*rnd(i*7)))+')'; var rr=R*(0.7+0.3*rnd(i*9)); ctx.beginPath(); ctx.moveTo(Math.cos(a)*inner,Math.sin(a)*inner); ctx.lineTo(Math.cos(a)*rr,Math.sin(a)*rr); ctx.stroke(); } ctx.restore(); }
function starBurst(ctx,cx,cy,r,pts,rot,fill){ ctx.save(); ctx.translate(cx,cy); ctx.rotate(rot); ctx.beginPath();
  for(var i=0;i<pts*2;i++){ var rr=i%2?r*0.5:r, a=i/(pts*2)*6.283, x=Math.cos(a)*rr*(0.9+0.2*rnd(i)), y=Math.sin(a)*rr*(0.9+0.2*rnd(i)); if(i)ctx.lineTo(x,y); else ctx.moveTo(x,y); } ctx.closePath(); ctx.fillStyle=fill; ctx.fill(); ctx.restore(); }
function sfx(ctx,cx,cy,txt,scale,rot,fill,size,font){ ctx.save(); ctx.translate(cx,cy); ctx.rotate(rot); ctx.scale(scale,scale);
  ctx.font="900 "+(size||40)+"px "+font; ctx.textAlign='center'; ctx.textBaseline='middle'; ctx.lineJoin='round';
  ctx.lineWidth=10; ctx.strokeStyle='#1a0b22'; ctx.strokeText(txt,0,0); ctx.lineWidth=4; ctx.strokeStyle='#fff'; ctx.strokeText(txt,0,0); ctx.fillStyle=fill; ctx.fillText(txt,0,0); ctx.restore(); }
function titleCard(ctx,cx,cy,sc,shx,font,size){ ctx.save(); ctx.translate(cx+shx,cy); ctx.rotate(-0.04); ctx.scale(sc,sc); ctx.textAlign='center'; ctx.textBaseline='middle'; ctx.lineJoin='round';
  function line(txt,y,s,fill){ ctx.font="900 "+s+"px "+font; ctx.lineWidth=12; ctx.strokeStyle='#1a0b22'; ctx.strokeText(txt,0,y); ctx.lineWidth=4; ctx.strokeStyle='#fff'; ctx.strokeText(txt,0,y); ctx.fillStyle=fill; ctx.fillText(txt,0,y); }
  line('THE GRAPES',-size*0.62,size,'#b06be8'); line('OF WRATH!',size*0.62,size*1.05,'#ff4d9d'); ctx.restore(); }
function halftone(ctx,W,H,alpha){ ctx.fillStyle='rgba(255,255,255,'+alpha+')'; for(var y=0;y<H;y+=11){ for(var x=0;x<W;x+=11){ var d=Math.hypot(x-W/2,y-H/2), r=Math.max(0,2.4-d/110); if(r>0.2){ ctx.beginPath(); ctx.arc(x,y,r,0,6.283); ctx.fill(); } } } }
function gumdrop(ctx,x,y,r,col,lit){ ctx.save(); ctx.translate(x,y);
  if(lit>0.05){ var g=ctx.createRadialGradient(0,-r*0.2,0,0,-r*0.2,r*2.0); g.addColorStop(0,'rgba('+col+','+(0.55*lit)+')'); g.addColorStop(1,'rgba('+col+',0)'); ctx.fillStyle=g; ctx.beginPath(); ctx.arc(0,-r*0.2,r*2.0,0,6.283); ctx.fill(); }
  var a=lit>0.05?1:0.26; ctx.beginPath(); ctx.moveTo(-r,r*0.7); ctx.quadraticCurveTo(-r,-r,0,-r); ctx.quadraticCurveTo(r,-r,r,r*0.7); ctx.closePath(); ctx.fillStyle='rgba('+col+','+a+')'; ctx.fill();
  ctx.beginPath(); ctx.ellipse(0,r*0.7,r,r*0.28,0,0,6.283); ctx.fill();
  ctx.fillStyle='rgba(255,255,255,'+(0.5*a)+')'; ctx.beginPath(); ctx.ellipse(-r*0.3,-r*0.42,r*0.26,r*0.16,-0.4,0,6.283); ctx.fill(); ctx.restore(); }

function makeSeq(font,tsize){ return function(ctx,W,H,t){ bg(ctx,W,H); var P=3.8, lt=t%P;
  if(lt<1.05) focusLines(ctx,W,H,t,lt/1.05,'255,250,228');
  if(lt>=1.45&&lt<2.2) burstLines(ctx,W,H,t,(lt-1.45)/0.75,'255,245,210');
  if(lt>=1.4&&lt<1.62){ ctx.fillStyle='rgba(255,255,255,'+(1-(lt-1.4)/0.22)*0.7+')'; ctx.fillRect(0,0,W,H); }
  if(lt>=1.05&&lt<3.4){ var tl=lt-1.05, sc=tl<0.28?2.2-1.2*easeOut(tl/0.28):1.0, shx=tl<0.4?(rnd(Math.floor(t*60))-0.5)*8*(1-tl/0.4):0, fade=tl>2.0?1-(tl-2.0)/0.35:1; ctx.globalAlpha=Math.max(0,fade); titleCard(ctx,W*0.5,H*0.42,sc,shx,font,tsize); ctx.globalAlpha=1; }
  if(lt>=1.5&&lt<2.25){ var s=(lt-1.5)/0.75, sc2=s<0.22?easeOut(s/0.22)*1.2:1.2-0.2*((s-0.22)/0.78), al=s>0.72?1-(s-0.72)/0.28:1; starBurst(ctx,W*0.66,H*0.78,52*sc2,11,0.2,'rgba(255,225,77,'+(al*0.85)+')'); sfx(ctx,W*0.66,H*0.78,'BA-DOON!',sc2*0.8,-0.07,'#ff4d9d',26,font); } }; }
function makeSfx(font){ return function(ctx,W,H,t){ bg(ctx,W,H); var span=0.8, idx=Math.floor(t/span)%WORDS.length, lt=(t%span)/span;
  var sc=lt<0.22?easeOut(lt/0.22)*1.16:1.16-0.14*easeIn((lt-0.22)/0.78), al=lt>0.78?1-(lt-0.78)/0.22:1, rot=(rnd(idx*3)-0.5)*0.5, shx=lt<0.3?(rnd(Math.floor(t*60))-0.5)*7:0;
  starBurst(ctx,W/2,H/2,72*sc,11,rot*0.5,'rgba(255,225,77,'+(al*0.85)+')'); ctx.globalAlpha=al*0.45; halftone(ctx,W,H,0.5); ctx.globalAlpha=1; sfx(ctx,W/2+shx,H/2,WORDS[idx],sc,rot,COLS[idx%COLS.length],40,font); }; }

function finStrike(ctx,W,H,t,cx,cy,lt){ for(var k=0;k<5;k++){ var px=cx+(k-2)*40, py=cy-46+rnd(k)*34, age=lt-k*0.16; if(age>=0&&age<0.2){ var s=1-age/0.2; starBurst(ctx,px,py,26*(1-s)+7,8,rnd(k)*3,'rgba(255,240,180,'+s+')'); sfx(ctx,px,py,'BAP',0.5*(0.7+0.3*s),0,'#ffd23f',22,FONT_HAND); } } if(rnd(Math.floor(t*30))>0.5) focusLines(ctx,W,H,t,0.45,'255,250,228'); }
function finCountdown(ctx,W,H,cx,cy,bt,gap){ var lit=5-Math.floor(Math.max(0,bt-0.5)/gap); if(lit<0)lit=0; if(lit>5)lit=5;
  for(var i=0;i<5;i++){ gumdrop(ctx,cx+(i-2)*44,cy,16,PIP[i], i<lit?1:0); }
  if(bt>0.5&&lit>0){ var pul=1+0.28*Math.sin(bt*14); sfx(ctx,cx,cy-58,String(lit),pul,0,'#fff',36,FONT_HAND); } return lit; }
function finBurst(ctx,W,H,cx,cy,ct){ if(ct<0.15){ ctx.fillStyle='rgba(255,255,255,'+(1-ct/0.15)*0.9+')'; ctx.fillRect(0,0,W,H); }
  for(var i=0;i<30;i++){ var a=i/30*6.283+rnd(i), d=easeOut(ct)*(W*0.45)*(0.4+0.6*rnd(i*3)); gumdrop(ctx,cx+Math.cos(a)*d, cy+Math.sin(a)*d-ct*18, 6+rnd(i*7)*5, PIP[i%5], 1-ct); }
  starBurst(ctx,cx,cy,80*easeOut(ct),12,0.1,'rgba(255,225,77,'+(1-ct)*0.7+')'); var sc=ct<0.25?easeOut(ct/0.25)*1.25:1.25-0.3*((ct-0.25)/0.75); sfx(ctx,cx,cy,'KA-BLOOM!',sc,-0.06,'#ff4d9d',40,FONT_HAND); }
function drawFin(ctx,W,H,t){ bg(ctx,W,H); var P=5.4, lt=t%P, cx=W/2, cy=H*0.5;
  if(lt<1.0) finStrike(ctx,W,H,t,cx,cy,lt);
  if(lt>=1.0&&lt<3.9){ var bt=lt-1.0; var dk=Math.min(0.45,Math.max(0,bt-0.5)/2.8*0.45); finCountdown(ctx,W,H,cx,cy,bt,0.5); ctx.fillStyle='rgba(0,0,0,'+dk+')'; ctx.fillRect(0,0,W,H); }
  if(lt>=3.9&&lt<4.9) finBurst(ctx,W,H,cx,cy,(lt-3.9)/1.0);
  if(lt>=4.5){ var dt=Math.min(1,(lt-4.5)/0.5); sfx(ctx,cx,cy+58,'DEFEATED',1,0,'rgba(190,120,240,'+dt+')',26,FONT_RYE); } }
function drawPips(ctx,W,H,t){ bg(ctx,W,H); var P=3.2, lt=t%P; finCountdown(ctx,W,H,W/2,H*0.55,lt,0.5); }
function drawPop(ctx,W,H,t){ bg(ctx,W,H); var P=1.8, lt=(t%P)/1.0; if(lt<=1) finBurst(ctx,W,H,W/2,H*0.5,lt); }

var TILES=[['c_seq_rye',makeSeq(FONT_RYE,22)],['c_seq_hand',makeSeq(FONT_HAND,24)],['c_sfx_rye',makeSfx(FONT_RYE)],['c_sfx_hand',makeSfx(FONT_HAND)],['c_fin',drawFin],['c_pips',drawPips],['c_pop',drawPop]];
var _started=false;
function start(){ if(_started)return; _started=true; var C=TILES.map(function(x){ var c=document.getElementById(x[0]); return [c.getContext('2d'),c.width,c.height,x[1]]; }); var t0=performance.now();
  function frame(now){ var t=(now-t0)/1000; for(var i=0;i<C.length;i++){ var c=C[i]; c[3](c[0],c[1],c[2],t); } requestAnimationFrame(frame); } requestAnimationFrame(frame); }
if(document.fonts&&document.fonts.load){ Promise.all([document.fonts.load("900 40px 'Rye'"),document.fonts.load("900 40px 'Permanent Marker'")]).then(start).catch(start); setTimeout(start,1200); } else { start(); }
</script></body></html>"""
OUT.write_text(HTML)
print("wrote", OUT, "(%d KB)" % (len(HTML)//1024))
