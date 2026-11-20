"use client";

// Building blocks for the Share forms. They mirror the app's grouped List sections:
// a small header, a rounded card of rows, and an optional footer note. Chosen values
// show in the brand color, like the app's orange menu labels.

import { useEffect, useId, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { releaseYears } from "@/lib/shareOptions";
import type { PersonMatch } from "@/lib/sharePost";
import { croppedAspect, cropStyle, type VideoCrop } from "@/lib/videoCrop";
import VideoCropEditor from "./VideoCropEditor";

const noYears: string[] = [];
let yearsCache: string[] | null = null;
const noSubscribe = () => () => {};
/**
 * The release-year menu's options. Read in the browser only: the year comes from the
 * clock, which the server mustn't read while prerendering the Share pages.
 */
export function useReleaseYears(): string[] {
  return useSyncExternalStore(noSubscribe, () => (yearsCache ??= releaseYears()), () => noYears);
}

const rowBase = "flex min-h-12 items-center gap-3 px-4 py-2.5";
const input = "w-full bg-transparent px-4 py-3 text-[15px] outline-none placeholder:text-muted";

export function Section({ title, footer, children }: { title?: string; footer?: ReactNode; children: ReactNode }) {
  return (
    // The Category picker sits across the top; everything else flows into two columns.
    <section className={title === "Category" ? "relative z-10 lg:col-span-2" : undefined}>
      {title && <h3 className="mb-1.5 px-4 font-sans text-xs font-semibold uppercase tracking-wide text-muted">{title}</h3>}
      <div className={`divide-y divide-border rounded-2xl bg-surface ${title === "Category" ? "" : "overflow-hidden"}`}>{children}</div>
      {footer && <p className="mt-1.5 px-4 text-xs text-muted">{footer}</p>}
    </section>
  );
}

export function Row({ label, children, htmlFor }: { label: ReactNode; children?: ReactNode; htmlFor?: string }) {
  return (
    <div className={rowBase}>
      <label htmlFor={htmlFor} className="shrink-0 text-[15px]">
        {label}
      </label>
      <div className="ml-auto flex min-w-0 items-center justify-end gap-2 text-right">{children}</div>
    </div>
  );
}

export function TextInput({
  value,
  onChange,
  placeholder,
  type = "text",
  maxLength = 200,
}: {
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  type?: "text" | "url";
  maxLength?: number;
}) {
  return (
    <input
      type={type}
      aria-label={placeholder}
      className={input}
      value={value}
      maxLength={maxLength}
      placeholder={placeholder}
      onChange={(e) => onChange(e.target.value)}
    />
  );
}

export function TextArea({
  value,
  onChange,
  placeholder,
  rows = 3,
  maxLength = 2000,
}: {
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  rows?: number;
  maxLength?: number;
}) {
  return (
    <textarea
      aria-label={placeholder}
      className={`${input} block resize-y`}
      rows={rows}
      value={value}
      maxLength={maxLength}
      placeholder={placeholder}
      onChange={(e) => onChange(e.target.value)}
    />
  );
}

/** A single-choice row. Native select underneath, so it works with keyboard and screen readers. */
export function SelectRow({
  label,
  value,
  options,
  onChange,
  placeholder = "Select",
}: {
  label: string;
  value: string;
  options: readonly string[];
  onChange: (v: string) => void;
  placeholder?: string;
}) {
  const id = useId();
  // The Category choice at the top of each form is a styled dropdown instead of the native menu.
  if (label === "Category") return <Dropdown label={label} value={value} options={options} onChange={onChange} placeholder={placeholder} />;
  return (
    <Row label={label} htmlFor={id}>
      <select
        id={id}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="max-w-[16rem] cursor-pointer appearance-none truncate bg-transparent text-right text-[15px] text-brand outline-none"
      >
        <option value="" disabled>
          {placeholder}
        </option>
        {options.map((o) => (
          <option key={o} value={o}>
            {o}
          </option>
        ))}
      </select>
      <ChevronUpDown />
    </Row>
  );
}

/** A styled dropdown: a button showing the choice, and a floating list to pick from. */
function Dropdown({
  label,
  value,
  options,
  onChange,
  placeholder,
}: {
  label: string;
  value: string;
  options: readonly string[];
  onChange: (v: string) => void;
  placeholder: string;
}) {
  const [open, setOpen] = useState(false);
  const box = useRef<HTMLDivElement>(null);
  const listID = useId();

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (!box.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  return (
    <div ref={box} className="relative p-2">
      <button
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listID}
        onClick={() => setOpen((o) => !o)}
        className={`flex w-full items-center justify-between gap-3 rounded-xl bg-background px-4 py-3 text-left text-[15px] font-medium ring-1 transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand ${
          open ? "ring-brand" : "ring-border hover:ring-brand/50"
        }`}
      >
        <span className={value ? "text-foreground" : "text-muted"}>{value || placeholder}</span>
        <svg viewBox="0 0 12 12" className={`h-3 w-3 shrink-0 text-muted transition-transform ${open ? "rotate-180" : ""}`} aria-hidden>
          <path d="M2 4l4 4 4-4" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
        </svg>
      </button>
      {open && (
        <ul
          id={listID}
          role="listbox"
          aria-label={label}
          className="absolute inset-x-2 top-full z-30 mt-1 max-h-72 overflow-auto rounded-xl border border-border bg-background p-1 shadow-xl"
        >
          {options.map((o) => {
            const on = o === value;
            return (
              <li key={o} role="option" aria-selected={on}>
                <button
                  type="button"
                  onClick={() => {
                    onChange(o);
                    setOpen(false);
                  }}
                  className={`flex w-full items-center justify-between gap-3 rounded-lg px-3 py-2.5 text-left text-[15px] transition ${
                    on ? "bg-brand/10 font-semibold text-brand" : "hover:bg-surface"
                  }`}
                >
                  {o}
                  {on && (
                    <svg viewBox="0 0 12 12" className="h-3.5 w-3.5 shrink-0" aria-hidden>
                      <path d="M2.5 6.5l2.5 2.5 4.5-5.5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  )}
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

/** A multi-choice row that opens into a set of chips, like the app's genre menu. */
export function MultiSelectRow({
  label,
  values,
  options,
  onChange,
}: {
  label: string;
  values: string[];
  options: readonly string[];
  onChange: (v: string[]) => void;
}) {
  const [open, setOpen] = useState(false);
  const summary = values.length ? [...values].sort().join(", ") : "Select";
  return (
    <div>
      <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open} className={`${rowBase} w-full text-left`}>
        <span className="shrink-0 text-[15px]">{label}</span>
        <span className="ml-auto truncate text-[15px] text-brand">{summary}</span>
        <ChevronUpDown />
      </button>
      {open && (
        <div className="flex flex-wrap gap-2 px-4 pb-3">
          {options.map((o) => {
            const on = values.includes(o);
            return (
              <button
                key={o}
                type="button"
                aria-pressed={on}
                onClick={() => onChange(on ? values.filter((v) => v !== o) : [...values, o])}
                className={`rounded-full border px-3 py-1 text-sm transition ${
                  on ? "border-brand bg-brand text-white" : "border-border hover:bg-foreground/5"
                }`}
              >
                {o}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

export function ToggleRow({ label, checked, onChange }: { label: string; checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <Row label={label}>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        onClick={() => onChange(!checked)}
        className={`relative h-[30px] w-[50px] shrink-0 rounded-full transition ${checked ? "bg-brand" : "bg-foreground/20"}`}
      >
        <span
          className={`absolute top-[2px] h-[26px] w-[26px] rounded-full bg-white shadow transition-all ${checked ? "left-[22px]" : "left-[2px]"}`}
        />
      </button>
    </Row>
  );
}

export function Segmented({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: readonly string[];
  onChange: (v: string) => void;
}) {
  return (
    <div className="px-4 py-2.5">
      <p className="mb-2 text-[15px]">{label}</p>
      <div role="radiogroup" aria-label={label} className="flex rounded-lg bg-foreground/10 p-0.5">
        {options.map((o) => (
          <button
            key={o}
            type="button"
            role="radio"
            aria-checked={value === o}
            onClick={() => onChange(o)}
            className={`flex-1 rounded-md py-1.5 text-sm font-medium transition ${value === o ? "bg-background shadow-sm" : "text-muted"}`}
          >
            {o}
          </button>
        ))}
      </div>
    </div>
  );
}

export function DateRow({
  label,
  value,
  onChange,
  type = "date",
  min,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  type?: "date" | "time";
  min?: string;
}) {
  const id = useId();
  return (
    <Row label={label} htmlFor={id}>
      <input
        id={id}
        type={type}
        value={value}
        min={min}
        onChange={(e) => onChange(e.target.value)}
        className="rounded-lg bg-foreground/10 px-2.5 py-1 text-[15px] outline-none"
      />
    </Row>
  );
}

/** A "More" row that reveals optional fields underneath. */
export function MoreRows({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false);
  if (open) return <>{children}</>;
  return (
    <button type="button" onClick={() => setOpen(true)} className={`${rowBase} w-full text-left text-[15px] text-brand`}>
      More
      <svg viewBox="0 0 12 12" className="h-3 w-3" aria-hidden>
        <path d="M2 4l4 4 4-4" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      </svg>
    </button>
  );
}

// MARK: - Files

function usePreviews(files: File[]) {
  const urls = useMemo(() => files.map((f) => URL.createObjectURL(f)), [files]);
  useEffect(() => () => urls.forEach((u) => URL.revokeObjectURL(u)), [urls]);
  return urls;
}

function Thumb({ file, url, icon }: { file?: File; url?: string; icon: ReactNode }) {
  const box = "flex h-11 w-11 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-foreground/10 text-muted";
  if (file && url && file.type.startsWith("image/")) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={url} alt="" className={`${box} object-cover`} />;
  }
  if (file && url && file.type.startsWith("video/")) {
    return <video src={url} muted playsInline preload="metadata" className={`${box} object-cover`} />;
  }
  return <span className={box}>{icon}</span>;
}

/** True when a dropped file fits an <input accept> list (".pdf", "image/*", "application/pdf"). */
function matchesAccept(file: File, accept: string) {
  const rules = accept.split(",").map((r) => r.trim().toLowerCase()).filter(Boolean);
  if (!rules.length) return true;
  const name = file.name.toLowerCase();
  const type = file.type.toLowerCase();
  return rules.some((r) => (r.startsWith(".") ? name.endsWith(r) : r.endsWith("/*") ? type.startsWith(r.slice(0, -1)) : type === r));
}

/**
 * A large target you can click or drop files onto. Files that don't match `accept` are
 * ignored on drop, the same as the file picker would filter them.
 */
export function DropZone({
  accept,
  multiple,
  onFiles,
  icon,
  title,
  hint,
  compact,
}: {
  accept: string;
  multiple?: boolean;
  onFiles: (f: File[]) => void;
  icon: ReactNode;
  title: string;
  hint?: string;
  compact?: boolean;
}) {
  const [over, setOver] = useState(false);
  const [rejected, setRejected] = useState(false);
  return (
    <label
      onDragEnter={(e) => {
        e.preventDefault();
        setOver(true);
      }}
      onDragOver={(e) => {
        e.preventDefault();
        setOver(true);
      }}
      onDragLeave={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setOver(false);
      }}
      onDrop={(e) => {
        e.preventDefault();
        setOver(false);
        const dropped = Array.from(e.dataTransfer.files);
        const ok = dropped.filter((f) => matchesAccept(f, accept));
        setRejected(dropped.length > 0 && ok.length === 0);
        if (ok.length) onFiles(multiple ? ok : ok.slice(0, 1));
      }}
      className={`flex cursor-pointer flex-col items-center justify-center gap-2 rounded-2xl border-2 border-dashed px-4 text-center transition focus-within:ring-2 focus-within:ring-brand ${
        compact ? "min-h-28 py-5" : "min-h-52 py-10"
      } ${over ? "border-brand bg-brand/10" : "border-foreground/20 hover:border-brand/60 hover:bg-foreground/5"}`}
    >
      <span className={`flex items-center justify-center rounded-full bg-brand/15 text-brand ${compact ? "h-10 w-10" : "h-14 w-14"}`}>{icon}</span>
      <span className="text-[15px] font-medium">{over ? "Drop to add" : title}</span>
      <span className="text-sm text-muted">
        {rejected ? "That file type isn't accepted here." : hint ?? (over ? "" : "Drag and drop, or click to browse")}
      </span>
      <input
        type="file"
        accept={accept}
        multiple={multiple}
        aria-label={title}
        className="sr-only"
        onChange={(e) => {
          setRejected(false);
          onFiles(Array.from(e.target.files ?? []));
          e.target.value = "";
        }}
      />
    </label>
  );
}

/**
 * Picks one file. Shows a drop area until chosen, then a large preview with Replace and
 * Remove. `noun` is lowercase, like the app ("video", "thumbnail", "poster").
 */
export function FileRow({
  noun,
  accept,
  file,
  onChange,
  icon = <FileIcon />,
  optional,
  crop,
  onCropChange,
}: {
  noun: string;
  accept: string;
  file: File | null;
  onChange: (f: File | null) => void;
  icon?: ReactNode;
  optional?: boolean;
  /** Videos only: the playback crop. Passing `onCropChange` adds a Crop button once a video is picked. */
  crop?: VideoCrop | null;
  onCropChange?: (c: VideoCrop | null) => void;
}) {
  const files = useMemo(() => (file ? [file] : []), [file]);
  const [url] = usePreviews(files);
  const [cropping, setCropping] = useState(false);
  const title = `${optional ? "Add" : "Select"} ${noun}`;
  const canCrop = Boolean(onCropChange && file?.type.startsWith("video/"));
  // A new or removed file starts uncropped, as in the app.
  const change = (f: File | null) => {
    onCropChange?.(null);
    onChange(f);
  };
  return (
    <div className="p-3">
      {file ? (
        <div className="overflow-hidden rounded-2xl bg-foreground/5">
          {url && file.type.startsWith("image/") && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={url} alt="" className="max-h-72 w-full object-contain" />
          )}
          {url && file.type.startsWith("video/") &&
            (crop ? (
              <CroppedVideoPreview src={url} crop={crop} />
            ) : (
              <video src={url} controls playsInline preload="metadata" className="max-h-72 w-full bg-black" />
            ))}
          {url && file.type.startsWith("audio/") && <audio src={url} controls className="w-full p-3" />}
          <div className="flex items-center gap-3 px-4 py-3">
            {!file.type.match(/^(image|video|audio)\//) && <Thumb icon={icon} />}
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-medium">{`${noun[0].toUpperCase()}${noun.slice(1)} selected`}</p>
              <p className="truncate text-xs text-muted">{file.name} · {formatSize(file.size)}</p>
            </div>
            <label className="cursor-pointer text-sm font-medium text-brand hover:underline focus-within:ring-2 focus-within:ring-brand">
              Replace
              <input
                type="file"
                accept={accept}
                aria-label={`Replace ${noun}`}
                className="sr-only"
                onChange={(e) => {
                  const f = e.target.files?.[0];
                  if (f) change(f);
                  e.target.value = "";
                }}
              />
            </label>
            {canCrop && (
              <button type="button" onClick={() => setCropping(true)} className="flex items-center gap-1 text-sm font-medium text-brand hover:underline">
                <CropIcon />
                {crop ? "Edit crop" : "Crop"}
              </button>
            )}
            <button type="button" onClick={() => change(null)} className="text-sm text-muted hover:text-foreground">
              Remove
            </button>
          </div>
          {cropping && file && onCropChange && (
            <VideoCropEditor
              file={file}
              initial={crop ?? null}
              onCancel={() => setCropping(false)}
              onDone={(c) => {
                onCropChange(c);
                setCropping(false);
              }}
            />
          )}
        </div>
      ) : (
        <DropZone accept={accept} onFiles={(fs) => change(fs[0] ?? null)} icon={icon} title={title} hint={optional ? "Optional · drag and drop, or click to browse" : undefined} />
      )}
    </div>
  );
}

/**
 * The picked video as it will play: zoomed to its crop. Click to play or pause (the
 * browser's own controls would sit partly outside the crop and be cut off).
 */
export function CroppedVideoPreview({ src, crop, maxHeight = "18rem" }: { src: string; crop: VideoCrop; maxHeight?: string }) {
  const [natural, setNatural] = useState(16 / 9);
  const [playing, setPlaying] = useState(false);
  const ratio = croppedAspect(natural, crop);
  return (
    <div className="flex justify-center bg-black">
      <div className="relative cursor-pointer overflow-hidden" style={{ aspectRatio: ratio, width: `min(100%, calc(${maxHeight} * ${ratio}))` }}>
        <video
          src={`${src}#t=0.5`}
          playsInline
          preload="metadata"
          onLoadedMetadata={(e) => {
            const v = e.currentTarget;
            if (v.videoWidth && v.videoHeight) setNatural(v.videoWidth / v.videoHeight);
          }}
          onClick={(e) => {
            const v = e.currentTarget;
            if (v.paused) void v.play().catch(() => {});
            else v.pause();
          }}
          onPlay={() => setPlaying(true)}
          onPause={() => setPlaying(false)}
          style={cropStyle(crop)}
          className="object-fill"
        />
        {!playing && (
          <span className="pointer-events-none absolute inset-0 flex items-center justify-center">
            <span className="flex h-12 w-12 items-center justify-center rounded-full bg-black/60 text-white">
              <svg viewBox="0 0 24 24" className="ml-0.5 h-5 w-5" fill="currentColor" aria-hidden>
                <path d="M8 5v14l11-7z" />
              </svg>
            </span>
          </span>
        )}
        <span className="pointer-events-none absolute left-2 top-2 rounded-md bg-black/60 px-2 py-0.5 text-xs font-medium text-white">Cropped</span>
      </div>
    </div>
  );
}

/** Picks several files in order: photos, slides, stills. They can be reordered and removed. */
export function FilesRow({
  noun,
  accept,
  files,
  onChange,
  icon = <PhotoIcon />,
  optional,
}: {
  noun: string;
  accept: string;
  files: File[];
  onChange: (f: File[]) => void;
  icon?: ReactNode;
  optional?: boolean;
}) {
  const urls = usePreviews(files);
  const move = (i: number, by: number) => {
    const next = [...files];
    const [f] = next.splice(i, 1);
    next.splice(i + by, 0, f);
    onChange(next);
  };
  return (
    <div className="space-y-3 p-3">
      <DropZone
        accept={accept}
        multiple
        compact={files.length > 0}
        onFiles={(fs) => onChange([...files, ...fs])}
        icon={icon}
        title={files.length ? `${files.length} ${noun} selected · add more` : `${optional ? "Add" : "Select"} ${noun}`}
        hint={!files.length && optional ? "Optional · drag and drop, or click to browse" : undefined}
      />
      {files.length > 0 && (
        <ol className="grid grid-cols-3 gap-2 sm:grid-cols-4 lg:grid-cols-5">
          {files.map((f, i) => (
            <li key={`${f.name}-${f.lastModified}-${i}`} className="group relative aspect-square">
              {f.type.startsWith("video/") ? (
                <video src={urls[i]} muted playsInline preload="metadata" className="h-full w-full rounded-lg object-cover" />
              ) : f.type.startsWith("image/") ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={urls[i]} alt={f.name} className="h-full w-full rounded-lg object-cover" />
              ) : (
                <span className="flex h-full w-full flex-col items-center justify-center gap-1 rounded-lg bg-foreground/10 px-2 text-center text-xs text-muted">
                  {icon}
                  <span className="line-clamp-2 break-all">{f.name}</span>
                </span>
              )}
              <span className="absolute left-1 top-1 rounded bg-black/60 px-1.5 text-[11px] font-semibold text-white">{i + 1}</span>
              <div className="absolute inset-x-1 bottom-1 flex justify-between opacity-100 sm:opacity-0 sm:group-hover:opacity-100 sm:group-focus-within:opacity-100">
                <ThumbButton label="Move earlier" disabled={i === 0} onClick={() => move(i, -1)}>‹</ThumbButton>
                <ThumbButton label="Remove" onClick={() => onChange(files.filter((_, j) => j !== i))}>×</ThumbButton>
                <ThumbButton label="Move later" disabled={i === files.length - 1} onClick={() => move(i, 1)}>›</ThumbButton>
              </div>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}

function ThumbButton({ label, onClick, disabled, children }: { label: string; onClick: () => void; disabled?: boolean; children: ReactNode }) {
  return (
    <button
      type="button"
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      className="flex h-6 w-6 items-center justify-center rounded-full bg-black/60 text-sm leading-none text-white disabled:invisible"
    >
      {children}
    </button>
  );
}

function formatSize(bytes: number) {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)} GB`;
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(1)} MB`;
  return `${Math.max(1, Math.round(bytes / 1e3))} KB`;
}

// MARK: - Credits and lists

/** `profileID` links the credit to a Nexus member picked from the suggestions. */
export type Credit = { role: string; name: string; profileID?: string };

export const seedCredits = (roles: readonly string[]): Credit[] => roles.map((role) => ({ role, name: "" }));
export const filledCredits = (credits: Credit[]) => credits.filter((c) => c.name.trim());

/**
 * A row that opens a role/name editor underneath — the web version of the app's pushed
 * Cast, Crew and Credits pages. Shows "Add" until a name is filled in, then "Edited".
 */
export function CreditsRow({
  label,
  credits,
  onChange,
  rolePlaceholder = "Role",
  namePlaceholder = "Name",
  addLabel = "Add role",
}: {
  label: string;
  credits: Credit[];
  onChange: (c: Credit[]) => void;
  rolePlaceholder?: string;
  namePlaceholder?: string;
  addLabel?: string;
}) {
  const [open, setOpen] = useState(false);
  const edited = filledCredits(credits).length > 0;
  const update = (i: number, patch: Partial<Credit>) => onChange(credits.map((c, j) => (j === i ? { ...c, ...patch } : c)));
  return (
    <div>
      <DisclosureButton label={label} value={edited ? "Edited" : "Add"} open={open} onClick={() => setOpen((o) => !o)} />
      {open && (
        <div className="space-y-2 px-4 pb-3">
          {credits.map((c, i) => (
            <CreditLine
              key={i}
              credit={c}
              index={i}
              rolePlaceholder={rolePlaceholder}
              namePlaceholder={namePlaceholder}
              onChange={(patch) => update(i, patch)}
              onRemove={() => onChange(credits.filter((_, j) => j !== i))}
            />
          ))}
          <button type="button" onClick={() => onChange([...credits, { role: "", name: "" }])} className="text-sm font-medium text-brand">
            + {addLabel}
          </button>
        </div>
      )}
    </div>
  );
}

/**
 * Safari ignores autoComplete="off" and offers Contacts / AutoFill whenever a field's
 * name, placeholder or label looks like a person's name ("Name", "Actor"...). It does
 * skip fields whose name says "search", so credit boxes get a search-style name plus the
 * opt-outs other password managers read. Our own Nexus-member suggestions still show.
 */
function noAutofill(name: string) {
  return {
    name,
    autoComplete: "off",
    autoCorrect: "off",
    autoCapitalize: "words",
    spellCheck: false,
    "data-1p-ignore": true,
    "data-lpignore": "true",
    "data-form-type": "other",
  } as const;
}

/** A zero-width non-joiner after the first letter keeps Safari's "name" word match from firing; it's invisible and screen readers skip it. */
function noAutofillText(text: string) {
  return text.length > 1 ? `${text[0]}\u200C${text.slice(1)}` : text;
}

/**
 * One credit: a role box and a name box. Typing a name suggests Nexus members; picking
 * one fills in their name and links the credit to their profile. Typing over a picked
 * name unlinks it, so a credit only ever points at the person shown.
 */
export function CreditLine({
  credit,
  index,
  onChange,
  onRemove,
  rolePlaceholder = "Role",
  namePlaceholder = "Name",
  inputClass = "rounded-lg bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-brand",
}: {
  credit: Credit;
  index: number;
  onChange: (patch: Partial<Credit>) => void;
  /** Leave out for a line that can't be removed on its own (e.g. a showcase video's performer). */
  onRemove?: () => void;
  rolePlaceholder?: string;
  namePlaceholder?: string;
  inputClass?: string;
}) {
  const listId = useId();
  const [focused, setFocused] = useState(false);
  const [people, setPeople] = useState<PersonMatch[]>([]);
  const [active, setActive] = useState(0);
  const query = credit.profileID ? "" : credit.name.trim();

  // Look up members a moment after typing stops; an answer for older text is dropped.
  useEffect(() => {
    if (!focused || query.length < 2) return;
    const abort = new AbortController();
    const timer = setTimeout(async () => {
      try {
        const res = await fetch(`/api/people?q=${encodeURIComponent(query)}`, { signal: abort.signal });
        if (!res.ok) return;
        const body = (await res.json()) as { people: PersonMatch[] };
        setPeople(body.people);
        setActive(0);
      } catch {
        // Suggestions are a convenience: the name can always just be typed.
      }
    }, 150);
    return () => {
      clearTimeout(timer);
      abort.abort();
    };
  }, [query, focused]);

  const shown = focused && query.length >= 2 ? people : [];
  const pick = (p: PersonMatch) => {
    onChange({ name: p.name, profileID: p.id });
    setPeople([]);
  };

  return (
    <div>
      <div className="flex items-center gap-2">
        <input
          aria-label={`${rolePlaceholder} ${index + 1}`}
          {...noAutofill(`credit-role-search-${index}`)}
          value={credit.role}
          placeholder={noAutofillText(rolePlaceholder)}
          onChange={(e) => onChange({ role: e.target.value })}
          className={`w-2/5 ${inputClass}`}
        />
        <div className="relative min-w-0 flex-1">
          <input
            role="combobox"
            aria-label={`${noAutofillText(namePlaceholder)} for ${credit.role || `role ${index + 1}`}`}
            aria-expanded={shown.length > 0}
            aria-controls={listId}
            aria-autocomplete="list"
            {...noAutofill(`credit-person-search-${index}`)}
            value={credit.name}
            placeholder={noAutofillText(namePlaceholder)}
            onChange={(e) => onChange({ name: e.target.value, profileID: undefined })}
            onFocus={() => setFocused(true)}
            onBlur={() => setFocused(false)}
            onKeyDown={(e) => {
              if (!shown.length) return;
              if (e.key === "ArrowDown" || e.key === "ArrowUp") {
                e.preventDefault();
                setActive((a) => (a + (e.key === "ArrowDown" ? 1 : shown.length - 1)) % shown.length);
              } else if (e.key === "Enter") {
                e.preventDefault();
                pick(shown[active] ?? shown[0]);
              } else if (e.key === "Escape") {
                setPeople([]);
              }
            }}
            className={`w-full ${credit.profileID ? "pr-8" : ""} ${inputClass}`}
          />
          {credit.profileID && (
            <span title="Linked to their Nexus profile" className="absolute right-2 top-1/2 flex h-4 w-4 -translate-y-1/2 items-center justify-center rounded-full bg-brand text-white">
              <svg viewBox="0 0 12 12" className="h-2.5 w-2.5" aria-hidden>
                <path d="M2.5 6.2 5 8.5l4.5-5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              <span className="sr-only">Linked to their Nexus profile</span>
            </span>
          )}
        </div>
        {onRemove && <RemoveButton label={`Remove ${credit.role || "row"}`} onClick={onRemove} />}
      </div>
      {/* In the flow under the row, not floating: the form's cards clip anything that hangs outside them. */}
      {shown.length > 0 && (
        <ul id={listId} role="listbox" aria-label="Nexus members" className="mt-1 overflow-hidden rounded-lg border border-border bg-background">
          {shown.map((p, i) => (
            <li key={p.id} role="option" aria-selected={i === active}>
              <button
                type="button"
                tabIndex={-1}
                // Before the name box loses focus, so the pick isn't lost to the blur.
                onMouseDown={(e) => {
                  e.preventDefault();
                  pick(p);
                }}
                onMouseEnter={() => setActive(i)}
                className={`flex w-full items-center gap-2.5 px-3 py-2 text-left text-sm ${i === active ? "bg-foreground/10" : ""}`}
              >
                {p.imageUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={p.imageUrl} alt="" loading="lazy" className="h-7 w-7 shrink-0 rounded-full bg-surface object-cover" />
                ) : (
                  <span aria-hidden className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-brand text-[10px] font-semibold text-white">
                    {p.name.split(/\s+/).map((w) => w[0]).slice(0, 2).join("").toUpperCase()}
                  </span>
                )}
                <span className="min-w-0 flex-1 truncate font-medium">{p.name}</span>
                {p.subtitle && <span className="max-w-[45%] truncate text-xs text-muted">{p.subtitle}</span>}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

/** A row that opens a simple list editor — roles still needed, featured work. */
export function ListRow({
  label,
  items,
  onChange,
  placeholder,
  addLabel = "Add",
}: {
  label: string;
  items: string[];
  onChange: (items: string[]) => void;
  placeholder: string;
  addLabel?: string;
}) {
  const [open, setOpen] = useState(false);
  const edited = items.some((i) => i.trim());
  return (
    <div>
      <DisclosureButton label={label} value={edited ? "Edited" : "Add"} open={open} onClick={() => setOpen((o) => !o)} />
      {open && (
        <div className="space-y-2 px-4 pb-3">
          {items.map((item, i) => (
            <div key={i} className="flex items-center gap-2">
              <input
                aria-label={`${placeholder} ${i + 1}`}
                value={item}
                placeholder={placeholder}
                onChange={(e) => onChange(items.map((x, j) => (j === i ? e.target.value : x)))}
                className="min-w-0 flex-1 rounded-lg bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-brand"
              />
              <RemoveButton label={`Remove ${item || "row"}`} onClick={() => onChange(items.filter((_, j) => j !== i))} />
            </div>
          ))}
          <button type="button" onClick={() => onChange([...items, ""])} className="text-sm font-medium text-brand">
            + {addLabel}
          </button>
        </div>
      )}
    </div>
  );
}

/** A row that opens arbitrary fields underneath (streaming links, lyrics, equipment). */
export function DisclosureRow({ label, edited, children }: { label: string; edited: boolean; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  return (
    <div>
      <DisclosureButton label={label} value={edited ? "Edited" : "Add"} open={open} onClick={() => setOpen((o) => !o)} />
      {open && <div className="space-y-2 px-4 pb-3">{children}</div>}
    </div>
  );
}

export function SubField({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1 block text-xs font-medium text-muted">{label}</span>
      {children}
    </label>
  );
}

export const subInput = "w-full rounded-lg bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-brand";

function DisclosureButton({ label, value, open, onClick }: { label: string; value: string; open: boolean; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} aria-expanded={open} className={`${rowBase} w-full text-left`}>
      <span className="text-[15px]">{label}</span>
      <span className="ml-auto text-[15px] text-brand">{value}</span>
      <svg viewBox="0 0 12 12" className={`h-3 w-3 text-brand transition ${open ? "rotate-90" : ""}`} aria-hidden>
        <path d="M4 2l4 4-4 4" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      </svg>
    </button>
  );
}

function RemoveButton({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-lg leading-none text-muted hover:bg-foreground/10 hover:text-foreground"
    >
      ×
    </button>
  );
}

// MARK: - Icons

function ChevronUpDown() {
  return (
    <svg viewBox="0 0 12 16" className="h-3.5 w-2.5 shrink-0 text-brand" aria-hidden>
      <path d="M2 6l4-4 4 4M2 10l4 4 4-4" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function CropIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M6 2v14a2 2 0 0 0 2 2h14" />
      <path d="M18 22V8a2 2 0 0 0-2-2H2" />
    </svg>
  );
}

export function VideoIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden>
      <rect x="3" y="6" width="13" height="12" rx="2" fill="none" stroke="currentColor" strokeWidth="1.6" />
      <path d="M16 10l5-3v10l-5-3z" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
    </svg>
  );
}

export function PhotoIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden>
      <rect x="3" y="5" width="18" height="14" rx="2" fill="none" stroke="currentColor" strokeWidth="1.6" />
      <circle cx="9" cy="10" r="1.6" fill="currentColor" />
      <path d="M4 17l5-5 4 4 3-3 4 4" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
    </svg>
  );
}

export function AudioIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden>
      <path d="M9 18V6l10-2v12" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
      <circle cx="7" cy="18" r="2" fill="none" stroke="currentColor" strokeWidth="1.6" />
      <circle cx="17" cy="16" r="2" fill="none" stroke="currentColor" strokeWidth="1.6" />
    </svg>
  );
}

export function FileIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden>
      <path d="M6 3h8l4 4v14H6z" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
      <path d="M14 3v4h4" fill="none" stroke="currentColor" strokeWidth="1.6" />
    </svg>
  );
}

/**
 * The org or class behind a post: one choice from grouped chips, "Independent", or
 * "Other" with a typed-in name. `value` is the text that gets saved.
 */
export function AffiliationRow({
  label,
  value,
  groups,
  onChange,
}: {
  label: string;
  value: string;
  groups: { title: string; options: readonly string[] }[];
  onChange: (v: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [other, setOther] = useState(false);
  const chip = (text: string, on: boolean, pick: () => void) => (
    <button
      key={text}
      type="button"
      aria-pressed={on}
      onClick={pick}
      className={`rounded-full border px-3 py-1 text-sm transition ${on ? "border-brand bg-brand text-white" : "border-border hover:bg-foreground/5"}`}
    >
      {text}
    </button>
  );
  /** Picks a listed option; picking the selected one again clears it. */
  const choose = (o: string) => {
    setOther(false);
    onChange(!other && value === o ? "" : o);
  };
  return (
    <div>
      <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open} className={`${rowBase} w-full text-left`}>
        <span className="shrink-0 text-[15px]">{label}</span>
        <span className="ml-auto truncate text-[15px] text-brand">{value || (other ? "Other" : "Select")}</span>
        <ChevronUpDown />
      </button>
      {open && (
        <div className="space-y-3 px-4 pb-3">
          {groups.map((g) => (
            <div key={g.title}>
              <p className="mb-1.5 text-xs font-semibold uppercase tracking-wide text-muted">{g.title}</p>
              <div className="flex flex-wrap gap-2">{g.options.map((o) => chip(o, !other && value === o, () => choose(o)))}</div>
            </div>
          ))}
          <div className="flex flex-wrap gap-2">
            {chip("Independent", !other && value === "Independent", () => choose("Independent"))}
            {chip("Other", other, () => {
              setOther(!other);
              onChange("");
            })}
          </div>
          {other && (
            <input
              autoFocus
              aria-label={`Other ${label}`}
              className="w-full rounded-xl bg-background px-4 py-2.5 text-[15px] outline-none ring-1 ring-border placeholder:text-muted focus:ring-brand"
              value={value}
              maxLength={200}
              placeholder="Type the org or class"
              onChange={(e) => onChange(e.target.value)}
            />
          )}
        </div>
      )}
    </div>
  );
}
