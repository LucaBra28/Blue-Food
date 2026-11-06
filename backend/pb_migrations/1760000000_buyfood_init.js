/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  // --- users: nur Sign in with Apple ---
  const users = app.findCollectionByNameOrId("users");
  users.fields.add(new TextField({ name: "appleSub", hidden: true }));
  users.addIndex("idx_users_appleSub", true, "appleSub", "appleSub != ''");
  users.passwordAuth.enabled = false;
  users.oauth2.enabled = false;
  users.otp.enabled = false;
  users.mfa.enabled = false;
  users.authToken.duration = 31536000; // 1 Jahr
  users.createRule = null;                       // Konten entstehen nur ueber /api/buyfood/apple-auth
  users.listRule = "id = @request.auth.id";
  users.viewRule = "id = @request.auth.id";
  users.updateRule = "id = @request.auth.id && @request.body.appleSub:isset = false && @request.body.email:isset = false";
  users.deleteRule = "id = @request.auth.id";
  app.save(users);

  // --- lists ---
  const lists = new Collection({
    type: "base",
    name: "lists",
    fields: [
      { type: "text", name: "name", required: true, max: 100 },
      { type: "relation", name: "owner", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "relation", name: "members", collectionId: users.id, maxSelect: 100, cascadeDelete: false },
      { type: "text", name: "inviteCode" },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_lists_inviteCode ON lists (inviteCode)"],
    listRule: "@request.auth.id != '' && (owner = @request.auth.id || members ?= @request.auth.id)",
    viewRule: "@request.auth.id != '' && (owner = @request.auth.id || members ?= @request.auth.id)",
    createRule: "@request.auth.id != '' && @request.body.owner = @request.auth.id && @request.body.inviteCode:isset = false && @request.body.members:isset = false",
    updateRule: "owner = @request.auth.id && @request.body.owner:isset = false && @request.body.inviteCode:isset = false",
    deleteRule: "owner = @request.auth.id",
  });
  app.save(lists);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("lists")); } catch (_) {}
});
