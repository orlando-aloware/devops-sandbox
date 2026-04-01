resource "aws_dms_replication_subnet_group" "sandbox" {
  replication_subnet_group_id          = "${local.name}-dms-subnet"
  replication_subnet_group_description = "DMS sandbox subnet group"
  subnet_ids                           = data.aws_subnets.default.ids
}

resource "aws_dms_replication_instance" "sandbox" {
  replication_instance_id     = "${local.name}-dms"
  replication_instance_class  = "dms.t3.micro"
  allocated_storage           = 10
  publicly_accessible         = false
  replication_subnet_group_id = aws_dms_replication_subnet_group.sandbox.id
  vpc_security_group_ids      = [aws_security_group.sandbox.id]

  tags = { Name = "${local.name}-dms" }
}

resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${local.name}-source"
  endpoint_type = "source"
  engine_name   = "mysql"
  server_name   = aws_db_instance.source.address
  port          = 3306
  database_name = "sandbox"
  username      = "admin"
  password      = var.db_password

  tags = { Name = "${local.name}-source" }
}

resource "aws_dms_endpoint" "target" {
  endpoint_id   = "${local.name}-target"
  endpoint_type = "target"
  engine_name   = "redshift"
  server_name   = aws_redshift_cluster.target.endpoint
  port          = 5439
  database_name = "sandbox"
  username      = "admin"
  password      = var.db_password

  tags = { Name = "${local.name}-target" }
}

# Replication task — full-load-and-cdc on the 'orders' table
# start_replication_task = false: started manually after seed data is loaded
resource "aws_dms_replication_task" "sandbox" {
  replication_task_id      = "${local.name}-task"
  replication_instance_arn = aws_dms_replication_instance.sandbox.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn
  migration_type           = "full-load-and-cdc"
  start_replication_task   = false

  table_mappings = jsonencode({
    rules = [
      {
        rule-type = "selection"
        rule-id   = "1"
        rule-name = "include-orders"
        object-locator = {
          schema-name = "sandbox"
          table-name  = "orders"
        }
        rule-action = "include"
      }
    ]
  })

  replication_task_settings = jsonencode({
    TargetMetadata = {
      TargetSchema       = ""
      SupportLobs        = true
      FullLobMode        = false
      LobChunkSize       = 64
      LimitedSizeLobMode = true
      LobMaxSize         = 32
    }
    FullLoadSettings = {
      TargetTablePrepMode = "DROP_AND_CREATE"
    }
    Logging = {
      EnableLogging = true
    }
  })

  tags = { Name = "${local.name}-task", Purpose = "dms-sandbox" }
}
