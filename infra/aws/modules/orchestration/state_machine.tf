resource "aws_cloudwatch_log_group" "state_machine" {
  name              = "/aws/vendedlogs/states/${var.project}-${var.env}-pipeline"
  retention_in_days = 30
}

resource "aws_iam_role" "state_machine" {
  name = "${var.project}-${var.env}-state-machine"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "state_machine_perms" {
  name = "perms"
  role = aws_iam_role.state_machine.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          module.invoke_video_gen.lambda_arn,
          module.invoke_tts.lambda_arn,
          module.invoke_bg_audio.lambda_arn,
          module.invoke_lip_sync.lambda_arn,
          aws_lambda_function.update_job_failed.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        # Required by the "ecs:runTask.sync" pattern (AssembleFinalVideo).
        Effect   = "Allow"
        Action   = ["ecs:RunTask", "ecs:StopTask", "ecs:DescribeTasks"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = var.assembly_task_role_arns
      },
      {
        # ".sync" ECS integration polls task completion via an EventBridge
        # rule Step Functions manages automatically — this is the documented
        # permission set AWS requires for that to work.
        Effect   = "Allow"
        Action   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
        Resource = "arn:aws:events:*:*:rule/StepFunctionsGetEventsForECSTaskRule"
      }
    ]
  })
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${var.project}-${var.env}-pipeline"
  role_arn = aws_iam_role.state_machine.arn
  type     = "STANDARD"

  definition = templatefile("${path.module}/state_machine.asl.json.tpl", {
    invoke_video_gen_arn         = module.invoke_video_gen.lambda_arn
    invoke_tts_arn               = module.invoke_tts.lambda_arn
    invoke_bg_audio_arn          = module.invoke_bg_audio.lambda_arn
    invoke_lip_sync_arn          = module.invoke_lip_sync.lambda_arn
    update_job_failed_arn        = aws_lambda_function.update_job_failed.arn
    ecs_cluster_arn              = var.assembly_ecs_cluster_arn
    assembly_task_definition_arn = var.assembly_task_definition_arn
    assembly_subnet_ids_json     = jsonencode(var.assembly_subnet_ids)
    assembly_security_group_id   = var.assembly_security_group_id
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.state_machine.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
}
