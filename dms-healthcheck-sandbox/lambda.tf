# ── Redshift cluster (DMS target) ────────────────────────────────────────────
resource "aws_redshift_subnet_group" "sandbox" {
  name       = "${local.name}-rs-subnet"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_redshift_cluster" "target" {
  cluster_identifier        = "${local.name}-rs"
  database_name             = "sandbox"
  master_username           = "admin"
  master_password           = var.db_password
  node_type                 = "dc2.large"
  cluster_type              = "single-node"
  cluster_subnet_group_name = aws_redshift_subnet_group.sandbox.name
  vpc_security_group_ids    = [aws_security_group.sandbox.id]
  publicly_accessible       = false
  skip_final_snapshot       = true

  tags = { Name = "${local.name}-rs", Purpose = "dms-sandbox-target" }
}

# ── SNS topic + email subscription ───────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── IAM role for Lambda ───────────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "${local.name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dms_sns" {
  name = "${local.name}-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dms:DescribeTableStatistics",
          "dms:DescribeReplicationTasks",
          "dms:StopReplicationTask",
          "dms:StartReplicationTask"
        ]
        Resource = aws_dms_replication_task.sandbox.replication_task_arn
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# ── Lambda function (packages handler.py from jenkins-pipeline-collection) ────
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/handler.py"
  output_path = "${path.module}/.lambda.zip"
}

resource "aws_lambda_function" "dms_healthcheck" {
  function_name    = "${local.name}-healthcheck"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 180
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      DMS_TASK_ARN  = aws_dms_replication_task.sandbox.replication_task_arn
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
      AWS_REGION    = var.region
      MODE          = "ALERT"
    }
  }

  tags = { Name = "${local.name}-healthcheck", Purpose = "dms-sandbox" }
}

# ── EventBridge rule (DISABLED — enable to test scheduled trigger) ────────────
resource "aws_cloudwatch_event_rule" "nightly" {
  name                = "${local.name}-nightly"
  description         = "Nightly DMS healthcheck (sandbox, disabled by default)"
  schedule_expression = "cron(0 4 * * ? *)"
  state               = "DISABLED"
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.nightly.name
  target_id = "dms-healthcheck"
  arn       = aws_lambda_function.dms_healthcheck.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dms_healthcheck.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.nightly.arn
}
