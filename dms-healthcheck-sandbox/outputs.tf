output "rds_endpoint" {
  description = "RDS MySQL endpoint (use in seed_and_break.sh)"
  value       = aws_db_instance.source.endpoint
}

output "dms_task_arn" {
  description = "DMS task ARN — plug into handler.py DMS_TASK_ARN for sandbox testing"
  value       = aws_dms_replication_task.sandbox.replication_task_arn
}

output "lambda_function_name" {
  description = "Lambda function name for manual invocation"
  value       = aws_lambda_function.dms_healthcheck.function_name
}

output "sns_topic_arn" {
  description = "SNS topic ARN (check email subscription is confirmed before testing)"
  value       = aws_sns_topic.alerts.arn
}

output "test_commands" {
  description = "Quick reference commands for testing"
  value = <<-EOT
    # 1. Dry-run — list errored tables (no changes)
    aws lambda invoke --function-name ${aws_lambda_function.dms_healthcheck.function_name} \
      --profile ${var.aws_profile} --region ${var.region} \
      --payload '{"mode":"CHECK"}' --cli-binary-format raw-in-base64-out \
      response.json && cat response.json

    # 2. Alert mode — check tables and send email if errors found
    aws lambda invoke --function-name ${aws_lambda_function.dms_healthcheck.function_name} \
      --profile ${var.aws_profile} --region ${var.region} \
      --payload '{"mode":"ALERT"}' --cli-binary-format raw-in-base64-out \
      response.json && cat response.json

    # 3. Reload — stop + reload-target (run AFTER break_dms step in seed_and_break.sh)
    aws lambda invoke --function-name ${aws_lambda_function.dms_healthcheck.function_name} \
      --profile ${var.aws_profile} --region ${var.region} \
      --payload '{"mode":"RELOAD"}' --cli-binary-format raw-in-base64-out \
      response.json && cat response.json
  EOT
}
