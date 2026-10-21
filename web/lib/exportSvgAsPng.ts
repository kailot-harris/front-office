/**
 * Client-side chart export utility.
 *
 * Captures an arbitrary DOM element (not just a bare <svg>) as a PNG, so a
 * chart's title/subtitle/legend/caption -- which are almost always plain
 * HTML siblings of the <svg>, not part of it -- are included in the export.
 *
 * Technique: walk the live DOM using real layout boxes (getBoundingClientRect
 * + getComputedStyle), manually drawing backgrounds/borders/text onto a
 * canvas, and separately rasterizing any nested <svg> elements (the chart
 * itself, plus any inline icons) to be drawn in place. This deliberately
 * avoids the SVG <foreignObject> + canvas.toBlob trick: Chromium taints the
 * canvas when a foreignObject contains HTML, so toBlob silently resolves
 * with `null` and nothing downloads -- no visible error, just a dead button.
 * Generic and data-agnostic -- works off any element ref alone, no
 * chart-specific logic. No server/API involvement -- safe to call from a
 * fully static export.
 */

const PNG_SCALE = 2;

const SVG_STYLE_PROPS = [
  'fill',
  'stroke',
  'stroke-width',
  'stroke-dasharray',
  'stroke-linecap',
  'stroke-linejoin',
  'opacity',
  'fill-opacity',
  'stroke-opacity',
  'font-family',
  'font-size',
  'font-weight',
  'text-anchor',
  'color',
] as const;

function inlineComputedStyles(source: Element, target: Element): void {
  const computed = window.getComputedStyle(source);
  let styleText = '';
  for (const prop of SVG_STYLE_PROPS) {
    const value = computed.getPropertyValue(prop);
    if (value) {
      styleText += `${prop}:${value};`;
    }
  }
  if (styleText) {
    const existing = target.getAttribute('style') || '';
    target.setAttribute('style', existing + styleText);
  }

  const sourceChildren = source.children;
  const targetChildren = target.children;
  for (let i = 0; i < sourceChildren.length; i++) {
    inlineComputedStyles(sourceChildren[i], targetChildren[i]);
  }
}

function withDateStamp(filename: string, extension: string): string {
  const base = filename.toLowerCase().endsWith(`.${extension}`)
    ? filename.slice(0, -(extension.length + 1))
    : filename;
  const dateStamp = new Date().toISOString().slice(0, 10);
  return `${base}_${dateStamp}.${extension}`;
}

function isTransparent(color: string): boolean {
  if (!color || color === 'transparent') return true;
  const match = color.match(/rgba?\(\s*[\d.]+\s*,\s*[\d.]+\s*,\s*[\d.]+\s*(?:,\s*([\d.]+)\s*)?\)/);
  if (match && match[1] !== undefined) {
    return parseFloat(match[1]) === 0;
  }
  return false;
}

function cornerRadius(cs: CSSStyleDeclaration, width: number, height: number): number {
  const raw = parseFloat(cs.borderRadius);
  if (!raw || Number.isNaN(raw)) return 0;
  return Math.min(raw, Math.min(width, height) / 2);
}

function roundedRectPath(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  if (w <= 0 || h <= 0) return;
  ctx.beginPath();
  if (r > 0 && typeof ctx.roundRect === 'function') {
    ctx.roundRect(x, y, w, h, r);
  } else {
    ctx.rect(x, y, w, h);
  }
}

function collectSvgNodes(node: Element, acc: SVGSVGElement[]): void {
  if (node.hasAttribute('data-export-exclude')) return;
  if (node.tagName.toLowerCase() === 'svg') {
    acc.push(node as unknown as SVGSVGElement);
    return;
  }
  for (const child of Array.from(node.children)) {
    collectSvgNodes(child, acc);
  }
}

function rasterizeSvgToImage(svgEl: SVGSVGElement): Promise<HTMLImageElement> {
  return new Promise((resolve) => {
    const clone = svgEl.cloneNode(true) as SVGSVGElement;
    inlineComputedStyles(svgEl, clone);

    const rect = svgEl.getBoundingClientRect();
    const width = rect.width || svgEl.width?.baseVal?.value || 24;
    const height = rect.height || svgEl.height?.baseVal?.value || 24;

    clone.setAttribute('width', String(width));
    clone.setAttribute('height', String(height));
    if (!clone.getAttribute('xmlns')) {
      clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
    }

    const svgString = new XMLSerializer().serializeToString(clone);
    const blob = new Blob([svgString], { type: 'image/svg+xml;charset=utf-8' });
    const url = URL.createObjectURL(blob);

    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve(img);
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      resolve(img); // resolve with a broken (naturalWidth 0) image; draw step just skips it
    };
    img.src = url;
  });
}

