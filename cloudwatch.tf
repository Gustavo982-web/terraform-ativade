resource "aws_sns_topic" "alertas_infra" {
  name = "topico-alertas-infraestrutura"
}

resource "aws_sns_topic_subscription" "email_alerta" {
  topic_arn = aws_sns_topic.alertas_infra.arn
  protocol  = "email"
  endpoint  = var.email_alertas
}

-

# 1) CPU do RDS (saude do banco)
resource "aws_cloudwatch_metric_alarm" "cpu_rds" {
  alarm_name          = "alarme-cpu-alta-rds"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU do RDS acima de 80%."
  alarm_actions       = [aws_sns_topic.alertas_infra.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.banco-cosmos.identifier
  }
}

# 2) CPU do ECS (saude da aplicacao / compute)
resource "aws_cloudwatch_metric_alarm" "cpu_ecs" {
  alarm_name          = "alarme-cpu-alta-ecs"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU do servico ECS acima de 80%."
  alarm_actions       = [aws_sns_topic.alertas_infra.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app_service.name
  }
}

# 3) Targets nao-saudaveis no ALB (aplicacao fora do ar)
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts_alb" {
  alarm_name          = "alarme-targets-nao-saudaveis-alb"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "Existe pelo menos 1 target nao-saudavel no ALB."
  alarm_actions       = [aws_sns_topic.alertas_infra.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app_tg.arn_suffix
  }
}

# 4) Erros 5XX na aplicacao (falha interna vista pelo usuario)
resource "aws_cloudwatch_metric_alarm" "erros_5xx_alb" {
  alarm_name          = "alarme-erros-5xx-aplicacao"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Dispara quando o ALB detecta erros internos (5XX) na aplicacao Node.js."
  alarm_actions       = [aws_sns_topic.alertas_infra.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}
