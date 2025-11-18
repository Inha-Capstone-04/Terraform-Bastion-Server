output "api_server_public_ip" {
  description = "API Server (Prod)의 Public IP 주소"
  value       = aws_instance.api_server.public_ip
}

output "livekit_server_public_ip" {
  description = "LiveKit Server의 Public IP 주소"
  value       = aws_instance.livekit_server.public_ip
}

output "api_server_dev_public_ip" {
  description = "API Server (Dev)의 Public IP 주소"
  value       = aws_instance.api_server_dev.public_ip
}

output "s3_bucket_name" {
  description = "생성된 S3 버킷의 이름"
  value       = aws_s3_bucket.my_bucket.id
}

output "rds_endpoint" {
  description = "RDS 데이터베이스 연결 주소 (Endpoint)"
  value       = aws_db_instance.my_postgres_db.endpoint
}

output "rds_port" {
  description = "RDS 데이터베이스 연결 포트"
  value       = aws_db_instance.my_postgres_db.port
}

output "api_server_ecr_url" {
  description = "API 서버 ECR 리포지토리 URL"
  value       = aws_ecr_repository.api_server_ecr.repository_url
}

output "livekit_server_ecr_url" {
  description = "LiveKit 서버 ECR 리포지토리 URL"
  value       = aws_ecr_repository.livekit_server_ecr.repository_url
}