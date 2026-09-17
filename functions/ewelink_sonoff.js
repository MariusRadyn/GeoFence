/**
 * SONOFF / eWeLink cloud control (CoolKit V2 + OAuth).
 *
 * The old ewelink-api APP_ID was revoked ("appid unauthorized").
 * Create your own app at https://dev.ewelink.cc/ and set in functions/.env:
 *   EWELINK_APP_ID=...
 *   EWELINK_APP_SECRET=...
 *   EWELINK_REDIRECT_URL=https://europe-west1-limitless-iot-17e8f.cloudfunctions.net/onEwelinkOAuthCallback
 *
 * Register that same redirect URL in the eWeLink developer console.
 */

const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const { defineString } = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const eWeLink = require("ewelink-api-next").default;
const { FUNCTIONS_REGION } = require("./region");

const ewelinkAppId = defineString("EWELINK_APP_ID", { default: "" });
const ewelinkAppSecret = defineString("EWELINK_APP_SECRET", { default: "" });
const ewelinkRedirectUrl = defineString("EWELINK_REDIRECT_URL", {
  default: `https://${FUNCTIONS_REGION}-limitless-iot-17e8f.cloudfunctions.net/onEwelinkOAuthCallback`,
});

const REGIONS = new Set(["us", "eu", "as", "cn"]);

function db() {
  return getFirestore();
}

function accountRef(uid) {
  return db().collection("ewelink_accounts").doc(uid);
}

function pendingRef(state) {
  return db().collection("ewelink_oauth_pending").doc(state);
}

function requireAuth(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign in required.",
    );
  }
  return context.auth.uid;
}

function normalizeRegion(raw) {
  const region = String(raw || "eu").trim().toLowerCase();
  return REGIONS.has(region) ? region : "eu";
}

function requireAppCredentials() {
  const appId = String(ewelinkAppId.value() || "").trim();
  const appSecret = String(ewelinkAppSecret.value() || "").trim();
  if (!appId || !appSecret) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "eWeLink developer credentials are not configured. " +
        "Create an app at https://dev.ewelink.cc/ and set EWELINK_APP_ID / EWELINK_APP_SECRET.",
    );
  }
  return { appId, appSecret };
}

function redirectUrl() {
  return String(ewelinkRedirectUrl.value() || "").trim();
}

function createClient(region) {
  const { appId, appSecret } = requireAppCredentials();
  return new eWeLink.WebAPI({
    appId,
    appSecret,
    region: normalizeRegion(region),
  });
}

function createLoginUrl({ appId, appSecret, redirectUrl: redirect, state }) {
  const seq = Date.now().toString();
  const params = {
    clientId: appId,
    redirectUrl: redirect,
    grantType: "authorization_code",
    state,
    nonce: crypto.randomBytes(4).toString("hex"),
    seq,
    authorization: crypto
      .createHmac("sha256", appSecret)
      .update(`${appId}_${seq}`)
      .digest("base64"),
  };
  const qs = Object.entries(params)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join("&");
  return `https://c2ccdn.coolkit.cc/oauth/index.html?${qs}`;
}

const EWELINK_ERROR_EN = {
  400: "Invalid request to eWeLink.",
  401: "eWeLink authorization failed. Unlink and link your account again.",
  402: "eWeLink session expired. Unlink and link your account again.",
  403: "eWeLink refused this request.",
  404: "Device not found on this eWeLink account.",
  405: "Method not allowed by eWeLink.",
  406: "eWeLink authentication failed. Unlink and link your account again.",
  407: "Wrong eWeLink region. Try linking again.",
  500: "eWeLink server error. Try again shortly.",
  503: "Device is offline or unreachable.",
  504: "eWeLink request timed out.",
  1000: "eWeLink rate limit reached. Wait a moment and try again.",
  4000: "Device control failed.",
  4001: "Device does not support this command.",
  4002: "Device is offline, or the control command does not match this device.",
  4003: "Device is busy. Try again.",
  5000: "eWeLink internal error.",
};

function containsCjk(text) {
  return /[\u3400-\u9FFF]/.test(String(text || ""));
}

function friendlyEwelinkMessage(response, fallback) {
  const code = Number(response?.error);
  const raw = String(response?.msg || response?.message || "").trim();
  if (Number.isFinite(code) && EWELINK_ERROR_EN[code]) {
    return `${EWELINK_ERROR_EN[code]} (code ${code})`;
  }
  if (raw && !containsCjk(raw)) {
    return Number.isFinite(code) && code !== 0
      ? `${raw} (code ${code})`
      : raw;
  }
  if (Number.isFinite(code) && code !== 0) {
    return `${fallback || "eWeLink request failed."} (code ${code})`;
  }
  return fallback || "eWeLink request failed.";
}

