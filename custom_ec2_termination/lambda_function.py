import boto3
import random

ecs = boto3.client('ecs')

ECS_CLUSTER = "milanoid-test-cluster"


def lambda_handler(event, context):
    idle_instances = []
    asg_name = event.get("AutoScalingGroupName")
    container_instance_arns = ecs.list_container_instances(cluster=ECS_CLUSTER)['containerInstanceArns']
    if not container_instance_arns:
        print(f"ASG Name: {asg_name}")
        raise ValueError(f"No container instances found in cluster: {ECS_CLUSTER}")
    container_details = ecs.describe_container_instances(cluster=ECS_CLUSTER, containerInstances=container_instance_arns)
    # Map EC2 instance IDs to container instance ARNs
    ecs_instances = {c['ec2InstanceId']: c['containerInstanceArn'] for c in container_details['containerInstances']}
    for ec2_instance_id, container_instance_arn in ecs_instances.items():
        tasks = ecs.list_tasks(cluster=ECS_CLUSTER, containerInstance=container_instance_arn, desiredStatus='RUNNING')
        if not tasks['taskArns']:
            idle_instances.append(ec2_instance_id)

    random.shuffle(idle_instances)
    print(f"ASG Name: {asg_name}")
    print({"InstanceIDs": idle_instances})
    return {"InstanceIDs": idle_instances}
