// Reines JS (laeuft in PocketBase/goja und in Node): Verifikation von Apple-Identity-Tokens (RS256).
// Erlaubte Bundle-IDs (muss mit dem Xcode-Projekt uebereinstimmen).
const BUNDLE_IDS = ["de.lucabraunsteiner.buyfood"];
const APPLE_ISS = "https://appleid.apple.com";
const SHA256_DIGESTINFO = "3031300d060960864801650304020105000420";

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function b64urlToHex(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/").replace(/=+$/, "");
  let bits = "";
  for (const ch of s) {
    const v = B64.indexOf(ch);
    if (v < 0) throw new Error("bad base64");
    bits += v.toString(2).padStart(6, "0");
  }
  let hex = "";
  for (let i = 0; i + 8 <= bits.length; i += 8) {
    hex += parseInt(bits.slice(i, i + 8), 2).toString(16).padStart(2, "0");
  }
  return hex;
}

function hexToUtf8(hex) {
  let out = "";
  for (let i = 0; i < hex.length; i += 2) out += "%" + hex.slice(i, i + 2);
  return decodeURIComponent(out);
}

function modPow(base, exp, mod) {
  let result = 1n;
  base = base % mod;
  while (exp > 0n) {
    if (exp & 1n) result = (result * base) % mod;
    exp >>= 1n;
    base = (base * base) % mod;
  }
  return result;
}

// sha256Hex(string) -> hex. Wird injiziert ($security.sha256 bzw. node:crypto).
function verifyRS256(token, jwk, sha256Hex) {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("malformed token");
  const n = BigInt("0x" + b64urlToHex(jwk.n));
  const e = BigInt("0x" + b64urlToHex(jwk.e));
  const k = Math.ceil(n.toString(16).length / 2);
  const sig = BigInt("0x" + b64urlToHex(parts[2]));
  if (sig >= n) return false;
  const em = modPow(sig, e, n).toString(16).padStart(k * 2, "0");
  const digest = sha256Hex(parts[0] + "." + parts[1]);
  const padLen = k - 3 - (SHA256_DIGESTINFO.length / 2) - 32;
  const expected = "0001" + "ff".repeat(padLen) + "00" + SHA256_DIGESTINFO + digest;
  return em === expected;
}

function decodePart(part) {
  return JSON.parse(hexToUtf8(b64urlToHex(part)));
}

// Gibt die Claims zurueck oder wirft einen Fehler.
function verifyAppleToken(token, { keys, bundleIds, rawNonce, now, sha256Hex }) {
  const parts = String(token).split(".");
  if (parts.length !== 3) throw new Error("malformed token");
  const header = decodePart(parts[0]);
  const claims = decodePart(parts[1]);
  if (header.alg !== "RS256") throw new Error("unsupported alg");
  const jwk = keys.find((k) => k.kid === header.kid && k.kty === "RSA");
  if (!jwk) throw new Error("unknown key");
  if (!verifyRS256(token, jwk, sha256Hex)) throw new Error("bad signature");
  if (claims.iss !== APPLE_ISS) throw new Error("bad issuer");
  if (!bundleIds.includes(claims.aud)) throw new Error("bad audience");
  if (!claims.exp || claims.exp < now) throw new Error("token expired");
  if (!claims.sub) throw new Error("no subject");
  if (rawNonce) {
    if (claims.nonce !== sha256Hex(rawNonce)) throw new Error("bad nonce");
  }
  return claims;
}

module.exports = { BUNDLE_IDS, verifyAppleToken, verifyRS256 };
