cluster_name      = "vault-cluster-1"
disable_mlock     = true
ui                = true
default_lease_ttl = "168h"
max_lease_ttl     = "720h"
log_level         = "INFO"
log_format        = "standard"

listener "tcp" {
  tls_disable        = false
  address            = "0.0.0.0:8200"
  cluster_address    = "0.0.0.0:8201"
  tls_client_ca_file = "/vault/certs/tls.ca"
  tls_cert_file      = "/vault/certs/tls.crt"
  tls_key_file       = "/vault/certs/tls.key"
}

storage "raft" {
  setNodeId = true
  path      = "/vault/data"
  retry_join {
    leader_api_addr         = "https://vault-0.cluster:8200"
    leader_ca_cert_file     = "/vault/certs/tls.ca"
    leader_client_cert_file = "/vault/certs/tls.crt"
    leader_client_key_file  = "/vault/certs/tls.key"
  }
  retry_join {
    leader_api_addr         = "https://vault-1.cluster:8200"
    leader_ca_cert_file     = "/vault/certs/tls.ca"
    leader_client_cert_file = "/vault/certs/tls.crt"
    leader_client_key_file  = "/vault/certs/tls.key"
  }
  retry_join {
    leader_api_addr         = "https://vault-2.cluster:8200"
    leader_ca_cert_file     = "/vault/certs/tls.ca"
    leader_client_cert_file = "/vault/certs/tls.crt"
    leader_client_key_file  = "/vault/certs/tls.key"
  }
}

service_registration "kubernetes" {}
