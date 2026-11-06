/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  const lists = app.findCollectionByNameOrId("lists");
  const member = "(list.owner = @request.auth.id || list.members ?= @request.auth.id)";
  const items = new Collection({
    type: "base",
    name: "items",
    fields: [
      { type: "relation", name: "list", required: true, collectionId: lists.id, maxSelect: 1, cascadeDelete: true },
      { type: "text", name: "name", required: true, max: 200 },
      { type: "bool", name: "checked" },
      { type: "relation", name: "createdBy", collectionId: users.id, maxSelect: 1, cascadeDelete: false },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: ["CREATE INDEX idx_items_list ON items (list)"],
    listRule: "@request.auth.id != '' && " + member,
    viewRule: "@request.auth.id != '' && " + member,
    createRule: "@request.auth.id != '' && @request.body.createdBy = @request.auth.id && " +
      "(@request.body.list.owner = @request.auth.id || @request.body.list.members ?= @request.auth.id)",
    updateRule: "@request.auth.id != '' && " + member + " && @request.body.list:isset = false && @request.body.createdBy:isset = false",
    deleteRule: "@request.auth.id != '' && " + member,
  });
  app.save(items);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("items")); } catch (_) {}
});