function drawTextNode(
  ctx: CanvasRenderingContext2D,
  textNode: Text,
  originX: number,
  originY: number
): void {
  const text = textNode.textContent;
  if (!text || !text.trim()) return;
  const parent = textNode.parentElement;
  if (!parent) return;

  const range = document.createRange();
  range.selectNodeContents(textNode);
  const rects = Array.from(range.getClientRects());
  if (rects.length === 0) return;

  const cs = window.getComputedStyle(parent);
  ctx.font = `${cs.fontStyle} ${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
  ctx.fillStyle = cs.color;
  ctx.textBaseline = 'alphabetic';
  const fontSizePx = parseFloat(cs.fontSize) || 12;
  const baselineOffset = fontSizePx * 0.22;

  if (rects.length === 1) {
    ctx.fillText(text.trim(), rects[0].left - originX, rects[0].bottom - originY - baselineOffset);
    return;
  }

  // Wrapped across multiple visual lines: approximate each line's substring
  // proportionally to that line's rect width vs. the total rect width.
  const totalWidth = rects.reduce((sum, r) => sum + r.width, 0) || 1;
  let charCursor = 0;
  for (let i = 0; i < rects.length; i++) {
    const r = rects[i];
    const isLast = i === rects.length - 1;
    const share = r.width / totalWidth;
    const lineLen = isLast ? text.length - charCursor : Math.round(text.length * share);
    const line = text.slice(charCursor, charCursor + lineLen).trim();
    charCursor += lineLen;
    if (line) {
      ctx.fillText(line, r.left - originX, r.bottom - originY - baselineOffset);
    }
  }
}

function drawTree(
  ctx: CanvasRenderingContext2D,
  node: Node,
  originX: number,
  originY: number,
  svgImages: Map<SVGSVGElement, HTMLImageElement>
): void {
  if (node.nodeType === Node.TEXT_NODE) {
    drawTextNode(ctx, node as Text, originX, originY);
    return;
  }

  if (!(node instanceof Element)) return;
  if (node.hasAttribute('data-export-exclude')) return;

  const tag = node.tagName.toLowerCase();

  if (tag === 'svg') {
    const img = svgImages.get(node as unknown as SVGSVGElement);
    if (img && img.naturalWidth > 0) {
      const rect = node.getBoundingClientRect();
      ctx.drawImage(img, rect.left - originX, rect.top - originY, rect.width, rect.height);
    }
    return;
  }

  const rect = node.getBoundingClientRect();
  if (rect.width > 0 && rect.height > 0) {
    const cs = window.getComputedStyle(node);
    const radius = cornerRadius(cs, rect.width, rect.height);

    const bg = cs.backgroundColor;
    if (bg && !isTransparent(bg)) {
      roundedRectPath(ctx, rect.left - originX, rect.top - originY, rect.width, rect.height, radius);
      ctx.fillStyle = bg;
      ctx.fill();
    }

    const borderWidth = parseFloat(cs.borderTopWidth) || 0;
    if (borderWidth > 0 && cs.borderTopStyle !== 'none' && !isTransparent(cs.borderTopColor)) {
      roundedRectPath(ctx, rect.left - originX, rect.top - originY, rect.width, rect.height, radius);
      ctx.strokeStyle = cs.borderTopColor;
      ctx.lineWidth = borderWidth;
      ctx.stroke();
    }
  }

  for (const child of Array.from(node.childNodes)) {
    drawTree(ctx, child, originX, originY, svgImages);
  }
}

/**
 * Exports `element` (and everything inside it -- title, subtitle, caption,
 * legend, the chart itself, etc.) as a downloaded PNG. `element` should be
 * the container that visually represents "this chart", not just its <svg>.
 *
 * Elements marked `data-export-exclude` (e.g. the export button itself) are
 * skipped entirely.
 */
export function exportSvgAsPng(element: Element, filename: string): void {
  if (typeof window === 'undefined' || typeof document === 'undefined' || !element) {
    return;
  }

  const containerRect = element.getBoundingClientRect();
  const width = containerRect.width || 500;
  const height = containerRect.height || 300;

  const svgNodes: SVGSVGElement[] = [];
  collectSvgNodes(element, svgNodes);

  Promise.all(svgNodes.map((svg) => rasterizeSvgToImage(svg))).then((images) => {
    const svgImages = new Map<SVGSVGElement, HTMLImageElement>();
    svgNodes.forEach((svg, i) => svgImages.set(svg, images[i]));

    const canvas = document.createElement('canvas');
    canvas.width = width * PNG_SCALE;
    canvas.height = height * PNG_SCALE;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // The captured card's own background is often semi-transparent
    // (relies on the page's dark backdrop), so paint the app's dark
    // background first rather than leaving it transparent/black.
    ctx.fillStyle = '#0b0f17';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.scale(PNG_SCALE, PNG_SCALE);

    drawTree(ctx, element, containerRect.left, containerRect.top, svgImages);

    const normalizedFilename = withDateStamp(filename, 'png');

    canvas.toBlob((blob) => {
      if (!blob) return;
      const pngUrl = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = pngUrl;
      link.download = normalizedFilename;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(pngUrl);
    }, 'image/png');
  });
}
