/**
 * Universal links: lets the Nexus iPhone app open nexusbylac.com/tv links (the QR code on
 * the Apple TV app's sign-in screen). Without the app installed, the link opens the website's
 * /tv page instead. Must match the app's Associated Domains entitlement and bundle ID.
 */
export function GET() {
  return Response.json({
    applinks: {
      details: [
        {
          appIDs: ["SWSR3QZKD9.LAA.Longhorn-Artists-Connect"],
          components: [{ "/": "/tv", comment: "Approve an Apple TV sign-in" }],
        },
      ],
    },
  });
}
