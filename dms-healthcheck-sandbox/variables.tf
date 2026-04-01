variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile"
  default     = "aquaware"
}

variable "db_password" {
  description = "RDS + Redshift master password"
  sensitive   = true
  default     = "SandboxPass123!"
}

variable "alert_email" {
  description = "Email address to receive DMS error alerts"
  default     = "orlando@aloware.com"
}
