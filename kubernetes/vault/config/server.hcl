disable_mlock     = true
ui                = true
default_lease_ttl = "168h"
max_lease_ttl     = "720h"
log_level         = "INFO"
log_format        = "standard"

listener "tcp" {
  tls_disable        = true
  address            = "0.0.0.0:8200"
  cluster_address    = "0.0.0.0:8201"
  tls_cert_file      = "/vault/certs/tls.crt"
  tls_key_file       = "/vault/certs/tls.key"
  tls_client_ca_file = "/vault/certs/tls.ca"
}

storage "raft" {
  path = "/vault/data"
}

service_registration "kubernetes" {}
