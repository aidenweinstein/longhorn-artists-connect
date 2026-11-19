/** Sign in with Apple settings, safe to import anywhere (no Node APIs). See lib/apple.ts. */

export function appleClientID(): string {
  return process.env.APPLE_WEB_CLIENT_ID?.trim() ?? "";
}

/** True when Sign in with Apple can work here (shows the buttons). */
export function appleEnabled(): boolean {
  return !!appleClientID() && !!process.env.VERIFICATION_URL;
}

/** The return URL registered on the Services ID: APPLE_REDIRECT_URI, else this site's. */
export function appleRedirectURI(origin: string): string {
  return process.env.APPLE_REDIRECT_URI?.trim() || `${origin}/auth/apple/callback`;
}

export function appleAuthorizeURL(origin: string, state: string, nonce: string): string {
  const params = new URLSearchParams({
    client_id: appleClientID(),
    redirect_uri: appleRedirectURI(origin),
    // An id_token straight back, so no client secret is needed. No scopes: Nexus
    // identifies people by their school email, never Apple's email or name.
    response_type: "code id_token",
    response_mode: "form_post",
    state,
    nonce,
  });
  return `https://appleid.apple.com/auth/authorize?${params}`;
}

