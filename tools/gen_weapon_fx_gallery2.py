#!/usr/bin/env python3
"""Generate the SECOND interactive HTML gallery of candidate WEAPON-FX for Not_This_Again.

Companion to tools/gen_weapon_fx_gallery.py. The owner APPROVED 5 effects from the
first gallery (Gumdrop Buckshot Scatter, Homing Sparkle Swarm, Rainbow Comet Trail,
Gumball Gatling Bloom, Confetti Cannon) and REJECTED 8 (Candy Plasma Beam, Licorice
Arc Chain, Peppermint Nova, Peppermint Vortex, Caramel Napalm, Sugar-Crystal Shatter
Beam, Jawbreaker Mortar Arc, Prism Refraction Fan). They want REROLLS + MORE options
because the debug screen has a broad weapon roster that all needs new fire FX.

Game weapon roster this batch is designed to cover (from level_3d.gd / debug_menu.gd):
  FireModes:  CANDY (jelly-bean six-shooter), RIFLE, FROSTBITE (shipped), FRENZY, RAINBOW
  Bonus guns: Marshmallow Cannon (heavy), Liquorice Whip (whip), Frostbite Rifle
              (precision), Sugar Mortar (arc), Gumdrop Grenade (lob), Peppermint
              Shotgun (spread), Caramel Lasso (lasso).

Every option below is a GENUINELY NEW idea (not a recolor of an approved/rejected
effect) and is mobile-safe: shippable with ONLY additive 2D-canvas overlays (a la
godot/scripts/frost_bolts.gd), CPUParticles3D, and additive sprites. NO custom
spatial (3D) shaders — those white-rect on our Android renderer.

This emits a self-contained HTML file (inline <style>+<script>) with one live
additive <canvas> animation per tile, a name, a weapon-TYPE tag, and a one-line
in-engine build note. Reuses the exact shared helpers (glow / bolt / mulberry) from
the first generator so the FROSTBITE technique is available to every tile.

Usage:
    python3 tools/gen_weapon_fx_gallery2.py <out_dir> <out_filename>
e.g. python3 tools/gen_weapon_fx_gallery2.py \
        docs/superpowers/assets/weapon_fx_2026-06-06 weapon-fx-gallery-2.html
"""
import pathlib
import sys

# Each FX: (key, NAME, weapon-tag, build-note, JS-step-body).
# Step-body conventions (identical to gallery 1):
#   ctx   -> CanvasRenderingContext2D (composite already set to 'lighter')
#   W, H  -> canvas size in CSS px
#   t     -> seconds since load (float, monotonic)
#   rnd(seed)                              -> deterministic pseudo-random [0,1)
#   glow(x,y,r,col,a)                      -> soft radial additive blob
#   bolt(ax,ay,bx,by,col,seed,life,power)  -> fractal 3-pass additive lightning
#   The page low-alpha dark-fills each tile BEFORE step (trails smear), then sets
#   composite to 'lighter'.