function throwIfApiError(response, fallback) {
  if (!response || typeof response !== "object") {
    throw new functions.https.HttpsError(
      "internal",
      fallback || "Unexpected eWeLink response.",
    );
  }
  if (response.error === 0 || response.error === false || response.error == null) {
    return response.data || response;
  }
  throw new functions.https.HttpsError(
    "failed-precondition",
    friendlyEwelinkMessage(response, fallback),
  );
}

function friendlyCaughtError(err, fallback) {
  if (err instanceof functions.https.HttpsError) return err;
  const raw = String(err?.message || err || "").trim();
  const codeMatch = raw.match(/\b(?:error|code)[:=\s]*(\d{3,5})\b/i) ||
    raw.match(/\b(\d{3,5})\b/);
  const code = codeMatch ? Number(codeMatch[1]) : NaN;
  if (Number.isFinite(code) && EWELINK_ERROR_EN[code]) {
    return new functions.https.HttpsError(
      "failed-precondition",
      `${EWELINK_ERROR_EN[code]} (code ${code})`,
    );
  }
  if (containsCjk(raw)) {
    return new functions.https.HttpsError(
      "failed-precondition",
      Number.isFinite(code)
        ? `${fallback || "eWeLink request failed."} (code ${code})`
        : fallback || "eWeLink request failed.",
    );
  }
  return new functions.https.HttpsError(
    "internal",
    raw || fallback || "eWeLink request failed.",
  );
}

/**
 * CoolKit channel counts by UIID (from eWeLink / homebridge mappings).
 * Some single-relay devices still use a 4-slot `switches` payload (SCM).
 */
const CHANNELS_BY_UIID = {
  1: 1, 2: 2, 3: 3, 4: 4, 5: 1, 6: 1, 7: 2, 8: 3, 9: 4,
  14: 1, 24: 1, 27: 1, 29: 2, 30: 3, 31: 4, 32: 1,
  77: 1, 78: 1, 81: 1, 82: 2, 83: 3, 84: 4, 107: 1, 112: 1,
  113: 2, 114: 3, 126: 2, 130: 4, 138: 1, 139: 2, 140: 3, 141: 4,
  160: 1, 161: 2, 162: 3, 165: 2, 182: 1, 190: 1, 191: 1,
  209: 1, 210: 2, 211: 3, 212: 4, 225: 1, 226: 1, 262: 4,
  264: 1, 268: 1, 275: 2, 276: 1, 1009: 1, 1256: 1,
  2256: 2, 3256: 3, 4256: 4, 7004: 1, 7005: 1, 7010: 1,
  7028: 1, 7029: 2, 7030: 3, 7032: 1, 7040: 2, 20001: 1, 20004: 4,
};

function deviceUiid(device) {
  return Number(
    device.uiid ??
      device.extra?.uiid ??
      device.extra?.extra?.uiid ??
      0,
  );
}

function resolveChannelCount(device, params, switches) {
  const uiid = deviceUiid(device);
  if (CHANNELS_BY_UIID[uiid] != null) {
    return CHANNELS_BY_UIID[uiid];
  }

  // Named channels in tags (when present) are a good real count.
  const names = device.tags?.channelName || device.tags?.ck_channel_name;
  if (names && typeof names === "object") {
    const n = Object.keys(names).length;
    if (n > 0) return n;
  }

  // Classic single-relay payload.
  if (typeof params.switch === "string" && !Array.isArray(params.switches)) {
    return 1;
  }

  // Many single plugs still report 4 outlets — treat unknown 4-slot as 1
  // unless the model name clearly says multi-gang.
  const model = String(device.productModel || device.name || "").toLowerCase();
  const looksMulti =
    /\b(2|3|4)\s*ch\b|dual|4ch|3ch|2ch|m5-2|m5-3|t5-2|t5-3|t5-4|gang/.test(
      model,
    );
  if (Array.isArray(switches) && switches.length === 4 && !looksMulti) {
    return 1;
  }

  return Array.isArray(switches) && switches.length > 0 ? switches.length : 1;
}

