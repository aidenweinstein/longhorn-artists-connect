/**
 * Shrinks a chosen photo to at most `max` px on its long side and re-encodes it as JPEG,
 * so uploads stay small (and well under the server action size limit). Browser only.
 */
export async function preparePhoto(file: File, max = 1024, name = "photo.jpg"): Promise<File> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, max / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85));
  if (!blob) throw new Error("Couldn't read that photo.");
  return new File([blob], name, { type: "image/jpeg" });
}
