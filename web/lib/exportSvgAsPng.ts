/**
 * Client-side SVG -> PNG export utility.
 *
 * Serializes a live <svg> element, draws it onto an offscreen canvas
 * (scaled up for crispness), and downloads the result as a PNG via
 * canvas.toBlob. No server/API involvement — safe to call from a fully
 * static export.
 */

const PNG_SCALE = 2;

// Style properties worth inlining. Most of these components style their SVG
// shapes/text via Tailwind utility classes (e.g. `fill-emerald-400`), which
// only resolve while the page's stylesheet is attached. A standalone
// serialized <svg> loaded into an <img> has no stylesheet, so we snapshot
// the *computed* values from the live DOM onto each cloned node as inline
// `style` before serializing.
const STYLE_PROPS = [
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
  'background-color',
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

function getSvgPixelSize(svg: SVGSVGElement): { width: number; height: number } {
  const viewBox = svg.viewBox && svg.viewBox.baseVal;
  const widthAttr = svg.getAttribute('width');
  const heightAttr = svg.getAttribute('height');

  const rect = svg.getBoundingClientRect();

  let width = rect.width || (widthAttr ? parseFloat(widthAttr) : 0) || (viewBox ? viewBox.width : 0);
  let height = rect.height || (heightAttr ? parseFloat(heightAttr) : 0) || (viewBox ? viewBox.height : 0);

  if (!width || !Number.isFinite(width)) width = 600;
  if (!height || !Number.isFinite(height)) height = 400;

  return { width, height };
}

export function exportSvgAsPng(svgRef: SVGSVGElement, filename: string): void {
  if (typeof window === 'undefined' || typeof document === 'undefined' || !svgRef) {
    return;
  }

  const svgClone = svgRef.cloneNode(true) as SVGSVGElement;
  inlineComputedStyles(svgRef, svgClone);
  const { width, height } = getSvgPixelSize(svgRef);

  svgClone.setAttribute('width', String(width));
  svgClone.setAttribute('height', String(height));
  if (!svgClone.getAttribute('xmlns')) {
    svgClone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
  }

  const serializer = new XMLSerializer();
  const svgString = serializer.serializeToString(svgClone);
  const svgBlob = new Blob([svgString], { type: 'image/svg+xml;charset=utf-8' });
  const svgUrl = URL.createObjectURL(svgBlob);

  const normalizedFilename = filename.toLowerCase().endsWith('.png')
    ? filename
    : `${filename}.png`;

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

    // White background so transparent SVGs don't export as black in viewers
    // that don't honor alpha.
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
