resource "aws_ebs_volume" "ebs_volume" {
  count             = length(local.regions)
  availability_zone = local.regions[count.index]["availability_zone"]
  size              = 100

  tags = {
    Name = "${vars.base_tag}-${local.regions[count.index]["region"]}"
  }
}

resource "aws_volume_attachment" "ebs_attach" {
  count       = length(local.regions)
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs_volume[count.index].id
  instance_id = aws_instance.ec2_instance[count.index].id
}

resource "aws_ebs_snapshot" "data_snapshot" {
  count       = length(local.regions)
  volume_id   = aws_ebs_volume.ebs_volume[count.index].id
  description = "Nightly snapshot of ebs_volume EBS volume"

  tags = {
    Name = "${vars.base_tag}-Snapshot-${vars.domain_name}-${local.regions[count.index]["region"]}"
  }
}

resource "aws_ebs_snapshot_copy" "data_snapshot_copy" {
  count             = length(local.regions)
  source_snapshot_id = aws_ebs_snapshot.data_snapshot[count.index].id
  source_region      = local.regions[count.index]["region"]
  description        = "Copy of nightly snapshot for backup retention"

  tags = {
    Name = "${vars.base_tag}-Snapshot-Copy-${vars.domain_name}-${local.regions[count.index]["region"]}"
  }
}

resource "aws_snapshot_create_volume_permission" "data_snapshot_permission" {
  count          = length(local.regions)
  snapshot_id    = aws_ebs_snapshot.data_snapshot[count.index].id
  account_id     = "self"
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
      Snapshot = "${vars.base_tag}-data_snapshot"
      Volume = "${vars.base_tag}-ebs_volume"
    }
  }
}
