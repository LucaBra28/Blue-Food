/// <reference path="../pb_data/types.d.ts" />
// Einladungen dürfen der eingeladenen Person und dem Ersteller der Liste angezeigt werden (Basis für Live-Updates).
migrate((app) => {
  const inv = app.findCollectionByNameOrId("invites");
  const rule = "@request.auth.id != '' && ((@request.auth.appleEmail != '' && email = @request.auth.appleEmail) || list.owner = @request.auth.id)";
  inv.listRule = rule;
  inv.viewRule = rule;
  app.save(inv);
}, (app) => {
  const inv = app.findCollectionByNameOrId("invites");
  inv.listRule = null; inv.viewRule = null;
  app.save(inv);
});
