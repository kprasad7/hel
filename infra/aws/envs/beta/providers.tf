terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  backend "s3" {
    bucket         = "vidplatform-tf-state"
    key            = "aws/beta/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "vidplatform-tf-lock"
  }
}

provider "aws" {
  region = var.aws_region
}
