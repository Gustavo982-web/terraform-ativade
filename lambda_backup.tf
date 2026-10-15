# -----------------------------------------------------------------------------
# Lambda de backup: dispara snapshot do RDS + export para o S3 (KMS).
# Invocacao manual (na demo). depends_on do ECS garante que a Lambda so e
# criada depois que o servico ECS existe.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# Empacota o codigo da Lambda em zip
data "archive_file" "lambda_backup_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_backup"
  output_path = "${path.module}/lambda_backup.zip"
}

# ---------- IAM Role da Lambda (execucao) ----------
resource "aws_iam_role" "lambda_backup_role" {
  name = "lambda_backup_role_desafio"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Logs no CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_backup_logs" {
  role       = aws_iam_role.lambda_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Permissoes da Lambda: criar snapshot, iniciar export e passar a export-role
resource "aws_iam_role_policy" "lambda_backup_policy" {
  name = "lambda-backup-rds-export"
  role = aws_iam_role.lambda_backup_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RdsSnapshotExport"
        Effect = "Allow"
        Action = [
          "rds:CreateDBSnapshot",
          "rds:DescribeDBSnapshots",
          "rds:StartExportTask",
          "rds:DescribeExportTasks",
          "rds:DeleteDBSnapshot"
        ]
        Resource = "*"
      },
      {
        Sid      = "PassExportRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.rds_export_role.arn
      },
      {
        Sid    = "UseKmsKey"
        Effect = "Allow"
        Action = [
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:Encrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = aws_kms_key.backup.arn
      }
    ]
  })
}

# ---------- IAM Role que o servico de Export do RDS assume ----------
resource "aws_iam_role" "rds_export_role" {
  name = "rds_export_to_s3_role_desafio"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "export.rds.amazonaws.com" }
    }]
  })
}

# Permissoes do export: escrever no bucket + usar a KMS
resource "aws_iam_role_policy" "rds_export_policy" {
  name = "rds-export-s3-kms"
  role = aws_iam_role.rds_export_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Write"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
      },
      {
        Sid    = "KmsUse"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:RetireGrant"
        ]
        Resource = aws_kms_key.backup.arn
      }
    ]
  })
}

# ---------- A funcao Lambda ----------
resource "aws_lambda_function" "backup" {
  filename         = data.archive_file.lambda_backup_zip.output_path
  source_code_hash = data.archive_file.lambda_backup_zip.output_base64sha256
  function_name    = "backup-rds-para-s3"
  role             = aws_iam_role.lambda_backup_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 900

  environment {
    variables = {
      DB_INSTANCE_ID  = aws_db_instance.banco-cosmos.identifier
      S3_BUCKET       = aws_s3_bucket.backups.id
      KMS_KEY_ARN     = aws_kms_key.backup.arn
      EXPORT_ROLE_ARN = aws_iam_role.rds_export_role.arn
      ACCOUNT_ID      = data.aws_caller_identity.current.account_id
    }
  }

  tags = {
    Name = "lambda-backup-cosmos"
  }

  # Garante que a Lambda so e criada depois do servico ECS (ordem de criacao).
  # O disparo do backup e manual (na demo), apos o banco estar populado.
  depends_on = [
    aws_ecs_service.app_service,
    aws_iam_role_policy.lambda_backup_policy
  ]
}
