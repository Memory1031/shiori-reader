# Shiori 字标概念预览

使用内置 image_gen 生成。用户认可后，首页使用亮色透明原图（复制到 assets/brand/shiori.png）作为唯一形状母版，暗色模式通过 Flutter ShaderMask 仅将文字区域渲染为暖白，图形不变；预览暗色图不直接打包。两次透明暗图生成尝试存在杂点或棋盘背景，已弃用，未覆盖原图。此方式避免两张位图几何差异和背景色块。

## Light prompt

Use case: logo-design. Create one refined horizontal logo-and-wordmark concept for Shiori, a quiet novel reading mobile app. LIGHT MODE version. Text EXACTLY "Shiori" (S h i o r i), no other text. Integrated unified composition: small original abstract ribbon/bookmark symbol with a gently folded page gesture on the LEFT, elegant subtly customized humanist lettering on the RIGHT. Literary, restrained, warm and contemporary, not generic bold Material app title. The symbol should feel part of the same typographic family, not a badge. Excellent small toolbar legibility, medium-weight clean strokes, balanced compact kerning. Warm charcoal #302C2B lettering, restrained muted sage accent on the symbol. Flat crisp vector-like graphic on solid warm ivory #FAF8F4 background. Wide canvas, logo centered with ample but not excessive whitespace, brand fills about 70 percent width. No Chinese glyph, no tag or chip or enclosing rounded square, no gradients, shadows, 3D, mockup device, tagline, ornament, watermark or extra layout. This is the master design for a matching dark variant, keep forms simple and reproducible.

## Dark edit prompt

Create the matching DARK MODE variant of this exact Shiori logo. Preserve the bookmark/page symbol geometry, wordmark letterforms, exact spelling "Shiori", proportions, alignment, spacing, canvas and scale unchanged. Change ONLY the palette: wordmark warm ivory #EEE7EB; bookmark muted pale sage #B8CDB1; background solid warm near-black #1B181C. Flat graphic with crisp clean edges and uniform fills; no gradients, texture, bevel, shadow or glow. No added text or objects. This is a color variant of the same identity, not a redesign.
