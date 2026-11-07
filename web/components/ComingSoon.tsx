export default function ComingSoon({ title, body }: { title: string; body: string }) {
  return (
    <div className="mx-auto mt-16 max-w-md rounded-2xl border border-border bg-surface p-10 text-center">
      <h1 className="text-2xl font-bold">{title}</h1>
      <p className="mt-2 text-muted">{body}</p>
    </div>
  );
}
