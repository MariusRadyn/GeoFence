/**
 * PayFast (payments) + Bob Go (shipping) for the Limitless shop.
 *
 * PayFast (.env):
 *   PAYFAST_MERCHANT_ID=
 *   PAYFAST_MERCHANT_KEY=
 *   PAYFAST_PASSPHRASE=          (optional but recommended)
 *   PAYFAST_SANDBOX=true
 *
 * Bob Go shipping (optional until token is ready):
 *   BOB_GO_API_TOKEN=
 *   BOB_GO_SANDBOX=true
 *   BOB_COLLECTION_*  (pickup address)
 */

const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const { defineString } = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { FUNCTIONS_REGION } = require("./region");

const payfastMerchantId = defineString("PAYFAST_MERCHANT_ID", { default: "" });
const payfastMerchantKey = defineString("PAYFAST_MERCHANT_KEY", { default: "" });
const payfastPassphrase = defineString("PAYFAST_PASSPHRASE", { default: "" });
const payfastSandbox = defineString("PAYFAST_SANDBOX", { default: "true" });

const bobGoApiToken = defineString("BOB_GO_API_TOKEN", { default: "" });
const bobGoSandbox = defineString("BOB_GO_SANDBOX", { default: "true" });
const shopReturnUrl = defineString("SHOP_RETURN_URL", {
  default: "https://limitless-iot-17e8f.web.app/shop-payment.html",
});
const shopCancelUrl = defineString("SHOP_CANCEL_URL", {
  default: "https://limitless-iot-17e8f.web.app/shop-payment.html?status=cancelled",
});
const collectionStreet = defineString("BOB_COLLECTION_STREET", {
  default: "46 Pope Ellis Dr",
});
const collectionSuburb = defineString("BOB_COLLECTION_SUBURB", {
  default: "Ashburton",
});
const collectionCity = defineString("BOB_COLLECTION_CITY", {
  default: "Pietermaritzburg",
});
const collectionCode = defineString("BOB_COLLECTION_CODE", { default: "3201" });
const collectionName = defineString("BOB_COLLECTION_NAME", {
  default: "Trinity Global",
});
const collectionPhone = defineString("BOB_COLLECTION_PHONE", {
  default: "0330000000",
});
const collectionEmail = defineString("BOB_COLLECTION_EMAIL", {
  default: "info@trinityglobal.co.za",
});
const shopDomain = defineString("SHOP_DOMAIN", {
  default: "limitless-iot-17e8f.web.app",
});

function db() {
  return getFirestore();
}

function isTrue(value) {
  return String(value || "").toLowerCase() === "true";
}

function payfastProcessUrl() {
  return isTrue(payfastSandbox.value())
    ? "https://sandbox.payfast.co.za/eng/process"
    : "https://www.payfast.co.za/eng/process";
}

function bobGoBase() {
  return isTrue(bobGoSandbox.value())
    ? "https://api.sandbox.bobgo.co.za/v2"
    : "https://api.bobgo.co.za/v2";
}

function webhookUrl(name) {
  return `https://${FUNCTIONS_REGION}-limitless-iot-17e8f.cloudfunctions.net/${name}`;
}

function requirePayfastCredentials({ forSubscription = false } = {}) {
  const merchantId = String(payfastMerchantId.value() || "").trim();
  const merchantKey = String(payfastMerchantKey.value() || "").trim();
  const passphrase = String(payfastPassphrase.value() || "").trim();
  if (!merchantId || !merchantKey) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "PayFast is not configured. Set PAYFAST_MERCHANT_ID and PAYFAST_MERCHANT_KEY in functions/.env.",
    );
  }
  if (forSubscription && !passphrase) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "PayFast subscriptions require PAYFAST_PASSPHRASE (set the same passphrase in your PayFast account).",
    );
  }
  return { merchantId, merchantKey, passphrase };
}

/** PHP-compatible urlencode (spaces as +, hex upper-case, encodes !~*'()). */
function phpUrlEncode(value) {
  return encodeURIComponent(String(value))
    .replace(/%20/g, "+")
    .replace(/[!'()*~]/g, (c) => {
      const hex = c.charCodeAt(0).toString(16).toUpperCase();
      return `%${hex.padStart(2, "0")}`;
    })
    .replace(/%[0-9a-f]{2}/gi, (m) => m.toUpperCase());
}

/**
 * PayFast checkout / ITN signature.
 * Uses submission order (Object insertion order / posted order) — not alphabetical.
 */
