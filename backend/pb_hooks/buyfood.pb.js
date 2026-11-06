// BuyFood: Sign in with Apple (eigener Token-Endpunkt) + Listen-Einladungen.

// ---- Sign in with Apple ----
routerAdd("POST", "/api/buyfood/apple-auth", (e) => {
  const lib = require(`${__hooks}/lib.js`);
  const body = e.requestInfo().body || {};
  const identityToken = String(body.identityToken || "");
  const rawNonce = String(body.nonce || "");
  const fullName = String(body.fullName || "").trim().slice(0, 100);
  if (!identityToken) throw new BadRequestError("identityToken fehlt");
  if (!rawNonce) throw new BadRequestError("nonce fehlt");

  let keys;
  try {
    const res = $http.send({ url: "https://appleid.apple.com/auth/keys", method: "GET", timeout: 10 });
    keys = res.json.keys;
  } catch (err) {
    throw new ApiError(502, "Apple-Schluessel nicht erreichbar", {});
  }

  let claims;
  try {
    claims = lib.verifyAppleToken(identityToken, {
      keys,
      bundleIds: lib.BUNDLE_IDS,
      rawNonce,
      now: Math.floor(Date.now() / 1000),
      sha256Hex: (s) => $security.sha256(s),
    });
  } catch (err) {
    throw new UnauthorizedError("Apple-Token ungueltig: " + err.message);
  }

  let user;
  try {
    user = $app.findFirstRecordByData("users", "appleSub", claims.sub);
  } catch (_) {
    const col = $app.findCollectionByNameOrId("users");
    user = new Record(col);
    user.set("appleSub", claims.sub);
    user.set("email", claims.sub + "@apple.buyfood.invalid");
    user.set("emailVisibility", false);
    user.set("verified", true);
    user.set("name", fullName || "Neuer Nutzer");
    user.setPassword($security.randomString(40));
    $app.save(user);
  }
  const mail = String(claims.email || "").trim().toLowerCase();
  const verified = claims.email_verified === true || claims.email_verified === "true";
  if (mail && verified && user.getString("appleEmail") !== mail) {
    user.set("appleEmail", mail);
    $app.save(user);
  }
  if (fullName && (user.getString("name") === "" || user.getString("name") === "Neuer Nutzer")) {
    user.set("name", fullName);
    $app.save(user);
  }
  return e.json(200, { token: user.newAuthToken(), record: user });
});

// ---- Liste verlassen (Mitglied) ----
routerAdd("POST", "/api/buyfood/lists/{id}/leave", (e) => {
  let list;
  try { list = $app.findRecordById("lists", e.request.pathValue("id")); }
  catch (_) { throw new NotFoundError("Liste nicht gefunden"); }
  const uid = e.auth.id;
  if (list.getString("owner") === uid) throw new BadRequestError("Der Ersteller kann die Liste nicht verlassen");
  list.set("members", list.getStringSlice("members").filter((m) => m !== uid));
  $app.save(list);
  return e.json(200, { ok: true });
}, $apis.requireAuth("users"));

// ---- Mitglied entfernen (nur Ersteller) ----
routerAdd("POST", "/api/buyfood/lists/{id}/remove-member", (e) => {
  let list;
  try { list = $app.findRecordById("lists", e.request.pathValue("id")); }
  catch (_) { throw new NotFoundError("Liste nicht gefunden"); }
  if (list.getString("owner") !== e.auth.id) throw new ForbiddenError("Nur der Ersteller darf Mitglieder entfernen");
  const userId = String((e.requestInfo().body || {}).userId || "");
  if (!userId || userId === e.auth.id) throw new BadRequestError("Ungültige Person");
  list.set("members", list.getStringSlice("members").filter((m) => m !== userId));
  $app.save(list);
  return e.json(200, list);
}, $apis.requireAuth("users"));

