/**
 * Sign in with Apple, styled per Apple's guidelines for a dark screen: white
 * button, black Apple logo and text. A plain link: `/auth/apple` is a route
 * handler that redirects to Apple, so it must not be prefetched.
 */
export default function AppleSignInButton({ label = "Sign in with Apple" }: { label?: string }) {
  return (
    <a
      href="/auth/apple"
      className="flex w-full items-center justify-center gap-2 rounded-full bg-white px-6 py-3 text-center text-[15px] font-semibold text-black transition hover:bg-white/85"
    >
      <svg aria-hidden viewBox="0 0 24 24" className="h-[18px] w-[18px] -translate-y-px fill-current">
        <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
      </svg>
      {label}
    </a>
  );
}
