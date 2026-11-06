/// <reference path="../pb_data/types.d.ts" />
// Push-Geräte: Jedes iPhone meldet sein APNs-Token für den angemeldeten Nutzer.
// Die alte Benachrichtigungs-Collection (Inbox) entfällt.
migrate((app) => {
  try { app.delete(app.findCollectionByNameOrId("notifications")); } catch (_) {}

  const users = app.findCollectionByNameOrId("users");
  const devices = new Collection({
    type: "base",
    name: "devices",
    fields: [
      { type: "relation", name: "user", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "text", name: "token", required: true, max: 200 },
      { type: "select", name: "env", values: ["sandbox", "production"], maxSelect: 1 },
      { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_devices_token ON devices (token)"],
    listRule: "user = @request.auth.id",
    viewRule: "user = @request.auth.id",
    createRule: "@request.auth.id != '' && @request.body.user = @request.auth.id",
    updateRule: "user = @request.auth.id && @request.body.user:isset = false",
    deleteRule: "user = @request.auth.id",
  });
  app.save(devices);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("devices")); } catch (_) {}
});
