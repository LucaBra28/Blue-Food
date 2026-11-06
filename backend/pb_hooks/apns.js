// Reines JS (laeuft in PocketBase/goja und in Node): APNs-JWT (ES256 / P-256) fuer Push-Nachrichten.
// Alle Funktionen arbeiten mit Hex-Strings, damit sie ohne Bibliotheken auskommen.

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// P-256 Parameter
const P = 0xffffffff00000001000000000000000000000000ffffffffffffffffffffffffn;
const N = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551n;
const GX = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296n;
const GY = 0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5n;

function modPow(base, exp, mod) {
  let result = 1n;
  base = ((base % mod) + mod) % mod;
  while (exp > 0n) {
    if (exp & 1n) result = (result * base) % mod;
    exp >>= 1n;
    base = (base * base) % mod;
  }
  return result;
}

function hexToB64url(hex) {
  let bits = "";
  for (let i = 0; i < hex.length; i += 2) bits += parseInt(hex.slice(i, i + 2), 16).toString(2).padStart(8, "0");
  let out = "";
  for (let i = 0; i < bits.length; i += 6) {
    const chunk = bits.slice(i, i + 6).padEnd(6, "0");
    out += B64[parseInt(chunk, 2)];
  }
  return out.replace(/\+/g, "-").replace(/\//g, "_");
}

function asciiToHex(s) {
  let out = "";
  for (let i = 0; i < s.length; i++) out += s.charCodeAt(i).toString(16).padStart(2, "0");
  return out;
}

function b64urlToHex(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/").replace(/=+$/, "");
  let bits = "";
  for (const ch of s) {
    const v = B64.indexOf(ch);
    if (v < 0) throw new Error("bad base64");
    bits += v.toString(2).padStart(6, "0");
  }
  let hex = "";
  for (let i = 0; i + 8 <= bits.length; i += 8) hex += parseInt(bits.slice(i, i + 8), 2).toString(16).padStart(2, "0");
  return hex;
}

// Affine Punktoperationen auf P-256 (null = Unendlich).
function pointAdd(p1, p2) {
  if (p1 === null) return p2;
  if (p2 === null) return p1;
  if (p1.x === p2.x) {
    if ((p1.y + p2.y) % P === 0n) return null;
    return pointDouble(p1);
  }
  const l = ((p2.y - p1.y) * modPow(p2.x - p1.x, P - 2n, P)) % P;
  const l2 = ((l * l) % P + P) % P;
  const x3 = (((l2 - p1.x - p2.x) % P) + 2n * P) % P;
  const y3 = (((l * (p1.x - x3) - p1.y) % P) + 2n * P) % P;
  return { x: x3, y: y3 };
}

function pointDouble(p) {
  if (p === null || p.y === 0n) return null;
  const a = P - 3n;
  const l = ((3n * p.x * p.x + a) * modPow(2n * p.y, P - 2n, P)) % P;
  const l2 = ((l * l) % P + P) % P;
  const x3 = (((l2 - 2n * p.x) % P) + 2n * P) % P;
  const y3 = (((l * (p.x - x3) - p.y) % P) + 2n * P) % P;
  return { x: x3, y: y3 };
}

function pointMul(k, p) {
  let result = null;
  let addend = p;
  while (k > 0n) {
    if (k & 1n) result = pointAdd(result, addend);
    addend = pointDouble(addend);
    k >>= 1n;
  }
  return result;
}

// Holt den 32-Byte-Privatschluessel aus einem .p8 (PKCS#8 PEM).
function privateScalarFromPem(pem) {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const hex = b64urlToHex(body);
  // SEC1-Teil: 02 01 01 04 20 <32 Bytes d>
  const marker = "02010104" + "20";
  const idx = hex.indexOf(marker);
  if (idx < 0) throw new Error("Privatschluessel nicht lesbar");
  const d = hex.slice(idx + marker.length, idx + marker.length + 64);
  if (d.length !== 64) throw new Error("Privatschluessel unvollstaendig");
  return BigInt("0x" + d);
}

// ECDSA-Signatur (r, s) ueber einen SHA-256-Hash. randHex liefert zufaellige Hex-Strings.
function ecdsaSign(hashHex, d, randHex) {
  const z = BigInt("0x" + hashHex);
  for (let attempt = 0; attempt < 10; attempt++) {
    const k = (((BigInt("0x" + randHex()) % (N - 1n)) + 1n));
    const R = pointMul(k, { x: GX, y: GY });
    const r = R.x % N;
    if (r === 0n) continue;
    const s = (modPow(k, N - 2n, N) * ((z + r * d) % N)) % N;
    if (s === 0n) continue;
    return { r, s };
  }
  throw new Error("Signatur fehlgeschlagen");
}

// Erzeugt das JWT fuer APNs: { keyPem, keyId, teamId, nowSec, sha256Hex, randHex }
function apnsJWT({ keyPem, keyId, teamId, nowSec, sha256Hex, randHex }) {
  const header = asciiToHex(JSON.stringify({ alg: "ES256", kid: keyId }));
  const payload = asciiToHex(JSON.stringify({ iss: teamId, iat: nowSec }));
  const signingInput = hexToB64url(header) + "." + hexToB64url(payload);
  const d = privateScalarFromPem(keyPem);
  const { r, s } = ecdsaSign(sha256Hex(signingInput), d, randHex);
  const sig = r.toString(16).padStart(64, "0") + s.toString(16).padStart(64, "0");
  return signingInput + "." + hexToB64url(sig);
}

// Liest eine Datei als Text (PocketBase liefert je nach Version String oder Bytes).
function readFileText(os, path) {
  const raw = os.readFile(path);
  if (typeof raw === "string") return raw;
  let s = "";
  for (let i = 0; i < raw.length; i++) s += String.fromCharCode(raw[i]);
  return s;
}

// Sendet eine Push-Nachricht an alle Geräte der genannten Nutzer.
// deps = { app: $app, http: $http, security: $security, os: $os }; data = zusätzliche Felder (z. B. listId).
function pushToUsers(deps, userIds, title, body, data) {
  const app = deps.app;
  const devices = [];
  for (let i = 0; i < userIds.length; i++) {
    try {
      const found = app.findRecordsByFilter("devices", "user = {:u}", "", 50, 0, { u: userIds[i] });
      for (let j = 0; j < found.length; j++) devices.push(found[j]);
    } catch (_) {}
  }
  if (!devices.length) return;

  const cfg = JSON.parse(readFileText(deps.os, "/pb/secrets/apns.json"));
  const jwt = apnsJWT({
    keyPem: readFileText(deps.os, cfg.keyFile),
    keyId: cfg.keyId,
    teamId: cfg.teamId,
    nowSec: Math.floor(Date.now() / 1000),
    sha256Hex: (s) => deps.security.sha256(s),
    randHex: () => deps.security.sha256(deps.security.randomString(32)),
  });

  const message = { aps: { alert: { title: title, body: body }, sound: "default" } };
  if (data) {
    for (const key in data) message[key] = data[key];
  }
  const payload = JSON.stringify(message);

  for (let i = 0; i < devices.length; i++) {
    const dev = devices[i];
    const host = dev.getString("env") === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    try {
      const res = deps.http.send({
        url: "https://" + host + "/3/device/" + dev.getString("token"),
        method: "POST",
        headers: {
          "authorization": "bearer " + jwt,
          "apns-topic": cfg.topic,
          "apns-push-type": "alert",
          "content-type": "application/json",
        },
        body: payload,
        timeout: 10,
      });
      // 410 = Gerät hat die App entfernt oder Token ist ungültig
      if (res.statusCode === 410) app.delete(dev);
    } catch (err) {
      console.log("push failed: " + err);
    }
  }
}

// Einstellungen stehen in listPrefs; fehlt ein Eintrag, gelten die Standardwerte.
function prefsFor(app, userId, listId) {
  try {
    const found = app.findRecordsByFilter("listPrefs", "user = {:u} && list = {:l}", "", 1, 0, { u: userId, l: listId });
    if (found.length) {
      return {
        notifyAdded: found[0].getBool("notifyAdded"),
        notifyChecked: found[0].getBool("notifyChecked"),
      };
    }
  } catch (_) {}
  return { notifyAdded: true, notifyChecked: true };
}

function actorName(app, actorId) {
  if (!actorId) return "Jemand";
  try { return app.findRecordById("users", actorId).getString("name") || "Jemand"; } catch (_) { return "Jemand"; }
}

module.exports = { apnsJWT, privateScalarFromPem, pushToUsers, prefsFor, actorName };
