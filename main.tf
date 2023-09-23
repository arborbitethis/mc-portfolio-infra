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

provider "random"  {}


######################################################
#  ECR
######################################################

resource "aws_ecr_repository" "portfolio_ecr" {
  name                 = "mc-portfolio-ecr"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

######################################################
#  s3
######################################################

resource "random_id" "s3_random" {
  byte_length = 8
}


resource "aws_s3_bucket" "portfolio_s3" {
  bucket = "mc-portfolio-s3-${random_id.s3_random.hex}" 
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.portfolio_s3.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "this" {
  depends_on = [aws_s3_bucket_ownership_controls.this]

  bucket = aws_s3_bucket.portfolio_s3.id
  acl    = "private"
}


######################################################
#  Networking
######################################################

resource "aws_vpc" "portfolio_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
}

resource "aws_subnet" "portfolio_subnet" {
  vpc_id            = aws_vpc.portfolio_vpc.id
  availability_zone = var.aws_availability_zone
  cidr_block        = cidrsubnet(aws_vpc.portfolio_vpc.cidr_block, 4, 1)
}

resource "aws_security_group" "portfolio_security_group" {
  name_prefix = "portfolio-sg"
  vpc_id = aws_vpc.portfolio_vpc.id

  ingress {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

######################################################
#  Lambda IAM
######################################################

resource "aws_iam_role" "portfolio_lambda_iam_role" {
  name = "portfolio-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM policy to create and push logs to CloudWatch
resource "aws_iam_policy" "portfolio_lambda_iam_policy" {
  name        = "portfolio-lambda-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject"
      ]
      Resource = ["arn:aws:logs:*:*:*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "portfolio_lambda_policy_attachment" {
  policy_arn = aws_iam_policy.portfolio_lambda_iam_policy.arn
  role = aws_iam_role.portfolio_lambda_iam_role.name
}


######################################################
#  Lambda 
######################################################
# resource "aws_lambda_function" "portfolio_lambda" {
#   function_name    = "portfolio-lambda"
#   filename         = "lambda_function_payload.zip"
#   source_code_hash = filebase64sha256("lambda_function_payload.zip")
#   handler          = "index.handler"
#   role             = aws_iam_role.example.arn
#   runtime          = "nodejs14.x"
#   vpc_config {
#     subnet_ids = [aws_subnet.example.id]
#     security_group_ids = [aws_security_group.example.id]
#   }
# }


######################################################
#  API Gateway
######################################################

resource "aws_apigatewayv2_api" "portfolio_api_gateway" {
  name          = "portfolio-http-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["https://www.courter.dev"]
    allow_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST" ,"PUT"]
    allow_headers = ["Content-Type", "Authorization", "X-Amz-Date", "X-Api-Key", "X-Amz-Security-Token"]
  }
}

