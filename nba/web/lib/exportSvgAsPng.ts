/**
 * Client-side chart export utility.
 *
 * Captures an arbitrary DOM element (not just a bare <svg>) as a PNG, so a
 * chart's title/subtitle/legend/caption -- which are almost always plain
 * HTML siblings of the <svg>, not part of it -- are included in the export.
 *
 * Technique: clone the element, inline every element's *computed* style
 * (Tailwind utility classes only resolve while the page's stylesheet is
 * attached, so a standalone serialized clone needs literal values), wrap the
 * clone in a single-use SVG <foreignObject>, rasterize that to an offscreen
 * canvas, then download as PNG. Generic and data-agnostic -- works off any
 * element ref alone, no chart-specific logic. No server/API involvement --
 * safe to call from a fully static export.
 */

const PNG_SCALE = 2;

const STYLE_PROPS = [
  // SVG shape/text styling
  'fill',
  'stroke',
  'stroke-width',
  'stroke-dasharray',
  'stroke-linecap',
  'stroke-linejoin',
  'opacity',
  'fill-opacity',
  'stroke-opacity',
  'text-anchor',
  // Typography
  'color',
  'font-family',
  'font-size',
  'font-weight',
  'font-style',
  'line-height',
  'letter-spacing',
  'text-transform',
  'text-decoration',
  'white-space',
  // Box model / layout
  'display',
  'flex-direction',
  'flex-wrap',
  'align-items',
  'justify-content',
  'justify-items',
  'gap',
  'row-gap',
  'column-gap',
  'width',
  'height',
  'min-width',
  'min-height',
  'max-width',
  'max-height',
  'padding-top',
  'padding-right',
  'padding-bottom',
  'padding-left',
  'margin-top',
  'margin-right',
  'margin-bottom',
  'margin-left',
  'border-top-width',
  'border-right-width',
  'border-bottom-width',
  'border-left-width',
  'border-top-color',
  'border-right-color',
  'border-bottom-color',
  'border-left-color',
  'border-top-style',
  'border-right-style',
  'border-bottom-style',
  'border-left-style',
  'border-radius',
  'background-color',
  'box-sizing',
  'position',
  'top',
  'left',
  'right',
  'bottom',
  'z-index',
  'overflow',
] as const;

function inlineComputedStyles(source: Element, target: Element): void {
  const computed = window.getComputedStyle(source);
  let styleText = '';
  for (const prop of STYLE_PROPS) {
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

function getElementPixelSize(el: Element): { width: number; height: number } {
  const rect = el.getBoundingClientRect();
  let width = rect.width;
  let height = rect.height;

  if (!width || !Number.isFinite(width)) width = 500;
  if (!height || !Number.isFinite(height)) height = 300;

  return { width, height };
}

/**
 * Exports `element` (and everything inside it -- title, subtitle, caption,
 * legend, the chart itself, etc.) as a downloaded PNG. `element` should be
 * the container that visually represents "this chart", not just its <svg>.
 *
 * Elements marked `data-export-exclude` (e.g. the export button itself) are
 * stripped from the captured clone.
 */
export function exportSvgAsPng(element: Element, filename: string): void {
  if (typeof window === 'undefined' || typeof document === 'undefined' || !element) {
    return;
  }

  const clone = element.cloneNode(true) as HTMLElement;
  inlineComputedStyles(element, clone);
  clone.querySelectorAll('[data-export-exclude]').forEach((el) => el.remove());

  const { width, height } = getElementPixelSize(element);

  clone.setAttribute('xmlns', 'http://www.w3.org/1999/xhtml');
  const serializer = new XMLSerializer();
  const htmlString = serializer.serializeToString(clone);

  const svgString =
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}">` +
    `<foreignObject width="100%" height="100%">${htmlString}</foreignObject>` +
    `</svg>`;

  const svgBlob = new Blob([svgString], { type: 'image/svg+xml;charset=utf-8' });
  const svgUrl = URL.createObjectURL(svgBlob);

  const normalizedFilename = withDateStamp(filename, 'png');

  const img = new Image();
  img.onload = () => {
    const canvas = document.createElement('canvas');
    canvas.width = width * PNG_SCALE;
    canvas.height = height * PNG_SCALE;

    const ctx = canvas.getContext('2d');
    if (!ctx) {
      URL.revokeObjectURL(svgUrl);
      return;
    }

    // The captured card's own background is often semi-transparent
    // (relies on the page's dark backdrop), so paint the app's dark
    // background first rather than leaving it transparent/black.
    ctx.fillStyle = '#0b0f17';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.scale(PNG_SCALE, PNG_SCALE);
    ctx.drawImage(img, 0, 0, width, height);

    URL.revokeObjectURL(svgUrl);

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
  };
  img.onerror = () => {
    URL.revokeObjectURL(svgUrl);
  };
  img.src = svgUrl;
}
