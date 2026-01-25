import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as crypto from "crypto";

admin.initializeApp();

const db = admin.firestore();
const bucket = admin.storage().bucket();

// ✅ Regione principale
const REGION = "europe-west1";

// =====================================================
// ✅ Nickname registry (global uniqueness)
// - Nicknames/{nicknameLower} -> { uid, nickname, updatedAt }
// - Clients MUST use callable setNickname()
// =====================================================
function normalizeNickname(input: any): { nickname: string; lower: string } {
  const raw = (input ?? "").toString().trim();
  // basic validation: 3-20 chars, letters/numbers/._-
  const nickname = raw;
  const lower = raw.toLowerCase();
  if (nickname.length < 3 || nickname.length > 20) {
    throw new HttpsError("invalid-argument", "Nickname deve essere lungo 3-20 caratteri.");
  }
  if (!/^[a-zA-Z0-9._-]+$/.test(nickname)) {
    throw new HttpsError(
      "invalid-argument",
      "Nickname non valido. Usa solo lettere, numeri, punto, underscore, trattino."
    );
  }
  return { nickname, lower };
}

async function setNicknameTxn(userId: string, nickname: string, lower: string) {
  const nickRef = db.collection("Nicknames").doc(lower);
  const userRef = db.collection("Users").doc(userId);

  await db.runTransaction(async (tx) => {
    const [nickSnap, userSnap] = await Promise.all([tx.get(nickRef), tx.get(userRef)]);

    if (!userSnap.exists) {
      throw new HttpsError("failed-precondition", "Profilo utente non trovato.");
    }

    if (nickSnap.exists) {
      const ownerUid = (nickSnap.data()?.uid ?? "") as string;
      if (ownerUid && ownerUid !== userId) {
        throw new HttpsError("already-exists", "Nickname già in uso.");
      }
    }

    const oldLower = ((userSnap.data()?.nicknameLower ?? "") as string).toLowerCase();
    if (oldLower && oldLower !== lower) {
      const oldRef = db.collection("Nicknames").doc(oldLower);
      const oldSnap = await tx.get(oldRef);
      if (oldSnap.exists && (oldSnap.data()?.uid ?? "") === userId) {
        tx.delete(oldRef);
      }
    }

    tx.set(
      nickRef,
      {
        uid: userId,
        nickname,
        nicknameLower: lower,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.set(
      userRef,
      {
        nickname,
        nicknameLower: lower,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
}

export const setNickname = onCall({ region: REGION }, async (req) => {
  const userId = requireAuth(req);
  const { nickname, lower } = normalizeNickname(req.data?.nickname);

  await setNicknameTxn(userId, nickname, lower);
  return { ok: true, nickname, nicknameLower: lower };
});

/**
 * ✅ Campi SEMPRE pubblici (enforced server-side)
 * NB: questi campi vengono propagati in UsersPublic + members anche se la privacy map dice altro.
 */
const ALWAYS_PUBLIC_FIELDS = new Set<string>([
  "photoUrl",
  "photoV",
  "coverUrl",
  "coverV",
  "nome",
  "cognome",
  "nickname",
  // ✅ campo canonico IT. Manteniamo anche l'alias storico "thought" finché non migri i dati.
  "pensiero",
  "thought",
]);

/**
 * 🔒 Campi sensibili: default = private se l’utente non imposta la privacy.
 * (l’utente può comunque scegliere "public" → richiede conferma lato client, opzionale lato server)
 */
const SENSITIVE_FIELDS = new Set<string>([
  // anagrafica
  "sesso",
  "dataNascita",
  "luogoNascita",
  "codiceFiscale",
  "cittadinanza",
  "statoCivile",

  // contatti / residenza
  "residenzaVia",
  "residenzaCap",
  "residenzaCitta",
  "residenzaProvincia",
  "residenzaNazione",
  "domicilioVia",
  "domicilioCap",
  "domicilioCitta",
  "domicilioProvincia",
  "domicilioNazione",
  "emailPersonale",
  "emailAziendale",
  "telefono",
  "contattoEmergenzaNome",
  "contattoEmergenzaTelefono",

  // lavoro/contratto
  "dataAssunzione",
  "tipoContratto",
  "inquadramento",
  "mansione",
  "reparto",
  "orarioLavoro",
  "sedeLavoro",
  "statoRapporto",
  "dataCessazione",

  // documenti/scadenze
  "documentoIdentitaTipo",
  "documentoIdentitaScadenza",
  "patenteScadenza",
  "cqcScadenza",
  "schedaConducenteScadenza",
  "iban",

  // stranieri
  "paeseOrigine",
  "tipoPermesso",
  "numeroPermesso",
  "dataRilascioPermesso",
  "dataScadenzaPermesso",
  "questuraRilascio",
  "motivoPermesso",
  "statoRinnovo",

  // retributivi
  "retribuzioneBase",
  "superminimo",
  "indennita",
  "benefit",
  "tipoPagamento",
  "frequenzaPagamento",

  // sicurezza/idoneità (senza dettagli sanitari!)
  "visitaMedicaEsito",
  "visitaMedicaData",
  "visitaMedicaScadenza",
  "dpiAssegnati",
  "corsiObbligatori",

  // note HR (delicate)
  "noteHR",
  "annotazioniDisciplinari",
  "commentiOrganizzativi",

  // consensi
  "consensoPrivacy",
  "dataConsenso",
  "versioneInformativa",
  "consensoFoto",
]);




// =====================================================
// ✅ UPDATE MY PROFILE (SERVER-DRIVEN)
// =====================================================
export const updateMyProfile = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);

  const fields = req.data?.fields ?? {};
  const privacyPatch = req.data?.privacy ?? {};

  if (typeof fields !== "object" || fields === null || Array.isArray(fields)) {
    throw new HttpsError("invalid-argument", "fields non valido");
  }
  if (typeof privacyPatch !== "object" || privacyPatch === null || Array.isArray(privacyPatch)) {
    throw new HttpsError("invalid-argument", "privacy non valido");
  }

  const userRef = db.collection("Users").doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Utente non trovato");

  const prev = (snap.data() ?? {}) as Record<string, any>;
  const prevProfile = (prev.profile ?? {}) as Record<string, any>;
  const prevCustom = (prevProfile.custom ?? {}) as Record<string, any>;
  const prevPrivacy = (prevProfile.privacy ?? {}) as Record<string, any>;

  // ✅ MERGE custom (non perdere campi non inviati)
  const nextCustom: Record<string, any> = { ...prevCustom };
  for (const [k, v] of Object.entries(fields)) nextCustom[k] = v;

  // ✅ MERGE privacy (non perdere campi non inviati)
  const nextPrivacy: Record<string, any> = { ...prevPrivacy, ...privacyPatch };

  await userRef.set(
    {
      profile: {
        custom: nextCustom,
        privacy: nextPrivacy,
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return { ok: true };
});







export const updateUserProfileField = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const fieldKey = (req.data?.fieldKey ?? "").toString().trim();
  const value = req.data?.value;

  if (!fieldKey) throw new HttpsError("invalid-argument", "fieldKey mancante");

  const userRef = db.collection("Users").doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Utente non trovato");

  // ✅ write SOLO dentro profile.custom
  await userRef.set(
    {
      profile: {
        custom: {
          [fieldKey]: value,
        },
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return { ok: true };
});






// ------------------------
// HELPERS
// ------------------------
function requireAuth(req: any) {
  if (!req.auth?.uid) throw new HttpsError("unauthenticated", "Devi essere autenticato.");
  return req.auth.uid as string;
}


function randomJoinCode(len = 6) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let out = "";
  for (let i = 0; i < len; i++) out += chars[crypto.randomInt(0, chars.length)];
  return out;
}

function asInt(v: any): number {
  if (typeof v === "number" && Number.isFinite(v)) return Math.trunc(v);
  const n = parseInt((v ?? "").toString(), 10);
  return Number.isFinite(n) ? n : 0;
}

async function ensureUserDoc(uid: string) {
  const u = await admin.auth().getUser(uid);
  const email = u.email ?? "";
  const emailLower = email.toLowerCase();
  await db.collection("Users").doc(uid).set(
    {
      uid,
      email,
      emailLower,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return { email, emailLower };
}

// ------------------------
// PUBLIC PROFILE PARSING
// ------------------------
function resolvePublicFromUserDoc(
  u: Record<string, any>,
  fallback?: { email?: string; emailLower?: string }
) {
  const profile = (u?.profile ?? {}) as Record<string, any>;
  const custom = (profile?.custom ?? {}) as Record<string, any>;

  // ✅ Priorità: profile.custom -> profile.* -> top-level legacy
  const nome = (custom?.nome ?? profile?.nome ?? u?.nome ?? "").toString().trim();
  const cognome = (custom?.cognome ?? profile?.cognome ?? u?.cognome ?? "").toString().trim();
  const nickname = (custom?.nickname ?? profile?.nickname ?? u?.nickname ?? "").toString().trim();

  const photoUrl = (custom?.photoUrl ?? profile?.photoUrl ?? u?.photoUrl ?? "").toString().trim();
  const photoV = asInt(custom?.photoV ?? profile?.photoV ?? u?.photoV ?? 0);

  const coverUrl = (custom?.coverUrl ?? profile?.coverUrl ?? u?.coverUrl ?? "").toString().trim();
  const coverV = asInt(custom?.coverV ?? profile?.coverV ?? u?.coverV ?? 0);

  const email = (u?.email ?? fallback?.email ?? "").toString().trim();
  const emailLower = (
    u?.emailLower ?? fallback?.emailLower ?? (email ? email.toLowerCase() : "")
  ).toString().trim();

  const displayName = [cognome, nome].filter(Boolean).join(" ").trim();

  return {
    nome,
    cognome,
    displayName,
    nickname,
    photoUrl,
    photoV,
    coverUrl,
    coverV,
    email,
    emailLower,
  };
}


async function getLeaguePublicProfile(
  uid: string,
  fallback?: { email?: string; emailLower?: string }
) {
  const userSnap = await db.collection("Users").doc(uid).get();
  const u = (userSnap.data() ?? {}) as Record<string, any>;
  return resolvePublicFromUserDoc(u, fallback);
}

/**
 * Campi pubblici uniformi per member e UsersPublic
 */
function memberPublicFields(pub: {
  nome: string;
  cognome: string;
  displayName: string;
  nickname?: string;
  photoUrl?: string;
  photoV?: number;
  coverUrl?: string;
  coverV?: number;
  email: string;
  emailLower: string;
}) {
  const nome = (pub.nome ?? "").toString().trim();
  const cognome = (pub.cognome ?? "").toString().trim();
  const nickname = (pub.nickname ?? "").toString().trim();
  const displayName = (pub.displayName ?? "").toString().trim();

  const displayNameLower = displayName.toLowerCase();

  const nomeLower = nome.toLowerCase();
  const cognomeLower = cognome.toLowerCase();
  const nicknameLower = nickname.toLowerCase();

  const fullNameLower = [cognome, nome].filter(Boolean).join(" ").toLowerCase();
  const reverseNameLower = [nome, cognome].filter(Boolean).join(" ").toLowerCase();

  return {
    displayNome: nome,
    displayCognome: cognome,
    displayNomeLower: nomeLower,
    displayCognomeLower: cognomeLower,
    displayName,
    displayNameLower,
    fullNameLower,
    reverseNameLower,
    nickname: nickname || null,
    nicknameLower: nicknameLower || null,
    photoUrl: pub.photoUrl || null,
    photoV: asInt(pub.photoV ?? 0),
    coverUrl: pub.coverUrl || null,
    coverV: asInt(pub.coverV ?? 0),
    emailLogin: pub.email,
    emailLower: pub.emailLower,
  };
}







// ======================================================
// ✅ AUTO-SYNC PROFILO SELETTIVO + PULIZIA (privacy-based, always-sync)
// Trigger: qualsiasi modifica in Users/{uid}
// - UsersPublic + members: SOLO campi con mode = "public" (con pulizia campi rimossi)
// - sharedProfilesAll: SOLO campi con mode = "league" (delete se vuoto)
// - sharedProfiles: SOLO campi con mode in ("emails","owner","special","comparto") (delete se vuoto)
// - sharePreferences: salva le preferenze di condivisione per ogni lega
// Supporta campi dinamici (custom) creati dalle leghe
// ======================================================
export const onUserProfileWrite = onDocumentWritten(
  { region: REGION, document: "Users/{uid}" },
  async (event) => {
    const uid = event.params.uid;
    const afterSnap = event.data?.after;

    // 🧹 Utente eliminato
    if (!afterSnap?.exists) {
      await db.collection("UsersPublic").doc(uid).delete().catch(() => {});
      return;
    }

    const afterData = afterSnap.data() ?? {};
    const profile = afterData.profile ?? {};

    const custom: Record<string, any> =
      typeof profile.custom === "object" && !Array.isArray(profile.custom)
        ? { ...profile.custom }
        : {};

    const privacy: Record<string, any> =
      typeof profile.privacy === "object" ? profile.privacy : {};

    // ----------------------------
    // 🔎 MODE RESOLVER
    // ----------------------------
    function getMode(fieldKey: string): string {
  // fieldKey può essere: "nome" oppure "custom.nome"
  const rawKey = fieldKey.startsWith("custom.") ? fieldKey.substring("custom.".length) : fieldKey;

  // ✅ sempre pubblici (chiave raw)
  if (ALWAYS_PUBLIC_FIELDS.has(rawKey)) return "public";

  const p = privacy[rawKey] ?? privacy[fieldKey] ?? {};
  const mode = (p.mode ?? "").toString().toLowerCase();

  if (mode) return mode;
  if (SENSITIVE_FIELDS.has(rawKey)) return "private";
  return "private";
}


    // ----------------------------
    // 🎯 FILTRI
    // ----------------------------
    function filterCustomByModes(modes: string[]) {
      const out: Record<string, any> = {};
      for (const [k, v] of Object.entries(custom)) {
        const mode = getMode(`custom.${k}`);
        if (modes.includes(mode)) out[k] = v;
      }
      return out;
    }

    const profilePublic = filterCustomByModes(["public"]);


    // ----------------------------
    // 👤 PROFILO PUBBLICO BASE
    // ----------------------------
    const pub = resolvePublicFromUserDoc(afterData);
    const derived = memberPublicFields(pub);

    // forza always-public
    if (pub.nome) profilePublic.nome = pub.nome;
    if (pub.cognome) profilePublic.cognome = pub.cognome;
    if (pub.nickname) profilePublic.nickname = pub.nickname;
    if (pub.photoUrl) profilePublic.photoUrl = pub.photoUrl;
    profilePublic.photoV = pub.photoV;
    if (pub.coverUrl) profilePublic.coverUrl = pub.coverUrl;
    profilePublic.coverV = pub.coverV;

    // ----------------------------
    // 📦 PAYLOADS
    // ----------------------------
    const payloadUsersPublic = {
      uid,
      fields: profilePublic,
      ...derived,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const payloadMembers = {
      uid,
      ...profilePublic,
      ...derived,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // ----------------------------
    // 1️⃣ UsersPublic
    // ----------------------------
    if (Object.keys(profilePublic).length > 0) {
      await db
        .collection("UsersPublic")
        .doc(uid)
        .set(payloadUsersPublic, { merge: false });
    } else {
      await db.collection("UsersPublic").doc(uid).delete().catch(() => {});
    }

    // ----------------------------
    // 2️⃣ Members (tutte le leghe)
    // ----------------------------
    const leagueIds: string[] = Array.isArray(afterData.leagueIds)
      ? afterData.leagueIds
      : [];

    for (const leagueId of leagueIds) {
      const mRef = db
        .collection("Leagues")
        .doc(leagueId)
        .collection("members")
        .doc(uid);

      await mRef.set(payloadMembers, { merge: true });
    }
  }
);


// ======================================================
        // ==== END onUserProfileWrite ====
// ======================================================




// ======================================================
// ⚙️ CALLABLE FUNCTIONS
// ======================================================

// ------------------------
// UPLOAD LOGO
// ------------------------
async function uploadLogoAndGetUrl(leagueId: string, base64: string, contentType: string) {
  const bytes = Buffer.from(base64, "base64");
  const path = `league_icons/${leagueId}.jpg`;
  const token = crypto.randomBytes(16).toString("hex");

  const file = bucket.file(path);
  await file.save(bytes, {
    contentType: contentType || "image/jpeg",
    resumable: false,
    metadata: {
      metadata: { firebaseStorageDownloadTokens: token },
    },
  });

  const encodedPath = encodeURIComponent(path);
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${token}`;
}




// ======================================================
// ⚙️ ROLE & PERMISSION HELPERS (usati da funzioni manager)
// ======================================================
async function roleAllows(leagueId: string, roleId: string, permKey: string): Promise<boolean> {
  if (!roleId) return false;
  if (roleId === "OWNER") return true;

  const roleSnap = await db.collection("Leagues").doc(leagueId).collection("roles").doc(roleId).get();
  if (!roleSnap.exists) return false;

  const perms = ((roleSnap.data() ?? {}).permissions ?? {}) as Record<string, any>;
  return perms[permKey] === true;
}

async function callerIsManager(leagueId: string, uid: string, permKey: string): Promise<boolean> {
  const mSnap = await db.collection("Leagues").doc(leagueId).collection("members").doc(uid).get();
  if (!mSnap.exists) return false;
  const roleId = (mSnap.data()?.roleId ?? "").toString();
  return roleAllows(leagueId, roleId, permKey);
}






// ------------------------
// CREATE LEAGUE
// ------------------------
export const createLeague = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);

  const nome = (req.data?.nome ?? "").toString().trim();
  if (!nome) throw new HttpsError("invalid-argument", "Nome mancante.");

  // ✅ nuovi campi richiesti al creatore
  const creatorNome = (req.data?.creatorNome ?? "").toString().trim();
  const creatorCognome = (req.data?.creatorCognome ?? "").toString().trim();
  if (!creatorNome || !creatorCognome) {
    throw new HttpsError("invalid-argument", "Inserisci Nome e Cognome del creatore.");
  }

  const ensured = await ensureUserDoc(uid);

  // ✅ prendo eventuali photo/cover/nickname già presenti
  const userSnap = await db.collection("Users").doc(uid).get();
  const u0 = (userSnap.data() ?? {}) as Record<string, any>;

  // ✅ costruisco pub usando i valori inseriti (Cognome Nome)
  const pub = resolvePublicFromUserDoc(
    { ...u0, nome: creatorNome, cognome: creatorCognome },
    ensured
  );

  // joinCode unico
  let joinCode = randomJoinCode(6);
  for (let i = 0; i < 10; i++) {
    const q = await db.collection("Leagues").where("joinCode", "==", joinCode).limit(1).get();
    if (q.empty) break;
    joinCode = randomJoinCode(6);
  }

  const leagueRef = db.collection("Leagues").doc();
  const leagueId = leagueRef.id;

  // logo
  let logoUrl = "";
  const logoBase64 = (req.data?.logoBase64 ?? "").toString().trim();
  const logoContentType = (req.data?.logoContentType ?? "image/jpeg").toString();
  if (logoBase64) logoUrl = await uploadLogoAndGetUrl(leagueId, logoBase64, logoContentType);

  await db.runTransaction(async (tx) => {
    tx.set(leagueRef, {
      nome,
      joinCode,
      joinCodeUpper: joinCode,
      createdByUid: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      logoUrl: logoUrl || null,
      memberCount: 1,
    });

    const ownerRoleRef = leagueRef.collection("roles").doc("OWNER");
    tx.set(
      ownerRoleRef,
      {
        name: "Owner",
        tier: 1,
        permissions: {
          invites_manage: true,
          roles_manage: true,
          members_manage: true,
          members_sensitive_read: true,
          programmi_read: true,
          programmi_write: true,
          mezzi_read: true,
          mezzi_write: true,
          manutenzioni_read: true,
          manutenzioni_write: true,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // ✅ member creato dalla function (no bootstrap dal client)
    const memberRef = leagueRef.collection("members").doc(uid);
    tx.set(
      memberRef,
      {
        uid,
        roleId: "OWNER",
        joinCode,
        ...memberPublicFields(pub),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // ✅ aggiorno Users (server-side): nome/cognome + activeLeagueId
    tx.set(
      db.collection("Users").doc(uid),
      {
        nome: creatorNome,
        cognome: creatorCognome,
        activeLeagueId: leagueId,
        leagueIds: admin.firestore.FieldValue.arrayUnion(leagueId),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });

  return { ok: true, leagueId, joinCode, logoUrl };
});


// ------------------------
// LIST LEAGUES FOR USER
// ------------------------
export const listLeaguesForUser = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const { emailLower } = await ensureUserDoc(uid);

  const userSnap = await db.collection("Users").doc(uid).get();
  const u = userSnap.data() ?? {};
  const activeLeagueId = (u.activeLeagueId ?? "").toString().trim();

  let leagueIds: string[] = Array.isArray(u.leagueIds)
    ? u.leagueIds.map((x: any) => (x ?? "").toString()).filter(Boolean)
    : [];

  if (leagueIds.length === 0) {
    try {
      const qs = await db.collectionGroup("members").where("uid", "==", uid).limit(100).get();
      leagueIds = qs.docs.map((d) => d.ref.parent.parent?.id ?? "").filter(Boolean);
    } catch (_) {}
  }

  const joined: any[] = [];
  for (const lid of [...new Set(leagueIds)].slice(0, 200)) {
    const ls = await db.collection("Leagues").doc(lid).get();
    if (!ls.exists) continue;
    const d = ls.data() ?? {};
    joined.push({
      leagueId: lid,
      nome: (d.nome ?? "League").toString(),
      joinCode: (d.joinCode ?? "").toString(),
      logoUrl: (d.logoUrl ?? "").toString(),
      active: lid === activeLeagueId,
    });
  }

  joined.sort((a, b) => {
    if (a.active && !b.active) return -1;
    if (b.active && !a.active) return 1;
    return a.nome.toLowerCase().localeCompare(b.nome.toLowerCase());
  });

  const invitedMap = new Map<string, any>();
  async function runInviteQuery(field: string) {
    try {
      const qs = await db.collectionGroup("invites").where(field, "==", emailLower).limit(200).get();
      for (const doc of qs.docs) {
        const inv = doc.data() ?? {};
        const status = (inv.status ?? "pending").toString().toLowerCase();
        if (status === "revoked" || status === "deleted") continue;

        const leagueRef = doc.ref.parent.parent;
        if (!leagueRef) continue;
        const leagueId = leagueRef.id;
        const key = `${leagueId}:${doc.id}`;
        if (invitedMap.has(key)) continue;

        const leagueSnap = await leagueRef.get();
        const ld = leagueSnap.data() ?? {};

        invitedMap.set(key, {
          leagueId,
          inviteId: doc.id,
          roleId: (inv.roleId ?? "member").toString(),
          nome: (ld.nome ?? "Lega").toString(),
          logoUrl: (ld.logoUrl ?? "").toString(),
        });
      }
    } catch (_) {}
  }

  await runInviteQuery("emailLower");
  await runInviteQuery("toEmailLower");
  await runInviteQuery("invitedEmailLower");

  const invited = Array.from(invitedMap.values()).sort((a, b) =>
    a.nome.toLowerCase().localeCompare(b.nome.toLowerCase())
  );

  return { ok: true, activeLeagueId, joined, invited };
});

// ------------------------
// SET ACTIVE LEAGUE
// ------------------------
export const setActiveLeague = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const leagueId = (req.data?.leagueId ?? "").toString().trim();
  if (!leagueId) throw new HttpsError("invalid-argument", "leagueId mancante");

  const m = await db.collection("Leagues").doc(leagueId).collection("members").doc(uid).get();
  if (!m.exists) throw new HttpsError("permission-denied", "Non sei membro di questa lega.");

  await db.collection("Users").doc(uid).set(
    { activeLeagueId: leagueId, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );

  return { ok: true, leagueId };
});

// ------------------------
// ACCEPT INVITE
// ------------------------
export const acceptInvite = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const leagueId = (req.data?.leagueId ?? "").toString().trim();
  const inviteId = (req.data?.inviteId ?? "").toString().trim();
  if (!leagueId || !inviteId) throw new HttpsError("invalid-argument", "Parametri mancanti.");

  const ensured = await ensureUserDoc(uid);
  const pub = await getLeaguePublicProfile(uid, ensured);

  const leagueRef = db.collection("Leagues").doc(leagueId);
  const invRef = leagueRef.collection("invites").doc(inviteId);
  let outRoleId = "member";

  await db.runTransaction(async (tx) => {
    const leagueSnap = await tx.get(leagueRef);
    if (!leagueSnap.exists) throw new HttpsError("not-found", "Lega non trovata");
    const league = leagueSnap.data() ?? {};
    const createdByUid = (league.createdByUid ?? "").toString().trim();
    const joinCode = (league.joinCode ?? "").toString().toUpperCase();

    const invSnap = await tx.get(invRef);
    if (!invSnap.exists) throw new HttpsError("not-found", "Invito non trovato");
    const inv = invSnap.data() ?? {};
    if ((inv.status ?? "pending") !== "pending") {
      throw new HttpsError("failed-precondition", "Invito non più valido");
    }

    const invitedRoleId = (inv.roleId ?? "member").toString().trim() || "member";
    const computedRoleId = createdByUid === uid ? "OWNER" : invitedRoleId;
    outRoleId = computedRoleId;

    const memberRef = leagueRef.collection("members").doc(uid);
    const mSnap = await tx.get(memberRef);
    if (!mSnap.exists) {
      tx.set(leagueRef, { memberCount: admin.firestore.FieldValue.increment(1) }, { merge: true });
    }

    tx.set(
      memberRef,
      {
        uid,
        roleId: computedRoleId,
        joinCode: joinCode || null,
        ...memberPublicFields(pub),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.set(
      invRef,
      {
        status: "accepted",
        acceptedByUid: uid,
        acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.set(
      db.collection("Users").doc(uid),
      {
        activeLeagueId: leagueId,
        leagueIds: admin.firestore.FieldValue.arrayUnion(leagueId),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });

  return { ok: true, leagueId, inviteId, roleId: outRoleId };
});

// ------------------------
// REQUEST JOIN BY CODE
// ------------------------
export const requestJoinByCode = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const joinCode = (req.data?.joinCode ?? "").toString().trim().toUpperCase();
  if (!joinCode) throw new HttpsError("invalid-argument", "JoinCode mancante");

  const ensured = await ensureUserDoc(uid);
  const pub = await getLeaguePublicProfile(uid, ensured);

  const q = await db.collection("Leagues").where("joinCodeUpper", "==", joinCode).limit(1).get();
  if (q.empty) throw new HttpsError("not-found", "JoinCode non trovato");

  const leagueId = q.docs[0].id;
  const leagueRef = db.collection("Leagues").doc(leagueId);

  const memberSnap = await leagueRef.collection("members").doc(uid).get();
  if (memberSnap.exists) {
    await db.collection("Users").doc(uid).set(
      {
        activeLeagueId: leagueId,
        leagueIds: admin.firestore.FieldValue.arrayUnion(leagueId),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return { ok: true, leagueId, alreadyMember: true, alreadyRequested: false };
  }

  const reqRef = leagueRef.collection("joinRequests").doc(uid);
  const reqSnap = await reqRef.get();
  const status = (reqSnap.data()?.status ?? "").toString().toLowerCase();
  if (reqSnap.exists && status === "pending") {
    return { ok: true, leagueId, alreadyMember: false, alreadyRequested: true };
  }

  await reqRef.set(
    {
      uid,
      status: "pending",
      ...memberPublicFields(pub),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return { ok: true, leagueId, alreadyMember: false, alreadyRequested: false };
});




// ======================================================
// 🧩 BLOCCO 4/4 — JOIN REQUESTS MANAGEMENT (MANAGER)
// ======================================================

// ------------------------
// LIST JOIN REQUESTS (pending)
// ------------------------
export const listJoinRequests = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const leagueId = (req.data?.leagueId ?? "").toString().trim();
  if (!leagueId) throw new HttpsError("invalid-argument", "leagueId mancante");

  const allowed = await callerIsManager(leagueId, uid, "members_manage");
  if (!allowed) throw new HttpsError("permission-denied", "Non autorizzato.");

  const qs = await db
    .collection("Leagues")
    .doc(leagueId)
    .collection("joinRequests")
    .where("status", "==", "pending")
    .orderBy("createdAt", "desc")
    .limit(200)
    .get();

  return {
    ok: true,
    requests: qs.docs.map((d) => ({ id: d.id, ...d.data() })),
  };
});

// ------------------------
// RESPOND TO JOIN REQUEST (accept/reject)
// ------------------------
async function respondToJoinRequestImpl(
  req: any,
  override?: {
    leagueId: string;
    requestId: string;
    accept: boolean;
    roleId?: string;
  }
) {
  const uid = requireAuth(req);

  const leagueId = (override?.leagueId ?? req.data?.leagueId ?? "").toString().trim();
  const requestId = (override?.requestId ?? req.data?.requestId ?? "").toString().trim();
  const accept = override?.accept ?? (req.data?.accept === true);
  const roleId = (override?.roleId ?? req.data?.roleId ?? "member").toString().trim() || "member";

  if (!leagueId || !requestId) {
    throw new HttpsError("invalid-argument", "leagueId/requestId mancanti");
  }

  const allowed = await callerIsManager(leagueId, uid, "members_manage");
  if (!allowed) throw new HttpsError("permission-denied", "Non autorizzato.");

  const leagueRef = db.collection("Leagues").doc(leagueId);
  const reqRef = leagueRef.collection("joinRequests").doc(requestId);

  const preSnap = await reqRef.get();
  if (!preSnap.exists) throw new HttpsError("not-found", "Richiesta non trovata");

  const preData = preSnap.data() ?? {};
  const preStatus = (preData.status ?? "").toString().toLowerCase().trim();
  if (preStatus !== "pending") throw new HttpsError("failed-precondition", "Richiesta già gestita");

  const targetUid = (preData.uid ?? requestId).toString().trim();
  const ensuredTarget = await ensureUserDoc(targetUid);
  const pubTarget = await getLeaguePublicProfile(targetUid, ensuredTarget);

  await db.runTransaction(async (tx) => {
    const reqSnap = await tx.get(reqRef);
    if (!reqSnap.exists) throw new HttpsError("not-found", "Richiesta non trovata");

    const data = reqSnap.data() ?? {};
    const status = (data.status ?? "").toString().toLowerCase().trim();
    if (status !== "pending") throw new HttpsError("failed-precondition", "Richiesta già gestita");

    // REJECT
    if (!accept) {
      tx.set(
        reqRef,
        {
          status: "rejected",
          decidedByUid: uid,
          decidedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return;
    }

    // ACCEPT → crea membro
    const memberRef = leagueRef.collection("members").doc(targetUid);
    const mSnap = await tx.get(memberRef);
    if (!mSnap.exists) {
      tx.set(leagueRef, { memberCount: admin.firestore.FieldValue.increment(1) }, { merge: true });
    }

    tx.set(
      memberRef,
      {
        uid: targetUid,
        roleId,
        ...memberPublicFields(pubTarget),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.set(
      db.collection("Users").doc(targetUid),
      {
        activeLeagueId: leagueId,
        leagueIds: admin.firestore.FieldValue.arrayUnion(leagueId),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.set(
      reqRef,
      {
        status: "accepted",
        decidedByUid: uid,
        decidedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });

  return { ok: true, leagueId, requestId, accept };
}

// Wrapper callable
export const respondToJoinRequest = onCall({ region: REGION }, async (req) => {
  return respondToJoinRequestImpl(req);
});

// ------------------------
// (Compat) acceptJoinRequest — per retrocompatibilità
// ------------------------
export const acceptJoinRequest = onCall({ region: REGION }, async (req) => {
  const leagueId = (req.data?.leagueId ?? "").toString().trim();
  const requesterUid = (req.data?.requesterUid ?? req.data?.requestId ?? "").toString().trim();

  if (!leagueId || !requesterUid) {
    throw new HttpsError("invalid-argument", "leagueId/requesterUid mancanti");
  }

  return respondToJoinRequestImpl(req, { leagueId, requestId: requesterUid, accept: true });
});
