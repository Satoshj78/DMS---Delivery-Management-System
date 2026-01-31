import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as crypto from "crypto";
import { FieldPath } from "firebase-admin/firestore";


admin.initializeApp();

const db = admin.firestore();
const bucket = admin.storage().bucket();

// ✅ Regione principale
const REGION = "europe-west1";
const SYNC_VERSION = "sync-2026-01-31-members-v3";
const DEBUG_SYNC = true; // metti false quando hai finito



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

  // ✅ leggo PRIMA (fuori tx) l'eventuale vecchio nicknameLower, solo read
  let oldLower = "";
  try {
    const userSnap = await db.collection("Users").doc(userId).get();
    oldLower = ((userSnap.data()?.nicknameLower ?? "") as string).toLowerCase();
  } catch (_) {}

  await db.runTransaction(async (tx) => {
    const nickSnap = await tx.get(nickRef);

    // se nickname già preso da altro uid → KO
    if (nickSnap.exists) {
      const ownerUid = (nickSnap.data()?.uid ?? "") as string;
      if (ownerUid && ownerUid !== userId) {
        throw new HttpsError("already-exists", "Nickname già in uso.");
      }
    }

    // libera eventuale vecchio nickname (se era mio)
    if (oldLower && oldLower !== lower) {
      const oldRef = db.collection("Nicknames").doc(oldLower);
      const oldSnap = await tx.get(oldRef);
      if (oldSnap.exists && (oldSnap.data()?.uid ?? "") === userId) {
        tx.delete(oldRef);
      }
    }

    // ✅ scrivo SOLO su Nicknames
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
  });
}


