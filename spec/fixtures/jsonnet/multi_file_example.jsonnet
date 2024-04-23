function(vars)
{
  MULTI_FILE_RENDER: true,
  "service": {
    "name": "%s-service" % vars.name,
    "container": {
      "name": vars.container_name,
      "sha": vars.container_sha
    }
  },
  "service-monitor": {
    MULTI_FILE_RENDER_NAME: "%s-service-monitor" % vars.name,
    "name": vars.name,
    "selector": {
      "matchLabels": {
        "app": vars.name
      }
    }
  }
}
