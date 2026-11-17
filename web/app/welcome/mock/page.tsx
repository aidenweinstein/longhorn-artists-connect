import type { Metadata } from "next";
import WelcomeScreen from "../WelcomeScreen";

export const metadata: Metadata = { title: "Mock launch · Nexus" };

/** Mock launch: the launch page as a new visitor sees it, leading into a practice sign-up. */
export default function MockWelcome() {
  return <WelcomeScreen mock />;
}
