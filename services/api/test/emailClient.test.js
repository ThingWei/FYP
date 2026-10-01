import test from 'node:test';
import assert from 'node:assert/strict';
import { env } from '../src/config/env.js';
import { createEmailClient } from '../src/integrations/emailClient.js';

test('sends the reset code through a configured Nodemailer SMTP transport', async () => {
  const original = {
    emailMode: env.emailMode,
    emailFrom: env.emailFrom,
    passwordResetSecret: env.passwordResetSecret,
    smtpHost: env.smtpHost,
    smtpPort: env.smtpPort,
    smtpSecure: env.smtpSecure,
    smtpUsername: env.smtpUsername,
    smtpPassword: env.smtpPassword,
  };
  let transportOptions;
  let deliveredMessage;
  env.emailMode = 'smtp';
  env.emailFrom = 'RentHub <sender@example.com>';
  env.passwordResetSecret = 'test-password-reset-secret-32-characters';
  env.smtpHost = 'smtp.example.com';
  env.smtpPort = 587;
  env.smtpSecure = false;
  env.smtpUsername = 'sender@example.com';
  env.smtpPassword = 'app-password';
  const client = createEmailClient({
    smtpTransportFactory: (options) => {
      transportOptions = options;
      return {
        sendMail: async (message) => {
          deliveredMessage = message;
          return { messageId: 'smtp-test' };
        },
      };
    },
  });

  try {
    const result = await client.sendPasswordResetCode({
      email: 'recipient@example.com',
      displayName: 'Aina <Test>',
      code: '482913',
    });

    assert.equal(result.messageId, 'smtp-test');
    assert.deepEqual(transportOptions.auth, {
      user: 'sender@example.com',
      pass: 'app-password',
    });
    assert.equal(transportOptions.requireTLS, true);
    assert.equal(deliveredMessage.from, 'RentHub <sender@example.com>');
    assert.equal(deliveredMessage.to, 'recipient@example.com');
    assert.match(deliveredMessage.text, /482913/);
    assert.match(deliveredMessage.html, /Aina &lt;Test&gt;/);
  } finally {
    Object.assign(env, original);
  }
});
