#!/usr/bin/env python3
"""Generate the FOURTH interactive HTML gallery of candidate WEAPON-FX for Not_This_Again.

Companion to tools/gen_weapon_fx_gallery.py, gen_weapon_fx_gallery2.py and
gen_weapon_fx_gallery3.py.

THE BRIEF — MARSHMALLOW-ONLY REROLL (ultrathink):
  The owner has REJECTED every prior marshmallow take. Marshmallow reads weak
  when the FX is just a soft puffy blob. It works when the softness is given
  AGENCY by a force (fire, expansion-pressure, compression-spring, stickiness)
  and when it leans into a MECHANIC unique to marshmallow, not just the look.

  Four fresh, visually-impressive, mechanically-DISTINCT marshmallow FX:
    1. Marshmallow Puff Mortar (HEAVY/LOB) — dense pellet lobs, lands, then
       EXPLOSIVELY balloons into a giant billowing cloud (~15-20x over ~0.4s)
       that smothers a zone; cloud surface toasts white -> golden -> char-brown
       at the edges (DoT feel). The microwave/campfire puff, weaponized.
    2. Gooey Snare (WHIP/BIND) — a molten stream whips out; on impact it leaves
       sagging STICKY STRANDS (catenary additive lines) that LINK 3-4 enemy
       anchor points, gum a cluster + slow-pulse. Multi-target webbing, distinct
       from the single-loop Caramel Lasso.
    3. S'mores Charge Cannon (CHARGE/HEAVY) — charge-and-release: STACK three
       layers (graham tan -> chocolate brown -> marshmallow white), then RELEASE
       a flaming s'more projectile that detonates into graham-shrapnel chips,
       chocolate splatter flecks, and a marshmallow goo burst.
    4. Peeps Swarm (SUMMON/SPREAD) — a volley of little marshmallow Peeps
       critters (chick/bunny silhouettes, pastel yellow/pink) hop/waddle forward
       as soft decoy minions, then POP one by one in sugar-crystal bursts.

  None recolor / duplicate the approved or rejected FX from galleries 1-3. All
  four are visually + mechanically distinct from each other.

MOBILE-SAFE (build note on every tile): in-engine these ship as additive
2D-canvas overlays (a la godot/scripts/frost_bolts.gd), CPUParticles3D (which
MUST carry a mesh), or additive sprites — NEVER custom spatial (3D) shaders,
which white-rect on our Android renderer. The canvas mockup is just the look
target.

Emits a self-contained HTML file (inline <style>+<script>) with one live
additive <canvas> animation per tile, a name, a weapon-TYPE tag, a one-line
mechanic description, and the mobile-safe build note. Reuses the exact shared
helpers (glow / bolt / mulberry) so the FROSTBITE technique is available to
every tile.

Usage:
    python3 tools/gen_weapon_fx_gallery4.py <out_dir> <out_filename>
e.g. python3 tools/gen_weapon_fx_gallery4.py \
        docs/superpowers/assets/weapon_fx_2026-06-06 weapon-fx-gallery-4.html
"""
import pathlib
import sys

# Each FX: (key, NAME, weapon-tag, mechanic, build-note, JS-step-body).
# Step-body conventions (identical to galleries 1-3):
#   ctx   -> CanvasRenderingContext2D (composite already set to 'lighter')
#   W, H  -> canvas size in CSS px
#   t     -> seconds since load (float, monotonic)
#   rnd(seed)                              -> deterministic pseudo-random [0,1)
#   glow(x,y,r,col,a)                      -> soft radial additive blob
#   bolt(ax,ay,bx,by,col,seed,life,power)  -> fractal 3-pass additive lightning
#   The page low-alpha dark-fills each tile BEFORE step (trails smear), then sets
#   composite to 'lighter'.

