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

  const nome = (u?.nome ?? profile.nome ?? "").toString().trim();
  const cognome = (u?.cognome ?? profile.cognome ?? "").toString().trim();
  const nickname = (u?.nickname ?? profile.nickname ?? "").toString().trim();

  const photoUrl = (u?.photoUrl ?? profile.photoUrl ?? "").toString().trim();
  const photoV = asInt(u?.photoV ?? profile.photoV ?? 0);

  const coverUrl = (u?.coverUrl ?? profile.coverUrl ?? "").toString().trim();
  const coverV = asInt(u?.coverV ?? profile.coverV ?? 0);

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
    const uid = ((event.params as any)?.uid ?? "").toString().trim();
    if (!uid) return;

    const afterSnap = event.data?.after;

    // 🧹 Eliminazione utente → pulizia UsersPublic (e volendo anche sharedProfiles…)
    if (!afterSnap?.exists) {
      console.log(`🧹 Utente ${uid} eliminato → pulizia UsersPublic`);
      await db.collection("UsersPublic").doc(uid).delete().catch(() => {});
      return;
    }

    const afterData = (afterSnap.data() ?? {}) as Record<string, any>;

    // -----------------------------
    // ✅ PROFILO FLAT: Users/{uid}.profile.<campo>
    // -----------------------------
    const profile = ((afterData.profile ?? {}) as Record<string, any>) || {};
    const profilePrivacy =
      ((profile.privacy ?? {}) as Record<string, any>) ||
      ((afterData._fieldSharing ?? {}) as Record<string, any>) ||
      ((afterData.fieldSharing ?? {}) as Record<string, any>) ||
      {};
    const allLeaguesScope = (afterData.allLeaguesScope ?? {}) as Record<string, any>;

    console.log(`🚀 onUserProfileWrite(${uid}) — sync profilo (flat) + privacy...`);

    // ----------------------------------------------------
    // 🔹 Recupero email, anche da Auth se mancante
    // ----------------------------------------------------
    let email = (afterData.email ?? "").toString().trim();
    let emailLower = (afterData.emailLower ?? "").toString().trim();
    if (!email || !emailLower) {
      try {
        const authUser = await admin.auth().getUser(uid);
        email = authUser.email ?? email;
        emailLower = authUser.email?.toLowerCase() ?? emailLower;
      } catch (err) {
        console.error(`⚠️ Errore getUser(${uid}):`, err);
      }
    }

    // ----------------------------------------------------
    // 🔹 Normalizzazione campi base (nome/cognome/foto/cover ecc.)
    // ----------------------------------------------------
    const pub = resolvePublicFromUserDoc(afterData, { email, emailLower });

    // ----------------------------------------------------
    // 🔒 Campi da NON propagare mai (interni / preferenze / privacy-map)
    // ----------------------------------------------------
    const BLOCKED_KEYS = new Set([
      "_fieldSharing",
      "fieldSharing",
      "allLeaguesScope",
      "sharedTo",
      "sharedToEmails",
      "sharedToLeagues",
      "fcmTokens",
    ]);

    // Pool campi: SOLO profile (flat) + campi calcolati per ricerca/visualizzazione (members/UsersPublic)
    const profileFieldPool: Record<string, any> = { ...profile };
    delete profileFieldPool.privacy;

    // 🔸 Custom fields (profile.custom) gestiti a livello di singola chiave (privacy: custom.<key>)
    const customPool: Record<string, any> = (profile?.custom && typeof profile.custom === 'object' && !Array.isArray(profile.custom))
      ? { ...(profile.custom as any) }
      : {};
    delete profileFieldPool.custom;



    // ----------------------------------------------------
    // 🔤 Canonicalizzazione chiavi (preferenza IT)
    // Nota: NON modifica il documento Users (evita loop), ma normalizza ciò che PROPAGHIAMO.
    // ----------------------------------------------------
    const KEY_ALIAS_TO_IT: Record<string, string> = {
      // anagrafica
      firstName: "nome",
      lastName: "cognome",
      birthDate: "dataNascita",
      placeOfBirth: "luogoNascita",
      taxCode: "codiceFiscale",
      fiscalCode: "codiceFiscale",
      citizenship: "cittadinanza",
      maritalStatus: "statoCivile",

      // contatti
      phone: "telefono",
      phoneNumber: "telefono",

      // campo pensiero
      thought: "pensiero",
    };

    function canonicalFieldKey(raw: string): string {
      const k = (raw ?? "").toString().trim();
      if (!k) return k;
      // privacy dei custom: custom.<key>
      if (k.startsWith("custom.")) return k;
      return KEY_ALIAS_TO_IT[k] ?? k;
    }

    function normalizeFlatKeys(src: Record<string, any>): Record<string, any> {
      const out: Record<string, any> = {};
      for (const [k, v] of Object.entries(src ?? {})) {
        const ck = canonicalFieldKey(k);
        // se arrivano sia alias EN che IT, preferisci IT se già presente e non vuoto
        if (out[ck] == null || out[ck] === "") out[ck] = v;
      }
      return out;
    }

    function normalizePrivacyKeys(src: Record<string, any>): Record<string, any> {
      const out: Record<string, any> = {};
      for (const [k, v] of Object.entries(src ?? {})) {
        const ck = canonicalFieldKey(k);
        out[ck] = v;
      }
      return out;
    }

    const profileFieldPoolEff = normalizeFlatKeys(profileFieldPool);
    const profilePrivacyEff = normalizePrivacyKeys(profilePrivacy);

    const derivedPublic = memberPublicFields(pub);

    function safeModeRaw(v: any): string {
      return (v ?? "").toString().trim().toLowerCase();
    }

    // 🔎 Mode per campo: public/league/emails/uids/owner/special/comparto/private
    // NOTE: compat client attuale
    // - mode: 'public' | 'private' | 'shared'
    // - league/allLeagues: true => condiviso con tutta la lega
    // - emails/uids non vuoti => condiviso con lista
    function getMode(fieldKey: string): string {
      // ✅ campi sempre pubblici
      if (ALWAYS_PUBLIC_FIELDS.has(fieldKey)) return "public";

      const s = (profilePrivacyEff?.[fieldKey] ?? {}) as Record<string, any>;
      const rawMode = safeModeRaw(s?.mode);

      const hasEmails = Array.isArray(s?.emails) && s.emails.length > 0;
      const hasUids = Array.isArray(s?.uids) && s.uids.length > 0;
      const isLeague = s?.league === true || s?.allLeagues === true;

      // ✅ compat: se il client salva mode='private' ma ha target, trattalo come condivisione
      if (rawMode === "private") {
        if (isLeague) return "league";
        if (hasEmails || hasUids) return hasUids && !hasEmails ? "uids" : "emails";
        return "private";
      }

      // ✅ formato preferito: mode='shared' + target
      if (rawMode === "shared") {
        if (isLeague) return "league";
        if (hasEmails || hasUids) return hasUids && !hasEmails ? "uids" : "emails";
        return "private";
      }

      // ✅ mode nuovo (se già 'league/emails/uids/owner/special/comparto')
      if (rawMode) return rawMode;

      // ✅ legacy booleans (senza mode)
      if (s?.public === true) return "public";
      if (isLeague) return "league";
      if (hasEmails || hasUids) return hasUids && !hasEmails ? "uids" : "emails";

      // 🔒 default: sensibili → private, altri → private (safe-by-default)
      if (SENSITIVE_FIELDS.has(fieldKey)) return "private";
      return "private";
    }

    function filterProfileByModes(allowedModes: string[]) {
      const out: Record<string, any> = {};

      // Top-level profile fields (flat)
      for (const [k, v] of Object.entries(profileFieldPoolEff)) {
        if (BLOCKED_KEYS.has(k)) continue;
        const mode = getMode(k);
        if (allowedModes.includes(mode)) out[k] = v;
      }

      // Custom fields (profile.custom) with privacy key: custom.<key>
      const customOut: Record<string, any> = {};
      for (const [ck, cv] of Object.entries(customPool)) {
        const fk = `custom.${ck}`;
        const mode = getMode(fk);
        if (allowedModes.includes(mode)) customOut[ck] = cv;
      }
      if (Object.keys(customOut).length > 0) {
        out.custom = customOut;
      }

      return out;
    }

    function realFieldCount(payload: Record<string, any>) {
      // Se il payload usa lo schema {fields:{...}}, conta SOLO i campi visibili.
      const f = (payload as any).fields;
      if (f && typeof f === 'object' && !Array.isArray(f)) {
        return Object.keys(f as any).length;
      }
      // Fallback legacy: uid + updatedAt non contano
      return Math.max(0, Object.keys(payload).length - 2);
    }

    function stripToDeleteMap(keys: string[]) {
      const m: Record<string, any> = {};
      for (const k of keys) m[k] = admin.firestore.FieldValue.delete();
      return m;
    }

    async function applyUpsertOrDelete(
      docRef: FirebaseFirestore.DocumentReference,
      payload: Record<string, any>,
      label: string
    ) {
      const cnt = realFieldCount(payload);
      if (cnt > 0) {
        // merge:false per evitare che i campi diventati PRIVATI restino appesi
        await docRef.set(payload, { merge: false });
        console.log(`✅ ${label} aggiornato (fields: ${cnt})`);
      } else {
        await docRef.delete().catch(() => {});
        console.log(`🧹 ${label} eliminato (0 fields)`);
      }
    }

    // -----------------------------
    // ✅ PAYLOADS
    // -----------------------------
    const profilePublic = filterProfileByModes(["public"]);
    const profileLeague = filterProfileByModes(["league"]);
    const profileShared = filterProfileByModes(["emails", "uids", "owner", "special", "comparto"]);

    // Members: campi public + derived (flat) — serve per liste/ordinamenti
    const payloadPublicMembers = {
      uid,
      ...profilePublic,
      ...derivedPublic,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // UsersPublic: standardizza → fields: {...} + metadata/search al root
    const payloadUsersPublic = {
      uid,
      fields: profilePublic,
      ...derivedPublic,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // sharedProfilesAll: SOLO league (fields)
    const payloadLeague = {
      uid,
      fields: profileLeague,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // sharedProfiles: SOLO emails/uids/owner/special/comparto (fields)
    const payloadSharedBase = {
      uid,
      fields: profileShared,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // ----------------------------------------------------
    // 1️⃣ UsersPublic — SOLO PUBLIC (delete se vuoto)
    // ---------------------------------------------------- — SOLO PUBLIC (delete se vuoto)
    // ----------------------------------------------------
    await applyUpsertOrDelete(db.collection("UsersPublic").doc(uid), payloadUsersPublic, `UsersPublic/${uid}`);

    // ----------------------------------------------------
    // 2️⃣ Members — SOLO PUBLIC + PULIZIA CAMPI RIMOSSI
    // ----------------------------------------------------
    let membersQs: FirebaseFirestore.QuerySnapshot<FirebaseFirestore.DocumentData>;
    try {
      membersQs = await db.collectionGroup("members").where("uid", "==", uid).get();
      console.log(`📂 Query members completata — trovati: ${membersQs.size}`);
    } catch (err: any) {
      console.error(`⚠️ Errore nella query collectionGroup("members"): ${err.message}`);
      membersQs = { docs: [], size: 0, empty: true } as any;
    }

    // Chiavi “profilo public” correnti (incl. derived)
    const publicKeysNow = new Set(Object.keys(payloadPublicMembers));

    for (const doc of membersQs.docs) {
      try {
        // 1) merge dei campi public correnti
        if (realFieldCount(payloadPublicMembers) > 0) {
          await doc.ref.set(payloadPublicMembers, { merge: true });
        }

        // 2) pulizia: rimuovo campi “profilo” che non sono più public
        const cur = (await doc.ref.get()).data() ?? {};
        const keysToRemove: string[] = [];

        for (const k of Object.keys(cur)) {
          if (k === "uid") continue;

          // campi tipici di membership da NON toccare
          if (
            k === "createdAt" ||
            k === "joinedAt" ||
            k === "roleId" ||
            k === "role" ||
            k === "active" ||
            k === "status" ||
            k === "joinCode" ||
            k === "updatedAt"
          ) {
            continue;
          }

          // se era un campo profilo/ricerca e ora non è più nel payload public → delete
          if (!publicKeysNow.has(k)) keysToRemove.push(k);
        }

        if (keysToRemove.length > 0) {
          await doc.ref.set(stripToDeleteMap(keysToRemove), { merge: true });
          console.log(`🧹 Pulizia member: ${doc.ref.path} (rimossi ${keysToRemove.length} campi)`);
        }

        console.log(`🔄 Aggiornato member: ${doc.ref.path}`);
      } catch (innerErr) {
        console.error(`❌ Errore aggiornando/pulendo ${doc.ref.path}:`, innerErr);
      }
    }

    // Leghe coinvolte
    const leagueIds = Array.from(
      new Set(membersQs.docs.map((d) => d.ref.parent.parent?.id ?? "").filter(Boolean))
    );
    console.log(`🏆 Leghe da aggiornare: ${leagueIds.join(", ") || "(nessuna)"}`);

    // Targets: union di email/uids presenti nelle regole privacy
    const emailTargets = Array.from(
      new Set(
        Object.values(profilePrivacyEff)
          .flatMap((v: any) => (Array.isArray(v?.emails) ? v.emails : []))
          .map((e: any) => (e ?? "").toString().trim().toLowerCase())
          .filter(Boolean)
)
);

const uidTargets = Array.from(
new Set(
        Object.values(profilePrivacyEff)
          .flatMap((v: any) => (Array.isArray(v?.uids) ? v.uids : []))
          .map((x: any) => (x ?? "").toString().trim())
          .filter(Boolean)
)
);

const wantsComparto = Object.values(profilePrivacyEff).some((v: any) => safeModeRaw(v?.mode) === "comparto");
const wantsOwner = Object.values(profilePrivacyEff).some((v: any) => safeModeRaw(v?.mode) === "owner");
const wantsSpecial = Object.values(profilePrivacyEff).some((v: any) => safeModeRaw(v?.mode) === "special");

// ----------------------------------------------------
// 3️⃣ sharePreferences + sharedProfilesAll + sharedProfiles
// ----------------------------------------------------
for (const leagueId of leagueIds) {
      const leagueRef = db.collection("Leagues").doc(leagueId);

      // sharePreferences (sempre)
      await leagueRef.collection("sharePreferences").doc(uid).set(
        {
          uid,
          allLeaguesScope: allLeaguesScope ?? {},
          fieldSharing: profilePrivacyEff ?? {},
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      // sharedProfilesAll — SOLO LEAGUE (delete se vuoto)
      await applyUpsertOrDelete(
        leagueRef.collection("sharedProfilesAll").doc(uid),
        payloadLeague,
        `sharedProfilesAll/${uid} in ${leagueId}`
      );

      // compartoLower owner (serve per regola allowSameComparto)
      let ownerCompartoLower: string | null = null;
      if (wantsComparto) {
        try {
          const mSnap = await leagueRef.collection("members").doc(uid).get();
          ownerCompartoLower = ((mSnap.data()?.compartoLower ?? "") as string).toString().trim().toLowerCase() || null;
        } catch (_) {
          ownerCompartoLower = null;
        }
      }

      // sharedProfiles — SOLO SHARED (delete se vuoto)
      const payloadSharedWithTargets = {
        ...payloadSharedBase,
        allowLeagueMembers: false,
        allowedEmailsLower: emailTargets,
        allowedUids: uidTargets,
        sharedToEmails: emailTargets,
        sharedToUids: uidTargets,

        allowSameComparto: wantsComparto,
        ownerCompartoLower: ownerCompartoLower,
        allowOwner: wantsOwner,
        allowSpecial: wantsSpecial,

        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await applyUpsertOrDelete(
        leagueRef.collection("sharedProfiles").doc(uid),
        payloadSharedWithTargets,
        `sharedProfiles/${uid} in ${leagueId}`
      );
    }

    console.log(`🎯 onUserProfileWrite(${uid}) — sincronizzazione completata.`);
  }
);








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

  const ensured = await ensureUserDoc(uid);
  const pub = await getLeaguePublicProfile(uid, ensured);

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
