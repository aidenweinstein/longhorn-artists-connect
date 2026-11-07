"use client";

// Building blocks for the Share forms. They mirror the app's grouped List sections:
// a small header, a rounded card of rows, and an optional footer note. Chosen values
// show in the brand color, like the app's orange menu labels.

import { useEffect, useId, useMemo, useState, type ReactNode } from "react";

const rowBase = "flex min-h-12 items-center gap-3 px-4 py-2.5";
const input = "w-full bg-transparent px-4 py-3 text-[15px] outline-none placeholder:text-muted";

export function Section({ title, footer, children }: { title?: string; footer?: ReactNode; children: ReactNode }) {
  return (
    <section>
      {title && <h3 className="mb-1.5 px-4 font-sans text-xs font-semibold uppercase tracking-wide text-muted">{title}</h3>}
      <div className="divide-y divide-border overflow-hidden rounded-2xl bg-surface">{children}</div>
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

/**
 * Picks one file. Shows "Select <noun>" until chosen, then the file with a remove button.
 * `noun` is lowercase, like the app ("video", "thumbnail", "poster").
 */
export function FileRow({
  noun,
  accept,
  file,
  onChange,
  icon = <FileIcon />,
  optional,
}: {
  noun: string;
  accept: string;
  file: File | null;
  onChange: (f: File | null) => void;
  icon?: ReactNode;
  optional?: boolean;
}) {
  const files = useMemo(() => (file ? [file] : []), [file]);
  const [url] = usePreviews(files);
  return (
    <div className={rowBase}>
      <Thumb file={file ?? undefined} url={url} icon={icon} />
      <div className="min-w-0 flex-1">
        <p className="text-[15px]">
          {file ? `${noun[0].toUpperCase()}${noun.slice(1)} selected` : `Select ${noun}`}
          {optional && !file && <span className="text-muted"> (optional)</span>}
        </p>
        {file && <p className="truncate text-xs text-muted">{file.name} · {formatSize(file.size)}</p>}
      </div>
      {file ? (
        <button type="button" onClick={() => onChange(null)} className="text-sm text-muted hover:text-foreground">
          Remove
        </button>
      ) : (
        <PickButton accept={accept} onPick={(fs) => onChange(fs[0] ?? null)} label={`Choose ${noun}`} />
      )}
    </div>
  );
}

/** Picks several files in order — photos, slides, stills. They can be reordered and removed. */
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
    <div>
      <div className={rowBase}>
        <Thumb icon={icon} />
        <p className="flex-1 text-[15px]">
          {files.length ? `${files.length} ${noun} selected` : `Select ${noun}`}
          {optional && !files.length && <span className="text-muted"> (optional)</span>}
        </p>
        <PickButton accept={accept} multiple onPick={(fs) => onChange([...files, ...fs])} label={files.length ? "Add more" : `Choose ${noun}`} />
      </div>
      {files.length > 0 && (
        <ol className="flex gap-2 overflow-x-auto px-4 pb-3">
          {files.map((f, i) => (
            <li key={`${f.name}-${f.lastModified}-${i}`} className="group relative shrink-0">
              {f.type.startsWith("video/") ? (
                <video src={urls[i]} muted playsInline preload="metadata" className="h-24 w-24 rounded-lg object-cover" />
              ) : (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={urls[i]} alt={f.name} className="h-24 w-24 rounded-lg object-cover" />
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

function PickButton({ accept, multiple, onPick, label }: { accept: string; multiple?: boolean; onPick: (f: File[]) => void; label: string }) {
  return (
    <label className="cursor-pointer rounded-full bg-brand/15 px-3 py-1 text-sm font-medium text-brand hover:bg-brand/25 focus-within:ring-2 focus-within:ring-brand">
      {multiple ? label.replace(/^Choose .*/, "Choose") : "Choose"}
      <input
        type="file"
        accept={accept}
        multiple={multiple}
        aria-label={label}
        className="sr-only"
        onChange={(e) => {
          onPick(Array.from(e.target.files ?? []));
          e.target.value = "";
        }}
      />
    </label>
  );
}

function formatSize(bytes: number) {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)} GB`;
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(1)} MB`;
  return `${Math.max(1, Math.round(bytes / 1e3))} KB`;
}

// MARK: - Credits and lists

export type Credit = { role: string; name: string };

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
            <div key={i} className="flex items-center gap-2">
              <input
                aria-label={`${rolePlaceholder} ${i + 1}`}
                value={c.role}
                placeholder={rolePlaceholder}
                onChange={(e) => update(i, { role: e.target.value })}
                className="w-2/5 rounded-lg bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-brand"
              />
              <input
                aria-label={`${namePlaceholder} for ${c.role || `role ${i + 1}`}`}
                value={c.name}
                placeholder={namePlaceholder}
                onChange={(e) => update(i, { name: e.target.value })}
                className="min-w-0 flex-1 rounded-lg bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-brand"
              />
              <RemoveButton label={`Remove ${c.role || "row"}`} onClick={() => onChange(credits.filter((_, j) => j !== i))} />
            </div>
          ))}
          <button type="button" onClick={() => onChange([...credits, { role: "", name: "" }])} className="text-sm font-medium text-brand">
            + {addLabel}
          </button>
        </div>
      )}
    </div>
  );
}

/** A row that opens a simple list editor — cast names, roles still needed. */
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