FX = [
    # ---- 1. Marshmallow Puff Mortar -------------------------------------
    ("puff_mortar", "Marshmallow Puff Mortar", "HEAVY",
     "A dense pellet lobs out, lands, and EXPLOSIVELY balloons ~18x into a billowing toasting cloud that smothers the zone.",
     "MARSHMALLOW: a tiny dense additive pellet on a lobbed arc -> on landing, CPUParticles3D cauliflower puff (offset white billboards scaling up fast) + an additive overlay that grades the cloud edge white->gold->char-brown for the DoT smother. No spatial shader.",
     r"""
        // A dense pellet arcs in, LANDS, then explosively balloons into a giant toasting puff cloud.
        var period=2.6, ph=(t % period)/period;
        var ox=16, oy=H-16, lx=W*0.52, ly=H*0.56;
        var flight=0.26;
        if(ph<flight){
          // small DENSE pellet on a lob arc (reads heavy, not puffy yet)
          var f=ph/flight;
          var x=ox+(lx-ox)*f, y=oy+(ly-oy)*f - Math.sin(f*3.14159)*H*0.46;
          for(var i=0;i<6;i++){ var ff=f-i*0.035; if(ff<0)break; var tx=ox+(lx-ox)*ff, ty=oy+(ly-oy)*ff-Math.sin(ff*3.14159)*H*0.46; glow(tx,ty, 3*(1-i/8)+1.5, '255,245,235', (1-i/6)*0.45); }
          glow(x,y, 7, '255,255,250', 0.95);
          glow(x,y, 3, '255,235,215', 1.0);
          ctx.fillStyle='rgba(255,255,255,0.9)'; ctx.beginPath(); ctx.arc(x,y,3.4,0,7); ctx.fill();
        } else {
          var e=(ph-flight)/(1-flight);
          // EXPLOSIVE balloon: cloud radius rockets up over the first ~0.4s, then slow settle.
          var grow = e<0.32 ? Math.pow(e/0.32,0.6) : 1;      // fast billow then hold
          var settle = e<0.82 ? 0 : (e-0.82)/0.18;           // gentle dissipate at the end
          var R = (W*0.40)*grow;                              // ~18x the pellet
          var fade = 1-settle*0.85;
          // landing shock flash
          if(e<0.12){ var c=1-e/0.12; glow(lx,ly, 26*c+6, '255,240,210', c*0.8); }
          // cauliflower lobes: several offset additive puffs, jiggling = boiling cloud surface
          var lobes=13;
          for(var k=0;k<lobes;k++){
            var ka=k/lobes*6.283 + k*0.7;
            var lr=R*(0.45+rnd(k*5)*0.55);
            var jig=0.06*Math.sin(t*5 + k*1.7);
            var px=lx+Math.cos(ka)*lr*(0.55+jig);
            var py=ly+Math.sin(ka)*lr*(0.42+jig) - R*0.12;   // bias upward (rising cloud)
            // toast grade: outer/older lobes brown, inner stays creamy white
            var edge=lr/R;
            var col = edge<0.55 ? '255,252,246' : edge<0.78 ? '240,205,140' : '150,95,55';
            var puffR = (R*0.34)*(0.7+rnd(k*3)*0.6)*grow;
            glow(px,py, puffR, col, (0.20+ (1-edge)*0.30)*fade);
          }
          // creamy hot core
          glow(lx,ly-R*0.1, R*0.5*grow, '255,253,248', (0.30)*fade);
          glow(lx,ly-R*0.1, R*0.22*grow, '255,255,255', (0.4)*fade);
          // toasting embers crawling the char edge (the DoT tell)
          for(var k=0;k<10;k++){
            var ea=k/10*6.283 + t*0.5;
            var er=R*(0.78+0.16*Math.sin(t*3+k));
            glow(lx+Math.cos(ea)*er, ly+Math.sin(ea)*er*0.7 - R*0.12, 3+rnd(k*9)*2, '255,150,70', (0.4+0.3*Math.sin(t*8+k))*fade);
          }
        }
     """),

    # ---- 2. Gooey Snare --------------------------------------------------
    ("gooey_snare", "Gooey Snare", "WHIP",
     "A molten stream whips out and on impact leaves sagging sticky strands that LINK 3-4 enemies together, gumming the cluster with a slow pulse.",
     "MARSHMALLOW: a thrown additive stream + per-link catenary strands as additive quadratic-curve polylines (frost_bolts-style multi-pass) with drip globs sliding down; CPUParticles3D goo flecks at each anchor. Multi-target bind, no spatial shader.",
     r"""
        // A molten stream whips out, then SAGGING sticky strands link several anchors + a bind pulse.
        var period=2.8, ph=(t % period)/period;
        var ox=14, oy=H*0.5;
        // anchor cluster (the snared enemies)
        var anchors=[ [W*0.58,H*0.30], [W*0.82,H*0.46], [W*0.66,H*0.74], [W*0.40,H*0.62] ];
        var shoot=0.22;
        if(ph<shoot){
          // molten stream whipping out toward the cluster
          var f=ph/shoot;
          var tx=ox+(anchors[0][0]-ox)*f, ty=oy+(anchors[0][1]-oy)*f;
          ctx.lineCap='round';
          ctx.strokeStyle='rgba(255,235,210,'+(0.5)+')'; ctx.lineWidth=6*(1-f)+2;
          ctx.beginPath(); ctx.moveTo(ox,oy); ctx.lineTo(tx,ty); ctx.stroke();
          ctx.strokeStyle='rgba(255,255,255,0.9)'; ctx.lineWidth=2;
          ctx.beginPath(); ctx.moveTo(Math.max(ox,tx-40),oy+(ty-oy)*0.85); ctx.lineTo(tx,ty); ctx.stroke();
          glow(tx,ty, 9, '255,250,240', 0.95);
          glow(ox,oy, 12, '255,225,190', 0.6);
        } else {
          var e=(ph-shoot)/(1-shoot);
          var snap=Math.min(1, e/0.18);                 // strands snap taut
          // sticky strands between consecutive anchors + back to muzzle (a web)
          var links=[ [ox,oy, anchors[0][0],anchors[0][1]],
                      [anchors[0][0],anchors[0][1], anchors[1][0],anchors[1][1]],
                      [anchors[1][0],anchors[1][1], anchors[2][0],anchors[2][1]],
                      [anchors[2][0],anchors[2][1], anchors[3][0],anchors[3][1]],
                      [anchors[3][0],anchors[3][1], anchors[0][0],anchors[0][1]] ];
          var pulse=0.5+0.5*Math.sin(t*4.5);            // slow bind pulse
          for(var li=0;li<links.length;li++){
            var L=links[li];
            var midx=(L[0]+L[2])*0.5, midy=(L[1]+L[3])*0.5;
            // catenary sag: more sag as it settles, gently swaying
            var sag=(18+8*Math.sin(t*1.3+li))*snap;
            var cpx=midx + Math.sin(t*1.1+li)*4, cpy=midy+sag;
            // multi-pass gooey glow strand (frost technique)
            for(var p=0;p<3;p++){
              var a=[0.12,0.34,0.8][p]*(0.6+pulse*0.4), wd=[9,5,2][p];
              ctx.strokeStyle=['rgba(255,210,160,'+a+')','rgba(255,235,200,'+a+')','rgba(255,252,245,'+a+')'][p];
              ctx.lineWidth=wd; ctx.lineCap='round'; ctx.beginPath();
              ctx.moveTo(L[0],L[1]); ctx.quadraticCurveTo(cpx,cpy, L[2],L[3]); ctx.stroke();
            }
            // a drip glob sliding down the strand belly
            var dp=((t*0.5 + li*0.3)%1);
            var dx=L[0]+(L[2]-L[0])*0.5, dy=cpy+ dp*14;
            glow(dx,dy, 4*(1-dp)+1.5, '255,240,215', (1-dp)*0.85);
          }
          // anchors gummed: pulsing sticky knots + goo flecks
          for(var ai=0;ai<anchors.length;ai++){
            var A=anchors[ai];
            glow(A[0],A[1], 8+pulse*6, '255,245,225', 0.4+pulse*0.4);
            glow(A[0],A[1], 4, '255,255,255', 0.8);
            for(var k=0;k<4;k++){ var ka=rnd(ai*7+k)*6.283; var d=6+rnd(ai*3+k)*7; glow(A[0]+Math.cos(ka)*d, A[1]+Math.sin(ka)*d, 2.2, '255,235,205', 0.5+pulse*0.3); }
          }
          glow(ox,oy, 10, '255,225,190', 0.5);
        }
     """),

    # ---- 3. S'mores Charge Cannon ---------------------------------------
    ("smores_charge", "S'mores Charge Cannon", "CHARGE",
     "Charge stacks three layers (graham -> chocolate -> marshmallow), then RELEASES a flaming s'more that detonates into tri-color shrapnel: graham chips, chocolate flecks, marshmallow goo.",
     "MARSHMALLOW: charge = three stacked additive sprites building at the muzzle; release = an additive streak projectile; detonation = three CPUParticles3D bursts (tan chips / brown flecks / white-gold goo) + a warm bloom. No spatial shader.",
     r"""
        // Charge STACKS graham/chocolate/marshmallow, RELEASES a flaming s'more, tri-color detonation.
        var period=3.0, ph=(t % period)/period;
        var ox=22, oy=H*0.5;
        var chargeEnd=0.45, flightEnd=0.62;
        if(ph<chargeEnd){
          // stacking build: three layers rise in sequence + a tightening shimmer
          var c=ph/chargeEnd;
          var layers=[ ['215,165,95', -7, 0.0],   // graham tan (bottom)
                       ['120,70,40',   0, 0.33],   // chocolate brown (middle)
                       ['255,252,246', 7, 0.66] ]; // marshmallow white (top)
          for(var i=0;i<layers.length;i++){
            var Ldef=layers[i]; var on=Math.min(1,Math.max(0,(c-Ldef[2])/0.33));
            var yy=oy+Ldef[1];
            // pancake disc for the layer
            glow(ox,yy, 12*on+2, Ldef[0], on*0.7);
            ctx.save(); ctx.translate(ox,yy); ctx.scale(1,0.4);
            ctx.fillStyle='rgba('+Ldef[0]+','+(on*0.55)+')'; ctx.beginPath(); ctx.arc(0,0,10*on+1,0,7); ctx.fill(); ctx.restore();
          }
          // charge shimmer ring tightening as it nears full
          var rr=20*(1-c)+5;
          for(var k=0;k<8;k++){ var ka=k/8*6.283 + t*4; glow(ox+Math.cos(ka)*rr, oy+Math.sin(ka)*rr*0.5, 2.5, '255,230,190', 0.3+c*0.5); }
          glow(ox,oy, 6+c*6, '255,245,220', 0.4+c*0.5);
        } else if(ph<flightEnd){
          // RELEASE: flaming s'more streaks out
          var f=(ph-chargeEnd)/(flightEnd-chargeEnd);
          var hx=ox + f*(W*0.5 - ox + W*0.1);
          for(var i=0;i<7;i++){ var ff=f-i*0.04; if(ff<0)break; var tx=ox+ff*(W*0.5-ox+W*0.1); glow(tx,oy, 6*(1-i/9)+2, i%2?'255,200,110':'255,250,235', (1-i/7)*0.6); }
          // a tumbling layered s'more (tan/brown/white stacked)
          ctx.save(); ctx.translate(hx,oy); ctx.rotate(f*9);
          var cols=['215,165,95','120,70,40','255,252,246'];
          for(var i=0;i<3;i++){ ctx.fillStyle='rgba('+cols[i]+',0.9)'; ctx.fillRect(-7,-6+i*4,14,3.4); }
          ctx.restore();
          glow(hx,oy, 12, '255,210,130', 0.85);
          glow(hx,oy, 5, '255,255,245', 1.0);
        } else {
          // DETONATION at the impact point — tri-color shrapnel
          var e=(ph-flightEnd)/(1-flightEnd);
          var dx=W*0.6, dy=oy, fade=1-e;
          // warm bloom
          glow(dx,dy, 44*Math.min(1,e*3)*(1-e)+6, '255,225,170', fade*0.8);
          glow(dx,dy, 18*Math.min(1,e*4)*(1-e)+4, '255,255,240', fade);
          // graham chips (tan) — chunky, fly far + fall
          for(var k=0;k<10;k++){ var ka=rnd(k)*6.283; var d=e*W*0.5*(0.6+rnd(k*3)*0.4); var px=dx+Math.cos(ka)*d, py=dy+Math.sin(ka)*d*0.7 - e*16 + e*e*36;
            ctx.save(); ctx.translate(px,py); ctx.rotate(rnd(k*5)*6.283 + e*6); ctx.fillStyle='rgba(215,165,95,'+(fade*0.95)+')'; ctx.fillRect(-3,-2.2,6,4.4); ctx.restore(); }
          // chocolate splatter flecks (brown) — small, scattered
          for(var k=0;k<14;k++){ var ka=rnd(k*7)*6.283; var d=e*W*0.42*(0.4+rnd(k*9)*0.6); glow(dx+Math.cos(ka)*d, dy+Math.sin(ka)*d*0.7 + e*e*22, 2.4, '120,70,40', fade*0.9); }
          // marshmallow goo burst (white/gold) — soft puffs
          for(var k=0;k<8;k++){ var ka=k/8*6.283 + 0.4; var d=e*W*0.34; glow(dx+Math.cos(ka)*d, dy+Math.sin(ka)*d*0.7, 9*fade+2, k%2?'255,250,235':'255,225,150', fade*0.6); }
        }
     """),

    # ---- 4. Peeps Swarm --------------------------------------------------
    ("peeps_swarm", "Peeps Swarm", "SUMMON",
     "A volley of pastel marshmallow Peeps critters hop forward as soft decoy minions, then POP one by one in little sugar-crystal bursts.",
     "MARSHMALLOW: each Peep is an additive sprite (chick/bunny silhouette) animated with a per-critter bouncy hop offset; the pop is a CPUParticles3D sugar-crystal sparkle burst. Crowd-y decoy summon, no spatial shader.",
     r"""
        // Pastel Peeps hop/waddle forward as decoys, then POP one by one in sugar-crystal sparkles.
        var ox=18;
        var N=5;
        var lifespan=2.4;
        for(var i=0;i<N;i++){
          // each critter on its own looping life cycle, staggered
          var phase=((t + i*0.5)% lifespan)/lifespan;
          var lane=H*0.30 + i*(H*0.40/(N-1));
          var travel=phase;
          var x=ox + travel*(W-44);
          // bouncy hop: stacked short arcs, squash at each landing
          var hopFreq=5.0, hp=(travel*hopFreq + i*0.3)%1;
          var hop=Math.abs(Math.sin(hp*3.14159));
          var y=lane - hop*12;
          var squash=hp>0.85||hp<0.12 ? 1 : 0;          // flat on contact
          var pastel = i%2 ? '255,210,120' : '255,170,200';  // peep yellow / pink
          var popStart=0.82;
          if(phase<popStart){
            var alive=1;
            // soft body glow
            glow(x,y, 11, pastel, 0.55);
            glow(x,y, 5, '255,255,250', 0.5);
            // chick/bunny silhouette: body + head + (ears or beak)
            ctx.save(); ctx.translate(x,y);
            var bw=8*(1+squash*0.35), bh=9*(1-squash*0.3);
            ctx.fillStyle='rgba('+pastel+',0.92)';
            ctx.beginPath(); ctx.ellipse(0,0,bw,bh,0,0,7); ctx.fill();             // body
            ctx.beginPath(); ctx.arc(0,-bh*0.9,bw*0.62,0,7); ctx.fill();           // head
            if(i%2){ // bunny ears
              ctx.beginPath(); ctx.ellipse(-2.5,-bh*1.7,2,5,-0.2,0,7); ctx.fill();
              ctx.beginPath(); ctx.ellipse(2.5,-bh*1.7,2,5,0.2,0,7); ctx.fill();
            } else { // chick beak
              ctx.fillStyle='rgba(255,150,60,0.95)';
              ctx.beginPath(); ctx.moveTo(bw*0.5,-bh*0.9); ctx.lineTo(bw*1.1,-bh*0.8); ctx.lineTo(bw*0.5,-bh*0.6); ctx.fill();
            }
            // sugar-sparkle dot eyes
            ctx.fillStyle='rgba(40,20,30,0.9)';
            ctx.beginPath(); ctx.arc(-2,-bh*0.95,1,0,7); ctx.arc(2,-bh*0.95,1,0,7); ctx.fill();
            ctx.restore();
          } else {
            // POP — sugar-crystal sparkle burst
            var pe=(phase-popStart)/(1-popStart);
            glow(x,y, 22*pe+4, '255,255,250', (1-pe)*0.8);
            glow(x,y, 10*(1-pe)+2, pastel, (1-pe)*0.9);
            for(var k=0;k<10;k++){
              var ka=k/10*6.283 + i; var d=pe*30;
              var sx=x+Math.cos(ka)*d, sy=y+Math.sin(ka)*d;
              glow(sx,sy, 2.6*(1-pe)+0.6, k%2?'255,255,255':pastel, (1-pe)*0.9);
              // crystalline 4-point spark on the brightest
              ctx.strokeStyle='rgba(255,255,255,'+((1-pe)*0.8)+')'; ctx.lineWidth=1;
              ctx.beginPath(); ctx.moveTo(sx-3,sy); ctx.lineTo(sx+3,sy); ctx.moveTo(sx,sy-3); ctx.lineTo(sx,sy+3); ctx.stroke();
            }
          }
        }
        // muzzle / spawn shimmer where the volley keeps emerging
        glow(ox,H*0.5, 14, '255,245,230', 0.4+0.2*Math.sin(t*6));
     """),
]

