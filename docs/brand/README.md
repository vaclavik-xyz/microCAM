# microCAM brand assets (direction D)

## Files

| File | Use |
|---|---|
| `AppIcon.icns` | macOS app icon (16–1024, @1x/@2x). Built from `AppIcon.iconset/`. |
| `AppIcon-1024.png` | Master icon, 1024×1024, 824 px squircle with shadow (Big Sur+ grid). |
| `AppIcon.iconset/` | Source PNGs for `iconutil`. 16 and 32 px (incl. 16@2x) use the flat silhouette variant for legibility; 64 px and up use the 3D render. |
| `logo-light.svg/.png/@2x.png` | Icon + wordmark, transparent, for light backgrounds. |
| `logo-dark.svg/.png/@2x.png` | Icon + wordmark, transparent, for dark backgrounds. |
| `wordmark-light.svg`, `wordmark-dark.svg` (+ `@2x.png`) | Wordmark only, pure vector. |
| `symbol-red.svg`, `symbol-black.svg`, `symbol-white.svg` | One-colour microscope silhouette, pure vector (print, stickers, favicon-like use). |
| `og-image.png` (+ `.svg`) | Open Graph / social preview, 1200×630. |

All text is converted to outlines; no fonts are needed. The logo SVGs embed the icon as a PNG (the icon is a 3D render); the wordmark and symbol SVGs are pure vector.

## Tokens

- Red `#E41E33` (gradient bottom `#CC0226`), ink `#0A0A0A`, white `#FFFFFF`.
- Wordmark: DM Sans ExtraBold, `micro` in red + `CAM` in ink/white, red REC dot at the top-right of the `M`.
- Headlines (OG): DM Sans Bold; body: DM Sans Medium.

## Rules

- Keep the red dot on the wordmark; it is the REC light and matches the dot on the camera in the icon.
- Minimum clear space around the logo: the height of the `C` in `CAM`.
- Do not recolour the icon. For one-colour use, take a `symbol-*.svg`.