function payfastSignature(data, passphrase) {
  const pairs = [];
  for (const [key, value] of Object.entries(data)) {
    if (key === "signature") continue;
    if (value === undefined || value === null) continue;
    const str = String(value).trim();
    // Keep "0" (e.g. cycles=0 for indefinite subscriptions).
    if (str === "") continue;
    pairs.push(`${key}=${phpUrlEncode(str)}`);
  }
  let paramString = pairs.join("&");
  if (passphrase) {
    paramString += `&passphrase=${phpUrlEncode(String(passphrase).trim())}`;
  }
  return crypto.createHash("md5").update(paramString).digest("hex");
}

function payfastSignatureFromOrdered(orderedPairs, passphrase) {
  const data = {};
  for (const [key, value] of orderedPairs) {
    if (key === "signature") continue;
    data[key] = value;
  }
  return payfastSignature(data, passphrase);
}

function getPayfastRawBody(req) {
  if (Buffer.isBuffer(req.rawBody)) return req.rawBody.toString("utf8");
  if (typeof req.rawBody === "string") return req.rawBody;
  if (typeof req.body === "string") return req.body;
  if (req.body && typeof req.body === "object" && !Buffer.isBuffer(req.body)) {
    const params = new URLSearchParams();
    for (const [k, v] of Object.entries(req.body)) {
      if (v === undefined || v === null) continue;
      params.append(k, Array.isArray(v) ? String(v[0]) : String(v));
    }
    return params.toString();
  }
  return "";
}

function parsePayfastOrdered(raw) {
  const params = new URLSearchParams(raw || "");
  const ordered = [];
  const map = {};
  for (const [k, v] of params.entries()) {
    ordered.push([k, v]);
    map[k] = v;
  }
  return { ordered, map };
}

/** PayFast sometimes posts ITNs as multipart/form-data (not urlencoded). */
function parseMultipartFormData(raw, contentType) {
  const m = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(String(contentType || ""));
  const boundary = ((m && (m[1] || m[2])) || "").trim();
  if (!boundary || !raw) return { ordered: [], map: {} };

  const ordered = [];
  const map = {};
  const parts = String(raw).split(`--${boundary}`);
  for (const part of parts) {
    if (!part || part === "--" || part.trim() === "--") continue;
    let chunk = part;
    if (chunk.startsWith("\r\n")) chunk = chunk.slice(2);
    if (chunk.endsWith("\r\n")) chunk = chunk.slice(0, -2);
    if (chunk === "--" || chunk.startsWith("--")) continue;

    const sep = chunk.indexOf("\r\n\r\n");
    if (sep < 0) continue;
    const header = chunk.slice(0, sep);
    let value = chunk.slice(sep + 4);
    if (value.endsWith("\r\n")) value = value.slice(0, -2);

    const nameMatch = /Content-Disposition:\s*form-data;\s*name="([^"]+)"/i.exec(
      header,
    );
    if (!nameMatch) continue;
    const name = nameMatch[1];
    ordered.push([name, value]);
    map[name] = value;
  }
  return { ordered, map };
}

function parsePayfastRequest(req) {
  const contentType = String(
    req.get?.("content-type") || req.headers?.["content-type"] || "",
  );
  const raw = Buffer.isBuffer(req.rawBody)
    ? req.rawBody.toString("utf8")
    : typeof req.rawBody === "string"
      ? req.rawBody
      : typeof req.body === "string"
        ? req.body
        : "";

  if (contentType.includes("multipart/form-data") && raw) {
    const parsed = parseMultipartFormData(raw, contentType);
    if (parsed.ordered.length) {
      return { ...parsed, raw, contentType };
    }
  }

  if (raw && !contentType.includes("multipart/form-data")) {
    const parsed = parsePayfastOrdered(raw);
    if (parsed.ordered.length) {
      return { ...parsed, raw, contentType };
    }
  }

  // Framework-parsed body fallback (multipart or JSON-ish object).
  if (req.body && typeof req.body === "object" && !Buffer.isBuffer(req.body)) {
    const ordered = [];
    const map = {};
    for (const [k, v] of Object.entries(req.body)) {
      if (v === undefined || v === null) continue;
      const str = Array.isArray(v) ? String(v[0]) : String(v);
      ordered.push([k, str]);
      map[k] = str;
    }
    return { ordered, map, raw: raw || getPayfastRawBody(req), contentType };
  }

  return { ordered: [], map: {}, raw: raw || "", contentType };
}

function orderedToUrlEncoded(ordered) {
  return ordered
    .map(([k, v]) => `${phpUrlEncode(k)}=${phpUrlEncode(String(v))}`)
    .join("&");
}