function summarizeDevice(itemData, itemType) {
  const device = itemData && typeof itemData === "object" ? itemData : {};
  const params = device.params || {};
  const rawSwitches = Array.isArray(params.switches)
    ? params.switches.map((s) => ({
        outlet: Number(s.outlet ?? 0),
        switch: String(s.switch || "off"),
      }))
    : null;

  const channelCount = resolveChannelCount(device, params, rawSwitches);
  const usesSwitchesProtocol = Array.isArray(params.switches);

  let switches = null;
  if (usesSwitchesProtocol && channelCount > 1 && rawSwitches) {
    switches = [...rawSwitches]
      .sort((a, b) => a.outlet - b.outlet)
      .filter((s) => s.outlet >= 0 && s.outlet < channelCount)
      .slice(0, channelCount);
  }

  let state = null;
  if (typeof params.switch === "string") {
    state = params.switch;
  } else if (rawSwitches && rawSwitches.length > 0) {
    const first =
      rawSwitches.find((s) => s.outlet === 0) || rawSwitches[0];
    state = first.switch;
  }

  const deviceId = String(device.deviceid || device.deviceId || "").trim();
  return {
    deviceId,
    name: String(device.name || deviceId || "Device"),
    online: device.online === true,
    productModel: String(device.productModel || ""),
    brandName: String(device.brandName || "SONOFF"),
    itemType: Number(itemType || 1),
    uiid: deviceUiid(device) || null,
    channelCount,
    usesSwitchesProtocol,
    state,
    switches,
  };
}

async function loadAccount(uid) {
  const snap = await accountRef(uid).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Link your eWeLink account first.",
    );
  }
  const data = snap.data() || {};
  if (!data.at) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "eWeLink link is incomplete. Please link again.",
    );
  }
  return data;
}

function clientFromAccount(account) {
  const client = createClient(account.region || "eu");
  client.at = account.at;
  client.rt = account.rt || "";
  client.userApiKey = account.apiKey || "";
  return client;
}