FX = [
    ("whip_lash", "Candy Whip-Crack Lash", "WHIP",
     "Additive 2D-canvas polyline (frost_bolts-style multi-pass glow) snapped along a swung arc each fire + a bright sonic-crack flash sprite at the tip.",
     r"""
        // A licorice whip swings down and CRACKS — the lash sharpens to a tip flash.
        var period=1.0, ph=(t % period)/period;
        var ox=14, oy=H*0.22;
        var swing = -0.4 + ph*2.2;                 // angle sweeps through
        var tipx = ox + Math.cos(swing)*(W*0.82);
        var tipy = oy + Math.sin(swing)*(H*0.7) + 10;
        // the lash: a curving polyline from grip to tip, whip-thin near the tip
        ctx.lineCap='round';
        for (var p=0;p<3;p++){
          var a=[0.14,0.42,0.9][p], wd=[12,6,2.2][p];
          ctx.strokeStyle=['rgba(255,90,160,'+a+')','rgba(255,150,200,'+a+')','rgba(255,240,250,'+a+')'][p];
          ctx.beginPath();
          for (var s=0;s<=24;s++){
            var f=s/24;
            var ang=swing - (1-f)*0.9*(0.4+0.6*Math.sin(ph*3.14));   // tail lags
            var r=f*Math.sqrt((tipx-ox)*(tipx-ox)+(tipy-oy)*(tipy-oy));
            var x=ox+Math.cos(ang)*r, y=oy+Math.sin(ang)*r;
            ctx.lineWidth=wd*(1-f*0.7);            // taper to tip
            if(s===0)ctx.moveTo(x,y); else ctx.lineTo(x,y);
          }
          ctx.stroke();
        }
        // CRACK: supersonic flash at the tip near the end of the swing
        if (ph>0.7){
          var c=(ph-0.7)/0.3;
          glow(tipx,tipy, 26*(1-c)+6, '255,255,255', (1-c)*0.95);
          glow(tipx,tipy, 50*(1-c)+10, '255,120,180', (1-c)*0.6);
          for(var k=0;k<8;k++){ var ka=k/8*6.283; var d=(1-c)*30; glow(tipx+Math.cos(ka)*d, tipy+Math.sin(ka)*d, 4, '255,220,240', (1-c)*0.8); }
        }
        glow(ox,oy, 10, '255,120,180', 0.5);
     """),

    ("shockring", "Sucker-Punch Shock-Ring", "HEAVY",
     "Single additive expanding-disc sprite (scaled radial gradient) + a thin leading ring sprite; CPUParticles3D dust ring at ground contact. One sprite per shot.",
     r"""
        // A flat ground-hugging shock disc that punches outward then snaps gone.
        var period=1.1, ph=(t % period)/period;
        var cx=W*0.5, cy=H*0.62;
        var R=ph*W*0.55;
        // filled additive disc (soft), strongest at the leading edge
        var g=ctx.createRadialGradient(cx,cy,R*0.55,cx,cy,R);
        g.addColorStop(0,'rgba(255,180,80,0)');
        g.addColorStop(0.8,'rgba(255,180,80,'+(1-ph)*0.22+')');
        g.addColorStop(1,'rgba(255,240,180,'+(1-ph)*0.5+')');
        ctx.fillStyle=g; ctx.beginPath(); ctx.ellipse(cx,cy,R,R*0.42,0,0,7); ctx.fill();
        // crisp leading rim
        ctx.lineWidth=4*(1-ph)+1; ctx.strokeStyle='rgba(255,255,230,'+(1-ph)*0.85+')';
        ctx.beginPath(); ctx.ellipse(cx,cy,R,R*0.42,0,0,7); ctx.stroke();
        // launch flash
        glow(cx,cy, 30*(1-ph)+8, '255,220,150', (1-ph)*0.8);
        // kicked-up flecks
        for(var k=0;k<14;k++){ var ka=rnd(k)*6.283; var d=R*(0.7+rnd(k*3)*0.3); glow(cx+Math.cos(ka)*d, cy+Math.sin(ka)*d*0.42 - ph*12, 3, '255,210,140', (1-ph)*0.7); }
     """),

    ("cannonball", "Jawbreaker Cannonball", "HEAVY",
     "CPUParticles3D smoke-trail emitter parented to a heavy billboard ball + an additive muzzle-blast sprite at fire and an impact-bloom sprite on hit.",
     r"""
        // A heavy jawbreaker rolls across leaving a smoky additive trail; muzzle blasts.
        var period=1.3, ph=(t % period)/period;
        var ox=18, oy=H*0.5;
        var x=ox + ph*(W-36);
        var y=oy + Math.sin(ph*3.14)*-6;
        // muzzle blast at launch
        if(ph<0.12){ var c=ph/0.12; glow(ox,oy, 30*(1-c)+8,'255,160,40',(1-c)*0.8); glow(ox,oy,14*(1-c)+5,'255,240,180',(1-c)); }
        // smoke trail (warm, fading puffs)
        for(var i=0;i<12;i++){
          var ff=ph-i*0.03; if(ff<0)break;
          var tx=ox+ff*(W-36), ty=oy+Math.sin(ff*3.14)*-6 + Math.sin(i*1.7+t*3)*3;
          glow(tx,ty, 9*(1-i/14)+4, '255,150,90', (1-i/12)*0.35);
        }
        // the ball: dense core + glossy highlight
        glow(x,y, 13, '120,90,180', 0.7);
        glow(x,y, 9, '210,120,255', 0.8);
        glow(x-3,y-3, 3, '255,255,255', 0.9);
        // impact bloom at the far wall
        if(ph>0.9){ var e=(ph-0.9)/0.1; glow(W-18,oy, 40*e+6,'255,180,80',(1-e)*0.9); glow(W-18,oy,18*e+4,'255,255,220',(1-e)); }
     """),

    ("taffy_tether", "Taffy-Stretch Tether", "PRECISION",
     "Two additive sprites (anchor + hooked target) joined by a stretched additive quad whose alpha pulses; thickness shrinks as it stretches. No shader.",
     r"""
        // A sticky taffy strand fires out, hooks a point, and stretches taut + thin.
        var period=1.4, ph=(t % period)/period;
        var ox=16, oy=H*0.5;
        var reach = Math.min(1, ph/0.45);          // shoots out, then holds + stretches
        var tx=ox + reach*(W-34);
        var ty=oy + Math.sin(t*2.0)*22*(reach);
        var stretch = ph>0.45 ? (ph-0.45)/0.55 : 0;
        // sag while loose, taut while pulled
        var sag = (1-stretch)*40;
        ctx.lineCap='round';
        for(var p=0;p<3;p++){
          var a=[0.16,0.45,0.85][p], wd=[14,7,2.4][p]*(1-stretch*0.55);
          ctx.strokeStyle=['rgba(255,170,90,'+a+')','rgba(255,210,140,'+a+')','rgba(255,250,230,'+a+')'][p];
          ctx.lineWidth=wd; ctx.beginPath();
          for(var s=0;s<=20;s++){ var f=s/20; var x=ox+(tx-ox)*f; var y=oy+(ty-oy)*f + Math.sin(f*3.14)*sag; if(s===0)ctx.moveTo(x,y); else ctx.lineTo(x,y); }
          ctx.stroke();
        }
        glow(ox,oy, 11, '255,190,110', 0.6);
        glow(tx,ty, 12+stretch*6, '255,230,160', 0.7+stretch*0.2);
        glow(tx,ty, 5, '255,255,255', 0.9);
     """),

    ("drill", "Peppermint Drill Lance", "PRECISION",
     "An additive striped-cone sprite that spins (rotation animates UV illusion via 2 counter-rotating sprites) + CPUParticles3D shaving spray at the tip.",
     r"""
        // A spinning candy-cane drill bores forward; spiral stripes + tip shavings.
        var ox=14, oy=H*0.5, len=W*0.7;
        var tipx=ox+len + Math.sin(t*22)*3;
        // cone body — two layered envelopes
        ctx.fillStyle='rgba(255,80,110,0.18)';
        ctx.beginPath(); ctx.moveTo(ox,oy-22); ctx.lineTo(tipx,oy); ctx.lineTo(ox,oy+22); ctx.closePath(); ctx.fill();
        // animated diagonal stripes (the 'spin') as additive segments
        for(var s=0;s<14;s++){
          var f=((s/14)+ (t*1.4)%1)%1;
          var x=ox+f*len;
          var halfh=22*(1-f);
          var off=Math.sin(f*18 + t*16)*6;
          ctx.strokeStyle = s%2? 'rgba(255,255,255,'+(0.6*(1-f))+')':'rgba(255,90,120,'+(0.5*(1-f))+')';
          ctx.lineWidth=3;
          ctx.beginPath(); ctx.moveTo(x,oy-halfh+off); ctx.lineTo(x,oy+halfh+off); ctx.stroke();
        }
        // boring tip
        glow(tipx,oy, 14+Math.sin(t*30)*4, '255,255,255', 0.8);
        glow(tipx,oy, 26, '255,120,150', 0.5);
        // shavings flung from the tip
        for(var k=0;k<12;k++){ var ph=(t*1.8+rnd(k))%1; var ang=(rnd(k*3)-0.5)*2.2; var d=ph*60; glow(tipx+Math.cos(ang)*d, oy+Math.sin(ang)*d, 3*(1-ph)+1, k%2?'255,255,255':'255,140,170', (1-ph)*0.9); }
     """),

    ("flak", "Marshmallow Flak Burst", "HEAVY",
     "Timed-fuse shells: CPUParticles3D one-shot puffy-sphere bursts of soft marshmallow billboards at staggered air positions + additive flash per pop.",
     r"""
        // Multiple soft puff-bursts pop in the air at staggered times (airburst flak).
        for(var b=0;b<5;b++){
          var period=1.2, ph=((t + b*0.21) % period)/period;
          var bx = 50 + ((b*61)%200)/200*(W-100);
          var by = H*0.30 + ((b*97)%140) - 20;
          if(ph<0.5){
            // shell rising to its burst point
            var f=ph/0.5; var sx=24, sy=H-12;
            glow(sx+(bx-sx)*f, sy+(by-sy)*f, 4, '255,240,220', 0.6);
          } else {
            var e=(ph-0.5)/0.5;
            // soft expanding cottony puff
            var R=8+e*30;
            glow(bx,by, R, '255,245,235', (1-e)*0.6);
            glow(bx,by, R*0.6, '255,255,255', (1-e)*0.8);
            for(var k=0;k<9;k++){ var ka=k/9*6.283; var d=e*R*1.1; glow(bx+Math.cos(ka)*d, by+Math.sin(ka)*d, 7*(1-e)+2, '255,235,225', (1-e)*0.7); }
          }
        }
     """),

    ("multi_lash", "Licorice Three-Tail Lash", "WHIP",
     "Three additive frost_bolts-style polylines fanned from one grip, each a recoloured ribbon; tips converge then snap apart. Pure additive 2D-canvas.",
     r"""
        // Three licorice tails crack out in a fan and whip independently.
        var ox=14, oy=H*0.5;
        var period=0.95, ph=(t % period)/period;
        var ext = Math.min(1, ph/0.5);
        var cols=['80,200,255','255,120,200','180,255,120'];
        ctx.lineCap='round';
        for(var tail=0; tail<3; tail++){
          var baseAng=(tail-1)*0.45;
          var wob = Math.sin(t*7 + tail*2.1);
          var tipAng = baseAng + wob*0.4*(1-ext*0.5);
          var len=(W*0.74)*ext;
          for(var p=0;p<3;p++){
            var a=[0.14,0.4,0.85][p], wd=[10,5,1.8][p];
            var c=cols[tail];
            ctx.strokeStyle=p===2?'rgba(255,255,255,'+a+')':'rgba('+c+','+a+')';
            ctx.beginPath();
            for(var s=0;s<=18;s++){ var f=s/18; var ang=baseAng + (tipAng-baseAng)*f + Math.sin(f*6+t*8+tail)*0.06; var r=f*len; var x=ox+Math.cos(ang)*r, y=oy+Math.sin(ang)*r; ctx.lineWidth=wd*(1-f*0.7); if(s===0)ctx.moveTo(x,y); else ctx.lineTo(x,y); }
            ctx.stroke();
          }
          // tip crack
          var ex=ox+Math.cos(tipAng)*len, ey=oy+Math.sin(tipAng)*len;
          if(ph>0.55) glow(ex,ey, 12*(1-(ph-0.55)/0.45)+3, '255,255,255', (1-(ph-0.55)/0.45)*0.9);
        }
        glow(ox,oy, 10, '255,255,255', 0.5);
     """),

    ("fizz_cone", "Soda-Spray Fizz Cone", "SPREAD",
     "CPUParticles3D wide forward cone of tiny additive fizz billboards with high spawn rate + low lifetime; foamy muzzle bloom sprite. Reads like a shaken can.",
     r"""
        // A frothy carbonated cone — dense tiny bubbles spraying forward, popping.
        var ox=18, oy=H*0.5;
        glow(ox,oy, 18, '180,235,255', 0.4);
        for(var k=0;k<60;k++){
          var ph=((t*1.1 + rnd(k))%1);
          var ang=(rnd(k*3)-0.5)*0.95;             // forward cone
          var spd=120+rnd(k*7)*230;
          var x=ox + Math.cos(ang)*spd*ph;
          var y=oy + Math.sin(ang)*spd*ph + Math.sin(t*10+k)*4;
          var col=['200,240,255','255,255,255','160,255,230','230,210,255'][k%4];
          var sz=2+rnd(k*2)*3;
          glow(x,y, sz*(1-ph)+1, col, (1-ph)*0.85);
          // occasional bright bubble-pop
          if(rnd(Math.floor(t*6)+k)<0.06) glow(x,y, 6, '255,255,255', (1-ph));
        }
        // foam head clinging to the muzzle
        for(var f=0;f<6;f++){ var fa=t*2+f; glow(ox+8+f*2, oy+Math.sin(fa)*8, 5, '255,255,255', 0.4); }
     """),

    ("boomerang", "Lollipop Boomerang", "PRECISION",
     "A spinning additive lollipop sprite on a CPUParticles3D-driven out-and-back curve + a fading additive arc-ribbon trail. Returns to the muzzle.",
     r"""
        // A lollipop spins out on a curved path, loops, and arcs back — ribbon trail.
        var period=1.6, ph=(t % period)/period;
        var ox=18, oy=H*0.5;
        function pos(f){
          // out-and-back lissajous-ish loop
          var x=ox + Math.sin(f*3.14159)*(W-44);
          var y=oy + Math.sin(f*6.283)* (H*0.30);
          return [x,y];
        }
        // ribbon trail
        for(var i=0;i<22;i++){
          var ff=ph-i*0.018; if(ff<0)break;
          var p=pos(ff);
          var hueix=i%4;
          var col=['255,120,160','255,210,120','120,220,255','190,140,255'][hueix];
          glow(p[0],p[1], 6*(1-i/26)+2, col, (1-i/22)*0.8);
        }
        var head=pos(ph);
        // spinning candy disc (cross of two bright bars)
        ctx.save(); ctx.translate(head[0],head[1]); ctx.rotate(t*14);
        for(var b=0;b<2;b++){ ctx.rotate(b*1.5708); ctx.strokeStyle='rgba(255,255,255,0.85)'; ctx.lineWidth=3; ctx.beginPath(); ctx.moveTo(-10,0); ctx.lineTo(10,0); ctx.stroke(); }
        ctx.restore();
        glow(head[0],head[1], 12, '255,150,190', 0.7);
        glow(head[0],head[1], 5, '255,255,255', 0.95);
     """),

    ("cluster_pop", "Gummy-Grenade Cluster Pop", "LOB",
     "A lobbed additive billboard splits into bomblets (CPUParticles3D sub-emitters), each a delayed additive flash + spark ring. Staggered chain of small pops.",
     r"""
        // One grenade lobs in, then bursts into several delayed bomblet pops.
        var period=1.7, ph=(t % period)/period;
        var ox=16, oy=H-14, lx=W*0.6, ly=H*0.42;
        var flight=0.4;
        if(ph<flight){
          var f=ph/flight;
          var x=ox+(lx-ox)*f, y=oy + (ly-oy)*f - Math.sin(f*3.14)*H*0.45;
          for(var i=0;i<6;i++){ var ff=f-i*0.04; if(ff<0)break; var tx=ox+(lx-ox)*ff, ty=oy+(ly-oy)*ff-Math.sin(ff*3.14)*H*0.45; glow(tx,ty,5*(1-i/8)+2,'120,255,140',(1-i/6)*0.6); }
          glow(x,y, 8, '200,255,200', 0.9);
        } else {
          var e=(ph-flight)/(1-flight);
          // primary pop
          glow(lx,ly, 26*Math.min(1,e*3)*(1-e)+6, '180,255,160', (1-e)*0.8);
          // 6 bomblets, each on its own staggered fuse
          for(var k=0;k<6;k++){
            var delay=0.1+rnd(k)*0.35;
            if(e<delay)continue;
            var be=(e-delay)/(1-delay);
            var ang=rnd(k*3)*6.283;
            var bx=lx+Math.cos(ang)*(40+rnd(k*5)*40);
            var by=ly+Math.sin(ang)*(30+rnd(k*7)*30);
            var col=['120,255,140','255,230,120','255,120,180','120,220,255'][k%4];
            glow(bx,by, 18*(1-be)+4, col, (1-be)*0.85);
            glow(bx,by, 7*(1-be)+2, '255,255,255', (1-be));
            for(var s=0;s<6;s++){ var sa=s/6*6.283; var d=be*22; glow(bx+Math.cos(sa)*d, by+Math.sin(sa)*d, 2.5, col, (1-be)*0.7); }
          }
        }
     """),

    ("sprinkle_storm", "Sprinkle Storm", "FRENZY",
     "CPUParticles3D dense downpour of tiny coloured additive capsule billboards (random spin) over a wide area — a screen-filling frenzy rain of sprinkles.",
     r"""
        // A dense slanted rain of glowing sprinkles sweeping across — frenzy filler.
        for(var k=0;k<70;k++){
          var ph=((t*0.9 + rnd(k))%1);
          var sx=rnd(k*3)*W;
          var x=sx + ph*60 - 30;                   // slight slant drift
          var y=ph*(H+30) - 20;
          var col=['255,90,130','120,220,255','255,220,90','150,255,150','200,130,255','255,150,220'][k%6];
          var len=6+rnd(k*5)*5;
          ctx.save(); ctx.translate(x,y); ctx.rotate(0.6 + rnd(k*2)*1.2);
          ctx.strokeStyle='rgba('+col+',0.85)'; ctx.lineWidth=2.4; ctx.lineCap='round';
          ctx.beginPath(); ctx.moveTo(-len*0.5,0); ctx.lineTo(len*0.5,0); ctx.stroke();
          ctx.restore();
          glow(x,y, 2.5, col, 0.5);
        }
        // soft ambient frenzy bloom
        glow(W*0.5, H*0.5, W*0.5, '255,180,220', 0.05);
     """),

    ("railgun", "Hard-Candy Railgun Slug", "RIFLE",
     "A single ultra-bright additive beam-streak sprite that fires once and fades fast + helical additive spark sprites peeling off + recoil muzzle bloom. Hitscan look.",
     r"""
        // A charged hitscan slug: brief charge, then a blinding straight streak + helix sparks.
        var period=1.3, ph=(t % period)/period;
        var ox=14, oy=H*0.5;
        if(ph<0.45){
          // charge-up: energy gathering at the muzzle
          var c=ph/0.45;
          glow(ox,oy, 6+c*16, '120,200,255', c*0.7);
          glow(ox,oy, 4+c*6, '255,255,255', c*0.9);
          for(var k=0;k<8;k++){ var ka=k/8*6.283 + t*6; var d=(1-c)*26+6; glow(ox+Math.cos(ka)*d, oy+Math.sin(ka)*d, 3, '160,220,255', c*0.8); }
        } else {
          var e=(ph-0.45)/0.55;
          var fade=1-e;
          // the slug streak (straight, thick to thin core)
          ctx.lineCap='round';
          ctx.strokeStyle='rgba(120,200,255,'+(0.2*fade)+')'; ctx.lineWidth=16*fade;
          ctx.beginPath(); ctx.moveTo(ox,oy); ctx.lineTo(W-10,oy); ctx.stroke();
          ctx.strokeStyle='rgba(220,245,255,'+(0.7*fade)+')'; ctx.lineWidth=5*fade;
          ctx.beginPath(); ctx.moveTo(ox,oy); ctx.lineTo(W-10,oy); ctx.stroke();
          ctx.strokeStyle='rgba(255,255,255,'+(0.95*fade)+')'; ctx.lineWidth=1.6;
          ctx.beginPath(); ctx.moveTo(ox,oy); ctx.lineTo(W-10,oy); ctx.stroke();
          // helical sparks peeling off the beam
          for(var x=ox;x<W-10;x+=14){ var hy=oy+Math.sin(x*0.12 - e*20)*10*fade; glow(x,hy, 3, '180,230,255', fade*0.8); }
          // recoil muzzle bloom + impact flash
          glow(ox,oy, 30*fade+6, '160,220,255', fade*0.8);
          glow(W-12,oy, 30*fade+6, '255,255,255', fade*0.9);
        }
     """),

    ("lasso_loop", "Caramel Lasso Loop", "LASSO",
     "An additive spinning rope-loop sprite (procedural ellipse polyline, frost-style glow) orbiting the cowboy + a trailing caramel-glint ribbon. Pure additive 2D.",
     r"""
        // A glowing caramel lariat spins as a tilted ellipse, twirling over the hero.
        var cx=W*0.5, cy=H*0.52, spin=t*3.0;
        var rx=W*0.34, ry=H*0.18;
        ctx.lineCap='round';
        // rope loop, multi-pass glow
        for(var p=0;p<3;p++){
          var a=[0.14,0.42,0.85][p], wd=[12,6,2.2][p];
          ctx.strokeStyle=['rgba(255,160,70,'+a+')','rgba(255,200,120,'+a+')','rgba(255,245,210,'+a+')'][p];
          ctx.lineWidth=wd; ctx.beginPath();
          for(var s=0;s<=48;s++){ var ang=s/48*6.283; var x=cx+Math.cos(ang)*rx; var y=cy+Math.sin(ang)*ry + Math.sin(ang+spin)*8; if(s===0)ctx.moveTo(x,y); else ctx.lineTo(x,y); }
          ctx.closePath(); ctx.stroke();
        }
        // a bright glint racing around the loop
        var ga=spin%6.283; var gx=cx+Math.cos(ga)*rx, gy=cy+Math.sin(ga)*ry + Math.sin(ga+spin)*8;
        for(var i=0;i<10;i++){ var aa=ga-i*0.12; var x=cx+Math.cos(aa)*rx, y=cy+Math.sin(aa)*ry+Math.sin(aa+spin)*8; glow(x,y, 5*(1-i/12)+1, '255,235,180', (1-i/10)*0.8); }
        glow(gx,gy, 9, '255,255,255', 0.9);
        // the held tail dropping to the grip
        ctx.strokeStyle='rgba(255,200,120,0.5)'; ctx.lineWidth=4; ctx.beginPath(); ctx.moveTo(cx-rx,cy); ctx.lineTo(16,H-12); ctx.stroke();
     """),

    ("ricochet", "Peppermint Ricochet Round", "CANDY",
     "A small bright additive pellet sprite that bounces off the play-bounds with a spark flash per bounce (CPUParticles3D one-shot) + short additive trail. Six-shooter feel.",
     r"""
        // A single candy pellet pings around the box, sparking on each wall bounce.
        var ox=16, oy=H*0.5;
        // simulate a deterministic bouncing path via reflected coordinates
        var vx=1.0, vy=0.42;
        var spd=(W*1.3);
        var period=1.5, tt=(t%period);
        var px=ox + vx*spd*tt, py=oy + vy*spd*tt;
        // reflect into [pad, W-pad] / [pad, H-pad]
        function refl(v,lo,hi){ var span=hi-lo; var m=((v-lo)%(2*span)+2*span)%(2*span); return lo + (m<span? m : 2*span-m); }
        function bounces(v,lo,hi){ var span=hi-lo; return Math.floor(Math.abs(v-lo)/span); }
        var pad=12;
        var X=refl(px,pad,W-pad), Y=refl(py,pad,H-pad);
        // short trail (recompute past positions)
        for(var i=0;i<14;i++){
          var ti=tt-i*0.012; if(ti<0)break;
          var x=refl(ox+vx*spd*ti,pad,W-pad), y=refl(oy+vy*spd*ti,pad,H-pad);
          glow(x,y, 5*(1-i/16)+1, '255,120,150', (1-i/14)*0.8);
        }
        glow(X,Y, 8, '255,255,255', 0.95);
        glow(X,Y, 16, '255,140,170', 0.5);
        // spark flash when near a wall (a bounce just happened)
        if(X<pad+6||X>W-pad-6||Y<pad+6||Y>H-pad-6){ glow(X,Y, 22, '255,255,255', 0.7); for(var k=0;k<6;k++){ var ka=k/6*6.283; glow(X+Math.cos(ka)*10, Y+Math.sin(ka)*10, 3, '255,200,210', 0.8); } }
     """),
]

