variable "project_id" {
  description = "GCP project ID (from the Wiz CloudLabs voucher)"
  type        = string
}

variable "region" {
  type    = string
  default = "us-east4"
}

variable "zone" {
  type    = string
  default = "us-east4-a"
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "wiz"
}

variable "alert_email" {
  description = "Email that receives the detective-control alerts"
  type        = string
}
