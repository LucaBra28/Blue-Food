/// <reference path="../pb_data/types.d.ts" />
// Kategorisierung entfernt: Felder am Artikel und in den Listen-Einstellungen werden nicht mehr genutzt.
migrate((app) => {
  const items = app.findCollectionByNameOrId("items");
  items.fields.removeByName("category");
  app.save(items);

  const prefs = app.findCollectionByNameOrId("listPrefs");
  prefs.fields.removeByName("autoCategories");
  app.save(prefs);
}, (app) => {
  const items = app.findCollectionByNameOrId("items");
  items.fields.add(new TextField({ name: "category", max: 40 }));
  app.save(items);

  const prefs = app.findCollectionByNameOrId("listPrefs");
  prefs.fields.add(new BoolField({ name: "autoCategories" }));
  app.save(prefs);
});