TAG_COLORS = {
    "HEAVY": "#ffd23f", "WHIP": "#ff9f5a", "CHARGE": "#ff7eb6",
    "SUMMON": "#7ed957",
}

TAG_LABELS = {
    "HEAVY": "HEAVY / LOB (puff mortar)",
    "WHIP": "WHIP / BIND (gooey snare)",
    "CHARGE": "CHARGE / HEAVY (s'mores cannon)",
    "SUMMON": "SUMMON / SPREAD (peeps swarm)",
}


def build_tiles_js() -> str:
    entries = []
    for key, name, tag, mech, note, body in FX:
        entries.append(
            "{key:%r, draw:function(ctx,W,H,t,rnd,glow,bolt){%s}}" % (key, body)
        )
    return "[\n" + ",\n".join(entries) + "\n]"


def build_cards_html() -> str:
    cards = []
    for key, name, tag, mech, note, _ in FX:
        col = TAG_COLORS.get(tag, "#7ed957")
        cards.append(f"""    <div class="card" style="border-color:{col}">
      <div class="tag" style="background:{col}">{tag}</div>
      <canvas id="fx_{key}" width="240" height="240"></canvas>
      <div class="cn">{name}</div>
      <div class="cm">{mech}</div>
      <div class="cd">{note}</div>
    </div>""")
    return "\n".join(cards)


