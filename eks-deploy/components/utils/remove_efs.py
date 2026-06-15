import time
import boto3

profile_name = 'default'

cluster_name = 'eks-test'

region_name='ap-southeast-1'

session = boto3.Session(region_name=region_name, profile_name=profile_name)

ec2 = session.client('ec2')
efs = session.client('efs')
iam = session.client('iam')

def delete_efs_policy(policy_name):
    try:
        response = iam.list_policies(Scope='Local')
        policy_arn = None
        for policy in response['Policies']:
            if policy['PolicyName'] == policy_name:
                policy_arn = policy['Arn']
                break

        if policy_arn is None:
            print(f"Policy '{policy_name}' not found.")
        else:
            try:
                response = iam.delete_policy(PolicyArn=policy_arn)
                print(f"Successfully deleted policy '{policy_name}'.")
            except Exception as e:
                print(f"Error deleting policy '{policy_name}': {e}")
                
    except Exception as e:
        print(f"Error: {e}")

def get_file_system_id_by_tag(tag_key, tag_value):
    
    paginator = efs.get_paginator('describe_file_systems')

    for page in paginator.paginate():
        for file_system in page['FileSystems']:
            file_system_id = file_system['FileSystemId']
            
            # 获取文件系统的标签
            tags_response = efs.describe_tags(FileSystemId=file_system_id)
            tags = tags_response['Tags']
            
            # 查找与指定标签匹配的文件系统
            for tag in tags:
                if tag['Key'] == tag_key and tag['Value'] == tag_value:
                    print(f"File System ID with tag {tag_key}={tag_value}: {file_system_id}")
                    return file_system_id

    print("No file system found with the specified tag.")
    return None

def delete_mount_targets(file_system_id):  
    paginator = efs.get_paginator('describe_mount_targets')
    
    for page in paginator.paginate(FileSystemId=file_system_id):
        for mount_target in page['MountTargets']:
            mount_target_id = mount_target['MountTargetId']
            print(f"Deleting mount target: {mount_target_id}")
            efs.delete_mount_target(MountTargetId=mount_target_id)
            print(f"Deleted mount target: {mount_target_id}")
    mount_targets_deleted = False
    while not mount_targets_deleted:
        mount_targets = efs.describe_mount_targets(FileSystemId=file_system_id)['MountTargets']
        if len(mount_targets) == 0:
            mount_targets_deleted = True
        else:
            print("Waiting for mount targets to be deleted...")
            time.sleep(10)


def delete_security_group_by_name(group_name):
    response = ec2.describe_security_groups(
        Filters=[
            {
                'Name': 'group-name',
                'Values': [group_name]
            }
        ]
    )

    groups = response['SecurityGroups']
    group_id_list = []

    if len(groups) == 0:
        print(f"No security group found with the name '{group_name}'.")
        return
    
    for group in groups:
        group_id = group['GroupId']
        group_id_list.append(group_id)

        try:
            response = ec2.delete_security_group(GroupId=group_id)
            print(f"Security group '{group_name}' with ID '{group_id}' has been deleted.")
        except Exception as e:
            print(f"Error deleting security group '{group_name}' with ID '{group_id}': {e}")

    return group_id_list

file_system_id = get_file_system_id_by_tag('cluster_name', cluster_name)
delete_mount_targets(file_system_id)

group_name = "EFS-SecurityGroup"
delete_security_group_by_name(group_name)

try:
    efs.delete_file_system(FileSystemId=file_system_id)
    print(f"File system with ID '{file_system_id}' has been deleted.")
except Exception as e:
    print(f"Error deleting file system with ID '{file_system_id}': {e}")

print("EFS mount targets and security group deleted!")

delete_efs_policy("AmazonEKS_EFS_CSI_Driver_Policy")
