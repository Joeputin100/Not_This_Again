#!/usr/bin/env python3
"""Companion fragment: the 4 Raisin Kidd (Pai Mei withered-martial-artist) concept
renders as a clickable picker. Images base64-embedded so the file is self-contained
(survives the companion server idling). Writes a CONTENT FRAGMENT (no <html>) so the
brainstorm frame wraps it with theme + selection infra.

Usage: python3 tools/gen_raisin_concept_gallery.py <out_path.html>
"""
import base64
import pathlib
import sys

ROOT = pathlib.Path("/home/projects/Not_This_Again")
ART = ROOT / "docs/superpowers/assets/raisin_kidd_2026-06-06"
OUT = pathlib.Path(sys.argv[1])


def b64(p: pathlib.Path) -> str:
    return base64.b64encode(p.read_bytes()).decode()


# (choice, file, title, blurb, fight-flavor)
CARDS = [
    ("grandmaster", "concept_1_paimei.png", "The Grandmaster",
     "Serene, regal, untouchable — floats and strokes his impossibly long beard. The faithful Pai&nbsp;Mei homage, pure kung-fu master.",
     "Reads as the contemptuous defender who can't be touched."),
    ("gunslinger", "concept_2_western.png", "The Candy-Shaolin Gunslinger",
     "Duster coat, black hat, bolo tie over silk robes, open-palm stance. East-meets-Wild-West — fits the candy-WESTERN frame hardest.",
     "Reads as a fusion striker, equal parts monk and outlaw."),
    ("mystic", "concept_3_pressure.png", "The Gumdrop Mystic",
     "Purple robes, braided beard, fingertips glowing with candy-gumdrop energy, a candy-cane staff. Leans into the magic.",
     "Best telegraphs the Five-Point Exploding Gumdrop technique."),
    ("trickster", "concept_4_cackle.png", "The Leaping Trickster",
     "Dynamic and mischievous, caught mid-leap brandishing a candy-cane, gumdrop-button robe. Lively, acrobatic, a cackling showman.",
     "Reads as the fast, evasive acrobat who never holds still."),
]

cards_html = ""
for choice, fn, title, blurb, flavor in CARDS:
    img = b64(ART / fn)
    cards_html += f"""
  <div class="card" data-choice="{choice}" onclick="toggleSelect(this)">
    <div class="card-image" style="background:#1a1226;padding:0">
      <img src="data:image/png;base64,{img}" style="width:100%;display:block;border-radius:8px 8px 0 0">
    </div>
    <div class="card-body">
      <h3>{title}</h3>
      <p>{blurb}</p>
      <p style="color:#9c86c8;font-size:13px;margin-top:6px"><b>Fight feel:</b> {flavor}</p>
    </div>
  </div>"""

HTML = f"""<h2>Raisin Kidd — pick his look</h2>
<p class="subtitle">You've locked the character: the withered Pai&nbsp;Mei–style raisin kung-fu grandmaster, with
<b>The Grapes of Wrath</b> and the <b>Five-Point Raisin Exploding Gumdrop Technique</b>, a sinister cackle, and his own voice.
These four are just his <b>look</b>. Pick the one that's him — or mix (e.g. Grandmaster's serenity + Gunslinger's duster).
I'll refine the winner into the final boss sheet.</p>

<div class="cards" style="grid-template-columns:repeat(2,minmax(0,1fr))">{cards_html}
</div>
"""

OUT.write_text(HTML)
print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")
