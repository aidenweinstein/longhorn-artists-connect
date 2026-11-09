/**
 * Reads an image's pixel dimensions from its first 512 KB (JPEG or PNG) with a range
 * request, so layouts can use each post's true aspect ratio instead of cropping.
 */
export async function imageAspect(url: string): Promise<number | undefined> {
  try {
    const res = await fetch(url, { headers: { Range: "bytes=0-524287" }, cache: "no-store" });
    if (!res.ok && res.status !== 206) return undefined;
    const bytes = new Uint8Array(await res.arrayBuffer());
    const size = pngSize(bytes) ?? jpegSize(bytes);
    return size && size.w > 0 && size.h > 0 ? size.w / size.h : undefined;
  } catch {
    return undefined;
  }
}

function pngSize(b: Uint8Array) {
  if (b.length < 24 || b[0] !== 0x89 || b[1] !== 0x50) return undefined;
  const v = new DataView(b.buffer, b.byteOffset);
  return { w: v.getUint32(16), h: v.getUint32(20) };
}

function jpegSize(b: Uint8Array) {
  if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8) return undefined;
  let i = 2;
  let orientation = 1;
  while (i + 9 < b.length) {
    if (b[i] !== 0xff) { i++; continue; }
    const marker = b[i + 1];
    const len = (b[i + 2] << 8) | b[i + 3];
    if (marker === 0xe1) orientation = exifOrientation(b, i + 4, len - 2) ?? orientation;
    // SOF0–SOF15, excluding DHT (C4), JPG (C8) and DAC (CC).
    if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
      const h = (b[i + 5] << 8) | b[i + 6];
      const w = (b[i + 7] << 8) | b[i + 8];
      // EXIF orientations 5–8 are rotated 90°, so the displayed image is h × w.
      return orientation >= 5 ? { w: h, h: w } : { w, h };
    }
    i += 2 + len;
  }
  return undefined;
}

function exifOrientation(b: Uint8Array, start: number, length: number): number | undefined {
  if (String.fromCharCode(...b.subarray(start, start + 4)) !== "Exif") return undefined;
  const tiff = start + 6;
  if (tiff + 8 > b.length) return undefined;
  const little = b[tiff] === 0x49;
  const v = new DataView(b.buffer, b.byteOffset);
  const u16 = (o: number) => v.getUint16(o, little);
  const u32 = (o: number) => v.getUint32(o, little);
  const ifd = tiff + u32(tiff + 4);
  const end = Math.min(b.length, start + length);
  if (ifd + 2 > end) return undefined;
  const count = u16(ifd);
  for (let n = 0; n < count; n++) {
    const entry = ifd + 2 + n * 12;
    if (entry + 12 > end) break;
    if (u16(entry) === 0x0112) return u16(entry + 8);
  }
  return undefined;
}
