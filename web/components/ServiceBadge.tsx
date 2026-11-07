import { existsSync } from "node:fs";
import path from "node:path";

/**
 * Logo files for streaming services, dropped into public/logos/ from each brand's
 * official asset kit (Spotify: developer.spotify.com/documentation/design;
 * Apple Music: toolbox.marketingtools.apple.com). Any service without a file there
 * shows as a plain text pill instead.
 */
const LOGO_FILES: Record<string, string> = {
  spotify: "spotify",
  "apple music": "apple-music",
};

function logoFor(service: string): string | undefined {
  const base = LOGO_FILES[service.trim().toLowerCase()];
  if (!base) return undefined;
  for (const ext of ["svg", "png"]) {
    if (existsSync(path.join(process.cwd(), "public", "logos", `${base}.${ext}`))) return `/logos/${base}.${ext}`;
  }
  return undefined;
}

/** One "Also On" pill: the service's logo and name, linked when there's a URL. */
export default function ServiceBadge({ service, url }: { service: string; url?: string }) {
  const logo = logoFor(service);
  const body = (
    <>
      {logo && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={logo} alt="" className="h-5 w-5 shrink-0 object-contain" />
      )}
      <span>{service}</span>
    </>
  );
  const cls = "inline-flex items-center gap-2 rounded-full bg-foreground/10 px-3.5 py-1.5 text-sm font-medium";
  return url ? (
    <a href={url} target="_blank" rel="noopener noreferrer" className={`${cls} hover:bg-foreground/20`}>
      {body}
    </a>
  ) : (
    <span className={cls}>{body}</span>
  );
}
