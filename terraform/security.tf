# AUDIT LOGGING: Admin Activity logs are always on; this adds Data Access logs for every service
resource "google_project_iam_audit_config" "all" {
  project = var.project_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }
  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# PREVENTIVE CONTROL: GKE only admits images from our own Artifact Registry repo
resource "google_binary_authorization_policy" "policy" {
  global_policy_evaluation_mode = "ENABLE" # still allow Google-maintained system images

  admission_whitelist_patterns {
    name_pattern = "${local.image_repo}/**"
  }

  default_admission_rule {
    evaluation_mode  = "ALWAYS_DENY"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
  }

  depends_on = [google_project_service.services]
}

# DETECTIVE CONTROL: log-based alert on firewall changes, IAM policy changes and kubectl exec into pods
resource "google_monitoring_notification_channel" "email" {
  display_name = "Security alerts"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

resource "google_monitoring_alert_policy" "risky_changes" {
  display_name = "Risky change detected (firewall / IAM / pod exec)"
  combiner     = "OR"

  conditions {
    display_name = "Matching audit log entry"
    condition_matched_log {
      filter = <<-EOT
        logName:"cloudaudit.googleapis.com" AND (
          protoPayload.methodName=~"compute.firewalls.(insert|patch|update)" OR
          protoPayload.methodName="SetIamPolicy" OR
          protoPayload.methodName="io.k8s.core.v1.pods.exec.create"
        )
      EOT
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
    auto_close = "1800s"
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
}
