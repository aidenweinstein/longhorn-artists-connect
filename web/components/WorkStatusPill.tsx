import { workStatusDisplay } from "@/lib/workStatus";

/** "● Looking for Work", "● Booked until Dec 12", "● Busy". Renders nothing without a current status. */
export default function WorkStatusPill({ status, className = "" }: { status?: string; className?: string }) {
  const info = workStatusDisplay(status);
  if (!info) return null;
  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-semibold ${info.tone} ${className}`}>
      <span aria-hidden className={`h-1.5 w-1.5 rounded-full ${info.dot}`} />
      {info.label}
    </span>
  );
}
