import { Suspense, type ReactNode } from "react";
import Sidebar from "@/components/Sidebar";
import TopBar from "@/components/TopBar";
import PortfolioBarActions from "@/components/PortfolioBarActions";
import AccountLink, { AccountPlaceholder } from "@/components/AccountLink";
import SchoolBadge, { SchoolBadgePlaceholder, VisitorOtherSchools } from "@/components/SchoolBadge";
import SchoolTheme from "@/components/SchoolTheme";
import VisitorPages, { VisitorPagesPlaceholder } from "@/components/VisitorPages";

export default function AppLayout({ children }: { children: ReactNode }) {
  return (
    // The window itself never scrolls: only <main> does. With no position: fixed
    // bar at the top of the window, Safari keeps its toolbar the page's neutral
    // background instead of tinting it the school color.
    <div className="flex h-dvh flex-col overflow-hidden">
      {/* Your school's colors on every main page (it needs the session, so it streams in). */}
      <Suspense>
        <SchoolTheme />
      </Suspense>
      <Suspense>
        <TopBar
          portfolioActions={
            <Suspense>
              <PortfolioBarActions />
            </Suspense>
          }
        />
      </Suspense>
      <div className="flex min-h-0 flex-1">
        <Sidebar
          school={
            <Suspense fallback={<SchoolBadgePlaceholder />}>
              <SchoolBadge />
            </Suspense>
          }
          pages={
            // All five main pages when signed in; a guest only gets Home.
            <Suspense fallback={<VisitorPagesPlaceholder />}>
              <VisitorPages />
            </Suspense>
          }
          otherSchools={
            <Suspense>
              <VisitorOtherSchools />
            </Suspense>
          }
          account={
            <Suspense fallback={<AccountPlaceholder />}>
              <AccountLink />
            </Suspense>
          }
        />
        <main id="app-scroll" className="min-w-0 flex-1 overflow-y-auto">
          <div className="px-3 pb-6 pt-3">{children}</div>
        </main>
      </div>
    </div>
  );
}
