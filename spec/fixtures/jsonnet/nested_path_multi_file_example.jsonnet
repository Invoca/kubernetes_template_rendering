function(vars)
{
  MULTI_FILE_RENDER: true,
  "pr-1/app/service": {
    "name": "%s-service" % vars.name,
  },
  "pr-1/mysql/database": {
    MULTI_FILE_RENDER_NAME: "pr-1/mysql/%s-database" % vars.name,
    "kind": "Deployment",
  },
}
