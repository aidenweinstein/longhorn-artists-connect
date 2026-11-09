import { Suspense, type ReactNode } from "react";
import Sidebar from "@/components/Sidebar";
import TopBar from "@/components/TopBar";
import AccountLink, { AccountPlaceholder } from "@/components/AccountLink";

export default function AppLayout({ children }: { children: ReactNode }) {
  return (
    // The window itself never scrolls: only <main> does. With no position: fixed
    // bar at the top of the window, Safari keeps its toolbar the page's neutral
    // background instead of tinting it the school color.
    <div className="flex h-dvh flex-col overflow-hidden">
      <Suspense>
        <TopBar />
      </Suspense>
      <div className="flex min-h-0 flex-1">
        <Sidebar
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
