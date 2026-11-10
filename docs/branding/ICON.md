# Folder In Bar 앱 아이콘

내장 `image_gen` 도구로 생성했습니다. 파란 폴더와 그 위의 메뉴 막대가 앱의 기능을 나타냅니다. 메뉴 막대의 작은 아이콘은 별도의 단색 시스템 심벌을 사용하며, 이 컬러 아이콘은 앱 번들·Finder·설치 화면 등에 사용합니다.

최종 PNG를 `OneButton/Assets.xcassets/AppIcon.appiconset/`의 macOS 표준 16–1024px 크기로 변환해 포함합니다. 크기 변환은 `sips`, `.icns` 패키징은 Xcode asset compiler가 처리합니다.

## 최초 생성 프롬프트

Use case: logo-brand. Asset type: one finished macOS application icon for an app called Folder In Bar, a small menu bar utility that opens files from a selected folder. Create a single premium, minimal, beautifully crafted macOS icon, square 1024x1024 composition. The main shape is an elegant blue folder integrated with a simple horizontal menu-bar motif above it: a short dark navy rounded bar with one small blue square indicator, and a clear friendly blue folder just below, forming one cohesive central mark. Put this on an off-white softly rounded square icon tile, about 84 percent of the canvas width, centered with generous transparent outer margin and a subtle realistic shadow. Refined gentle depth, crisp contours, restrained soft gradients, clean Apple-like desktop utility aesthetic, high legibility when reduced to 32 pixels. The folder must dominate; the horizontal bar is a small supporting motif, no window chrome or tiny details. No letters, no text, no numbers, no wordmark, no watermark, no other objects. Outside the icon tile must be genuinely transparent, not a painted checkerboard. Single straight-on icon only, no mockup, no desktop, no multiple variants.

## 외곽 정리 프롬프트

Refine this exact macOS app icon. Preserve the central blue folder, dark menu bar with blue square, off-white rounded-square tile, overall proportions, colors, and gentle dimensional shading. Change ONLY the outer edge treatment: remove every isolated white speck, ragged halo, noisy fringing, and stray pixel outside the tile. Make the tile silhouette a perfectly smooth clean rounded rectangle. Outside it use true alpha transparency with at most a very subtle smooth shadow that fades cleanly to zero; no mottling, no checkerboard, no white haze or random pixels. Ensure a clean generous transparent margin around all four edges. Keep everything inside the tile unchanged. One icon, no text.

## 최종 색상·외곽 프롬프트

Produce the final app-icon asset from this design. Keep the exact blue folder shape, layout, and large simple proportions. Replace the white background tile with a deep midnight navy rounded-square tile, and change the small horizontal menu bar to pale icy blue so it remains clearly distinct on the navy tile. Keep the bar's small bright blue square indicator. The entire rounded-square tile must have a PERFECTLY CLEAN HARD SILHOUETTE with smooth antialiasing, absolutely NO outer shadow, NO glow, NO white border, NO feathering, NO grain, NO isolated pixels. All pixels outside that rounded-square tile must be fully transparent. The tile stays centered with about 8 percent transparent margin each side. The blue folder keeps its lovely restrained dimensional shading. The navy tile itself uses a very subtle smooth gradient only. No text, no additional elements. This is a shipping macOS app icon; outer alpha edges must look like a clean vector mask, no fuzzy extraction.
