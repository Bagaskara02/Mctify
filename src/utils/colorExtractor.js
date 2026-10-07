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
        const c1 = `rgb(${Math.round(r / half)}, ${Math.round(g / half)}, ${Math.round(b / half)})`;
        const c2 = `rgb(${Math.round(r2 / half)}, ${Math.round(g2 / half)}, ${Math.round(b2 / half)})`;
        const c3 = `rgb(${Math.min(255, Math.round((r + r2) / (count || 1) + 40))}, ${Math.round((g + g2) / (count || 1))}, ${Math.min(255, Math.round((b + b2) / (count || 1) + 40))})`;

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
