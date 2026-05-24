################################################################################
# Security Group: MongoDB EC2
# Intentional weaknesses: SSH open to 0.0.0.0/0
# Note: the MongoDB ingress rule from EKS nodes is a separate resource below
# to avoid a cycle with eks_nodes SG.
################################################################################
resource "aws_security_group" "mongodb_ec2" {
  name        = "${var.project_name}-mongodb-sg"
  description = "Security group for MongoDB EC2 instance"
  vpc_id      = aws_vpc.main.id

  # INTENTIONAL WEAKNESS: SSH open to the public internet
  ingress {
    description = "SSH from anywhere (intentional weakness)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-mongodb-sg"
  }
}

# Separate rule so eks_nodes SG can exist first before being referenced here
resource "aws_security_group_rule" "mongodb_from_eks_nodes" {
  type                     = "ingress"
  description              = "MongoDB from EKS nodes"
  from_port                = 27017
  to_port                  = 27017
  protocol                 = "tcp"
  security_group_id        = aws_security_group.mongodb_ec2.id
  source_security_group_id = aws_security_group.eks_nodes.id
}

################################################################################
# Security Group: ALB
################################################################################
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

################################################################################
# Security Group: EKS Cluster Control Plane
# Created without cross-SG ingress rules; those are added as separate resources
# below to break the eks_cluster <-> eks_nodes cycle.
################################################################################
resource "aws_security_group" "eks_cluster" {
  name        = "${var.project_name}-eks-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-cluster-sg"
  }
}

################################################################################
# Security Group: EKS Nodes
# Also created without cross-SG ingress rules for the same reason.
################################################################################
resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  # Self-referencing rule is fine inline (no external SG reference)
  ingress {
    description = "Allow nodes to communicate with each other"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description     = "Allow ALB to communicate with nodes"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Allow ALB NodePort range"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-nodes-sg"
  }
}

################################################################################
# Cross-referencing rules added AFTER both SGs exist — breaks the cycle
################################################################################

# Nodes → cluster API (443)
resource "aws_security_group_rule" "eks_nodes_to_cluster_api" {
  type                     = "ingress"
  description              = "Allow nodes to communicate with cluster API"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.eks_nodes.id
}

# Cluster control plane → nodes (ephemeral ports)
resource "aws_security_group_rule" "eks_cluster_to_nodes" {
  type                     = "ingress"
  description              = "Allow control plane to communicate with nodes"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.eks_cluster.id
}

################################################################################
# Allow EKS nodes (via EKS-managed cluster SG) to reach MongoDB on port 27017
# The node actually uses the EKS auto-created cluster SG, not our eks_nodes SG.
################################################################################
resource "aws_security_group_rule" "mongodb_from_eks_cluster_sg" {
  type                     = "ingress"
  description              = "Allow EKS nodes (cluster SG) to reach MongoDB"
  from_port                = 27017
  to_port                  = 27017
  protocol                 = "tcp"
  security_group_id        = aws_security_group.mongodb_ec2.id
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

################################################################################
# Allow ALB (via LBC-managed backend SG) to reach pods on port 8080
# The LBC creates its own SG dynamically, so we open port 8080 from the VPC
# CIDR on the EKS-managed cluster security group (the one actually attached
# to nodes, distinct from our Terraform-managed eks_nodes SG).
################################################################################
resource "aws_security_group_rule" "eks_cluster_sg_allow_8080" {
  type              = "ingress"
  description       = "Allow ALB to reach pods on port 8080 (via VPC CIDR)"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  cidr_blocks       = [aws_vpc.main.cidr_block]
}
