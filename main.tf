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
#  s3 IAM
######################################################

resource "aws_iam_user" "s3_user" {
  name = "s3-user"
}

resource "aws_iam_access_key" "s3_user_key" {
  user = aws_iam_user.s3_user.name
}

resource "aws_iam_user_policy" "s3_policy" {
  name = "s3-policy"
  user = aws_iam_user.s3_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Effect   = "Allow"
        Resource = [
          "${aws_s3_bucket.portfolio_s3.arn}",
          "${aws_s3_bucket.portfolio_s3.arn}/*"
        ]
      }
    ]
  })
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
#  EC2 instance 
######################################################





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

######################################################
#  Cloudwatch setup
######################################################

resource "aws_cloudwatch_log_group" "portfolio_api_gateway_log_group" {
  name = "/aws/lambda/${aws_apigatewayv2_api.portfolio_api_gateway.name}"
  retention_in_days = 30
}