async function payfastServerValidate(rawBody, contentType, ordered) {
  const host = isTrue(payfastSandbox.value())
    ? "sandbox.payfast.co.za"
    : "www.payfast.co.za";
  const url = `https://${host}/eng/query/validate`;

  const attempts = [];
  if (rawBody) {
    attempts.push({
      body: rawBody,
      headers: {
        "Content-Type":
          contentType && contentType.includes("multipart/")
            ? contentType
            : "application/x-www-form-urlencoded",
      },
    });
  }
  if (ordered && ordered.length) {
    attempts.push({
      body: orderedToUrlEncoded(ordered),
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
    });
  }

  for (const attempt of attempts) {
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: attempt.headers,
        body: attempt.body,
      });
      const text = (await res.text()).trim().toUpperCase();
      if (text === "VALID") return true;
      console.warn("PayFast validate response", text.slice(0, 120));
    } catch (err) {
      console.error("PayFast validate call failed", err);
    }
  }
  return false;
}

function addMonthsYmd(monthsAhead) {
  const d = new Date();
  d.setMonth(d.getMonth() + monthsAhead);
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function collectionAddress() {
  return {
    company: collectionName.value(),
    street_address: collectionStreet.value(),
    local_area: collectionSuburb.value(),
    suburb: collectionSuburb.value(),
    city: collectionCity.value(),
    zone: collectionCity.value(),
    country: "ZA",
    code: collectionCode.value(),
  };
}

function destinationAddress(dest) {
  const street = String(dest.street || dest.street_address || "").trim();
  const suburb = String(dest.suburb || dest.local_area || "").trim();
  const city = String(dest.city || "").trim();
  const code = String(dest.postalCode || dest.code || "").trim();
  return {
    street_address: street,
    local_area: suburb || city,
    suburb,
    city: city || suburb,
    zone: city || suburb,
    country: "ZA",
    code,
  };
}

function asNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function jsonError(res) {
  try {
    return res.json();
  } catch (_) {
    return res.text().then((t) => ({ raw: t }));
  }
}

async function bobGoRequest(path, { method = "POST", body } = {}) {
  const token = bobGoApiToken.value();
  if (!token) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "BOB_GO_API_TOKEN is not set. Create an API key in Bob Go (Settings → API keys).",
    );
  }
  const res = await fetch(`${bobGoBase()}/${path.replace(/^\//, "")}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await jsonError(res);
  if (!res.ok) {
    const message =
      (data && (data.message || data.detail || data.error)) ||
      `Bob Go ${res.status}`;
    throw new functions.https.HttpsError("unknown", String(message));
  }
  return data;
}

function extractRates(response) {
  if (Array.isArray(response)) return response;
  if (!response || typeof response !== "object") return [];
  for (const key of ["rates", "data", "results", "checkout_rates"]) {
    if (Array.isArray(response[key])) return response[key];
  }
  const requests = response.provider_rate_requests || [];
  const rates = [];
  for (const req of requests) {
    if (req.status && req.status !== "success") continue;
    for (const item of req.responses || []) {
      rates.push({
        ...item,
        provider_slug: req.provider_slug,
        provider_name: req.provider_name,
      });
    }
  }
  return rates;
}

function normalizeRate(rate, index) {
  const level = rate.service_level || {};
  const amount = asNumber(
    rate.total_price ?? rate.rate ?? rate.rate_amount ?? rate.amount ?? rate.price,
  );
  return {
    id:
      String(rate.id || rate.service_code || rate.service_level_code || index),
    name:
      rate.service_name ||
      level.name ||
      rate.provider_name ||
      rate.courier_name ||
      "Delivery",
    description: rate.description || rate.service_level_name || "",
    amount,
    currency: rate.currency || "ZAR",
    eta: rate.delivery_date || rate.estimated_delivery || rate.eta || "",
    providerSlug: rate.provider_slug || "",
    serviceLevelCode: rate.service_level_code || "",
  };
}

function parcelFromItem(item) {
  return {
    description: String(item.name || "Parcel"),
    submitted_length_cm: asNumber(item.lengthCm, 20),
    submitted_width_cm: asNumber(item.widthCm, 15),
    submitted_height_cm: asNumber(item.heightCm, 10),
    submitted_weight_kg: asNumber(item.weightKg, 1),
    custom_parcel_reference: String(item.productId || item.name || ""),
  };
}

exports.getBobGoRates = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
    }
    const dest = destinationAddress(data.destination || {});
    if (!dest.street_address || !dest.code) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Street address and postal code are required for shipping rates.",
      );
    }
    const items = Array.isArray(data.items) ? data.items : [];
    const parcels = items.flatMap((item) => {
      const qty = Math.max(1, Math.floor(asNumber(item.quantity, 1)));
      return Array.from({ length: qty }, () => parcelFromItem(item));
    });
    const cartTotal = asNumber(data.cartTotal);
    const origin = collectionAddress();
    const checkoutBody = {
      domain: shopDomain.value(),
      cart_total: cartTotal,
      currency: "ZAR",
      origin,
      destination: dest,
      items: items.map((item) => ({
        name: item.name,
        quantity: asNumber(item.quantity, 1),
        price: asNumber(item.price),
        weight: asNumber(item.weightKg, 1),
        length: asNumber(item.lengthCm, 20),
        width: asNumber(item.widthCm, 15),
        height: asNumber(item.heightCm, 10),
      })),
    };
    const ratesBody = {
      collection_address: origin,
      delivery_address: dest,
      parcels,
      collection_contact_full_name: collectionName.value(),
      collection_contact_mobile_number: collectionPhone.value(),
      collection_contact_email: collectionEmail.value(),
      delivery_contact_full_name: String(data.fullName || context.auth.token.name || ""),
      delivery_contact_mobile_number: String(data.phone || ""),
      delivery_contact_email: String(data.email || context.auth.token.email || ""),
      declared_value: cartTotal,
      timeout: 10000,
    };

    let raw = [];
    const attempts = [
      ["rates-at-checkout", checkoutBody],
      ["checkout-rates", checkoutBody],
      ["rates", ratesBody],
    ];
    let lastError = "";
    for (const [path, body] of attempts) {
      try {
        const response = await bobGoRequest(path, { body });
        raw = extractRates(response);
        if (raw.length) break;
      } catch (err) {
        lastError = err.message || String(err);
      }
    }
    if (!raw.length && lastError) {
      throw new functions.https.HttpsError(
        "unavailable",
        lastError || "No Bob Go shipping rates returned for this address.",
      );
    }
    return { rates: raw.map(normalizeRate) };
  });

function splitName(fullName) {
  const parts = String(fullName || "").trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return { first: "Customer", last: "" };
  if (parts.length === 1) return { first: parts[0], last: "" };
  return { first: parts[0], last: parts.slice(1).join(" ") };
}

function buildPayfastFields({ order, orderId, uid, customer }) {
  const monthly = asNumber(order.subscriptionMonthly);
  const oneTime = asNumber(order.total);
  const amount = oneTime > 0 ? oneTime : monthly;
  const { merchantId, merchantKey, passphrase } = requirePayfastCredentials({
    forSubscription: monthly > 0,
  });
  const names = splitName(customer.fullName || "");
  const email = String(customer.email || "").trim();
  const returnUrl = `${shopReturnUrl.value()}?orderId=${encodeURIComponent(orderId)}`;
  const notifyUrl = webhookUrl("onPayfastNotify");

  // Field order matters for the signature.
  const fields = {
    merchant_id: merchantId,
    merchant_key: merchantKey,
    return_url: returnUrl,
    cancel_url: shopCancelUrl.value(),
    notify_url: notifyUrl,
    name_first: names.first.slice(0, 100),
    name_last: names.last.slice(0, 100),
    email_address: email.slice(0, 100),
    m_payment_id: orderId.slice(0, 100),
    amount: amount.toFixed(2),
    item_name: `Limitless IOT order ${orderId.slice(0, 20)}`.slice(0, 100),
    custom_str1: uid.slice(0, 255),
    custom_str2: orderId.slice(0, 255),
  };
  if (!fields.name_last) delete fields.name_last;
  if (!fields.email_address) delete fields.email_address;

  if (monthly > 0) {
    // PayFast recurring subscription (monthly, indefinite).
    const sub = order.subscription && typeof order.subscription === "object"
      ? order.subscription
      : {};
    const billingDate =
      String(sub.firstChargeDate || "").trim() || addMonthsYmd(1);
    fields.subscription_type = "1";
    fields.billing_date = billingDate;
    fields.recurring_amount = monthly.toFixed(2);
    fields.frequency = "3"; // monthly
    fields.cycles = "0"; // indefinite

    // Prefer subscriber details collected on the Subscribe screen.
    const subFirst = String(sub.firstName || "").trim();
    const subLast = String(sub.lastName || "").trim();
    const subEmail = String(sub.email || "").trim();
    if (subFirst) fields.name_first = subFirst.slice(0, 100);
    if (subLast) fields.name_last = subLast.slice(0, 100);
    else if (!fields.name_last) delete fields.name_last;
    if (subEmail) fields.email_address = subEmail.slice(0, 100);
  }

  fields.signature = payfastSignature(fields, passphrase || null);
  return fields;
}

exports.createPayfastCheckout = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
    }
    const orderId = String(data.orderId || "").trim();
    if (!orderId) {
      throw new functions.https.HttpsError("invalid-argument", "orderId is required.");
    }
    const uid = context.auth.uid;
    const orderRef = db()
      .collection("users")
      .doc(uid)
      .collection("shop_orders")
      .doc(orderId);
    const snap = await orderRef.get();
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", "Order not found.");
    }
    const order = snap.data() || {};
    if (order.status && order.status !== "pending_payment") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "This order is not awaiting payment.",
      );
    }
    const monthly = asNumber(order.subscriptionMonthly);
    const amount = asNumber(order.total);
    if (amount <= 0 && monthly <= 0) {
      throw new functions.https.HttpsError("invalid-argument", "Order total is invalid.");
    }
    requirePayfastCredentials({ forSubscription: monthly > 0 });

    await orderRef.set(
      {
        paymentProvider: "payfast",
        paymentStatus: "redirected",
        hasSubscription: monthly > 0,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await db().collection("shop_orders_index").doc(orderId).set({
      userId: uid,
      orderId,
      paymentProvider: "payfast",
      hasSubscription: monthly > 0,
      subscriptionMonthly: monthly,
      updatedAt: FieldValue.serverTimestamp(),
    });

    const checkoutUrl =
      `${webhookUrl("payfastStart")}?orderId=${encodeURIComponent(orderId)}&uid=${encodeURIComponent(uid)}`;
    return { checkoutUrl };
  });

exports.payfastStart = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onRequest(async (req, res) => {
    try {
      const orderId = String(req.query.orderId || "").trim();
      const uid = String(req.query.uid || "").trim();
      if (!orderId || !uid) {
        res.status(400).send("Missing orderId or uid.");
        return;
      }
      const orderRef = db()
        .collection("users")
        .doc(uid)
        .collection("shop_orders")
        .doc(orderId);
      const snap = await orderRef.get();
      if (!snap.exists) {
        res.status(404).send("Order not found.");
        return;
      }
      const order = snap.data() || {};
      if (order.status && order.status !== "pending_payment") {
        res.status(400).send("This order is not awaiting payment.");
        return;
      }
      const customer = {
        ...(order.shipping || {}),
        email: (order.shipping && order.shipping.email) || order.email || "",
      };
      const fields = buildPayfastFields({ order, orderId, uid, customer });
      const action = payfastProcessUrl();
      const inputs = Object.entries(fields)
        .map(
          ([k, v]) =>
            `<input type="hidden" name="${k}" value="${String(v)
              .replace(/&/g, "&amp;")
              .replace(/"/g, "&quot;")
              .replace(/</g, "&lt;")}" />`,
        )
        .join("\n");
      res
        .status(200)
        .set("Content-Type", "text/html; charset=utf-8")
        .send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Redirecting to payment…</title>
