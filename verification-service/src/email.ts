/// Transactional mail via Resend.
///
/// University mail systems are the strictest filters you will meet. The
/// sending domain needs SPF, DKIM and DMARC before this is reliable — see the
/// deliverability section of the README. Plain wording, no images, no tracking
/// pixels and a real text/plain alternative all measurably help here.

import { Env } from "./util";

export async function sendVerificationCode(
    env: Env,
    params: { to: string; code: string; schoolName: string },
): Promise<void> {
    const subject = `${params.code} is your Longhorn Artists Connect code`;

    const text = [
        `Your verification code is ${params.code}`,
        ``,
        `Enter it in Longhorn Artists Connect to confirm your ${params.schoolName} email address.`,
        `The code expires in 10 minutes.`,
        ``,
        `If you didn't request this, you can ignore this email — no account was created.`,
        ``,
        `This mailbox isn't monitored — replies won't reach us.`,
    ].join("\n");

    const html = `
        <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:16px;line-height:1.5;color:#1a1a1a">
          <p>Your verification code is</p>
          <p style="font-size:32px;font-weight:600;letter-spacing:6px;margin:16px 0">${params.code}</p>
          <p>Enter it in Longhorn Artists Connect to confirm your ${escapeHTML(params.schoolName)} email address. The code expires in 10 minutes.</p>
          <p style="color:#666;font-size:14px">If you didn't request this, you can ignore this email — no account was created.</p>
          <p style="color:#999;font-size:12px">This mailbox isn't monitored — replies won't reach us.</p>
        </div>`;

    const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
            authorization: `Bearer ${env.RESEND_API_KEY}`,
            "content-type": "application/json",
        },
        body: JSON.stringify({
            from: `${env.MAIL_FROM_NAME} <${env.MAIL_FROM}>`,
            to: [params.to],
            subject,
            text,
            html,
        }),
    });

    if (!response.ok) {
        const detail = await response.text();
        throw new Error(`Resend ${response.status}: ${detail.slice(0, 300)}`);
    }
}

function escapeHTML(value: string): string {
    return value.replace(/[&<>"']/g, (c) =>
        ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!,
    );
}
