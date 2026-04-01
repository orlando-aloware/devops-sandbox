resource "aws_db_parameter_group" "mysql_cdc" {
  name   = "${local.name}-mysql-cdc"
  family = "mysql8.0"

  # Required for DMS CDC (binary logging)
  parameter {
    name         = "binlog_format"
    value        = "ROW"
    apply_method = "immediate"
  }

  parameter {
    name         = "binlog_row_image"
    value        = "Full"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_bin_trust_function_creators"
    value        = "1"
    apply_method = "immediate"
  }
}

resource "aws_db_subnet_group" "sandbox" {
  name       = "${local.name}-db-subnet"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "source" {
  identifier             = "${local.name}-mysql"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "sandbox"
  username               = "admin"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.sandbox.name
  vpc_security_group_ids = [aws_security_group.sandbox.id]
  publicly_accessible    = true
  skip_final_snapshot    = true
  deletion_protection    = false
  parameter_group_name   = aws_db_parameter_group.mysql_cdc.name

  tags = { Name = "${local.name}-mysql", Purpose = "dms-sandbox-source" }
}
