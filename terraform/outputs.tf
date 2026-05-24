output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "ssh_private_key_path" {
  description = "Path to the generated SSH private key for the MongoDB EC2 instance"
  value       = local_sensitive_file.mongodb_private_key.filename
}

output "ssh_command" {
  description = "SSH command to connect to the MongoDB EC2 instance"
  value       = "ssh -i wiz-exercise-key.pem ubuntu@${aws_instance.mongodb.public_ip}"
}

output "mongodb_public_ip" {
  description = "MongoDB EC2 public IP (SSH access)"
  value       = aws_instance.mongodb.public_ip
}

output "mongodb_private_ip" {
  description = "MongoDB EC2 private IP (app connection)"
  value       = aws_instance.mongodb.private_ip
}

output "mongodb_connection_string" {
  description = "MongoDB connection string for the tasky app"
  value       = "mongodb://${var.mongodb_app_username}:${var.mongodb_app_password}@${aws_instance.mongodb.private_ip}:27017/go-mongodb?authSource=go-mongodb"
  sensitive   = true
}

output "s3_backup_bucket_name" {
  description = "S3 bucket name for MongoDB backups"
  value       = aws_s3_bucket.mongodb_backups.bucket
}

output "s3_backup_bucket_url" {
  description = "Public URL for the S3 backup bucket"
  value       = "https://${aws_s3_bucket.mongodb_backups.bucket}.s3.amazonaws.com"
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_certificate_authority" {
  description = "EKS cluster CA data"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "ecr_repository_url" {
  description = "ECR repository URL for tasky image"
  value       = aws_ecr_repository.tasky.repository_url
}

output "aws_lbc_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller"
  value       = aws_iam_role.aws_lbc.arn
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig for EKS access"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}
