terraform {
  required_version = "~> 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key          = "registry/terraform.tfstate"
    use_lockfile = true
  }
}

variable "aws_region" {
  type = string
}

provider "aws" {
  region = var.aws_region
}

resource "aws_ecr_repository" "app" {
  name                 = "reto-java-ecs"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
}

output "repository_url" {
  value = aws_ecr_repository.app.repository_url
}
