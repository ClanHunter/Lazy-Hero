Details Logo Assets

Files created:
- `assets/details_wordmark.svg` — horizontal wordmark with tagline and a small graph accent.
- `assets/details_badge.svg` — square badge suitable for store/marketing with a stylized "D" and bar chart motif.
- `assets/details_favicon.svg` — small rounded-square favicon/launcher icon with monogram `D`.

Colors & style
- Primary dark background: #0F172A (near-black navy)
- Accent gold gradient: #F0C674 → #D99B1F
- Text/neutral: #1F2937 and #6B7280 for tagline
- Style: modern flat with warm gold accents to evoke reliability and prestige.

Usage & export
- The assets are SVG (scalable). To generate PNGs on Windows with ImageMagick (installed), run (PowerShell):

```powershell
magick convert assets\details_wordmark.svg -background none -resize 1200x assets\details_wordmark_1200.png
magick convert assets\details_badge.svg -background none -resize 512x assets\details_badge_512.png
magick convert assets\details_favicon.svg -background none -resize 64x assets\details_favicon_64.png
```

- Or using Inkscape (recommended for precise rasterization):

```powershell
inkscape --export-type=png --export-filename=assets\\details_badge_512.png --export-width=512 assets\\details_badge.svg
inkscape --export-type=png --export-filename=assets\\details_favicon_64.png --export-width=64 assets\\details_favicon.svg
``` 

Licensing & notes
- These assets are generated for your private use and integration into your project. If you want a different visual direction (metallic, embossed, or different colors), tell me and I will generate alternate variants.

Next steps
- I can produce additional color variants (light/dark), export PNGs at common sizes, or create a small README snippet with suggested placements for the addon page and Twitch/YouTube thumbnails.

