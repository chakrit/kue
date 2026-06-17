import "encoding/json"

import "encoding/base64"

// The prod9/infra docker-config shape: a registry-auth struct is JSON-marshalled
// and base64-encoded for a Kubernetes Secret's `.dockerconfigjson` data field.
registry: {"reg.io": {auth: "abc"}}
data: base64.Encode(null, json.Marshal({auths: registry}))
