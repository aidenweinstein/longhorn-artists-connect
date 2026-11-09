import { notFound } from "next/navigation";
import DesignForm from "@/components/share/forms/DesignForm";
import EventForm from "@/components/share/forms/EventForm";
import FilmForm from "@/components/share/forms/FilmForm";
import MusicForm from "@/components/share/forms/MusicForm";
import PerformanceForm from "@/components/share/forms/PerformanceForm";
import PhotographyForm from "@/components/share/forms/PhotographyForm";
import ProjectForm from "@/components/share/forms/ProjectForm";
import { SHARE_TYPES } from "@/lib/shareTypes";

const FORMS = {
  film: FilmForm,
  music: MusicForm,
  performance: PerformanceForm,
  photography: PhotographyForm,
  design: DesignForm,
  project: ProjectForm,
  event: EventForm,
} as const;

export function generateStaticParams() {
  return SHARE_TYPES.map((t) => ({ type: t.id }));
}

export default async function ShareSubmission(props: PageProps<"/share/[type]">) {
  const { type } = await props.params;
  const Form = FORMS[type as keyof typeof FORMS];
  if (!Form) notFound();
  return <Form />;
}