def build_legend_html() -> str:
    spans = []
    for tag in ["HEAVY", "WHIP", "CHARGE", "SUMMON"]:
        col = TAG_COLORS[tag]
        spans.append(f'    <span style="background:{col}">{TAG_LABELS[tag]}</span>')
    return "\n".join(spans)


def build_html() -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Not_This_Again — Weapon-FX Gallery 4 (marshmallow reroll)</title>
<style>
  *{{box-sizing:border-box}}
  body{{margin:0;background:#070510;color:#e8def7;font-family:system-ui,-apple-system,sans-serif}}
  .wrap{{max-width:1180px;margin:0 auto;padding:26px 18px 60px}}
  h1{{font-size:24px;margin:0 0 6px;color:#ffd23f;letter-spacing:.3px}}
  .sub{{font-size:14px;line-height:1.6;color:#bda9e0;max-width:920px;margin:0 0 16px}}
  .sub b{{color:#ffd98a}}
  .reframe{{font-size:13px;line-height:1.65;color:#ffe7d6;max-width:920px;margin:0 0 18px;
        border-left:3px solid #c98b5a;padding:8px 0 8px 13px;background:#170f0a;border-radius:0 8px 8px 0}}
  .reframe b{{color:#ffd0a8}}
  .note{{font-size:12.5px;line-height:1.6;color:#9ad9b0;max-width:920px;margin:0 0 22px;
        border-left:3px solid #2f6b46;padding:6px 0 6px 12px;background:#0a160f}}
  .legend{{display:flex;gap:10px;flex-wrap:wrap;margin:0 0 22px;font-size:11px;font-weight:700}}
  .legend span{{padding:3px 10px;border-radius:7px;color:#0c0814}}
  .grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:18px}}
  .card{{position:relative;background:#100a1e;border:2px solid #3a2a4f;border-radius:14px;padding:10px;text-align:center;overflow:hidden}}
  .card canvas{{width:100%;height:auto;aspect-ratio:1/1;border-radius:9px;display:block;background:#040208}}
  .tag{{position:absolute;top:8px;left:8px;color:#0c0814;font-size:10px;font-weight:800;padding:2px 9px;border-radius:7px;z-index:2}}
  .cn{{font-size:15px;color:#ffe1a0;margin-top:9px;font-weight:600}}
  .cm{{font-size:11.5px;color:#e8d6ff;margin-top:5px;line-height:1.45;font-style:italic}}
  .cd{{font-size:11px;color:#9fbfa6;margin-top:5px;line-height:1.45;border-top:1px solid #221a33;padding-top:5px}}
  .foot{{margin-top:30px;font-size:12px;color:#8d7bb0;line-height:1.6;max-width:920px}}
</style>
</head>
<body>
<div class="wrap">
  <h1>Weapon-FX Gallery 4 — Marshmallow, rerolled (ultrathink)</h1>
  <p class="sub">Marshmallow only. Every prior marshmallow take was rejected for
  reading <b>weak</b>. These four are a fresh start — each leans into a
  <b>distinct mechanic</b>, not just the soft look.</p>
  <p class="reframe"><b>The reframe:</b> marshmallow reads weak when the FX is just a
  soft puffy blob. It works the moment that softness is given <b>AGENCY by a
  force</b> — fire, expansion-pressure, a compression-spring, or stickiness — and
  when it leans into a <b>mechanic unique to marshmallow</b>, not just the look.
  So: a puff that <b>detonates and smothers</b>, goo that <b>binds a cluster</b>, a
  s'more that <b>charges and shatters into layers</b>, and Peeps that <b>swarm as
  decoys then pop</b>.</p>
  <p class="note"><b>Mobile-safe (every tile):</b> in-engine these ship as additive
  2D-canvas overlays (&agrave; la <code>frost_bolts.gd</code>), <b>CPUParticles3D
  (which must carry a mesh)</b>, or additive sprites — <b>never custom spatial /
  3D shaders</b>, which white-rect on our Android renderer. The canvas mockups
  below are only the look target.</p>
  <div class="legend">
{build_legend_html()}
  </div>
  <div class="grid">
{build_cards_html()}
  </div>
  <p class="foot">Pure HTML5 &lt;canvas&gt; + JS with <code>globalCompositeOperation='lighter'</code>,
  soft radial-gradient glow sprites, multi-pass bloom, and motion trails — a direct preview
  of the additive in-engine look. Tell me which to build.</p>
</div>
<script>
"use strict";
// ---- shared additive helpers (same as galleries 1-3) ---------------------
function mulberry(seed){{ // tiny deterministic PRNG
  return function(){{ seed|=0; seed=seed+0x6D2B79F5|0; var t=Math.imul(seed^seed>>>15,1|seed);
    t=t+Math.imul(t^t>>>7,61|t)^t; return ((t^t>>>14)>>>0)/4294967296; }};
}}
function makeRnd(){{ // rnd(intSeed) -> [0,1)
  return function(s){{ var f=mulberry(s|0); return f(); }};
}}
// soft additive radial blob
function makeGlow(ctx){{
  return function(x,y,r,col,a){{
    if(r<=0)return;
    var g=ctx.createRadialGradient(x,y,0,x,y,r);
    g.addColorStop(0,'rgba('+col+','+a+')');
    g.addColorStop(0.45,'rgba('+col+','+(a*0.35)+')');
    g.addColorStop(1,'rgba('+col+',0)');
    ctx.fillStyle=g; ctx.beginPath(); ctx.arc(x,y,r,0,7); ctx.fill();
  }};
}}
// fractal midpoint-displacement bolt, 3 additive passes (a la frost_bolts.gd)
function makeBolt(ctx){{
  function subdiv(ax,ay,bx,by,depth,w,out,r){{
    if(depth===0){{ out.push([ax,ay,bx,by,w]); return; }}
    var mx=(ax+bx)*0.5+(r()-0.5)*depth*7;
    var my=(ay+by)*0.5+(r()-0.5)*depth*7;
    subdiv(ax,ay,mx,my,depth-1,w,out,r);
    subdiv(mx,my,bx,by,depth-1,w,out,r);
    if(depth>=2 && r()<0.35){{
      var brx=mx+(r()-0.5)*16, bry=my+(r()-0.5)*16;
      subdiv(mx,my,brx,bry,depth-2,w*0.5,out,r);
    }}
  }}
  return function(ax,ay,bx,by,col,seed,life,power){{
    var r=mulberry(seed|0); var segs=[]; subdiv(ax,ay,bx,by,4,1.0,segs,r);
    ctx.lineCap='round';
    for(var i=0;i<segs.length;i++){{var s=segs[i];
      ctx.strokeStyle='rgba('+col+','+(0.16*life*s[4])+')'; ctx.lineWidth=9*s[4]*(1+power*0.3);
      ctx.beginPath(); ctx.moveTo(s[0],s[1]); ctx.lineTo(s[2],s[3]); ctx.stroke();}}
    for(var i=0;i<segs.length;i++){{var s=segs[i];
      ctx.strokeStyle='rgba('+col+','+(0.4*life*s[4])+')'; ctx.lineWidth=4*s[4]*(1+power*0.2);
      ctx.beginPath(); ctx.moveTo(s[0],s[1]); ctx.lineTo(s[2],s[3]); ctx.stroke();}}
    for(var i=0;i<segs.length;i++){{var s=segs[i]; if(s[4]<0.6)continue;
      ctx.strokeStyle='rgba(255,255,255,'+(0.95*life*s[4])+')'; ctx.lineWidth=1.6*s[4];
      ctx.beginPath(); ctx.moveTo(s[0],s[1]); ctx.lineTo(s[2],s[3]); ctx.stroke();}}
  }};
}}
// ---- tiles ---------------------------------------------------------------
var TILES = {build_tiles_js()};
var T0 = performance.now();
var insts = [];
for (var i=0;i<TILES.length;i++){{
  var cv = document.getElementById('fx_'+TILES[i].key);
  if(!cv) continue;
  var ctx = cv.getContext('2d');
  insts.push({{
    cv:cv, ctx:ctx, draw:TILES[i].draw,
    rnd:makeRnd(), glow:makeGlow(ctx), bolt:makeBolt(ctx),
    W:cv.width, H:cv.height
  }});
}}
function frame(now){{
  var t = (now - T0)/1000;
  for (var i=0;i<insts.length;i++){{
    var o=insts[i], ctx=o.ctx;
    ctx.globalCompositeOperation='source-over';
    ctx.fillStyle='rgba(4,2,8,0.30)';
    ctx.fillRect(0,0,o.W,o.H);
    ctx.globalCompositeOperation='lighter';
    try {{ o.draw(ctx,o.W,o.H,t,o.rnd,o.glow,o.bolt); }} catch(e){{ /* keep loop alive */ }}
  }}
  requestAnimationFrame(frame);
}}
requestAnimationFrame(frame);
</script>
</body>
</html>
"""


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    out_dir = pathlib.Path(sys.argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / sys.argv[2]
    out.write_text(build_html(), encoding="utf-8")
    print(f"wrote {out} ({out.stat().st_size} bytes, {len(FX)} tiles)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
