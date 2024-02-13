###############################################################################
# Firewall Policy
# https://cloud.google.com/firewall/docs/firewall-policies-rule-details
###############################################################################
resource "google_compute_network_firewall_policy_association" "main" {
  name              = "main"
  attachment_target = google_compute_network.main.id
  firewall_policy   = google_compute_network_firewall_policy.main.id
}

resource "google_compute_network_firewall_policy" "main" {
  name        = "vpc-firewall-policy"
  description = "VPC Firewall Policy"
}

resource "google_compute_network_firewall_policy_rule" "rfc1918" {
  rule_name       = "rfc1918"
  description     = "Allow RFC1918"
  action          = "allow"
  direction       = "EGRESS"
  priority        = 10
  disabled        = false
  enable_logging  = false
  firewall_policy = google_compute_network_firewall_policy.main.id

  match {
    dest_ip_ranges = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/24",
    ]
    layer4_configs {
      ip_protocol = "all"
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_ssh_ingress" {
  rule_name       = "allow-ssh-ingress"
  description     = "Allow SSH ingress"
  action          = "allow"
  direction       = "INGRESS"
  priority        = 40
  disabled        = false
  enable_logging  = true
  firewall_policy = google_compute_network_firewall_policy.main.id

  # target_service_accounts = [
  #   google_service_account.gitlab1.email,
  # ]

  match {
    src_region_codes = [
      "CA",
    ]
    src_threat_intelligences = [
      "iplist-public-clouds-gcp",
    ]
    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["22"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "deny_all_egress" {
  rule_name       = "deny-all-egress"
  description     = "Deny all EGRESS"
  action          = "deny"
  direction       = "EGRESS"
  priority        = 10000
  disabled        = false
  enable_logging  = true
  firewall_policy = google_compute_network_firewall_policy.main.id

  match {
    dest_ip_ranges = ["0.0.0.0/0"]
    layer4_configs {
      ip_protocol = "all"
    }
  }
}
