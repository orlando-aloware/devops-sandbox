provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name = "dms-sandbox-${random_id.suffix.hex}"
}