<style>
body{font-family:system-ui,sans-serif;background:#021824;color:#fff;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px;}
.card{max-width:420px;background:#15273f;border-radius:16px;padding:24px;line-height:1.45;border:2px solid #0480f6;}
</style></head>
<body><div class="card"><h2>Redirecting to payment…</h2>
<p>If nothing happens, tap the button below.</p>
<form id="pf" action="${action}" method="post">${inputs}
<button type="submit" style="margin-top:12px;padding:10px 16px;border:0;border-radius:8px;background:#ff9800;color:#fff;font-weight:600;">Continue</button>
</form></div>
<script>document.getElementById('pf').submit();</script>
</body></html>`);
    } catch (err) {
      console.error("payfastStart", err);
      res.status(500).send(String(err.message || err));
    }
  });

function payfastApiTimestamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  // Match PHP date("Y-m-d\\TH:i:sO") used by the PayFast SDK (+0000 style).
  return (
    `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}` +
    `T${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}+0000`
  );
}

/** API auth signature (headers + body + query + passphrase). Excludes testing. */
function payfastApiSignature(data, passphrase) {
  const payload = { ...data };
  if (passphrase) payload.passphrase = passphrase;
  const keys = Object.keys(payload)
    .filter((k) => {
      if (k === "signature" || k === "testing") return false;
      const v = payload[k];
      return v !== undefined && v !== null && String(v).trim() !== "";
    })
    .sort();
  const paramString = keys
    .map((k) => {
      const encoded = encodeURIComponent(String(payload[k]).trim()).replace(
        /%20/g,
        "+",
      );
      return `${k}=${encoded}`;
    })
    .join("&");
  return crypto.createHash("md5").update(paramString).digest("hex");
}

async function cancelPayfastSubscriptionToken(token) {
  const { merchantId, passphrase } = requirePayfastCredentials({
    forSubscription: true,
  });
  const timestamp = payfastApiTimestamp();
  const headersBase = {
    "merchant-id": merchantId,
    version: "v1",
    timestamp,
  };
  const signature = payfastApiSignature(headersBase, passphrase);
  const url = new URL(
    `https://api.payfast.co.za/subscriptions/${encodeURIComponent(token)}/cancel`,
  );
  if (isTrue(payfastSandbox.value())) {
    url.searchParams.set("testing", "true");
  }
  const res = await fetch(url.toString(), {
    method: "PUT",
    headers: {
      ...headersBase,
      signature,
    },
  });
  const text = await res.text();
  let parsed = null;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch (_) {
    parsed = null;
  }
  if (!res.ok) {
    const msg =
      (parsed && (parsed.status || parsed.data?.message)) ||
      text ||
      `PayFast cancel failed (${res.status})`;
    throw new functions.https.HttpsError("failed-precondition", String(msg));
  }
  return parsed || { ok: true };
}

