/**
 * Contact Us: Firestore queue + SMTP email.
 *
 * App writes to contact_messages (fast). This trigger emails in the background
 * so the user never waits on SMTP and never loses their draft on timeout.
 *
 * Setup:
 * 1. Blaze plan (outbound SMTP)
 * 2. firebase functions:secrets:set SMTP_PASS
 * 3. functions/.env for SMTP_* / CONTACT_TO
 * 4. firebase deploy --only functions
 * 5. Firestore rules: authenticated create on contact_messages
 */

const functions = require("firebase-functions/v1");
const bobShop = require("./bob_shop");
const ewelinkSonoff = require("./ewelink_sonoff");
Object.assign(exports, bobShop);
Object.assign(exports, ewelinkSonoff);
const { defineSecret, defineString } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { FieldValue } = require("firebase-admin/firestore");
const nodemailer = require("nodemailer");
const { FUNCTIONS_REGION } = require("./region");

initializeApp();

const smtpPass = defineSecret("SMTP_PASS");
const smtpHost = defineString("SMTP_HOST", {
  default: "mail.trinityglobal.co.za",
});
const smtpPort = defineString("SMTP_PORT", { default: "465" });
const smtpUser = defineString("SMTP_USER", {
  default: "info@trinityglobal.co.za",
});
const smtpFrom = defineString("SMTP_FROM", {
  default: "info@trinityglobal.co.za",
});
const contactTo = defineString("CONTACT_TO", {
  default: "info@trinityglobal.co.za",
});

async function sendContactEmail({ userName, userEmail, userId, message }) {
  const host = smtpHost.value();
  const port = Number(smtpPort.value() || 465);
  const user = smtpUser.value();
  const pass = smtpPass.value();
  const from = smtpFrom.value();
  const to = contactTo.value();

  if (!pass) {
    throw new Error("SMTP_PASS secret is not configured on the server.");
  }

  const transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass },
  });

  const subject = `Contact Us - ${userName}`;
  const text =
    `Name: ${userName}\n` +
    `Email: ${userEmail}\n` +
    `Firestore User ID: ${userId}\n\n` +
    `Message:\n${message}\n`;

  const html =
    `<p><strong>Name:</strong> ${escapeHtml(userName)}</p>` +
    `<p><strong>Email:</strong> ${escapeHtml(userEmail)}</p>` +
    `<p><strong>Firestore User ID:</strong> ${escapeHtml(userId)}</p>` +
    `<p><strong>Message:</strong></p>` +
    `<p>${escapeHtml(message).replace(/\n/g, "<br>")}</p>`;

  await transporter.sendMail({
    from: `"Limitless IOT" <${from}>`,
    to,
    replyTo: userEmail.includes("@") ? userEmail : undefined,
    subject,
    text,
    html,
  });
}

exports.onContactMessageCreated = functions
  .region(FUNCTIONS_REGION)
  .runWith({
    secrets: [smtpPass],
    timeoutSeconds: 60,
    memory: "256MB",
  })
  .firestore.document("contact_messages/{messageId}")
  .onCreate(async (snap) => {
    const data = snap.data() || {};
    if (data.status === "sent") return;

    const payload = {
      userName:
        String(data.userName || data.displayName || "").trim() ||
        "Unknown user",
      userEmail:
        String(data.userEmail || data.email || "").trim() || "Not provided",
      userId: String(data.userId || "").trim(),
      message: String(data.message || "").trim(),
    };

    if (!payload.message) {
      await snap.ref.update({
        status: "failed",
        error: "Empty message",
        updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }

    try {
      await sendContactEmail(payload);
      await snap.ref.update({
        status: "sent",
        sentAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        error: FieldValue.delete(),
      });
    } catch (err) {
      console.error("onContactMessageCreated SMTP error:", err);
      await snap.ref.update({
        status: "failed",
        error: String(err && err.message ? err.message : err),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
