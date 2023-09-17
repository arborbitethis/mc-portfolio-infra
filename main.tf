terraform {
  cloud {
    organization = "thew4yew"

    workspaces {
      name = "mc-portfolio-infra"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "test_bucket3" {
  bucket = "my-tf-test-bucket3"

  tags = {
    Name        = "terst bucket"
    Environment = "Dev"
  }
}
