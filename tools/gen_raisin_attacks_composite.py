#!/usr/bin/env python3
"""Composite preview: Raisin Kidd performing each special move with the manga FX
overlaid IN PLACE and ANCHORED TO HIS HANDS (charge at the palms -> orb + forward
cone for Grapes of Wrath; strike-lines from his hand to each tap, gumdrop burst on
the target in front of him for the finisher). Each move uses its OWN animation.
Transparent additive 2D-canvas over the looping video. Rye font.

NOTE: the base clips are STUDIO-BG (unmasked) previews. In-engine the boss ships as a
green-screen Veo clip chroma-keyed to transparent (the _make_video_billboard path).

Usage: python3 tools/gen_raisin_attacks_composite.py <out_path.html>
"""
import base64, pathlib, sys
OUT = pathlib.Path(sys.argv[1])
V = pathlib.Path("docs/superpowers/assets/raisin_kidd_2026-06-06")
GOW = base64.b64encode((V / "gow_masked.mp4").read_bytes()).decode()
FPS = base64.b64encode((V / "fps_masked.mp4").read_bytes()).decode()

HTML = r"""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Raisin Kidd — special moves (hand-anchored FX)</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Rye&display=swap" rel="stylesheet">
<style>
 body{margin:0;background:#0b0713;color:#e8def7;font-family:system-ui,sans-serif}
 .wrap{max-width:880px;margin:0 auto;padding:20px}
 h2{color:#ffd98a;margin:6px 0} .lead{color:#cbb6ea;font-size:14px;line-height:1.5;margin-bottom:14px}
 .grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}@media(max-width:680px){.grid{grid-template-columns:1fr}}
 .card{background:#140e22;border:2px solid #3a2a4f;border-radius:14px;padding:10px;text-align:center}
 .gow{border-color:#b06be8} .fin{border-color:#e84d86}
 .stage{position:relative;width:100%;aspect-ratio:9/16;border-radius:10px;overflow:hidden;background:#000}
 .stage video,.stage canvas{position:absolute;inset:0;width:100%;height:100%}
 .stage video{object-fit:cover} .stage canvas{pointer-events:none}
 .cn{font-size:16px;color:#ffd98a;margin-top:9px} .cd{font-size:12px;color:#cbb6ea;margin-top:3px;line-height:1.4} b{color:#ffd23f}
 .note{font-size:12px;color:#9c86c8;margin-top:10px;font-style:italic}
</style></head><body><div class="wrap">
<h2>Raisin Kidd — special moves, FX launching from his hands</h2>
<div class="lead">Each move now uses its OWN animation, and the focus-lines / orb / SFX originate at his <b>palms</b> and project forward — not centered on his body. Rye lettering. <i>Timing is a rough loop; in-engine the FX keys to the real animation + a hand bone.</i></div>
<div class="grid">
 <div class="card gow"><div class="stage"><video src="data:video/mp4;base64,__GOW_B64__" autoplay loop muted playsinline></video><canvas id="c_gow" width="360" height="640"></canvas></div>
  <div class="cn">The Grapes of Wrath</div><div class="cd">Charge at the palms → title slam → orb + forward cone + BA-DOON!</div></div>
 <div class="card fin"><div class="stage"><video src="data:video/mp4;base64,__FPS_B64__" autoplay loop muted playsinline></video><canvas id="c_fin" width="360" height="640"></canvas></div>
  <div class="cn">Five-Point Exploding Gumdrop <span style="color:#e84d86">(finisher)</span></div><div class="cd">Special-move card → strike-lines from his hand → gumdrop countdown + KA-BLOOM on the target</div></div>
</div>
<div class="note">MASKED + in-scene: his green-screen clip is chroma-keyed to transparent and composited over the Level-5 desert-temple backdrop — the real in-game look. The green-screen clips + backdrop are now game-ready assets.</div>
</div>
<script>
var RYE="'Rye', serif"; var PIP=['255,77,157','255,162,58','176,107,232','255,210,63','107,214,107'];
function rnd(s){ s=Math.sin(s*127.1)*43758.5453; return s-Math.floor(s); }
function lerp(a,b,t){return a+(b-a)*t;} function easeIn(t){return t*t;} function easeOut(t){return 1-(1-t)*(1-t);}
function focusAt(ctx,cx,cy,t,conv,maxR){ var N=40; ctx.save(); ctx.translate(cx,cy); ctx.rotate(t*0.05);
  for(var i=0;i<N;i++){ var a=i/N*6.283, inner=lerp(maxR,14,easeIn(conv))*(0.8+0.4*rnd(i)); ctx.lineWidth=rnd(i*3)>0.7?3.0:1.1; ctx.strokeStyle='rgba(255,200,245,'+(0.18+0.45*rnd(i*5))+')'; ctx.beginPath(); ctx.moveTo(Math.cos(a)*maxR,Math.sin(a)*maxR); ctx.lineTo(Math.cos(a)*inner,Math.sin(a)*inner); ctx.stroke(); } ctx.restore(); }
function cone(ctx,ox,oy,t,prog,dir,spread,L){ var R=L*easeOut(prog),N=26; ctx.save(); ctx.translate(ox,oy);
  for(var i=0;i<N;i++){ var a=dir+(rnd(i)*2-1)*spread, inner=8+rnd(i*2)*12; ctx.lineWidth=rnd(i*3)>0.6?3.2:1.2; ctx.strokeStyle='rgba(255,245,210,'+((1-prog)*0.9*(0.4+0.6*rnd(i*7)))+')'; var rr=R*(0.6+0.4*rnd(i*9)); ctx.beginPath(); ctx.moveTo(Math.cos(a)*inner,Math.sin(a)*inner); ctx.lineTo(Math.cos(a)*rr,Math.sin(a)*rr); ctx.stroke(); } ctx.restore(); }
function orb(ctx,x,y,r,c1,c2,a){ var g=ctx.createRadialGradient(x,y,0,x,y,r); g.addColorStop(0,'rgba('+c1+','+a+')'); g.addColorStop(0.5,'rgba('+c2+','+(0.7*a)+')'); g.addColorStop(1,'rgba('+c2+',0)'); ctx.fillStyle=g; ctx.beginPath(); ctx.arc(x,y,r,0,6.283); ctx.fill(); }
function starBurst(ctx,cx,cy,r,pts,rot,fill){ ctx.save(); ctx.translate(cx,cy); ctx.rotate(rot); ctx.beginPath();
  for(var i=0;i<pts*2;i++){ var rr=i%2?r*0.5:r, a=i/(pts*2)*6.283, x=Math.cos(a)*rr*(0.9+0.2*rnd(i)), y=Math.sin(a)*rr*(0.9+0.2*rnd(i)); if(i)ctx.lineTo(x,y); else ctx.moveTo(x,y); } ctx.closePath(); ctx.fillStyle=fill; ctx.fill(); ctx.restore(); }
function sfx(ctx,cx,cy,txt,scale,rot,fill,size){ ctx.save(); ctx.translate(cx,cy); ctx.rotate(rot); ctx.scale(scale,scale);
  ctx.font="900 "+size+"px "+RYE; ctx.textAlign='center'; ctx.textBaseline='middle'; ctx.lineJoin='round';
  ctx.lineWidth=10; ctx.strokeStyle='#1a0b22'; ctx.strokeText(txt,0,0); ctx.lineWidth=4; ctx.strokeStyle='#fff'; ctx.strokeText(txt,0,0); ctx.fillStyle=fill; ctx.fillText(txt,0,0); ctx.restore(); }
function titleCard(ctx,cx,cy,sc,shx,size){ ctx.save(); ctx.translate(cx+shx,cy); ctx.rotate(-0.04); ctx.scale(sc,sc); ctx.textAlign='center'; ctx.textBaseline='middle'; ctx.lineJoin='round';
  function L(txt,y,s,fill){ ctx.font="900 "+s+"px "+RYE; ctx.lineWidth=12; ctx.strokeStyle='#1a0b22'; ctx.strokeText(txt,0,y); ctx.lineWidth=4; ctx.strokeStyle='#fff'; ctx.strokeText(txt,0,y); ctx.fillStyle=fill; ctx.fillText(txt,0,y); }
  L('THE GRAPES',-size*0.62,size,'#c98ae8'); L('OF WRATH!',size*0.62,size*1.05,'#ff4d9d'); ctx.restore(); }
function moveCard(ctx,W,H,t,sc,shx,alpha){ ctx.save(); ctx.globalAlpha=alpha; ctx.translate(W/2+shx,H*0.3); ctx.rotate(-0.07); ctx.scale(sc,sc);
  starBurst(ctx,0,0,140,16,0.1,'rgba(255,225,77,0.22)'); starBurst(ctx,0,0,150,5,0.5,'rgba(255,77,157,0.16)'); ctx.textAlign='center'; ctx.textBaseline='middle'; ctx.lineJoin='round';
  function L(txt,y,s,fill){ ctx.font="900 "+s+"px "+RYE; ctx.lineWidth=13; ctx.strokeStyle='#1a0b22'; ctx.strokeText(txt,0,y); ctx.lineWidth=4.5; ctx.strokeStyle='#fff'; ctx.strokeText(txt,0,y); ctx.fillStyle=fill; ctx.fillText(txt,0,y); }
  L('FIVE-POINT RAISIN',-30,19,'#ffd23f'); L('EXPLODING',6,26,'#ff4d9d'); L('GUMDROP!',38,26,'#ff4d9d'); ctx.restore(); }
function gumdrop(ctx,x,y,r,col,lit){ ctx.save(); ctx.translate(x,y);
  if(lit>0.05){ orb(ctx,0,-r*0.2,r*2.0,col,col,0.55*lit); }
  var a=lit>0.05?1:0.3; ctx.beginPath(); ctx.moveTo(-r,r*0.7); ctx.quadraticCurveTo(-r,-r,0,-r); ctx.quadraticCurveTo(r,-r,r,r*0.7); ctx.closePath(); ctx.fillStyle='rgba('+col+','+a+')'; ctx.fill();
  ctx.beginPath(); ctx.ellipse(0,r*0.7,r,r*0.28,0,0,6.283); ctx.fill(); ctx.fillStyle='rgba(255,255,255,'+(0.5*a)+')'; ctx.beginPath(); ctx.ellipse(-r*0.3,-r*0.42,r*0.26,r*0.16,-0.4,0,6.283); ctx.fill(); ctx.restore(); }
function countdown(ctx,cx,cy,bt){ var lit=5-Math.floor(Math.max(0,bt-0.5)/0.5); if(lit<0)lit=0; if(lit>5)lit=5;
  for(var i=0;i<5;i++) gumdrop(ctx,cx+(i-2)*38,cy,14,PIP[i], i<lit?1:0);
  if(bt>0.5&&lit>0) sfx(ctx,cx,cy-50,String(lit),1+0.28*Math.sin(bt*14),0,'#fff',32); }
function bloom(ctx,W,H,cx,cy,ct){ if(ct<0.15){ ctx.fillStyle='rgba(255,255,255,'+(1-ct/0.15)*0.7+')'; ctx.fillRect(0,0,W,H); }
  for(var i=0;i<30;i++){ var a=i/30*6.283+rnd(i), d=easeOut(ct)*(W*0.55)*(0.4+0.6*rnd(i*3)); gumdrop(ctx,cx+Math.cos(a)*d, cy+Math.sin(a)*d-ct*16, 6+rnd(i*7)*5, PIP[i%5], 1-ct); }
  starBurst(ctx,cx,cy,90*easeOut(ct),12,0.1,'rgba(255,225,77,'+(1-ct)*0.7+')'); var sc=ct<0.25?easeOut(ct/0.25)*1.3:1.3-0.3*((ct-0.25)/0.75); sfx(ctx,cx,cy,'KA-BLOOM!',sc,-0.06,'#ff4d9d',36); }

function drawGOW(ctx,W,H,t){ ctx.clearRect(0,0,W,H); var P=4.2, lt=t%P, hx=W*0.5, hy=H*0.46, dir=1.5;
  if(lt<1.1){ var c=lt/1.1; focusAt(ctx,hx,hy,t,c,Math.max(W,H)*0.5); orb(ctx,hx,hy,30*c+6,'255,200,250','176,107,232',0.85*c); ctx.fillStyle='rgba(8,3,14,'+(0.26*c)+')'; ctx.fillRect(0,0,W,H); }
  if(lt>=1.1&&lt<2.5){ var r=(lt-1.1)/1.4; if(r<0.12){ ctx.fillStyle='rgba(255,255,255,'+(1-r/0.12)*0.5+')'; ctx.fillRect(0,0,W,H); }
    cone(ctx,hx,hy,t,r,dir,0.65,H*0.5); var ox=hx+Math.cos(dir)*easeOut(r)*H*0.42, oy=hy+Math.sin(dir)*easeOut(r)*H*0.42; orb(ctx,ox,oy,30*(1-r*0.3)+8,'255,210,250','255,77,157',1-r);
    if(r>0.15&&r<0.85){ var s=(r-0.15)/0.7, sc=s<0.3?easeOut(s/0.3)*1.2:1.2, al=s>0.7?1-(s-0.7)/0.3:1; ctx.globalAlpha=Math.max(0,al); sfx(ctx,ox,oy+34,'BA-DOON!',sc*0.85,-0.06,'#ff4d9d',24); ctx.globalAlpha=1; } }
  if(lt>=1.0&&lt<3.3){ var tl=lt-1.0, tsc=tl<0.28?2.0-1.0*easeOut(tl/0.28):1.0, sx=tl<0.4?(rnd(Math.floor(t*60))-0.5)*8*(1-tl/0.4):0, fd=tl>1.8?1-(tl-1.8)/0.4:1; ctx.globalAlpha=Math.max(0,fd); titleCard(ctx,W*0.5,H*0.16,tsc,sx,22); ctx.globalAlpha=1; } }
function drawFin(ctx,W,H,t){ ctx.clearRect(0,0,W,H); var P=6.4, lt=t%P, shx=W*0.57, shy=H*0.44, tx=W*0.5, ty=H*0.62;
  if(lt<1.6){ if(lt<0.6) focusAt(ctx,W*0.5,H*0.3,t,lt/0.6,Math.max(W,H)*0.55); var sc=lt<0.3?2.0-1.0*easeOut(lt/0.3):1.0, sx=lt<0.45?(rnd(Math.floor(t*60))-0.5)*10*(1-lt/0.45):0, fd=lt>1.2?1-(lt-1.2)/0.4:1; moveCard(ctx,W,H,t,sc,sx,Math.max(0,fd)); }
  if(lt>=1.6&&lt<2.9){ var st=lt-1.6; for(var k=0;k<5;k++){ var py=ty-34+k*17, px=tx+(k%2?10:-10), age=st-k*0.15; if(age>=0&&age<0.22){ var s=1-age/0.22;
    ctx.strokeStyle='rgba(255,235,180,'+s+')'; ctx.lineWidth=2.5; ctx.beginPath(); ctx.moveTo(shx,shy); ctx.lineTo(px,py); ctx.stroke();
    starBurst(ctx,px,py,22*(1-s)+6,8,rnd(k)*3,'rgba(255,240,180,'+s+')'); sfx(ctx,px,py,'BAP',0.45*(0.7+0.3*s),0,'#ffd23f',20); } } }
  if(lt>=2.9&&lt<5.1){ var bt=lt-2.9; countdown(ctx,tx,ty,bt); ctx.fillStyle='rgba(8,3,14,'+Math.min(0.42,Math.max(0,bt-0.5)/2.4*0.42)+')'; ctx.fillRect(0,0,W,H); }
  if(lt>=5.1&&lt<6.1) bloom(ctx,W,H,tx,ty,(lt-5.1)/1.0);
  if(lt>=5.6){ var dt=Math.min(1,(lt-5.6)/0.5); sfx(ctx,W*0.5,H*0.78,'DEFEATED',1,0,'rgba(200,130,245,'+dt+')',24); } }

var TILES=[['c_gow',drawGOW],['c_fin',drawFin]]; var _go=false;
function start(){ if(_go)return; _go=true; var C=TILES.map(function(x){ var c=document.getElementById(x[0]); return [c.getContext('2d'),c.width,c.height,x[1]]; }); var t0=performance.now();
  function frame(now){ var t=(now-t0)/1000; for(var i=0;i<C.length;i++){ var c=C[i]; c[3](c[0],c[1],c[2],t); } requestAnimationFrame(frame); } requestAnimationFrame(frame); }
if(document.fonts&&document.fonts.load){ document.fonts.load("900 40px 'Rye'").then(start).catch(start); setTimeout(start,1200); } else start();
</script></body></html>"""
HTML = HTML.replace("__GOW_B64__", GOW).replace("__FPS_B64__", FPS)
OUT.write_text(HTML)
print("wrote", OUT, "(%d KB)" % (len(HTML)//1024))