async function unlinkWheelsForSubscription(uid, orderId) {
  const oid = String(orderId || "").trim();
  if (!uid || !oid) return 0;
  const basesSnap = await db()
    .collection("users")
    .doc(uid)
    .collection("baseStations")
    .get();
  let cleared = 0;
  for (const baseDoc of basesSnap.docs) {
    const monsSnap = await baseDoc.ref.collection("monitors").get();
    for (const monDoc of monsSnap.docs) {
      const data = monDoc.data() || {};
      if (String(data.subscriptionOrderId || "").trim() !== oid) continue;
      await monDoc.ref.set(
        {
          subscriptionOrderId: "",
          subscriptionToken: "",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      cleared += 1;
    }
  }
  return cleared;
}

async function markOrderPaidAndShip({ orderId, userId, paymentId, payload }) {
  const indexSnap = await db().collection("shop_orders_index").doc(orderId).get();
  const uid = userId || (indexSnap.exists ? indexSnap.data().userId : "");
  if (!uid) {
    console.error("PayFast notify: no user for order", orderId);
    return;
  }
  const orderRef = db()
    .collection("users")
    .doc(uid)
    .collection("shop_orders")
    .doc(orderId);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) return;
  const order = orderSnap.data() || {};
  const token = String(payload.token || order.payfastToken || order.subscriptionToken || "");
  const paymentStatus = String(payload.payment_status || "").toUpperCase();

  if (order.status === "paid" || order.status === "shipped") {
    const updates = {};
    if (token && !order.subscriptionToken) {
      updates.payfastToken = token;
      updates.subscriptionToken = token;
      updates.hasSubscription = true;
      if (order.subscriptionStatus !== "cancelled") {
        updates.subscriptionStatus = "active";
      }
    }
    if (paymentStatus === "CANCELLED") {
      updates.subscriptionStatus = "cancelled";
      updates.subscriptionCancelledAt = FieldValue.serverTimestamp();
    }
    if (Object.keys(updates).length) {
      updates.updatedAt = FieldValue.serverTimestamp();
      await orderRef.set(updates, { merge: true });
      await db()
        .collection("shop_orders_index")
        .doc(orderId)
        .set(
          {
            hasSubscription: true,
            subscriptionToken: token || order.subscriptionToken || "",
            subscriptionStatus: updates.subscriptionStatus || order.subscriptionStatus || "",
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      if (paymentStatus === "CANCELLED") {
        await unlinkWheelsForSubscription(uid, orderId);
      }
    }
    return;
  }

  await orderRef.set(
    {
      status: "paid",
      paymentProvider: "payfast",
      paymentIntentId: paymentId || order.paymentIntentId || "",
      payfastToken: token,
      subscriptionToken: token,
      hasSubscription: asNumber(order.subscriptionMonthly) > 0 || !!token || !!order.hasSubscription,
      subscriptionStatus: token ? "active" : order.subscriptionStatus || "",
      paidAt: FieldValue.serverTimestamp(),
      paymentWebhook: payload,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  await db()
    .collection("shop_orders_index")
    .doc(orderId)
    .set(
      {
        userId: uid,
        orderId,
        status: "paid",
        shipping: order.shipping || {},
        items: Array.isArray(order.items) ? order.items : [],
        subtotal: asNumber(order.subtotal),
        total: asNumber(order.total),
        shippingAmount: asNumber(order.shippingAmount),
        email: order.email || (order.shipping && order.shipping.email) || "",
        hasSubscription: asNumber(order.subscriptionMonthly) > 0 || !!token,
        subscriptionToken: token,
        subscriptionStatus: token ? "active" : "",
        subscriptionMonthly: asNumber(order.subscriptionMonthly),
        createdAt: order.createdAt || FieldValue.serverTimestamp(),
        paidAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  try {
    await createShipmentForOrder(orderRef, { ...order, status: "paid" }, orderId);
  } catch (err) {
    console.error("Bob Go shipment after payment failed:", err);
    await orderRef.set(
      {
        shippingError: String(err.message || err),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}

async function createShipmentForOrder(orderRef, order, orderId) {
  const token = bobGoApiToken.value();
  if (!token) return;
  if (order.bobGoShipmentId) return;
  const shipping = order.shipping || {};
  const dest = destinationAddress(shipping);
  if (!dest.street_address || !dest.code) return;
  const items = Array.isArray(order.items) ? order.items : [];
  const parcels = items.flatMap((item) => {
    const qty = Math.max(1, Math.floor(asNumber(item.quantity, 1)));
    return Array.from({ length: qty }, () =>
      parcelFromItem({
        name: item.name,
        productId: item.productId,
        weightKg: item.weightKg,
        lengthCm: item.lengthCm,
        widthCm: item.widthCm,
        heightCm: item.heightCm,
      }),
    );
  });
  const rate = order.shippingRate || {};
  const body = {
    collection_address: collectionAddress(),
    collection_contact_name: collectionName.value(),
    collection_contact_mobile_number: collectionPhone.value(),
    collection_contact_email: collectionEmail.value(),
    delivery_address: dest,
    delivery_contact_name: shipping.fullName || "",
    delivery_contact_mobile_number: shipping.phone || "",
    delivery_contact_email: shipping.email || "",
    parcels,
    declared_value: asNumber(order.subtotal, asNumber(order.total)),
    custom_tracking_reference: orderId,
    custom_order_number: orderId,
    service_level_code: rate.serviceLevelCode || undefined,
    provider_slug: rate.providerSlug || undefined,
  };
  const response = await bobGoRequest("shipments", { body });
  await orderRef.set(
    {
      shippingProvider: "bob_go",
      bobGoShipmentId: String(response.id || ""),
      trackingReference: response.tracking_reference || "",
      trackingUrl: response.tracking_url || "",
      shippingStatus: response.status || response.submission_status || "submitted",
      shippingError: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function parsePayfastBody(req) {
  return parsePayfastRequest(req).map;
}

exports.onPayfastNotify = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") {
        res.status(405).send("Method not allowed");
        return;
      }
      const {
        ordered,
        map: body,
        raw,
        contentType,
      } = parsePayfastRequest(req);
      const { passphrase } = requirePayfastCredentials();
      const receivedSig = String(body.signature || "");
      const expected = payfastSignatureFromOrdered(ordered, passphrase || null);
      let valid =
        !!receivedSig &&
        receivedSig.toLowerCase() === expected.toLowerCase();

      // Fallback: ask PayFast to confirm the ITN payload (handles encoding edge cases).
      if (!valid && (raw || ordered.length)) {
        valid = await payfastServerValidate(raw, contentType, ordered);
        if (valid) {
          console.warn(
            "PayFast local signature mismatched; accepted via server validate",
            { receivedSig, expected, fieldCount: ordered.length },
          );
        }
      }

      if (!valid) {
        console.error("PayFast signature mismatch", {
          receivedSig,
          expected,
          keys: ordered.map(([k]) => k),
          hasPassphrase: !!passphrase,
          sandbox: isTrue(payfastSandbox.value()),
          contentType,
          fieldCount: ordered.length,
        });
        res.status(400).send("Bad signature");
        return;
      }

      const paymentStatus = String(body.payment_status || "").toUpperCase();
      const orderId = String(body.m_payment_id || body.custom_str2 || "").trim();
      const userId = String(body.custom_str1 || "").trim();
      const paymentId = String(body.pf_payment_id || "").trim();

      if (paymentStatus === "COMPLETE" && orderId) {
        const indexSnap = await db().collection("shop_orders_index").doc(orderId).get();
        const uid = userId || (indexSnap.exists ? indexSnap.data().userId : "");
        if (uid) {
          const orderSnap = await db()
            .collection("users")
            .doc(uid)
            .collection("shop_orders")
            .doc(orderId)
            .get();
          if (orderSnap.exists) {
            const orderData = orderSnap.data() || {};
            const alreadyPaid =
              orderData.status === "paid" || orderData.status === "shipped";
            // Recurring subscription charges may differ from the original cart total.
            if (!alreadyPaid) {
              const expectedAmount = asNumber(orderData.total).toFixed(2);
              const paidAmount = asNumber(body.amount_gross).toFixed(2);
              if (expectedAmount !== paidAmount) {
                console.error("PayFast amount mismatch", {
                  orderId,
                  expectedAmount,
                  paidAmount,
                });
                res.status(400).send("Amount mismatch");
                return;
              }
            }
          }
        }

        await markOrderPaidAndShip({
          orderId,
          userId,
          paymentId,
          payload: body,
        });
      } else if (paymentStatus === "CANCELLED" && orderId) {
        await markOrderPaidAndShip({
          orderId,
          userId,
          paymentId,
          payload: body,
        });
      }

      res.status(200).send("OK");
    } catch (err) {
      console.error("onPayfastNotify", err);
      res.status(500).send("Error");
    }
  });

exports.onBobGoWebhook = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onRequest(async (req, res) => {
    try {
      const body = typeof req.body === "object" && req.body ? req.body : {};
      const data = body.data && typeof body.data === "object" ? body.data : body;
      const orderId = String(
        data.custom_order_number ||
          data.custom_tracking_reference ||
          data.order_number ||
          "",
      );
      if (!orderId) {
        res.status(200).json({ ok: true, ignored: true });
        return;
      }
      const indexSnap = await db().collection("shop_orders_index").doc(orderId).get();
      if (!indexSnap.exists) {
        res.status(200).json({ ok: true, ignored: true });
        return;
      }
      const uid = indexSnap.data().userId;
      const status = String(data.status_friendly || data.status || "").toLowerCase();
      let orderStatus;
      if (status.includes("deliver")) orderStatus = "delivered";
      else if (status.includes("transit") || status.includes("collect") || status.includes("ship")) {
        orderStatus = "shipped";
      }
      const updates = {
        shippingStatus: data.status_friendly || data.status || "",
        trackingReference: data.tracking_reference || data.shipment_tracking_reference || "",
        trackingUrl: data.tracking_url || "",
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (orderStatus) updates.status = orderStatus;
      await db()
        .collection("users")
        .doc(uid)
        .collection("shop_orders")
        .doc(orderId)
        .set(updates, { merge: true });
      if (orderStatus) {
        await db().collection("shop_orders_index").doc(orderId).set(
          { status: orderStatus, updatedAt: FieldValue.serverTimestamp() },
          { merge: true },
        );
      }
      res.status(200).json({ ok: true });
    } catch (err) {
      console.error("onBobGoWebhook", err);
      res.status(500).json({ ok: false });
    }
  });

function isoDate(value) {
  if (!value) return "";
  if (typeof value.toDate === "function") return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

async function assertShopAdmin(uid) {
  const snap = await db().collection("users").doc(uid).get();
  if (!snap.exists || snap.data().isDeveloper !== true) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only the shop admin can export all paid orders.",
    );
  }
}

exports.cancelPayfastSubscription = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
    }
    const orderId = String((data && data.orderId) || "").trim();
    if (!orderId) {
      throw new functions.https.HttpsError("invalid-argument", "orderId is required.");
    }
    const uid = context.auth.uid;
    const orderRef = db()
      .collection("users")
      .doc(uid)
      .collection("shop_orders")
      .doc(orderId);
    const snap = await orderRef.get();
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", "Order not found.");
    }
    const order = snap.data() || {};
    const token = String(
      order.subscriptionToken || order.payfastToken || "",
    ).trim();
    if (!token) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "This order has no PayFast subscription token yet.",
      );
    }
    if (String(order.subscriptionStatus || "").toLowerCase() === "cancelled") {
      const wheelsCleared = await unlinkWheelsForSubscription(uid, orderId);
      return { ok: true, alreadyCancelled: true, token, wheelsCleared };
    }

    await cancelPayfastSubscriptionToken(token);

    await orderRef.set(
      {
        subscriptionStatus: "cancelled",
        subscriptionCancelledAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await db()
      .collection("shop_orders_index")
      .doc(orderId)
      .set(
        {
          subscriptionStatus: "cancelled",
          subscriptionToken: token,
          hasSubscription: true,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

    const wheelsCleared = await unlinkWheelsForSubscription(uid, orderId);

    return { ok: true, token, wheelsCleared };
  });

exports.listPaidShopOrders = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
    }
    await assertShopAdmin(context.auth.uid);
    const includeShipped = data && data.includeShipped === true;
    const indexSnap = await db().collection("shop_orders_index").get();
    const orders = [];
    for (const doc of indexSnap.docs) {
      const idx = doc.data() || {};
      const uid = idx.userId;
      const orderId = String(idx.orderId || doc.id);
      if (!uid) continue;
      let order = idx;
      if (!idx.shipping) {
        const snap = await db()
          .collection("users")
          .doc(uid)
          .collection("shop_orders")
          .doc(orderId)
          .get();
        if (!snap.exists) continue;
        order = { ...snap.data(), orderId };
      }
      const status = String(order.status || idx.status || "");
      if (status === "paid" || (includeShipped && status === "shipped")) {
        orders.push({
          orderId,
          status,
          email: order.email || "",
          shipping: order.shipping || {},
          items: Array.isArray(order.items) ? order.items : [],
          subtotal: asNumber(order.subtotal),
          total: asNumber(order.total),
          createdAt: isoDate(order.createdAt || order.paidAt),
        });
      }
    }
    return { orders };
  });
