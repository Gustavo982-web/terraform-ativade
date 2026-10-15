
resource "aws_kms_key" "backup" {
  description             = "Chave KMS para criptografia do backup do RDS exportado ao S3"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "kms-backup-cosmos"
  }
}

resource "aws_kms_alias" "backup" {
  name          = "alias/cosmos-backup"
  target_key_id = aws_kms_key.backup.key_id
}
