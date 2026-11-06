/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const items = app.findCollectionByNameOrId("items");
  const q = items.fields.getByName("quantity");
  q.onlyInt = false;
  q.min = 0.01;
  q.max = 100000;
  items.fields.add(new SelectField({
    name: "unit",
    maxSelect: 1,
    values: ["Stück", "g", "kg", "mg", "ml", "l", "Packung", "Flasche", "Dose"],
  }));
  app.save(items);
}, (app) => {
  const items = app.findCollectionByNameOrId("items");
  items.fields.removeByName("unit");
  app.save(items);
});
