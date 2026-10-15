resource "aws_ecs_cluster" "main" {
  name = "cluster-desafio-stefanini"
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role_desafio"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "task-aplicacao-node"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "api-backend"
      image     = var.docker_image
      essential = true
      portMappings = [
        {
          containerPort = var.app_port
          hostPort      = var.app_port
        }
      ]
      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "DB_MODE", value = "mysql" },
        { name = "DB_HOST", value = aws_db_instance.banco-cosmos.address },
        { name = "DB_PORT", value = "3306" },
        { name = "DB_USER", value = var.db_username },
        { name = "DB_PASSWORD", value = var.db_password },
        { name = "DB_NAME", value = "bancocosmo" },
        { name = "PORT", value = tostring(var.app_port) },
        { name = "APP_PORT", value = tostring(var.app_port) },
        { name = "APP_HOST", value = "0.0.0.0" }
      ]
    }
  ])
}

resource "aws_ecs_service" "app_service" {
  name                              = "servico-aplicacao-web"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.app.arn
  launch_type                       = "FARGATE"
  desired_count                     = 2
  health_check_grace_period_seconds = 300

  network_configuration {
    subnets          = [aws_subnet.privada_a.id, aws_subnet.privada_b.id]
    security_groups  = [aws_security_group.sg_ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = "api-backend"
    container_port   = var.app_port
  }

  depends_on = [
    aws_db_instance.banco-cosmos,
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.ecs_execution_role_policy
  ]
}