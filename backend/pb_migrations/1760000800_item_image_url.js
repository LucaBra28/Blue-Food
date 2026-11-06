/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const items = app.findCollectionByNameOrId("items");
  items.fields.add(new TextField({ name: "imageUrl", max: 500 }));
  app.save(items);
}, (app) => {
  const items = app.findCollectionByNameOrId("items");
  items.fields.removeByName("imageUrl");
  app.save(items);
});
