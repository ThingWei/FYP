import nodemailer from 'nodemailer';
import { env } from '../config/env.js';

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function message({ email, displayName, code }) {
  const minutes = env.passwordResetTtlMinutes;
  return {
    from: env.emailFrom,
    to: email,
    subject: 'Your RentHub password reset code',
    text: `Hello ${displayName},\n\nYour RentHub password reset code is ${code}. It expires in ${minutes} minutes.\n\nIf you did not request this, you can ignore this email.`,
    html: `<p>Hello ${escapeHtml(displayName)},</p><p>Your RentHub password reset code is:</p><p style="font-size:28px;font-weight:700;letter-spacing:6px">${code}</p><p>This code expires in ${minutes} minutes.</p><p>If you did not request this, you can ignore this email.</p>`,
  };
}

export function createEmailClient({
  smtpTransportFactory = (options) => nodemailer.createTransport(options),
} = {}) {
  let smtpTransport;
  let smtpTransportSignature;

  function assertConfigured({ passwordReset = true } = {}) {
    if (!['resend', 'smtp'].includes(env.emailMode)) {
      throw new Error('Configure EMAIL_MODE as smtp or resend.');
    }
    if (!env.emailFrom || passwordReset && !env.passwordResetSecret) {
      throw new Error('EMAIL_FROM and PASSWORD_RESET_SECRET are required.');
    }
    if (env.emailMode === 'resend' && !env.resendApiKey) {
      throw new Error('RESEND_API_KEY is required for Resend delivery.');
    }
    if (
      env.emailMode === 'smtp' &&
      (!env.smtpHost || !env.smtpUsername || !env.smtpPassword)
    ) {
      throw new Error(
        'SMTP_HOST, SMTP_USERNAME, and SMTP_PASSWORD are required for SMTP delivery.',
      );
    }
  }

  function getSmtpTransport() {
    const signature = JSON.stringify([
      env.smtpHost,
      env.smtpPort,
      env.smtpSecure,
      env.smtpUsername,
    ]);
    if (!smtpTransport || signature !== smtpTransportSignature) {
      smtpTransport = smtpTransportFactory({
        host: env.smtpHost,
        port: env.smtpPort,
        secure: env.smtpSecure,
        requireTLS: !env.smtpSecure,
        auth: {
          user: env.smtpUsername,
          pass: env.smtpPassword,
        },
        connectionTimeout: 10_000,
        greetingTimeout: 10_000,
        socketTimeout: 15_000,
      });
      smtpTransportSignature = signature;
    }
    return smtpTransport;
  }

  async function sendWithResend(emailMessage) {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        authorization: `Bearer ${env.resendApiKey}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ ...emailMessage, to: [emailMessage.to] }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) {
      let providerMessage = '';
      try {
        const payload = await response.json();
        providerMessage = payload.message ?? payload.name ?? '';
      } catch {
        // The HTTP status remains useful when the provider returns no JSON.
      }
      const error = new Error(
        `Resend returned HTTP ${response.status}${providerMessage ? `: ${providerMessage}` : ''}`,
      );
      error.deliveryOutcome = 'not_sent';
      error.retryable = response.status === 429 || response.status >= 500;
      throw error;
    }
    return response.json();
  }

  return {
    assertConfigured,

    async sendOverdueReminder({ email, displayName, itemTitle, bookingReference, returnDate, owner, followup }) {
      try { assertConfigured({ passwordReset: false }); }
      catch (error) { error.deliveryOutcome = 'not_sent'; throw error; }
      const text = `Hello ${displayName},\n\n${itemTitle} has not been recorded as returned.\nBooking: ${bookingReference}\nReturn date: ${returnDate} (Malaysia)\n\n${owner
        ? 'Message the renter to arrange the return. If the item has not been returned, open the rental in RentHub and select Report item not returned. Keep your handover photos and agreement for review.'
        : 'Please contact the Owner and submit your return through RentHub. New bookings are unavailable while an overdue item remains unreturned. If there is a problem, report an issue in the rental details.'}\n\n${followup ? 'This rental is now at least 24 hours overdue and has been flagged for administrator attention. ' : ''}An administrator can review an issue and any remaining held deposit; this does not guarantee compensation.\n\nOpen RentHub and go to your booking details.`;
      const emailMessage = { from: env.emailFrom, to: email,
        subject: followup ? 'RentHub: overdue return needs attention' : 'RentHub: item return overdue',
        text, html: `<p>${escapeHtml(text).replaceAll('\n', '<br>')}</p>` };
      return env.emailMode === 'smtp' ? getSmtpTransport().sendMail(emailMessage) : sendWithResend(emailMessage);
    },

    async sendPasswordResetCode(input) {
      assertConfigured();
      const emailMessage = message(input);
      if (env.emailMode === 'smtp') {
        return getSmtpTransport().sendMail(emailMessage);
      }
      return sendWithResend(emailMessage);
    },
  };
}

export const emailClient = createEmailClient();
