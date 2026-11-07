import { initials } from "./ContentGrid";

/**
 * A person's photo on the People pages, shown at its own full shape: nothing is
 * cropped, so a portrait stays portrait and a landscape stays landscape. Shows
 * initials in a 4:5 frame until there's a photo.
 */
export default function Headshot({ name, src }: { name: string; src?: string }) {
  if (src) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={src} alt={`Photo of ${name}`} loading="lazy" className="block h-auto w-full rounded-lg bg-background" />;
  }
  return (
    <span aria-hidden className="flex aspect-[4/5] w-full items-center justify-center rounded-lg bg-brand text-3xl font-semibold text-white">
      {initials(name)}
    </span>
  );
}
