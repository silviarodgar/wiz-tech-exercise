terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }

  # Uncomment and configure for remote state (recommended)
  # backend "s3" {
  #   bucket = "your-tf-state-bucket"
  #   key    = "wiz-tech-exercise/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "wiz-tech-exercise"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
