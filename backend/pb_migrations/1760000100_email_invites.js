/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  users.fields.add(new TextField({ name: "appleEmail", hidden: true }));
  users.addIndex("idx_users_appleEmail", false, "appleEmail", "");
  app.save(users);

  // Einladungscodes entfallen -> Felder/Regeln aufraeumen
  const lists = app.findCollectionByNameOrId("lists");
  lists.indexes = [];
  lists.fields.removeByName("inviteCode");
  lists.createRule = "@request.auth.id != '' && @request.body.owner = @request.auth.id && @request.body.members:isset = false";
  lists.updateRule = "owner = @request.auth.id && @request.body.owner:isset = false";
  app.save(lists);

  // Einladungen: nur ueber eigene Endpunkte (keine API-Regeln)
  const invites = new Collection({
    type: "base",
    name: "invites",
    fields: [
      { type: "relation", name: "list", required: true, collectionId: lists.id, maxSelect: 1, cascadeDelete: true },
      { type: "text", name: "email", required: true },
      { type: "relation", name: "invitedBy", collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_invites_list_email ON invites (list, email)"],
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
  });
  app.save(invites);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("invites")); } catch (_) {}
});
