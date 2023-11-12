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
#  Secrets
######################################################

resource "aws_secretsmanager_secret" "postgres_password" {
  name        = "postgres_password"
  description = "PostgreSQL password for ECS"
}

resource "aws_secretsmanager_secret_version" "postgres_password_version" {
  secret_id     = aws_secretsmanager_secret.postgres_password.id
  secret_string = "{\"POSTGRES_PASSWORD\":\"${var.postgres_password}\"}"
}


######################################################
#  Cloudwatch setup
######################################################

resource "aws_cloudwatch_log_group" "portfolio_api_gateway_log_group" {
  name = "/aws/lambda/${aws_apigatewayv2_api.portfolio_api_gateway.name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend_service_logs" {
  name = "/ecs/backend_service"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "db_service_logs" {
  name = "/ecs/db_service"
  retention_in_days = 30
}


######################################################
#  ECR
######################################################

resource "aws_ecr_repository" "portfolio_ecr_backend" {
  name                 = "mc-portfolio-backend"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "portfolio_ecr_db" {
  name                 = "mc-portfolio-backend-postgres"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

######################################################
#  Dynamo DB
######################################################
# TODO


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

  versioning {
    enabled = true
  }
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
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Public Subnet
resource "aws_subnet" "portfolio_public_subnet" {
  vpc_id            = aws_vpc.portfolio_vpc.id
  availability_zone = var.aws_availability_zone
  cidr_block        = cidrsubnet(aws_vpc.portfolio_vpc.cidr_block, 4, 0)
  map_public_ip_on_launch = true
}

# Private Subnet
resource "aws_subnet" "portfolio_private_subnet" {
  vpc_id            = aws_vpc.portfolio_vpc.id
  availability_zone = var.aws_availability_zone
  cidr_block        = cidrsubnet(aws_vpc.portfolio_vpc.cidr_block, 4, 1)
}

# Internet Gateway for the VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.portfolio_vpc.id
}

# Elastic IP for the NAT Gateway
resource "aws_eip" "nat_eip" {
  vpc = true
}

# NAT Gateway in the Public Subnet
resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.portfolio_public_subnet.id
}

# Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.portfolio_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Associate Public Route Table with Public Subnet
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.portfolio_public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Private Route Table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.portfolio_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }
}

# Associate Private Route Table with Private Subnet
resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.portfolio_private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Group for ECS tasks
resource "aws_security_group" "portfolio_security_group" {
  name_prefix = "portfolio-sg"
  vpc_id      = aws_vpc.portfolio_vpc.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


######################################################
#  Lambda 
######################################################
# Lambda Layer for dependencies
resource "aws_lambda_layer_version" "lambda_layer" {
  layer_name  = "image-time-analysis-layer"
  description = "Layer for Image Time Analysis dependencies"

  compatible_runtimes = ["python3.9"]

  s3_bucket = aws_s3_bucket.lambda_s3.id
  s3_key    = "img_processing/dependency_layer.zip"
}

# Lambda Function
resource "aws_lambda_function" "s3_new_object_trigger" {
  function_name = "ImageExifExtraction"
  handler       = "image_time_analysis.lambda_handler" # make sure this matches your file and function name
  runtime       = "python3.9"  # or whichever Python version you are using

  s3_bucket = aws_s3_bucket.lambda_s3.id
  s3_key    = "img_processing/image_time_analysis.zip"

  role = aws_iam_role.lambda_exec.arn

  timeout = 30

  # Attach the layer to the Lambda Function
  layers = [aws_lambda_layer_version.lambda_layer.arn]
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
#  ECS Cluster
######################################################

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "mc-portfolio-cluster"
}

# IAM roles for ECS tasks
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task definition for the backend service
resource "aws_ecs_task_definition" "backend_service" {
  family                   = "backend_service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name  = "backend_container",
    image = "${aws_ecr_repository.portfolio_ecr_backend.repository_url}:latest",
    portMappings = [{
      containerPort = 8000,
      hostPort      = 8000
    }],
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.backend_service_logs.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# Task definition for the database service
resource "aws_ecs_task_definition" "db_service" {
  family                   = "db_service"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  container_definitions    = <<DEFINITION
[
  {
    "name": "postgres",
    "image": "postgres:latest",
    "essential": true,
    "environment": [
      {
        "name": "POSTGRES_USER",
        "value": var.postgres_username
      }
    ],
    "secrets": [
      {
        "name": "PGPASSWORD",
        "valueFrom": aws_secretsmanager_secret.postgres_password.arn
      }
    ],
    "portMappings": [
      {
        "containerPort": 5432,
        "hostPort": 5432
      }
    ]
  }
]
DEFINITION
}

# Fargate Service for the backend task
resource "aws_ecs_service" "backend_service" {
  name            = "backend_service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend_service.arn
  launch_type     = "FARGATE"

  network_configuration {
    subnets = [aws_subnet.portfolio_private_subnet.id]
    security_groups = [aws_security_group.portfolio_security_group.id]
  }

  desired_count = 1
}

# Fargate Service for the database task
resource "aws_ecs_service" "db_service" {
  name            = "db_service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.db_service.arn
  launch_type     = "FARGATE"

  network_configuration {
    subnets = [aws_subnet.portfolio_private_subnet.id]
    security_groups = [aws_security_group.portfolio_security_group.id]
  }

  desired_count = 1
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



