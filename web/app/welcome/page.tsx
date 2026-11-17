import type { Metadata } from "next";
import WelcomeScreen from "./WelcomeScreen";

export const metadata: Metadata = { title: "Welcome to Nexus" };

export default function Welcome() {
  return <WelcomeScreen />;
}