TAG_COLORS = {
    "CANDY": "#7ed957", "RIFLE": "#5ac8ff", "FRENZY": "#ff7eb6",
    "WHIP": "#ff9f5a", "HEAVY": "#ffd23f", "PRECISION": "#9fd8ff",
    "SPREAD": "#5affd0", "LOB": "#b07eff", "LASSO": "#ffb86b",
}

TAG_LABELS = {
    "CANDY": "CANDY (six-shooter)",
    "RIFLE": "RIFLE",
    "FRENZY": "FRENZY",
    "WHIP": "WHIP (liquorice)",
    "HEAVY": "HEAVY (cannon)",
    "PRECISION": "PRECISION (rifle)",
    "SPREAD": "SPREAD (shotgun)",
    "LOB": "LOB (grenade)",
    "LASSO": "LASSO (caramel)",
}


def build_tiles_js() -> str:
    entries = []
    for key, name, tag, note, body in FX:
        entries.append(
            "{key:%r, draw:function(ctx,W,H,t,rnd,glow,bolt){%s}}" % (key, body)
        )
    return "[\n" + ",\n".join(entries) + "\n]"


def build_cards_html() -> str:
    cards = []
    for key, name, tag, note, _ in FX:
        col = TAG_COLORS.get(tag, "#7ed957")
        cards.append(f"""    <div class="card" style="border-color:{col}">
      <div class="tag" style="background:{col}">{tag}</div>
      <canvas id="fx_{key}" width="240" height="240"></canvas>
      <div class="cn">{name}</div>
      <div class="cd">{note}</div>
    </div>""")
    return "\n".join(cards)


