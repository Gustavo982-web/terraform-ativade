resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-grupo"
  subnet_ids = [aws_subnet.privada_a.id, aws_subnet.privada_b.id]


  tags = {
    Name = "RDS subnet Group- desafio"
  }

}

resource "aws_db_instance" "banco-cosmos" {
  allocated_storage     = 20
  max_allocated_storage = 20
  storage_type          = "gp2"
  engine                = "mysql"
  instance_class        = "db.t3.micro"
  multi_az              = false


  db_name  = "bancocosmo"
  username = var.db_username
  password = var.db_password



  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.sg_rds.id]
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = {
    Name = "rds-mysql-desafio"
  }


}