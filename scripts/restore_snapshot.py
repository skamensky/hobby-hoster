import boto3
import click
from botocore.exceptions import NoCredentialsError, ClientError
from pathlib import Path
import json

root_dir = Path(__file__).parent.parent
config_file = root_dir / "config.json"

import paramiko
import boto3

def run_ssh_command(instance_id, region,private_key_file,user, command):
    ec2 = boto3.client('ec2', region_name=region)

    # Get instance information
    instances = ec2.describe_instances(InstanceIds=[instance_id])
    instance = instances['Reservations'][0]['Instances'][0]
    public_dns = instance['PublicDnsName']

    # Load private key file
    k = paramiko.RSAKey.from_private_key_file(private_key_file)

    # Create SSH client
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    # Connect to the instance
    ssh.connect(hostname=public_dns, username=user, pkey=k)

    # Execute the command
    stdin, stdout, stderr = ssh.exec_command(command)

    # Get command output and errors
    output = stdout.read().decode().strip()
    error = stderr.read().decode().strip()

    ssh.close()

    return output, error

@click.command()
@click.option('--snapshot-id', prompt='Snapshot ID', help='The ID of the snapshot to restore.')
@click.option('--region', prompt='Region', help='The region where the snapshot is located.')
@click.option('--volume-size', default=100, help='The size of the volume to restore the snapshot to. Defaults to 100GB.')
def restore_snapshot_to_volume(snapshot_id, region, volume_size):



    config = json.load(config_file)
    base_tag = config["base_tag"]
    regions = config["regions"]
    if region not in regions:
        click.echo(f"Region {region} not found in config file. Can't restore a snapshot not within config's regions.")
        return
    
    if not snapshot_id.startswith(base_tag):
        click.echo(f"Snapshot {snapshot_id} does not belong to the base tag {base_tag}. Can't restore a snapshot not within config's base tag.")
        return

    # Create a new session for the specified region
    session = boto3.Session(region_name=region)
    ec2 = session.resource('ec2')

    instances = ec2.instances.filter(
        Filters=[
            {
                'Name': 'tag:Name',
                'Values': [f'{base_tag}*']
            }
        ]
    )

    if not instances:
        click.echo(f"No instances found.")
        return
    

    if len(instances) > 1:
        click.echo(f"Found more than one instance with the name {base_tag}-instance-{region} in the region {region}. Can't restore a snapshot to multiple instances.")
        return

    instance = instances[0]


    # check instance state:
    if instance.state['Name'].lower() != 'running':
        click.echo(f"Instance {instance.id} is not currently running. Can only restore a snapshot to a running instance.")
        return
    
    try:
        output, error = run_ssh_command(instance.id, region, config['ssh']['private_key_path'], config['ssh']['user'], "agent reload")
    except Exception as e:
        click.echo(f"Error reloading agent: {e}")
        return

    # Check if the snapshot exists
    snapshot = ec2.Snapshot(snapshot_id)
    if snapshot.state != 'completed':
        click.echo(f"Snapshot {snapshot_id} is not ready yet.")
        return

    # Confirm with the user before restoring
    if not click.confirm('Do you want to restore this snapshot?'):
        click.echo("Restore aborted.")
        return

    # Create a new volume from the snapshot
    volume = ec2.create_volume(
        AvailabilityZone=region,
        SnapshotId=snapshot_id,
        VolumeType='gp2',  # General Purpose SSD
        Size=volume_size
    )

    # Wait for the volume to become available
    volume.wait_until_available()


    # check if instance has /dev/sdh mounted. If so, unmount:

    device = '/dev/sdh'
    for volume in instance.volumes.all():
        if volume.attachments[0]['Device'] == device:
            volume.detach_from_instance(
                Device=device,
                InstanceId=instance.id,
                Force=True
            )
            volume.wait_until_available()

    volume.attach_to_instance(
        Device=device,
        InstanceId=instance.id
    )


        # execute ssh command sending "reload" to agent
        

if __name__ == "__main__":
    restore_snapshot_to_volume()