// ---- Mitglieder einer Liste (Namen) ----
routerAdd("GET", "/api/buyfood/lists/{id}/members", (e) => {
  let list;
  try { list = $app.findRecordById("lists", e.request.pathValue("id")); }
  catch (_) { throw new NotFoundError("Liste nicht gefunden"); }
  const uid = e.auth.id;
  const ownerId = list.getString("owner");
  const memberIds = list.getStringSlice("members");
  if (ownerId !== uid && !memberIds.includes(uid)) throw new NotFoundError("Liste nicht gefunden");
  const out = [ownerId, ...memberIds].map((id) => {
    let name = "Unbekannt", avatar = "";
    try {
      const u = $app.findRecordById("users", id);
      name = u.getString("name");
      avatar = u.getString("avatar");
    } catch (_) {}
    return { id, name, avatar, isOwner: id === ownerId };
  });
  return e.json(200, out);
}, $apis.requireAuth("users"));

// ---- Person per E-Mail einladen (nur Ersteller) ----
routerAdd("POST", "/api/buyfood/lists/{id}/invite", (e) => {
  let list;
  try { list = $app.findRecordById("lists", e.request.pathValue("id")); }
  catch (_) { throw new NotFoundError("Liste nicht gefunden"); }
  if (list.getString("owner") !== e.auth.id) throw new ForbiddenError("Nur der Ersteller darf einladen");
  const email = String((e.requestInfo().body || {}).email || "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new BadRequestError("Bitte eine gültige E-Mail-Adresse eingeben");
  if (email === e.auth.getString("appleEmail")) throw new BadRequestError("Das ist deine eigene E-Mail-Adresse");
  // Ist die Person schon Mitglied?
  const known = $app.findRecordsByFilter("users", "appleEmail = {:m}", "", 1, 0, { m: email });
  if (known.length && (known[0].id === list.getString("owner") || list.getStringSlice("members").includes(known[0].id))) {
    throw new BadRequestError("Diese Person ist bereits Mitglied");
  }
  const existing = $app.findRecordsByFilter("invites", "list = {:l} && email = {:m}", "", 1, 0, { l: list.id, m: email });
  if (!existing.length) {
    const rec = new Record($app.findCollectionByNameOrId("invites"));
    rec.set("list", list.id);
    rec.set("email", email);
    rec.set("invitedBy", e.auth.id);
    $app.save(rec);
    return e.json(200, { id: rec.id, email });
  }
  return e.json(200, { id: existing[0].id, email });
}, $apis.requireAuth("users"));

// ---- Ausstehende Einladungen einer Liste (nur Ersteller) ----
routerAdd("GET", "/api/buyfood/lists/{id}/invites", (e) => {
  let list;
  try { list = $app.findRecordById("lists", e.request.pathValue("id")); }
  catch (_) { throw new NotFoundError("Liste nicht gefunden"); }
  if (list.getString("owner") !== e.auth.id) throw new ForbiddenError("Nur der Ersteller darf das");
  const recs = $app.findRecordsByFilter("invites", "list = {:l}", "-created", 100, 0, { l: list.id });
  return e.json(200, recs.map((r) => ({ id: r.id, email: r.getString("email") })));
}, $apis.requireAuth("users"));

// ---- Einladung zurückziehen (Ersteller) ----
routerAdd("DELETE", "/api/buyfood/invites/{id}", (e) => {
  let inv;
  try { inv = $app.findRecordById("invites", e.request.pathValue("id")); }
  catch (_) { throw new NotFoundError("Einladung nicht gefunden"); }
  const list = $app.findRecordById("lists", inv.getString("list"));
  if (list.getString("owner") !== e.auth.id) throw new ForbiddenError("Nur der Ersteller darf das");
  $app.delete(inv);
  return e.json(200, { ok: true });
}, $apis.requireAuth("users"));

// ---- Meine Einladungen ----
routerAdd("GET", "/api/buyfood/invites", (e) => {
  const mail = e.auth.getString("appleEmail");
  if (!mail) return e.json(200, []);
  const recs = $app.findRecordsByFilter("invites", "email = {:m}", "-created", 100, 0, { m: mail });
  const out = [];
  for (const r of recs) {
    try {
      const list = $app.findRecordById("lists", r.getString("list"));
      let inviter = "Jemand";
      try { inviter = $app.findRecordById("users", r.getString("invitedBy")).getString("name") || inviter; } catch (_) {}
      out.push({ id: r.id, listName: list.getString("name"), inviterName: inviter });
    } catch (_) {}
  }
  return e.json(200, out);
}, $apis.requireAuth("users"));

// ---- Einladung annehmen / ablehnen (nur der Eingeladene) ----
// Hinweis: Jeder Handler läuft isoliert, daher keine gemeinsame Funktion außerhalb.
routerAdd("POST", "/api/buyfood/invites/{id}/accept", (e) => {
  let inv;
  try { inv = $app.findRecordById("invites", e.request.pathValue("id")); }
  catch (_) { throw new NotFoundError("Einladung nicht gefunden"); }
  const mail = e.auth.getString("appleEmail");
  if (!mail || inv.getString("email") !== mail) throw new NotFoundError("Einladung nicht gefunden");
  const list = $app.findRecordById("lists", inv.getString("list"));
  const members = list.getStringSlice("members");
  if (list.getString("owner") !== e.auth.id && !members.includes(e.auth.id)) {
    members.push(e.auth.id);
    list.set("members", members);
    $app.save(list);
  }
  $app.delete(inv);
  return e.json(200, list);
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/buyfood/invites/{id}/decline", (e) => {
  let inv;
  try { inv = $app.findRecordById("invites", e.request.pathValue("id")); }
  catch (_) { throw new NotFoundError("Einladung nicht gefunden"); }
  const mail = e.auth.getString("appleEmail");
  if (!mail || inv.getString("email") !== mail) throw new NotFoundError("Einladung nicht gefunden");
  $app.delete(inv);
  return e.json(200, { ok: true });
}, $apis.requireAuth("users"));

// ---- Benachrichtigungen (pro Liste und Nutzer, Standard: an) ----
// Artikel hinzugefügt: alle anderen Mitglieder der Liste (die es wollen).
onRecordCreateRequest((e) => {
  const apns = require(`${__hooks}/apns.js`);
  const actorId = e.auth ? e.auth.id : "";
  e.next();
  try {
    const item = e.record;
    const listId = item.getString("list");
    const list = $app.findRecordById("lists", listId);
    const members = [list.getString("owner")].concat(list.getStringSlice("members"));
    const targets = members.filter((id) => id && id !== actorId && apns.prefsFor($app, id, listId).notifyAdded);
    if (!targets.length) return;

    apns.pushToUsers(
      { app: $app, http: $http, security: $security, os: $os },
      targets,
      list.getString("name"),
      `${apns.actorName($app, actorId)} hat „${item.getString("name")}“ hinzugefügt`,
      { listId: listId }
    );
  } catch (err) {
    console.log("notification failed: " + err);
  }
}, "items");

// Artikel abgehakt: Ersteller bekommt eine Nachricht (wenn er das will).
onRecordUpdateRequest((e) => {
  const itemId = e.record.id;
  let wasChecked = false;
  try { wasChecked = $app.findRecordById("items", itemId).getBool("checked"); } catch (_) {}
  const apns = require(`${__hooks}/apns.js`);
  const actorId = e.auth ? e.auth.id : "";

  e.next();

  try {
    const item = $app.findRecordById("items", itemId);
    if (wasChecked || !item.getBool("checked")) return;

    const creatorId = item.getString("createdBy");
    if (!creatorId || creatorId === actorId) return;

    const list = $app.findRecordById("lists", item.getString("list"));
    const stillMember = list.getString("owner") === creatorId || list.getStringSlice("members").includes(creatorId);
    if (!stillMember) return;
    if (!apns.prefsFor($app, creatorId, list.id).notifyChecked) return;

    apns.pushToUsers(
      { app: $app, http: $http, security: $security, os: $os },
      [creatorId],
      list.getString("name"),
      `${apns.actorName($app, actorId)} hat „${item.getString("name")}“ abgehakt`,
      { listId: list.id }
    );
  } catch (err) {
    // Fehler bei der Benachrichtigung dürfen das Abhaken nicht verhindern.
    console.log("notification failed: " + err);
  }
}, "items");
