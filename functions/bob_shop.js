/**
 * Bob Pay (payments) + Bob Go (shipping) for the Limitless shop.
 *
 * Secrets:
 *   firebase functions:secrets:set BOB_PAY_API_KEY
 *   firebase functions:secrets:set BOB_GO_API_TOKEN
 *
 * Optional params (.env or Firebase params):
 *   BOB_PAY_SANDBOX=true
 *   BOB_GO_SANDBOX=true
 *   BOB_COLLECTION_*  (pickup address)
 */

const functions = require("firebase-functions/v1");
const { defineSecret, defineString } = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const bobPayApiKey = defineSecret("BOB_PAY_API_KEY");
const bobGoApiToken = defineSecret("BOB_GO_API_TOKEN");

const bobPaySandbox = defineString("BOB_PAY_SANDBOX", { default: "true" });
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

function bobPayBase() {
  return isTrue(bobPaySandbox.value())
    ? "https://api.sandbox.bobpay.co.za"
    : "https://api.bobpay.co.za";
}

function bobGoBase() {
  return isTrue(bobGoSandbox.value())
    ? "https://api.sandbox.bobgo.co.za/v2"
    : "https://api.bobgo.co.za/v2";
}

function webhookUrl(name) {
  return `https://us-central1-limitless-iot-17e8f.cloudfunctions.net/${name}`;
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

function toCents(amount) {
  return Math.round(asNumber(amount) * 100);
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
  .region("us-central1")
  .runWith({ secrets: [bobGoApiToken], timeoutSeconds: 30, memory: "256MB" })
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

function pickCheckoutUrl(payload) {
  if (!payload || typeof payload !== "object") return "";
  const nested = payload.data && typeof payload.data === "object" ? payload.data : {};
  const candidates = [
    payload.url,
    payload.checkout_url,
    payload.payment_url,
    payload.redirect_url,
    payload.hosted_url,
    payload.payment_intent_url,
    payload.intent_url,
    nested.url,
    nested.checkout_url,
    nested.payment_url,
    payload.links && payload.links.checkout,
    payload.links && payload.links.payment,
  ];
  return candidates.find((v) => typeof v === "string" && v.startsWith("http")) || "";
}

async function bobPayRequest(path, { method = "POST", body } = {}) {
  const key = bobPayApiKey.value();
  if (!key) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "BOB_PAY_API_KEY is not set. Create an API key in Bob Pay after merchant approval.",
    );
  }
  const res = await fetch(`${bobPayBase()}/${path.replace(/^\//, "")}`, {
    method,
    headers: {
      Authorization: `Bearer ${key}`,
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await jsonError(res);
  if (!res.ok) {
    const message =
      (data && (data.message || data.detail || data.error || data.error_description)) ||
      `Bob Pay ${res.status}`;
    throw new functions.https.HttpsError("unknown", String(message));
  }
  return data;
}

exports.createBobPayCheckout = functions
  .region("us-central1")
  .runWith({
    secrets: [bobPayApiKey],
    timeoutSeconds: 30,
    memory: "256MB",
  })
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
    const amount = asNumber(order.total);
    if (amount <= 0) {
      throw new functions.https.HttpsError("invalid-argument", "Order total is invalid.");
    }
    const returnUrl = `${shopReturnUrl.value()}?orderId=${encodeURIComponent(orderId)}`;
    const notifyUrl = webhookUrl("onBobPayWebhook");
    const customer = order.shipping || {};
    const payload = {
      amount: toCents(amount),
      currency: "ZAR",
      merchant_reference: orderId,
      reference: orderId,
      return_url: returnUrl,
      success_url: returnUrl,
      cancel_url: shopCancelUrl.value(),
      notify_url: notifyUrl,
      notification_url: notifyUrl,
      customer: {
        email: customer.email || context.auth.token.email || "",
        name: customer.fullName || context.auth.token.name || "",
        phone: customer.phone || "",
      },
      metadata: { orderId, userId: uid },
    };

    let intent;
    let lastError = "";
    for (const path of ["v1/payment-intents", "payment-intents", "v1/intents"]) {
      try {
        intent = await bobPayRequest(path, { body: payload });
        break;
      } catch (err) {
        lastError = err.message || String(err);
      }
    }
    if (!intent) {
      throw new functions.https.HttpsError(
        "unavailable",
        lastError || "Bob Pay did not accept the payment intent.",
      );
    }
    const checkoutUrl = pickCheckoutUrl(intent);
    if (!checkoutUrl) {
      console.error("Bob Pay intent missing checkout URL", JSON.stringify(intent));
      throw new functions.https.HttpsError(
        "internal",
        "Bob Pay did not return a checkout URL. Check API credentials and sandbox mode.",
      );
    }
    const paymentId = String(
      intent.id || (intent.data && intent.data.id) || "",
    );
    await orderRef.set(
      {
        paymentProvider: "bob_pay",
        paymentIntentId: paymentId,
        paymentStatus: "redirected",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await db().collection("shop_orders_index").doc(orderId).set({
      userId: uid,
      orderId,
      paymentIntentId: paymentId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { checkoutUrl, paymentIntentId: paymentId };
  });

function paidStatus(value) {
  const s = String(value || "").toLowerCase();
  return (
    s === "paid" ||
    s === "complete" ||
    s === "completed" ||
    s === "successful" ||
    s === "succeeded" ||
    s === "success"
  );
}

function extractWebhookRefs(body) {
  const data = body.data && typeof body.data === "object" ? body.data : {};
  const meta = body.metadata || data.metadata || {};
  return {
    orderId: String(
      body.merchant_reference ||
        body.reference ||
        data.merchant_reference ||
        data.reference ||
        meta.orderId ||
        "",
    ),
    paymentId: String(body.id || data.id || body.payment_intent_id || ""),
    status: body.status || data.status || body.event || "",
    userId: String(meta.userId || ""),
  };
}

async function markOrderPaidAndShip({ orderId, userId, paymentId, payload }) {
  const indexSnap = await db().collection("shop_orders_index").doc(orderId).get();
  const uid = userId || (indexSnap.exists ? indexSnap.data().userId : "");
  if (!uid) {
    console.error("Bob Pay webhook: no user for order", orderId);
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
  if (order.status === "paid" || order.status === "shipped") return;

  await orderRef.set(
    {
      status: "paid",
      paymentProvider: "bob_pay",
      paymentIntentId: paymentId || order.paymentIntentId || "",
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

exports.onBobPayWebhook = functions
  .region("us-central1")
  .runWith({
    secrets: [bobPayApiKey, bobGoApiToken],
    timeoutSeconds: 60,
    memory: "256MB",
  })
  .https.onRequest(async (req, res) => {
    try {
      const body = typeof req.body === "object" && req.body ? req.body : {};
      const refs = extractWebhookRefs(body);
      let orderId = refs.orderId;
      if (!orderId && req.query.orderId) orderId = String(req.query.orderId);
      if (!orderId) {
        res.status(400).json({ ok: false, error: "missing order id" });
        return;
      }
      const looksPaid =
        paidStatus(refs.status) ||
        String(body.event || "").toLowerCase().includes("success") ||
        String(body.event || "").toLowerCase().includes("paid") ||
        req.method === "GET";
      if (looksPaid) {
        await markOrderPaidAndShip({
          orderId,
          userId: refs.userId,
          paymentId: refs.paymentId,
          payload: body,
        });
      }
      res.status(200).json({ ok: true });
    } catch (err) {
      console.error("onBobPayWebhook", err);
      res.status(500).json({ ok: false });
    }
  });

exports.onBobGoWebhook = functions
  .region("us-central1")
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

exports.listPaidShopOrders = functions
  .region("us-central1")
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
