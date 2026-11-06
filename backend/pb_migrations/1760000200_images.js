/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  const avatar = users.fields.getByName("avatar");
  avatar.maxSelect = 1;
  avatar.maxSize = 5 * 1024 * 1024;
  avatar.mimeTypes = ["image/jpeg", "image/png"];
  avatar.thumbs = ["96x96", "300x300"];
  app.save(users);

  const lists = app.findCollectionByNameOrId("lists");
  lists.fields.add(new FileField({
    name: "image",
    maxSelect: 1,
    maxSize: 5 * 1024 * 1024,
    mimeTypes: ["image/jpeg", "image/png"],
    thumbs: ["120x120", "600x600"],
  }));
  app.save(lists);
}, (app) => {
  const lists = app.findCollectionByNameOrId("lists");
  lists.fields.removeByName("image");
  app.save(lists);
});
