"use client";

import { useState } from "react";
import { checkSetup, finishSchoolCheck, startSchoolCheck, type CheckStep } from "@/app/(app)/admin/checks/actions";

type School = { slug: string; name: string; color: string; logo: string };
type Row = { title: string; logo?: string; color?: string; state: "waiting" | "running" | "done"; steps: CheckStep[] };

/** Sends the test file straight to R2 from this browser, the way the Share page sends films. */
async function browserUpload(url: string, body: string): Promise<{ etag: string | null; browserError: string | null }> {
  try {
    const res = await fetch(url, { method: "PUT", body });
    if (!res.ok) return { etag: null, browserError: `R2 refused the upload (${res.status}): ${(await res.text()).slice(0, 200)}` };
    return { etag: res.headers.get("ETag"), browserError: null };
  } catch {
    return {
      etag: null,
      browserError: `The browser blocked the upload. R2 doesn't allow uploads from ${window.location.origin}: add it to the bucket's CORS rule (web/scripts/r2-cors.json), or test on https://nexusbylac.com.`,
    };
  }
}

export default function SystemCheck({ schools }: { schools: School[] }) {
  const [rows, setRows] = useState<Row[]>([]);
  const [running, setRunning] = useState(false);

  const update = (i: number, patch: Partial<Row>) => setRows((all) => all.map((r, n) => (n === i ? { ...r, ...patch } : r)));

  async function run() {
    setRunning(true);
    const initial: Row[] = [
      { title: "Setup", state: "running", steps: [] },
      ...schools.map((s) => ({ title: s.name, logo: s.logo, color: s.color, state: "waiting" as const, steps: [] })),
    ];
    setRows(initial);
    try {
      update(0, { state: "done", steps: await checkSetup() });
      for (const [n, school] of schools.entries()) {
        const i = n + 1;
        update(i, { state: "running" });
        try {
          const started = await startSchoolCheck(school.slug);
          if (!started.ok) {
            // No upload possible: still check saving a post for this school.
            const rest = await finishSchoolCheck(school.slug, null);
            update(i, { state: "done", steps: [...started.steps, ...rest] });
            continue;
          }
          const sent = await browserUpload(started.url, started.body);
          update(i, { state: "done", steps: await finishSchoolCheck(school.slug, { key: started.key, uploadID: started.uploadID, ...sent }) });
        } catch (error) {
          update(i, { state: "done", steps: [{ name: "Run the check", ok: false, detail: error instanceof Error ? error.message : String(error) }] });
        }
      }
    } finally {
      setRunning(false);
    }
  }

  const finished = rows.length > 0 && !running;
  const failures = rows.flatMap((r) => r.steps).filter((s) => !s.ok).length;

  return (
    <div className="mx-auto max-w-3xl space-y-8">
      <header>
        <h1 className="text-3xl font-bold">System check</h1>
        <p className="mt-1 text-muted">
          Runs a real submission for every school: an upload from this browser, saving a post tagged with the school, and reading it back.
          Test posts are hidden from every feed and deleted right after. Only admins can see this page.
        </p>
        <button
          className="mt-4 rounded-full bg-brand px-6 py-2.5 text-sm font-semibold text-white disabled:opacity-50"
          disabled={running}
          onClick={run}
        >
          {running ? "Running…" : rows.length ? "Run again" : "Run check"}
        </button>
        {finished && (
          <p className={`mt-4 rounded-xl p-3 text-sm ${failures ? "bg-red-500/10 text-red-500" : "bg-green-500/10 text-green-600"}`}>
            {failures ? `${failures} step${failures === 1 ? "" : "s"} failed. Details are below.` : "Everything passed. Submitting works for every school."}
          </p>
        )}
      </header>

      {rows.map((row) => (
        <section key={row.title} className="rounded-2xl border border-border p-5">
          <h2 className="flex items-center gap-3 text-lg font-semibold">
            {row.logo && (
              <span className="flex h-8 w-8 items-center justify-center overflow-hidden rounded-full" style={{ background: row.color }}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={row.logo} alt="" className="h-full w-full object-cover" />
              </span>
            )}
            {row.title}
            <span className="ml-auto text-sm font-normal text-muted">
              {row.state === "waiting" ? "Waiting" : row.state === "running" ? "Checking…" : row.steps.every((s) => s.ok) ? "All good" : "Problem found"}
            </span>
          </h2>
          {row.steps.length > 0 && (
            <ul className="mt-3 space-y-2">
              {row.steps.map((step, k) => (
                <li key={k} className="flex gap-3 text-sm">
                  <span className={step.ok ? "text-green-600" : "text-red-500"}>{step.ok ? "✓" : "✗"}</span>
                  <span>
                    <span className="font-medium">{step.name}</span>
                    {step.detail && <span className={`block ${step.ok ? "text-muted" : "text-red-500"}`}>{step.detail}</span>}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
      ))}
    </div>
  );
}
