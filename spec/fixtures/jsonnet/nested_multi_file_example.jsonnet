function(vars)
local userName = "%s-user" % vars.name;
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
  },
  "users": {
    MULTI_FILE_RENDER: true,
    "role": {
      MULTI_FILE_RENDER_NAME: "%s-role" % userName,
      "kind": "Role",
      "name": userName,
      "rules": []
    },
    "role-binding": {
      MULTI_FILE_RENDER_NAME: "%s-rolebinding" % userName,
      "kind": "RoleBinding",
      "roleRef": {
        "kind": "Role",
        "name": userName
      },
      "subjects": []
    }
  }
}
