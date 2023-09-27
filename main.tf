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


# Bucket for lambda functions

resource "aws_s3_bucket" "lambda_s3" {
  bucket = "mc-portfolio-s3-4-lambdas" 
}

resource "aws_s3_bucket_ownership_controls" "lambda_bucket_controls" {
  bucket = aws_s3_bucket.lambda_s3.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "lambda_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.lambda_bucket_controls]

  bucket = aws_s3_bucket.lambda_s3.id
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
#  Lambda 
######################################################

resource "aws_lambda_function" "s3_new_object_trigger" {
  function_name = "NewS3ObjectTrigger"
  handler       = "image_time_analysis.lambda_handler" # make sure this matches your file and function name
  runtime       = "python3.9"  # or whichever Python version you are using

  s3_bucket = aws_s3_bucket.lambda_s3.id
  s3_key    = "img_processing/image_time_analysis.zip"
  
  role = aws_iam_role.lambda_exec.arn
}
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_s3_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3_perms" {
  policy_arn = aws_iam_policy.s3_trigger_policy.arn
  role       = aws_iam_role.lambda_exec.name
}

resource "aws_iam_policy" "s3_trigger_policy" {
  name        = "S3TriggerLambdaPolicy"
  description = "Policy to allow Lambda to be triggered by S3 and log to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = "s3:GetObject",
        Effect = "Allow",
        Resource = "${aws_s3_bucket.portfolio_s3.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.portfolio_s3.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_new_object_trigger.arn
    events              = ["s3:ObjectCreated:*"]
  }
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_new_object_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "${aws_s3_bucket.portfolio_s3.arn}"
}




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