function htmlPage(title, body) {
  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title>
<style>
body{font-family:system-ui,sans-serif;background:#021824;color:#fff;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px;}
.card{max-width:420px;background:#15273f;border-radius:16px;padding:24px;line-height:1.45;}
a{color:#ffc43a}
</style></head><body><div class="card">${body}</div></body></html>`;
}

exports.ewelinkGetStatus = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onCall(async (_data, context) => {
    const uid = requireAuth(context);
    const snap = await accountRef(uid).get();
    if (!snap.exists) return { linked: false };
    const data = snap.data() || {};
    return {
      linked: Boolean(data.at),
      email: data.email || null,
      region: data.region || null,
    };
  });

exports.ewelinkStartOAuth = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onCall(async (data, context) => {
    const uid = requireAuth(context);
    const { appId, appSecret } = requireAppCredentials();
    const redirect = redirectUrl();
    if (!redirect) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "EWELINK_REDIRECT_URL is not configured.",
      );
    }

    const state = crypto.randomBytes(16).toString("hex");
    await pendingRef(state).set({
      uid,
      createdAt: FieldValue.serverTimestamp(),
      regionHint: normalizeRegion(data.region),
    });

    const url = createLoginUrl({
      appId,
      appSecret,
      redirectUrl: redirect,
      state,
    });

    return { url, state, redirectUrl: redirect };
  });

exports.onEwelinkOAuthCallback = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .https.onRequest(async (req, res) => {
    try {
      const code = String(req.query.code || "").trim();
      const region = normalizeRegion(req.query.region || req.query.regin);
      const state = String(req.query.state || "").trim();

      if (!code || !state) {
        res
          .status(400)
          .send(
            htmlPage(
              "Link failed",
              "<h2>Missing authorization code</h2><p>Please return to Limitless and try linking again.</p>",
            ),
          );
        return;
      }

      const pendingSnap = await pendingRef(state).get();
      if (!pendingSnap.exists) {
        res
          .status(400)
          .send(
            htmlPage(
              "Link failed",
              "<h2>Session expired</h2><p>Return to Limitless and tap Link again.</p>",
            ),
          );
        return;
      }

      const pending = pendingSnap.data() || {};
      const uid = String(pending.uid || "").trim();
      if (!uid) {
        res.status(400).send(htmlPage("Link failed", "<h2>Invalid session</h2>"));
        return;
      }

      const redirect = redirectUrl();
      const client = createClient(region);
      const tokenResponse = await client.oauth.getToken({
        region,
        redirectUrl: redirect,
        code,
      });
      const tokenData = throwIfApiError(tokenResponse, "eWeLink token exchange failed.");

      const at = String(tokenData.accessToken || tokenData.at || "").trim();
      const rt = String(tokenData.refreshToken || tokenData.rt || "").trim();
      const apiKey = String(
        (tokenData.user && (tokenData.user.apikey || tokenData.user.apiKey)) ||
          "",
      ).trim();
      const email = String(
        (tokenData.user && (tokenData.user.email || tokenData.user.phoneNumber)) ||
          "",
      ).trim();
      const resolvedRegion = normalizeRegion(tokenData.region || region);

      if (!at) {
        res
          .status(500)
          .send(
            htmlPage(
              "Link failed",
              "<h2>No access token returned</h2><p>Check your eWeLink app permissions in the developer console.</p>",
            ),
          );
        return;
      }

      await accountRef(uid).set(
        {
          email: email || null,
          at,
          rt: rt || null,
          apiKey: apiKey || null,
          region: resolvedRegion,
          linkedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          authMethod: "oauth",
        },
        { merge: true },
      );
      await pendingRef(state).delete();

      res.status(200).send(
        htmlPage(
          "Linked",
          "<h2>eWeLink linked</h2><p>You can close this tab and return to the Limitless app. Your devices will refresh automatically.</p>",
        ),
      );
    } catch (err) {
      console.error("onEwelinkOAuthCallback", err);
      const msg = friendlyEwelinkMessage(
        { error: err?.error, msg: err?.message || err },
        "Could not finish linking.",
      );
      res
        .status(500)
        .send(
          htmlPage(
            "Link failed",
            `<h2>Could not finish linking</h2><p>${msg.replace(/[<>&]/g, "")}</p>`,
          ),
        );
    }
  });

exports.ewelinkUnlinkAccount = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onCall(async (_data, context) => {
    const uid = requireAuth(context);
    await accountRef(uid).delete();
    return { linked: false };
  });

exports.ewelinkListDevices = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .https.onCall(async (_data, context) => {
    const uid = requireAuth(context);
    try {
      const account = await loadAccount(uid);
      const client = clientFromAccount(account);
      const response = await client.device.getAllThings({ lang: "en", num: 0 });
      const data = throwIfApiError(response, "Could not list eWeLink devices.");
      const thingList = Array.isArray(data.thingList) ? data.thingList : [];

      const devices = thingList
        .filter((item) => item && (item.itemType === 1 || item.itemType === 2))
        .map((item) => summarizeDevice(item.itemData, item.itemType))
        .filter((d) => d.deviceId);

      return {
        linked: true,
        email: account.email || null,
        region: account.region || null,
        devices,
      };
    } catch (err) {
      console.error("ewelinkListDevices", err);
      throw friendlyCaughtError(err, "Could not list eWeLink devices.");
    }
  });

exports.ewelinkSetDevicePower = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .https.onCall(async (data, context) => {
    const uid = requireAuth(context);
    const deviceId = String(data.deviceId || "").trim();
    const state = String(data.state || "").trim().toLowerCase();
    const channel = Math.max(1, Math.floor(Number(data.channel) || 1));
    const itemType = Number(data.itemType) === 2 ? 2 : 1;

    if (!deviceId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "deviceId is required.",
      );
    }
    if (state !== "on" && state !== "off" && state !== "toggle") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        'state must be "on", "off", or "toggle".',
      );
    }

    try {
      const account = await loadAccount(uid);
      const client = clientFromAccount(account);

      let nextState = state;
      if (state === "toggle") {
        const statusRes = await client.device.getThingStatus({
          type: itemType,
          id: deviceId,
          params: "switch|switches",
        });
        const statusData = throwIfApiError(statusRes, "Could not read device state.");
        const statusParams = statusData.params || {};
        if (Array.isArray(statusParams.switches)) {
          const row =
            statusParams.switches.find(
              (s) => Number(s.outlet) === channel - 1,
            ) || statusParams.switches[0];
          nextState = row?.switch === "on" ? "off" : "on";
        } else {
          nextState = statusParams.switch === "on" ? "off" : "on";
        }
      }

      const params = { switch: nextState };

      // Devices that speak the multi-outlet protocol (including 1-relay SCM)
      // must be controlled with `switches`, not `switch`.
      if (data.hasSwitches === true || data.usesSwitchesProtocol === true) {
        const statusRes = await client.device.getThingStatus({
          type: itemType,
          id: deviceId,
          params: "switches",
        });
        const statusData = throwIfApiError(statusRes, "Could not read switches.");
        const switches = Array.isArray(statusData.params?.switches)
          ? statusData.params.switches.map((s) => ({ ...s }))
          : [];
        if (switches.length > 0) {
          const outlet = channel - 1;
          const idx = switches.findIndex((s) => Number(s.outlet) === outlet);
          if (idx >= 0) {
            switches[idx].switch = nextState;
          } else {
            switches.push({ outlet, switch: nextState });
          }
          params.switches = switches;
          delete params.switch;
        }
      } else if (channel > 1 || data.multiChannel === true) {
        params.switches = [{ outlet: channel - 1, switch: nextState }];
        delete params.switch;
      }

      const result = await client.device.setThingStatus({
        type: itemType,
        id: deviceId,
        params,
      });
      throwIfApiError(result, "Could not change device power state.");

      return {
        deviceId,
        channel,
        state: nextState,
        status: "ok",
      };
    } catch (err) {
      console.error("ewelinkSetDevicePower", err);
      throw friendlyCaughtError(err, "Could not change device power state.");
    }
  });
