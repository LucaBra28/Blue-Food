/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const items = app.findCollectionByNameOrId("items");
  items.fields.add(new NumberField({ name: "quantity", min: 1, max: 999, onlyInt: true }));
  app.save(items);
}, (app) => {
  const items = app.findCollectionByNameOrId("items");
  items.fields.removeByName("quantity");
  app.save(items);
});
