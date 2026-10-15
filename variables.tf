variable "aws_region" {
  description = "Regiao da AWS onde os recursos serao criados"
  type        = string
  default     = "us-east-1"
}

variable "db_username" {
  description = "Usuario administrador do banco RDS MySQL"
  type        = string
}

variable "db_password" {
  description = "Senha do administrador do banco RDS MySQL"
  type        = string
  sensitive   = true
}

variable "docker_image" {
  description = "Imagem da aplicacao Node.js no Docker Hub"
  type        = string
  default     = ""
}

variable "email_alertas" {
  description = "E-mail para receber alertas do CloudWatch via SNS"
  type        = string

}

variable "app_port" {
  description = "Porta onde a aplicacao Node.js escuta dentro do container"
  type        = number
}