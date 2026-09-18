/**
 * Organisation invites: accept join codes and attach members to an Admin org.
 * Supports multiple organisations per user (orgs map + activeOrgId).
 *
 * Deploy: firebase deploy --only functions:acceptOrgInvite
 */

const functions = require("firebase-functions/v1");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { FUNCTIONS_REGION } = require("./region");

const COLLECTION_USERS = "users";
const COLLECTION_ORGS = "organizations";
const COLLECTION_MEMBERS = "members";
const COLLECTION_INVITES = "invites";
const COLLECTION_INVITE_CODES = "orgInviteCodes";
const FIELDS_ORG = "org";
const FIELDS_ORGS = "orgs";
const FIELDS_ACTIVE_ORG_ID = "activeOrgId";
const FIELDS_USERDATA = "userdata";

const ALLOWED_INVITE_ROLES = new Set(["supervisor", "employee"]);

exports.acceptOrgInvite = functions
  .region(FUNCTIONS_REGION)
  .https.onCall(async (data, context) => {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in to join a profile."
      );
    }

    const uid = context.auth.uid;
    const codeRaw = (data && data.code ? String(data.code) : "").trim();
    const code = codeRaw.toUpperCase();
    if (code.length < 4) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Enter a valid join code."
      );
    }

    const db = getFirestore();
    const userRef = db.collection(COLLECTION_USERS).doc(uid);
    const userSnap = await userRef.get();
    const existingOrgs =
      userSnap.exists && userSnap.get(FIELDS_ORGS)
        ? userSnap.get(FIELDS_ORGS)
        : {};

    let inviteDoc = null;
    let orgId = null;
    const codeRef = db.collection(COLLECTION_INVITE_CODES).doc(code);
    const codeSnap = await codeRef.get();

    if (codeSnap.exists) {
      if (codeSnap.get("usedBy")) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Join code already used."
        );
      }
      const expiresAt = codeSnap.get("expiresAt");
      if (expiresAt && expiresAt.toDate && expiresAt.toDate() < new Date()) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Join code is expired."
        );
      }
      orgId = String(codeSnap.get("orgId") || "");
      const inviteId = String(codeSnap.get("inviteId") || "");
      if (orgId && inviteId) {
        inviteDoc = await db
          .collection(COLLECTION_ORGS)
          .doc(orgId)
          .collection(COLLECTION_INVITES)
          .doc(inviteId)
          .get();
      }
    }

    if (!inviteDoc || !inviteDoc.exists) {
      const inviteQuery = await db
        .collectionGroup(COLLECTION_INVITES)
        .where("codeUpper", "==", code)
        .limit(5)
        .get();

      for (const doc of inviteQuery.docs) {
        const usedBy = doc.get("usedBy");
        if (usedBy) continue;
        const expiresAt = doc.get("expiresAt");
        if (expiresAt && expiresAt.toDate && expiresAt.toDate() < new Date()) {
          continue;
        }
        inviteDoc = doc;
        orgId = doc.ref.parent.parent.id;
        break;
      }
    }

    if (!inviteDoc || !inviteDoc.exists || !orgId) {
      throw new functions.https.HttpsError(
        "not-found",
        "Join code not found."
      );
    }

    if (inviteDoc.get("usedBy")) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Join code already used."
      );
    }

    if (existingOrgs && existingOrgs[orgId]) {
      throw new functions.https.HttpsError(
        "already-exists",
        "You already belong to this profile."
      );
    }

    const role = String(inviteDoc.get("role") || "").toLowerCase();
    if (!ALLOWED_INVITE_ROLES.has(role)) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Invite has an invalid role."
      );
    }

    const orgRef = db.collection(COLLECTION_ORGS).doc(orgId);
    const orgSnap = await orgRef.get();
    if (!orgSnap.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Profile no longer exists."
      );
    }

    const ownerUid = String(orgSnap.get("ownerUid") || orgId);
    if (ownerUid === uid || orgId === uid) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "You cannot join your own profile with an invite code."
      );
    }
    const orgName = String(orgSnap.get("name") || "Profile");
    const authToken = context.auth.token || {};
    const displayName =
      (userSnap.get(FIELDS_USERDATA) &&
        userSnap.get(FIELDS_USERDATA).displayName) ||
      authToken.name ||
      "";
    const email =
      (userSnap.get(FIELDS_USERDATA) && userSnap.get(FIELDS_USERDATA).email) ||
      authToken.email ||
      context.auth.token.email ||
      "";

    const membershipEntry = {
      role,
      ownerUid,
      orgName,
    };

    await db.runTransaction(async (tx) => {
      const freshInvite = await tx.get(inviteDoc.ref);
      if (!freshInvite.exists) {
        throw new functions.https.HttpsError("not-found", "Invite missing.");
      }
      if (freshInvite.get("usedBy")) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Join code already used."
        );
      }

      tx.set(
        orgRef.collection(COLLECTION_MEMBERS).doc(uid),
        {
          role,
          displayName: String(displayName || ""),
          email: String(email || ""),
          joinedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      tx.set(
        userRef,
        {
          [`${FIELDS_ORGS}.${orgId}`]: membershipEntry,
          [FIELDS_ACTIVE_ORG_ID]: orgId,
          [FIELDS_ORG]: {
            orgId,
            role,
            ownerUid,
            orgName,
          },
        },
        { merge: true }
      );

      tx.update(inviteDoc.ref, {
        usedBy: uid,
        usedAt: FieldValue.serverTimestamp(),
      });

      tx.set(
        codeRef,
        {
          usedBy: uid,
          usedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    });

    return {
      orgId,
      ownerUid,
      role,
      orgName,
    };
  });
