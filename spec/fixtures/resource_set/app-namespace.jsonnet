function(vars)
{
  "apiVersion": "v1",
  "kind": "Namespace",
  "metadata": {
    "name": "app-%s" % vars.namespace,
    "namespace": vars.namespace,
    "labels": {
      "owner": vars.owner
    }
  },
  "spec": {
    "finalizers": ["kubernetes"]
  }
}
