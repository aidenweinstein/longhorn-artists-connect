import Link from "next/link";
import { notFound } from "next/navigation";
import { SCRIPTS, findScript } from "@/lib/sampleNow";

export function generateStaticParams() {
  return SCRIPTS.map((s) => ({ id: s.id }));
}

/** Sides laid out like a screenplay page: Courier, centered character cues, indented dialogue. */
export default async function ScriptPage(props: PageProps<"/now/acting/script/[id]">) {
  const { id } = await props.params;
  const script = findScript(id);
  if (!script) notFound();

  return (
    <div className="w-full">
      <Link href="/now" className="text-sm font-semibold hover:underline">
        ← Back to Now
      </Link>
      <div className="mx-auto mt-4 max-w-[46rem] rounded-sm bg-white px-6 py-10 text-[#111] shadow-sm sm:px-16">
        <div className="mb-10 text-center font-mono">
          <p className="text-lg font-bold uppercase">{script.title}</p>
          <p className="mt-1 text-sm">Written by {script.writer}</p>
          <p className="mt-3 text-xs text-[#666]">
            {script.draft} · {script.pages}
          </p>
        </div>
        <div className="font-mono text-[13px] leading-[1.45] sm:text-sm">
          {script.lines.map(([kind, text], i) => {
            switch (kind) {
              case "scene":
                return <p key={i} className="mb-3 mt-6 font-bold uppercase first:mt-0">{text}</p>;
              case "action":
                return <p key={i} className="mb-3">{text}</p>;
              case "character":
                return <p key={i} className="mt-3 pl-[38%] uppercase">{text}</p>;
              case "paren":
                return <p key={i} className="pl-[30%]">{text}</p>;
              case "dialogue":
                return <p key={i} className="mb-3 pl-[20%] pr-[15%]">{text}</p>;
              case "transition":
                return <p key={i} className="my-3 text-right uppercase">{text}</p>;
            }
          })}
        </div>
      </div>
    </div>
  );
}
