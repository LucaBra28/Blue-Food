/// <reference path="../pb_data/types.d.ts" />
// Benachrichtigungen: Wenn jemand einen Artikel abhakt, bekommt der Ersteller einen Eintrag.
// Einträge entstehen nur serverseitig (Hook in buyfood.pb.js), daher createRule = null.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  const lists = app.findCollectionByNameOrId("lists");
  const mine = "@request.auth.id != '' && recipient = @request.auth.id";
  const notifications = new Collection({
    type: "base",
    name: "notifications",
    fields: [
      { type: "relation", name: "recipient", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "relation", name: "list", collectionId: lists.id, maxSelect: 1, cascadeDelete: true },
      { type: "text", name: "item", max: 50 },
      { type: "text", name: "itemName", max: 200 },
      { type: "text", name: "listName", max: 200 },
      { type: "text", name: "actorName", max: 100 },
      { type: "bool", name: "read" },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: ["CREATE INDEX idx_notifications_recipient ON notifications (recipient, read)"],
    listRule: mine,
    viewRule: mine,
    createRule: null,
    // Nur "read" darf vom Empfänger geändert werden.
    updateRule: mine + " && @request.body.recipient:isset = false && @request.body.itemName:isset = false && " +
      "@request.body.listName:isset = false && @request.body.actorName:isset = false && @request.body.item:isset = false",
    deleteRule: mine,
  });
  app.save(notifications);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("notifications")); } catch (_) {}
});