def build_legend_html() -> str:
    spans = []
    # legend in roster order
    order = ["CANDY", "RIFLE", "PRECISION", "SPREAD", "HEAVY", "WHIP", "LOB", "LASSO", "FRENZY"]
    for tag in order:
        col = TAG_COLORS[tag]
        spans.append(f'    <span style="background:{col}">{TAG_LABELS[tag]}</span>')
    return "\n".join(spans)


def build_html() -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Not_This_Again — Weapon-FX Gallery 2 (rerolls + roster)</title>
<style>
  *{{box-sizing:border-box}}
  body{{margin:0;background:#070510;color:#e8def7;font-family:system-ui,-apple-system,sans-serif}}
  .wrap{{max-width:1180px;margin:0 auto;padding:26px 18px 60px}}
  h1{{font-size:24px;margin:0 0 6px;color:#ffd23f;letter-spacing:.3px}}
  .sub{{font-size:14px;line-height:1.6;color:#bda9e0;max-width:900px;margin:0 0 16px}}
  .sub b{{color:#ffd98a}}
  .note{{font-size:12.5px;line-height:1.6;color:#9ad9b0;max-width:900px;margin:0 0 22px;
        border-left:3px solid #2f6b46;padding:6px 0 6px 12px;background:#0a160f}}
  .legend{{display:flex;gap:10px;flex-wrap:wrap;margin:0 0 22px;font-size:11px;font-weight:700}}
  .legend span{{padding:3px 10px;border-radius:7px;color:#0c0814}}
  .grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:18px}}
  .card{{position:relative;background:#100a1e;border:2px solid #3a2a4f;border-radius:14px;padding:10px;text-align:center;overflow:hidden}}
  .card canvas{{width:100%;height:auto;aspect-ratio:1/1;border-radius:9px;display:block;background:#040208}}
  .tag{{position:absolute;top:8px;left:8px;color:#0c0814;font-size:10px;font-weight:800;padding:2px 9px;border-radius:7px;z-index:2}}
  .cn{{font-size:15px;color:#ffe1a0;margin-top:9px;font-weight:600}}
  .cd{{font-size:11.5px;color:#b9a6dc;margin-top:4px;line-height:1.45}}
  .foot{{margin-top:30px;font-size:12px;color:#8d7bb0;line-height:1.6;max-width:900px}}
</style>
</head>
<body>
<div class="wrap">
  <h1>Weapon-FX Gallery 2 — fresh rerolls + broader weapon roster</h1>
  <p class="sub">Round two of candidate fire visuals, all at the <b>FROSTBITE</b> /
  <b>Rainbow Prism Chain</b> polish bar. These are <b>14 genuinely new ideas</b> — none
  repeat the 5 you already approved (Gumdrop Buckshot, Homing Sparkle Swarm, Rainbow
  Comet Trail, Gumball Gatling Bloom, Confetti Cannon) and none recolor the 8 you
  rejected (Plasma Beam, Licorice Arc Chain, Peppermint Nova, Peppermint Vortex,
  Caramel Napalm, Crystal Shatter Beam, Jawbreaker Mortar Arc, Prism Refraction Fan).</p>
  <p class="note">Each tile is tagged with the <b>weapon TYPE</b> it suits, mapped to the
  actual debug-screen roster: CANDY six-shooter, RIFLE, PRECISION (Frostbite Rifle),
  SPREAD (Peppermint Shotgun), HEAVY (Marshmallow Cannon), WHIP (Liquorice Whip), LOB
  (Gumdrop Grenade), LASSO (Caramel Lasso), and FRENZY. Every effect is mobile-safe:
  shippable with <b>only additive 2D-canvas overlays (à la frost_bolts.gd),
  CPUParticles3D, and additive sprites</b> — no custom spatial shaders.</p>
  <div class="legend">
{build_legend_html()}
  </div>
  <div class="grid">
{build_cards_html()}
  </div>
  <p class="foot">Pure HTML5 &lt;canvas&gt; + JS with <code>globalCompositeOperation='lighter'</code>,
  soft radial-gradient glow sprites, multi-pass bloom, and motion trails — a direct preview
  of the additive in-engine look. Tell me which to build and which weapon to bind each to;
  the whip/lasso/tether ones reuse the frost_bolts.gd polyline technique almost verbatim,
  so they are the cheapest to ship.</p>
</div>
<script>
"use strict";
// ---- shared additive helpers (same as gallery 1) -------------------------
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
