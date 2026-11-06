/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const items = app.findCollectionByNameOrId("items");
  const unit = items.fields.getByName("unit");
  unit.values = ["Stück", "g", "kg", "mg", "ml", "l", "Packung", "Flasche", "Dose", "Kiste"];
  app.save(items);
}, (app) => {
  const items = app.findCollectionByNameOrId("items");
  const unit = items.fields.getByName("unit");
  unit.values = ["Stück", "g", "kg", "mg", "ml", "l", "Packung", "Flasche", "Dose"];
  app.save(items);
});
