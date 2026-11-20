import type { Metadata } from "next";
import WelcomeScreen from "./WelcomeScreen";

// The title Google shows for the site (the welcome page is what it can see).
export const metadata: Metadata = { title: "Nexus by Longhorn Artists Connect" };

export default function Welcome() {
  return <WelcomeScreen />;
}
