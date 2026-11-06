/// <reference path="../pb_data/types.d.ts" />
// Kategorien am Artikel und Einstellungen pro Liste und Nutzer (Kategorisierung, Benachrichtigungen).
migrate((app) => {
  const items = app.findCollectionByNameOrId("items");
  items.fields.add(new TextField({ name: "category", max: 40 }));
  app.save(items);

  const users = app.findCollectionByNameOrId("users");
  const lists = app.findCollectionByNameOrId("lists");
  const mine = "@request.auth.id != '' && user = @request.auth.id";
  const prefs = new Collection({
    type: "base",
    name: "listPrefs",
    fields: [
      { type: "relation", name: "user", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "relation", name: "list", required: true, collectionId: lists.id, maxSelect: 1, cascadeDelete: true },
      { type: "bool", name: "autoCategories" },
      { type: "bool", name: "notifyAdded" },
      { type: "bool", name: "notifyChecked" },
      { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_listprefs_user_list ON listPrefs (user, list)"],
    listRule: mine,
    viewRule: mine,
    createRule: "@request.auth.id != '' && @request.body.user = @request.auth.id",
    updateRule: mine + " && @request.body.user:isset = false && @request.body.list:isset = false",
    deleteRule: mine,
  });
  app.save(prefs);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("listPrefs")); } catch (_) {}
  try {
    const items = app.findCollectionByNameOrId("items");
    items.fields.removeByName("category");
    app.save(items);
  } catch (_) {}
});
