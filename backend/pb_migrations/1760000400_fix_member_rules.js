/// <reference path="../pb_data/types.d.ts" />
// "members ?= x" trifft bei Mehrfach-Relationen nicht zu; "members.id ?= x" schon.
migrate((app) => {
  const lists = app.findCollectionByNameOrId("lists");
  const listMember = "(owner = @request.auth.id || members.id ?= @request.auth.id)";
  lists.listRule = "@request.auth.id != '' && " + listMember;
  lists.viewRule = "@request.auth.id != '' && " + listMember;
  app.save(lists);

  const items = app.findCollectionByNameOrId("items");
  const member = "(list.owner = @request.auth.id || list.members.id ?= @request.auth.id)";
  items.listRule = "@request.auth.id != '' && " + member;
  items.viewRule = "@request.auth.id != '' && " + member;
  items.createRule = "@request.auth.id != '' && @request.body.createdBy = @request.auth.id && " +
    "(@request.body.list.owner = @request.auth.id || @request.body.list.members.id ?= @request.auth.id)";
  items.updateRule = "@request.auth.id != '' && " + member + " && @request.body.list:isset = false && @request.body.createdBy:isset = false";
  items.deleteRule = "@request.auth.id != '' && " + member;
  app.save(items);
}, (app) => {});
