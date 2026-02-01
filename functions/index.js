const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();

async function assertAdmin(context) {
  if (!context.auth) {
    throw new HttpsError("unauthenticated", "Vous devez être connecté.");
  }

  const callerUid = context.auth.uid;
  const callerRef = admin.firestore().collection("users").doc(callerUid);
  const callerSnap = await callerRef.get();

  if (!callerSnap.exists) {
    throw new HttpsError("permission-denied", "Profil introuvable dans /users/{uid}.");
  }

  const data = callerSnap.data() || {};
  if (data.active !== true) {
    throw new HttpsError("permission-denied", "Compte inactif.");
  }
  if (data.role !== "ADMIN") {
    throw new HttpsError("permission-denied", "Action réservée ADMIN.");
  }
}

function assertRoleValid(role) {
  const allowed = ["ADMIN", "FERMIER", "VETERINAIRE", "DEPOT"];
  if (!allowed.includes(role)) {
    throw new HttpsError("invalid-argument", "Rôle invalide.");
  }
}

exports.adminCreateUser = onCall({ region: "europe-west1" }, async (request) => {
  await assertAdmin(request);

  const data = request.data || {};
  const email = String(data.email || "").trim().toLowerCase();
  const password = String(data.password || "");
  const displayName = String(data.displayName || "").trim();
  const role = String(data.role || "FERMIER").trim();
  const active = data.active === true;

  if (!email) throw new HttpsError("invalid-argument", "Email obligatoire.");
  if (!password || password.length < 6) {
    throw new HttpsError("invalid-argument", "Mot de passe >= 6 caractères obligatoire.");
  }
  assertRoleValid(role);

  try {
    const userRecord = await admin.auth().createUser({
      email,
      password,
      displayName: displayName || undefined,
      disabled: !active
    });

    const uid = userRecord.uid;

    await admin.firestore().collection("users").doc(uid).set(
      {
        uid,
        email,
        displayName: displayName || null,
        role,
        active,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      },
      { merge: true }
    );

    return { ok: true, uid };
  } catch (err) {
    const code = err && err.code ? String(err.code) : "";
    if (code.includes("auth/email-already-exists")) {
      throw new HttpsError("already-exists", "Cet email existe déjà dans Firebase Auth.");
    }
    throw new HttpsError("internal", `Erreur création user: ${err && err.message ? err.message : err}`);
  }
});
