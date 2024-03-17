data "aws_caller_identity" "current" {}

resource "aws_ebs_volume" "ebs_volume" {
  availability_zone = local.region["availability_zone"]
  size              = local.attached_volume_size

  tags = {
    Name = "${local.base_tag}-${var.region_name}"
  }
}

resource "aws_volume_attachment" "ebs_attach" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs_volume.id
  instance_id = aws_instance.ec2_instance.id
}

resource "aws_ebs_snapshot" "data_snapshot" {
  volume_id   = aws_ebs_volume.ebs_volume.id
  description = "Nightly snapshot of ebs_volume EBS volume"

  tags = {
    Name = "${local.base_tag}-Snapshot-${local.domain_name}-${var.region_name}"
  }
}

resource "aws_iam_role" "dlm_lifecycle_role" {
  name = "dlm_lifecycle_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
  Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "dlm_lifecycle_policy" {
  name        = "dlm_lifecycle_policy"
  description = "Policy for DLM to manage snapshots with specific tags"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DescribeInstances"
        ],
        Effect = "Allow",
        Resource = "*",
        Condition = {
          StringLike = {
            "ec2:ResourceTag/Name": "${local.base_tag}*"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dlm_lifecycle_policy_attachment" {
  role       = aws_iam_role.dlm_lifecycle_role.name
  policy_arn = aws_iam_policy.dlm_lifecycle_policy.arn
}

resource "aws_dlm_lifecycle_policy" "data_snapshot_policy" {
  description        = "7 day snapshot policy for ebs_volume EBS volume"
  execution_role_arn = aws_iam_role.dlm_lifecycle_role.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "Nightly Snapshots"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }

      retain_rule {
        count = 7
      }

      tags_to_add = {
        SnapshotCreator = "DLM"

      }

      copy_tags = false
    }

    target_tags = {
      Snapshot = "${local.base_tag}-data_snapshot"
      Volume = "${local.base_tag}-ebs_volume"
    }
  }
}
