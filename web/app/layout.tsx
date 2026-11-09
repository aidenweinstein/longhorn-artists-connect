import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import localFont from "next/font/local";
import "./globals.css";
import ScrollToTop from "@/components/ScrollToTop";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

// Pragmatica Extended (licensed). Only Bold so far, used for headings and names.
// To add weights, drop more .woff2 files in app/fonts and list them here.
const pragmatica = localFont({
  src: [{ path: "./fonts/PragmaticaExt-Bold.woff2", weight: "700", style: "normal" }],
  variable: "--font-pragmatica",
  display: "swap",
});

// Site name only: the whole site is private, so no post content in metadata.
export const metadata: Metadata = {
  title: "Nexus",
  description: "Longhorn Artists Connect",
};

// Without this, Safari samples the orange top bar and tints its own toolbar.
// Match the page background instead so the browser chrome stays neutral.
export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#121212" },
  ],
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} ${pragmatica.variable} h-full antialiased`}
    >
      <body className="min-h-full">
        <ScrollToTop />
        {children}
      </body>
    </html>
  );
}

