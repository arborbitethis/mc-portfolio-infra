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

resource "aws_secretsmanager_secret" "mux_token_secret" {
  name        = "mux_token_secret"
  description = "Secret for mux auth"
}

resource "aws_secretsmanager_secret_version" "mux_token_secret_version" {
  secret_id     = aws_secretsmanager_secret.mux_token_secret.id
  secret_string = "{\"MUX_TOKEN_SECRET\":\"${var.mux_token_secret}\"}"
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

###################################################
# NLB & relevant config
###################################################
resource "aws_lb" "portfolio_nlb" {
  name               = "portfolio-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.portfolio_public_subnet.id]

  enable_deletion_protection = false
}

resource "aws_lb_target_group" "db_service_tg" {
  name     = "db-service-tg"
  port     = 5432
  protocol = "TCP"
  vpc_id   = aws_vpc.portfolio_vpc.id
  target_type = "ip"

  health_check {
    protocol = "TCP"
  }
}

resource "aws_lb_target_group" "backend_service_tg" {
  name     = "backend-service-tg"
  port     = 8000
  protocol = "TCP"
  vpc_id   = aws_vpc.portfolio_vpc.id
  target_type = "ip"

  health_check {
    protocol = "TCP"
  }
}

resource "aws_lb_listener" "db_service_listener" {
  load_balancer_arn = aws_lb.portfolio_nlb.arn
  port              = "5432"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.db_service_tg.arn
  }
}

resource "aws_lb_listener" "backend_service_listener" {
  load_balancer_arn = aws_lb.portfolio_nlb.arn
  port              = "8000"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_service_tg.arn
  }
}


###################################################
# ECS Service Discovery
###################################################

resource "aws_service_discovery_private_dns_namespace" "db_sd" {
  name        = "mc-portfolio-database"
  vpc         = aws_vpc.portfolio_vpc.id
}

resource "aws_service_discovery_service" "db_service_sd" {
  name = "db-service"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.db_sd.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "backend_service_sd" {
  name = "mc-portfolio-backend-service"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.db_sd.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
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

resource "aws_iam_policy" "ecs_secrets_policy" {
  name        = "ecs-secrets-policy"
  description = "Policy to allow ECS tasks to access Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "secretsmanager:GetSecretValue",
        Resource = aws_secretsmanager_secret.postgres_password.arn
      },
      {
        Effect = "Allow",
        Action = "secretsmanager:GetSecretValue",
        Resource = aws_secretsmanager_secret.mux_token_secret.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_secrets_policy_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_secrets_policy.arn
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "db_service" {
  family                   = "db_service"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  container_definitions    = jsonencode([
    {
      name        = "postgres",
      image       = "postgres:latest",
      environment = [
        {
          name  = "POSTGRES_USER",
          value = var.postgres_username
        },
        {
          name = "POSTGRES_DB",
          value = var.postgres_database_name

        }
      ],
      secrets = [
        {
          name      = "POSTGRES_PASSWORD",
          valueFrom = aws_secretsmanager_secret.postgres_password.arn
        }
      ],
      portMappings = [
        {
          containerPort = 5432,
          hostPort      = 5432
        }
      ]
    }
  ])
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

  load_balancer {
    target_group_arn = aws_lb_target_group.db_service_tg.arn
    container_name   = "postgres"
    container_port   = 5432
  }

  service_registries {
    registry_arn = aws_service_discovery_service.db_service_sd.arn
  }

  desired_count = 1
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
    environment = [
      {
        name  = "MUX_TOKEN_ID",
        value = var.mux_token_id
      },
      {
        name = "MUX_TOKEN_SECRET",
        value = var.mux_token_secret
      },
      {
        name = "DATABASE_URL",
        value = "postgresql://${var.postgres_username}:${var.postgres_password}@db-service.mc-portfolio-database:5432/${var.postgres_database_name}"
      }
    ],
    # secrets = [
    #   {
    #     name      = "MUX_TOKEN_SECRET",
    #     valueFrom = aws_secretsmanager_secret.mux_token_secret.arn
    #   }
    # ],
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

  service_registries {
    registry_arn = aws_service_discovery_service.backend_service_sd.arn
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend_service_tg.arn
    container_name   = "backend_container"
    container_port   = 8000
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

resource "aws_apigatewayv2_vpc_link" "portfolio_vpc_link" {
  name               = "portfolio-vpc-link"
  subnet_ids         = [aws_subnet.portfolio_private_subnet.id] 
  security_group_ids = [aws_security_group.portfolio_security_group.id]
}


# resource "aws_apigatewayv2_integration" "portfolio_integration" {
#   api_id           = aws_apigatewayv2_api.portfolio_api_gateway.id
#   integration_type = "HTTP_PROXY"
#   integration_uri  = "http://backend_service.mc-portfolio-backend-service"
#   connection_type  = "VPC_LINK"
#   connection_id    = aws_apigatewayv2_vpc_link.portfolio_vpc_link.id
# }

resource "aws_apigatewayv2_integration" "portfolio_integration" {
  api_id              = aws_apigatewayv2_api.portfolio_api_gateway.id
  integration_type    = "HTTP_PROXY"
  integration_method  = "ANY"  
  integration_uri     = "http://${aws_lb.portfolio_nlb.dns_name}:8000"  
  connection_type     = "INTERNET"
}

resource "aws_apigatewayv2_route" "portfolio_route" {
  api_id    = aws_apigatewayv2_api.portfolio_api_gateway.id
  route_key = "ANY /{proxy+}"  
  target    = "integrations/${aws_apigatewayv2_integration.portfolio_integration.id}"
}

resource "aws_apigatewayv2_stage" "portfolio_api_stage" {
  api_id      = aws_apigatewayv2_api.portfolio_api_gateway.id
  name        = "v1"
  auto_deploy = true
}

