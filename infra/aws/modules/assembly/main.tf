# Uses the account's default VPC/subnets rather than creating a new VPC —
# the assembly task only needs outbound internet (to pull its ECR image) and
# calls to S3/DynamoDB (both reachable from a public subnet with a public IP,
# no NAT Gateway required — keeps this at Fargate's pay-per-task-second cost
# with no fixed monthly networking cost, matching the "serverless, cost
# optimized" brief). Revisit if this ever needs to run in a private subnet.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "assembly" {
  name        = "${var.project}-${var.env}-assembly"
  description = "Fargate assembly task - outbound only, nothing calls into it"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecr_repository" "assembly" {
  name                 = "${var.project}-${var.env}-assembly"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecs_cluster" "this" {
  name = "${var.project}-${var.env}-assembly"
}

resource "aws_cloudwatch_log_group" "assembly" {
  name              = "/ecs/${var.project}-${var.env}-assembly"
  retention_in_days = 30
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.project}-${var.env}-assembly-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${var.project}-${var.env}-assembly-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "task_perms" {
  name = "perms"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${var.artifacts_bucket_arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = var.jobs_table_arn
      }
    ]
  })
}

resource "aws_ecs_task_definition" "assembly" {
  family                   = "${var.project}-${var.env}-assembly"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "assembly"
      image     = "${aws_ecr_repository.assembly.repository_url}:${var.image_tag}"
      essential = true
      # JOB_ID / LIP_SYNC_KEY / BG_AUDIO_KEY / OUTPUT_KEY are supplied per-run
      # via Step Functions ContainerOverrides — only the static config lives here.
      environment = [
        { name = "ARTIFACTS_BUCKET", value = var.artifacts_bucket_name },
        { name = "ARTIFACTS_BUCKET_DOMAIN", value = var.artifacts_bucket_domain },
        { name = "JOBS_TABLE", value = var.jobs_table_name },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.assembly.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "assembly"
        }
      }
    }
  ])
}

data "aws_region" "current" {}
