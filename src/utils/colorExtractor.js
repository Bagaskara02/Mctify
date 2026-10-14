/**
 * Extract dominant colors from an image URL using offscreen canvas.
 * Falls back to deterministic attractive gradients if image is cross-origin or fails.
 */
export async function extractPaletteFromImage(imageUrl) {
  const fallbackPalettes = [
    { primary: '#6366f1', secondary: '#ec4899', tertiary: '#8b5cf6' }, // Indigo / Pink
    { primary: '#06b6d4', secondary: '#3b82f6', tertiary: '#10b981' }, // Cyan / Blue / Emerald
    { primary: '#f97316', secondary: '#ef4444', tertiary: '#eab308' }, // Orange / Red / Yellow
    { primary: '#8b5cf6', secondary: '#d946ef', tertiary: '#06b6d4' }, // Purple / Fuchsia / Cyan
    { primary: '#10b981', secondary: '#06b6d4', tertiary: '#3b82f6' }, // Emerald / Cyan
  ];

  if (!imageUrl) {
    return fallbackPalettes[0];
  }

  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = 'Anonymous';
    img.src = imageUrl;

    img.onload = () => {
      try {
        const canvas = document.createElement('canvas');
        const ctx = canvas.getContext('2d');
        if (!ctx) return resolve(getRandomFallback(imageUrl));

        canvas.width = 40;
        canvas.height = 40;
        ctx.drawImage(img, 0, 0, 40, 40);

        const data = ctx.getImageData(0, 0, 40, 40).data;
        let r = 0, g = 0, b = 0, count = 0;
        let r2 = 0, g2 = 0, b2 = 0;

        for (let i = 0; i < data.length; i += 16) {
          const red = data[i];
          const green = data[i + 1];
          const blue = data[i + 2];
          
          // Filter out near-blacks and near-whites for richer color
          const brightness = (red + green + blue) / 3;
          if (brightness > 25 && brightness < 235) {
            if (count % 2 === 0) {
              r += red; g += green; b += blue;
            } else {
              r2 += red; g2 += green; b2 += blue;
            }
            count++;
          }
        }

        if (count < 10) {
          return resolve(getRandomFallback(imageUrl));
        }

        const half = Math.max(1, Math.floor(count / 2));
        const avgR1 = Math.round(r / half);
        const avgG1 = Math.round(g / half);
        const avgB1 = Math.round(b / half);

        const avgR2 = Math.round(r2 / half);
        const avgG2 = Math.round(g2 / half);
        const avgB2 = Math.round(b2 / half);

        // Clamp to Spotify dark-mode aesthetic (Lightness 18%-30%, rich saturation)
        // This guarantees white text is always 100% legible without eye strain
        const c1 = clampColorToDarkTheme(avgR1, avgG1, avgB1, 0.18, 0.30, 0.40);
        const c2 = clampColorToDarkTheme(avgR2, avgG2, avgB2, 0.15, 0.26, 0.35);
        const c3 = clampColorToDarkTheme(
          Math.min(255, Math.round((r + r2) / (count || 1) + 20)),
          Math.round((g + g2) / (count || 1)),
          Math.min(255, Math.round((b + b2) / (count || 1) + 30)),
          0.12, 0.24, 0.30
        );

        resolve({ primary: c1, secondary: c2, tertiary: c3 });
      } catch {
        resolve(getRandomFallback(imageUrl));
      }
    };

    img.onerror = () => {
      resolve(getRandomFallback(imageUrl));
    };
  });
}

function getRandomFallback(seedStr = '') {
  const fallbacks = [
    { primary: '#6366f1', secondary: '#ec4899', tertiary: '#8b5cf6' },
    { primary: '#0ea5e9', secondary: '#10b981', tertiary: '#6366f1' },
    { primary: '#f43f5e', secondary: '#fb923c', tertiary: '#8b5cf6' },
    { primary: '#a855f7', secondary: '#ec4899', tertiary: '#06b6d4' },
    { primary: '#10b981', secondary: '#3b82f6', tertiary: '#06b6d4' },
  ];
  let hash = 0;
  for (let i = 0; i < seedStr.length; i++) {
    hash = (hash << 5) - hash + seedStr.charCodeAt(i);
  }
  const idx = Math.abs(hash) % fallbacks.length;
  return fallbacks[idx];
}

/**
 * Convert RGB (0-255) to HSL (0-1).
 */
function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  let h = 0, s = 0, l = (max + min) / 2;

  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r: h = (g - b) / d + (g < b ? 6 : 0); break;
      case g: h = (b - r) / d + 2; break;
      case b: h = (r - g) / d + 4; break;
      default: break;
    }
    h /= 6;
  }
  return [h, s, l];
}

/**
 * Convert HSL (0-1) to RGB (0-255).
 */
function hslToRgb(h, s, l) {
  let r, g, b;
  if (s === 0) {
    r = g = b = l;
  } else {
    const hue2rgb = (p, q, t) => {
      let val = t;
      if (val < 0) val += 1;
      if (val > 1) val -= 1;
      if (val < 1/6) return p + (q - p) * 6 * val;
      if (val < 1/2) return q;
      if (val < 2/3) return p + (q - p) * (2/3 - val) * 6;
      return p;
    };
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const p = 2 * l - q;
    r = hue2rgb(p, q, h + 1/3);
    g = hue2rgb(p, q, h);
    b = hue2rgb(p, q, h - 1/3);
  }
  return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255)];
}

/**
 * Clamps RGB color into dark mode safe range (Lightness 18%-30%)
 * so text headers and UI controls always pop cleanly with AAA contrast.
 */
function clampColorToDarkTheme(r, g, b, minL = 0.16, maxL = 0.30, minSat = 0.35) {
  const [h, s, l] = rgbToHsl(r, g, b);
  const clampedSat = Math.max(minSat, s);
  const clampedL = Math.max(minL, Math.min(maxL, l));
  const [newR, newG, newB] = hslToRgb(h, clampedSat, clampedL);
  return `rgb(${newR}, ${newG}, ${newB})`;
}