export const setNickname = onCall({ region: REGION }, async (req) => {
  const userId = requireAuth(req);
  const { nickname, lower } = normalizeNickname(req.data?.nickname);

  await setNicknameTxn(userId, nickname, lower);

  // ✅ Il client aggiorna Users/{uid}.profile.custom.nickname ecc.
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
export const updateMyProfile = onCall({ region: REGION }, async (_req) => {
  throw new HttpsError(
    "failed-precondition",
    "updateMyProfile disabilitata: il client deve scrivere direttamente su Users/{uid}. Le functions propagano soltanto."
  );
});

export const updateUserProfileField = onCall({ region: REGION }, async (_req) => {
  throw new HttpsError(
    "failed-precondition",
    "updateUserProfileField disabilitata: il client deve scrivere direttamente su Users/{uid}. Le functions propagano soltanto."
  );
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




function callerEmailFromAuth(req: any): { email: string; emailLower: string } {
  const email = (req.auth?.token?.email ?? "").toString().trim();
  return { email, emailLower: email ? email.toLowerCase() : "" };
}

async function readUserDocIfExists(uid: string): Promise<Record<string, any>> {
  try {
    const snap = await db.collection("Users").doc(uid).get();
    return (snap.exists ? (snap.data() ?? {}) : {}) as Record<string, any>;
  } catch {
    return {};
  }
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

  // ✅ PRIORITÀ: profile.custom -> (alias) -> legacy
  const nome =
    (custom?.nome ??
      custom?.firstName ?? // alias
      profile?.nome ??
      u?.nome ??
      "").toString().trim();

  const cognome =
    (custom?.cognome ??
      custom?.lastName ?? // alias
      profile?.cognome ??
      u?.cognome ??
      "").toString().trim();

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




// ✅ SOLO campi "pubblici" da mettere dentro members.fields (niente derived)
function buildMemberFieldsPayload(pub: {
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
  return {
    nome: (pub.nome ?? "").toString().trim() || null,
    cognome: (pub.cognome ?? "").toString().trim() || null,
    displayName: (pub.displayName ?? "").toString().trim() || null,
    nickname: (pub.nickname ?? "").toString().trim() || null,

    photoUrl: (pub.photoUrl ?? "").toString().trim() || null,
    photoV: asInt(pub.photoV ?? 0),

    coverUrl: (pub.coverUrl ?? "").toString().trim() || null,
    coverV: asInt(pub.coverV ?? 0),

    emailLogin: (pub.email ?? "").toString().trim() || null,
    emailLower: (pub.emailLower ?? "").toString().trim() || null,
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






// ======================================================
// ✅ AUTO-SYNC PROFILO SELETTIVO + PULIZIA (privacy-based)
// Trigger: qualsiasi modifica in Users/{uid}
// - UsersPublic: SOLO campi con mode = "publicGlobal" (+ ALWAYS_PUBLIC)
// - members: campi con mode = "publicLeague" + "publicGlobal" (+ ALWAYS_PUBLIC)
// - pulizia: se un campo era pubblico prima e ora non lo è più → delete
// ======================================================
export const onUserProfileWrite = onDocumentWritten(
  { region: REGION, document: "Users/{uid}" },
  async (event) => {
    const uid = event.params.uid;
    const afterSnap = event.data?.after;
    const beforeSnap = event.data?.before;



// ---------- DEBUG HELPERS ----------
const runId = `${Date.now()}_${Math.random().toString(16).slice(2)}`;

async function debugSet(data: Record<string, any>) {
  if (!DEBUG_SYNC) return;
  try {
    await db.collection("_debugSync").doc(uid).set(
      {
        uid,
        runId,
        syncVersion: SYNC_VERSION,
        ...data,
        ts: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  } catch (_) {}
}

console.log("[SYNC]", SYNC_VERSION, "runId:", runId, "uid:", uid, "afterExists:", !!afterSnap?.exists);
await debugSet({ stage: "start", afterExists: !!afterSnap?.exists });
// -----------------------------------




// 🔥 HEARTBEAT: ogni volta che la function gira, scrive qui
await db.collection("_debugSync").doc(uid).set(
  {
    uid,
    syncVersion: SYNC_VERSION,
    ranAt: admin.firestore.FieldValue.serverTimestamp(),
    afterExists: !!afterSnap?.exists,
  },
  { merge: true }
);




    // ----------------------------
// 🧹 DELETE USER (account eliminato)
// - elimina UsersPublic (sparisce dalle ricerche globali)
// - libera Nicknames/{nicknameLower}
// - per ogni lega: salva snapshot storico in membersArchive/{uid}
//   poi anonimizza members/{uid} (userDeleted=true)
// ----------------------------
if (!afterSnap?.exists) {
  // 1) ELIMINA traccia globale
  await db.collection("UsersPublic").doc(uid).delete().catch(() => {});

  // 2) Libera nickname globale (se presente nel BEFORE)
  try {
    const beforeData = (beforeSnap?.exists ? (beforeSnap.data() ?? {}) : {}) as Record<string, any>;
    const beforeProfile = (beforeData.profile ?? {}) as Record<string, any>;
    const beforeCustom = (beforeProfile.custom ?? {}) as Record<string, any>;

    const oldLower = (
      beforeData.nicknameLower ??
      beforeCustom.nicknameLower ??
      beforeCustom.nickname ??
      ""
)
.toString()
.toLowerCase()
.trim();

    if (oldLower) {
      await db.collection("Nicknames").doc(oldLower).delete().catch(() => {});
    }
  } catch (_) {}

  // 3) Trova tutti i member docs dell’utente in tutte le leghe
  const memberQs = await db.collectionGroup("members").where("uid", "==", uid).get();

  const docsToUpdate = memberQs.empty
    ? (await db.collectionGroup("members").where(FieldPath.documentId(), "==", uid).get()).docs
    : memberQs.docs;

  if (docsToUpdate.length === 0) return;

  // 4) BulkWriter (più veloce e meno timeout)
  const writer = db.bulkWriter();

  for (const d of docsToUpdate) {
    const leagueRef = d.ref.parent.parent; // Leagues/{leagueId}
    if (!leagueRef) continue;

    const snapData = d.data() ?? {};

    // 4a) ARCHIVIO storico (admin-only)
    const archiveRef = leagueRef.collection("membersArchive").doc(uid);
    writer.set(
      archiveRef,
      {
        uid,
        archivedAt: admin.firestore.FieldValue.serverTimestamp(),
        snapshot: snapData,
      },
      { merge: true }
    );

    // 4b) ANONIMIZZA member
    writer.set(
      d.ref,
      {
        userDeleted: true,
        userDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
        archived: true,

        // campi pubblici "neutri" in fields
        fields: {
          nome: null,
          cognome: null,
          displayName: "Utente eliminato",
          nickname: null,
          photoUrl: null,
          photoV: 0,
          coverUrl: null,
          coverV: 0,
          emailLogin: null,
          emailLower: null,
        },

        // derived per ricerche: svuota tutto
        displayName: "Utente eliminato",
        displayNameLower: "",
        fullNameLower: "",
        reverseNameLower: "",
        nicknameLower: "",
        displayNomeLower: "",
        displayCognomeLower: "",
        emailLower: "",

        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }

  await writer.close().catch(() => {});
  return;
}




    const afterData = (afterSnap.data() ?? {}) as Record<string, any>;
    const beforeData = (beforeSnap?.exists ? (beforeSnap.data() ?? {}) : {}) as Record<string, any>;

    const afterProfile = (afterData.profile ?? {}) as Record<string, any>;
    const afterCustom = { ...((afterProfile.custom ?? {}) as Record<string, any>) };
    const afterPrivacy = (afterProfile.privacy ?? {}) as Record<string, any>;

    const beforeProfile = (beforeData.profile ?? {}) as Record<string, any>;
    const beforeCustom = { ...((beforeProfile.custom ?? {}) as Record<string, any>) };
    const beforePrivacy = (beforeProfile.privacy ?? {}) as Record<string, any>;

    // ----------------------------
    // 🔐 PRIVACY RESOLVER
    // ----------------------------
    function getModeFrom(privacyObj: any, rawKey: string): string {
  // Always public forzato
  if (ALWAYS_PUBLIC_FIELDS.has(rawKey)) return "publicGlobal";

  const p = privacyObj?.[rawKey] ?? {};
  const modeRaw = (p?.mode ?? p?.visibility ?? "").toString().trim();
  const mode = modeRaw.toLowerCase();

  // canonici
  if (mode === "publicglobal") return "publicGlobal";
  if (mode === "publicleague") return "publicLeague";

  // ✅ alias che nel tuo progetto può comparire (plural)
  if (mode === "publicleagues") return "publicLeague";

  // retrocompat
  if (mode === "public") return "publicGlobal";
  if (mode === "league") return "publicLeague";
  if (mode === "private") return "private";
  if (mode === "uids") return "uids";
  if (mode === "emails") return "emails";

  // default
  if (SENSITIVE_FIELDS.has(rawKey)) return "private";
  return "private";
}


    // ----------------------------
    // 🧽 Normalizza valori "svuotati"
    // ----------------------------
    function normalizePublicValue(v: any): any {
      if (v === undefined || v === null) return null;

      if (typeof v === "string") {
        const t = v.trim();
        return t.length ? t : null;
      }

      if (Array.isArray(v)) {
        return v.length ? v : null;
      }

      if (typeof v === "object") {
        const keys = Object.keys(v);
        return keys.length ? v : null;
      }

      return v;
    }

    // ----------------------------
    // 🎯 PUBLIC FIELDS (AFTER)
    // ----------------------------
    const globalPublicCustom: Record<string, any> = {}; // -> UsersPublic (+ anche members)
    const leaguePublicCustom: Record<string, any> = {}; // -> solo members (include anche global)

    for (const [k, v] of Object.entries(afterCustom)) {
      const m = getModeFrom(afterPrivacy, k);

      if (m === "publicGlobal") {
        const nv = normalizePublicValue(v);
        globalPublicCustom[k] = nv;
        leaguePublicCustom[k] = nv;
      } else if (m === "publicLeague") {
        leaguePublicCustom[k] = normalizePublicValue(v);
      }
    }

    // ----------------------------
    // 🎯 PUBLIC FIELDS (BEFORE) per pulizia
    // ----------------------------
    const beforeGlobalPublicCustom: Record<string, any> = {};
    const beforeLeaguePublicCustom: Record<string, any> = {};

    for (const [k, v] of Object.entries(beforeCustom)) {
      const m = getModeFrom(beforePrivacy, k);

      if (m === "publicGlobal") {
        const nv = normalizePublicValue(v);
        beforeGlobalPublicCustom[k] = nv;
        beforeLeaguePublicCustom[k] = nv;
      } else if (m === "publicLeague") {
        beforeLeaguePublicCustom[k] = normalizePublicValue(v);
      }
    }

    // ----------------------------
    // 👤 BASE PUBLIC PROFILE (AFTER)
    // ----------------------------
    const pub = resolvePublicFromUserDoc(afterData);
    const derived = memberPublicFields(pub);

    // ✅ ALWAYS PUBLIC: forzali nel GLOBAL (e quindi anche nel LEAGUE)
    globalPublicCustom.nome = normalizePublicValue(pub.nome);
    globalPublicCustom.cognome = normalizePublicValue(pub.cognome);
    globalPublicCustom.nickname = normalizePublicValue(pub.nickname);
    globalPublicCustom.photoUrl = normalizePublicValue(pub.photoUrl);
    globalPublicCustom.coverUrl = normalizePublicValue(pub.coverUrl);
    globalPublicCustom.photoV = asInt(pub.photoV ?? 0);
    globalPublicCustom.coverV = asInt(pub.coverV ?? 0);

    // alias sempre propagati (null se vuoti)
    globalPublicCustom.pensiero = normalizePublicValue(afterCustom?.pensiero);
    globalPublicCustom.thought = normalizePublicValue(afterCustom?.thought);

    // include i global anche nel league
    Object.assign(leaguePublicCustom, globalPublicCustom);

    // ----------------------------
    // 👤 BASE PUBLIC PROFILE (BEFORE) per pulizia
    // ----------------------------
    const beforePub = resolvePublicFromUserDoc(beforeData);

    beforeGlobalPublicCustom.nome = normalizePublicValue(beforePub.nome);
    beforeGlobalPublicCustom.cognome = normalizePublicValue(beforePub.cognome);
    beforeGlobalPublicCustom.nickname = normalizePublicValue(beforePub.nickname);
    beforeGlobalPublicCustom.photoUrl = normalizePublicValue(beforePub.photoUrl);
    beforeGlobalPublicCustom.coverUrl = normalizePublicValue(beforePub.coverUrl);
    beforeGlobalPublicCustom.photoV = asInt(beforePub.photoV ?? 0);
    beforeGlobalPublicCustom.coverV = asInt(beforePub.coverV ?? 0);
    beforeGlobalPublicCustom.pensiero = normalizePublicValue(beforeCustom?.pensiero);
    beforeGlobalPublicCustom.thought = normalizePublicValue(beforeCustom?.thought);

    Object.assign(beforeLeaguePublicCustom, beforeGlobalPublicCustom);

    // ----------------------------
    // 🧹 DELETE MAPS
    // - UsersPublic: cancella SOLO campi che prima erano GLOBAL e ora NON lo sono più
    // - Members: cancella campi che prima erano LEAGUE (o GLOBAL) e ora NON lo sono più
    // ----------------------------

    // ✅ FIX: deletes "robusti" dentro fields (non fields.k con path a punti)
    const usersPublicFieldDeletes: Record<string, any> = {};
    for (const k of Object.keys(beforeGlobalPublicCustom)) {
      if (!(k in globalPublicCustom)) {
        usersPublicFieldDeletes[k] = admin.firestore.FieldValue.delete();
      }
    }

    const memberDeletes: Record<string, any> = {};
    for (const k of Object.keys(beforeLeaguePublicCustom)) {
      if (!(k in leaguePublicCustom)) {
        memberDeletes[k] = admin.firestore.FieldValue.delete();
      }
    }

        // ----------------------------
    // 📦 USERS PUBLIC (SOLO GLOBAL)
    // ----------------------------


await debugSet({
  stage: "before_usersPublic_write",
  globalKeys: Object.keys(globalPublicCustom).slice(0, 50),
});

    await db.collection("UsersPublic").doc(uid).set(
      {
        uid,
__syncVersion: SYNC_VERSION, // 👈 marker
        fields: {
          ...globalPublicCustom,
          ...usersPublicFieldDeletes,
        },
        ...derived,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

await debugSet({ stage: "after_usersPublic_write" });


// ----------------------------
// 🔁 MEMBERS (ALL LEAGUES) — LOG POTENTE (uid field)
// ----------------------------
await debugSet({ stage: "before_members_query" });

let docsToUpdate: FirebaseFirestore.QueryDocumentSnapshot[] = [];

try {
  const qs = await db
    .collectionGroup("members")
    .where("uid", "==", uid)
    .get();

  docsToUpdate = qs.docs;

  // log base
  console.log("[SYNC]", SYNC_VERSION, "members found by uid field:", docsToUpdate.length);

  // sample + primi path
  const samplePath = docsToUpdate[0]?.ref?.path ?? null;
  const firstPaths = docsToUpdate.slice(0, 10).map((d) => d.ref.path);

  console.log("[SYNC]", SYNC_VERSION, "members samplePath:", samplePath);
  console.log("[SYNC]", SYNC_VERSION, "members firstPaths(<=10):", firstPaths);

  await debugSet({
    stage: "members_query_ok",
    membersFound: docsToUpdate.length,
    samplePath,
    firstPaths,
  });
} catch (err: any) {
  console.error("[SYNC] members query failed:", err);
  await debugSet({
    stage: "members_query_failed",
    error: String(err?.message ?? err),
  });
  return;
}

if (docsToUpdate.length === 0) {
  console.log("[SYNC] NO members docs found for uid:", uid);
  await debugSet({
    stage: "members_none",
    hint:
      "Nessun /Leagues/{leagueId}/members con campo uid==uid trovato. Possibile: members creati senza campo uid.",
  });
  return;
}

const writer = db.bulkWriter();
const errors: any[] = [];

writer.onWriteError((error) => {
  const e = {
    path: error.documentRef?.path ?? null,
    message: (error as any)?.message ?? "unknown",
    code: (error as any)?.code ?? null,
    failedAttempts: error.failedAttempts,
  };
  errors.push(e);
  console.error("[SYNC] BulkWriter error:", e);
  // retry 1 volta
  return error.failedAttempts < 2;
});

for (const d of docsToUpdate) {
  writer.set(
    d.ref,
    {
      uid,
      __syncVersion: SYNC_VERSION, // marker visibile sul doc member

      fields: {
        ...leaguePublicCustom,
        ...memberDeletes,
      },

      ...derived,

      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

try {
  await writer.close();
  console.log("[SYNC] members updated OK:", docsToUpdate.length);

  await debugSet({
    stage: "members_write_done",
    membersUpdated: docsToUpdate.length,
    errorsCount: errors.length,
    errorsSample: errors.slice(0, 5),
  });
} catch (err: any) {
  console.error("[SYNC] writer.close failed:", err);
  await debugSet({
    stage: "members_write_close_failed",
    error: String(err?.message ?? err),
    errorsCount: errors.length,
    errorsSample: errors.slice(0, 5),
  });
}













// 👇 chiudi SOLO il trigger
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

  const creatorNome = (req.data?.creatorNome ?? "").toString().trim();
  const creatorCognome = (req.data?.creatorCognome ?? "").toString().trim();
  if (!creatorNome || !creatorCognome) {
    throw new HttpsError("invalid-argument", "Inserisci Nome e Cognome del creatore.");
  }

  const { email, emailLower } = callerEmailFromAuth(req);

  const u0 = await readUserDocIfExists(uid);
  const p0 = (u0.profile ?? {}) as Record<string, any>;
  const c0 = (p0.custom ?? {}) as Record<string, any>;

  const simulatedAfter = {
    ...u0,
    email: u0.email ?? email,
    emailLower: u0.emailLower ?? emailLower,
    profile: {
      ...p0,
      custom: {
        ...c0,
        nome: creatorNome,
        cognome: creatorCognome,
      },
    },
  };

  const pub = resolvePublicFromUserDoc(simulatedAfter, { email, emailLower });

  let joinCode = randomJoinCode(6);
  for (let i = 0; i < 10; i++) {
    const q = await db.collection("Leagues").where("joinCode", "==", joinCode).limit(1).get();
    if (q.empty) break;
    joinCode = randomJoinCode(6);
  }

  const leagueRef = db.collection("Leagues").doc();
  const leagueId = leagueRef.id;

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


    const memberRef = leagueRef.collection("members").doc(uid);

const derived = memberPublicFields(pub);              // ✅ derived a root (ricerche/ordinamenti)
const fieldsPayload = buildMemberFieldsPayload(pub);  // ✅ SOLO valori pubblici dentro fields

tx.set(
  memberRef,
  {
    uid,
    roleId: "OWNER",
    joinCode,

    // ✅ campi pubblici "canonici"
    fields: fieldsPayload,

    // ✅ derived a root (displayNameLower, fullNameLower, ecc.)
    ...derived,

    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  },
  { merge: true }
);



    // ❌ NON SCRIVERE SU USERS
  });

  // ✅ Il client farà:
  // Users/{uid}.activeLeagueId = leagueId
  // Users/{uid}.leagueIds = arrayUnion(leagueId)
  return { ok: true, leagueId, joinCode, logoUrl };
});




// ------------------------
// LIST LEAGUES FOR USER
// ------------------------
export const listLeaguesForUser = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const { emailLower } = callerEmailFromAuth(req);

  // ✅ activeLeagueId: leggilo solo se Users esiste (read-only)
  let activeLeagueId = "";
  try {
    const userSnap = await db.collection("Users").doc(uid).get();
    const u = userSnap.data() ?? {};
    activeLeagueId = (u.activeLeagueId ?? "").toString().trim();
  } catch (_) {}

  // ✅ leagueIds: preferisci da Users se c’è (read-only), altrimenti group query members
  let leagueIds: string[] = [];
  try {
    const userSnap = await db.collection("Users").doc(uid).get();
    const u = userSnap.data() ?? {};
    leagueIds = Array.isArray(u.leagueIds)
      ? u.leagueIds.map((x: any) => (x ?? "").toString()).filter(Boolean)
      : [];
  } catch (_) {}

  if (leagueIds.length === 0) {
    try {
      const qs = await db.collectionGroup("members").where("uid", "==", uid).limit(200).get();
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

  // ✅ inviti: query per emailLower (se vuota → niente inviti)
  const invitedMap = new Map<string, any>();
  async function runInviteQuery(field: string) {
    if (!emailLower) return;
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

  // ❌ NON scrive Users
  // ✅ Il client aggiorna Users/{uid}.activeLeagueId
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

  const { email, emailLower } = callerEmailFromAuth(req);
const pub = await getLeaguePublicProfile(uid, { email, emailLower });


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


const derived = memberPublicFields(pub);
const fieldsPayload = buildMemberFieldsPayload(pub);

tx.set(
  memberRef,
  {
    uid,
    roleId: computedRoleId,
    joinCode: joinCode || null,

    fields: fieldsPayload,
    ...derived,

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

  const { email, emailLower } = callerEmailFromAuth(req);
const pub = await getLeaguePublicProfile(uid, { email, emailLower });


  const q = await db.collection("Leagues").where("joinCodeUpper", "==", joinCode).limit(1).get();
  if (q.empty) throw new HttpsError("not-found", "JoinCode non trovato");

  const leagueId = q.docs[0].id;
  const leagueRef = db.collection("Leagues").doc(leagueId);

  const memberSnap = await leagueRef.collection("members").doc(uid).get();
  if (memberSnap.exists) {

    return { ok: true, leagueId, alreadyMember: true, alreadyRequested: false };
  }

  const reqRef = leagueRef.collection("joinRequests").doc(uid);
  const reqSnap = await reqRef.get();
  const status = (reqSnap.data()?.status ?? "").toString().toLowerCase();
  if (reqSnap.exists && status === "pending") {
    return { ok: true, leagueId, alreadyMember: false, alreadyRequested: true };
  }


  const derived = memberPublicFields(pub);
const fieldsPayload = buildMemberFieldsPayload(pub);

await reqRef.set(
  {
    uid,
    status: "pending",

    // ✅ stessa struttura dei members
    fields: fieldsPayload,

    // ✅ derived a root (ricerche/ordinamenti)
    ...derived,

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
  const pubTarget = await getLeaguePublicProfile(targetUid, undefined);


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



const derived = memberPublicFields(pubTarget);
const fieldsPayload = buildMemberFieldsPayload(pubTarget);

tx.set(
  memberRef,
  {
    uid: targetUid,
    roleId,

    fields: fieldsPayload,
    ...derived,

    createdAt: admin.firestore.FieldValue.serverTimestamp(),
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



export const deleteMyAccount = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);

  // (Opzionale) elimina file Storage utente se li hai in un prefix noto
  // Esempio:
  // await bucket.deleteFiles({ prefix: `users/${uid}/` }).catch(() => {});

  // 1) Cancella Users/{uid} con Admin SDK → farà scattare onUserProfileWrite (branch delete)
  await db.collection("Users").doc(uid).delete().catch(() => {});

  // 2) Cancella Firebase Auth user
  await admin.auth().deleteUser(uid).catch(() => {});

  return { ok: true };
});






export const debugForceSyncMyMembers = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);

  const userSnap = await db.collection("Users").doc(uid).get();
  if (!userSnap.exists) throw new HttpsError("not-found", "Users doc not found");

  const afterData = (userSnap.data() ?? {}) as Record<string, any>;
  const pub = resolvePublicFromUserDoc(afterData);
  const derived = memberPublicFields(pub);

  // qui non applichiamo privacy: mettiamo SOLO ALWAYS_PUBLIC per test
  const leaguePublicCustom: Record<string, any> = {};
  leaguePublicCustom.nome = (pub.nome ?? null);
  leaguePublicCustom.cognome = (pub.cognome ?? null);
  leaguePublicCustom.nickname = (pub.nickname ?? null);
  leaguePublicCustom.photoUrl = (pub.photoUrl ?? null);
  leaguePublicCustom.coverUrl = (pub.coverUrl ?? null);
  leaguePublicCustom.photoV = asInt(pub.photoV ?? 0);
  leaguePublicCustom.coverV = asInt(pub.coverV ?? 0);

  const qs = await db
    .collectionGroup("members")
    .where(FieldPath.documentId(), "==", uid)
    .get();

  const writer = db.bulkWriter();
  for (const d of qs.docs) {
    writer.set(
      d.ref,
      {
        uid,
        fields: {
          ...leaguePublicCustom,
        },
        ...derived,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
  await writer.close();

  return { ok: true, membersUpdated: qs.docs.length };
});


