import re
import os
import time
import boto3

# aws profile name
profile_name = '{{profile}}'
# 你的 EKS 集群名
cluster_name = '{{clustername}}'

region_name='{{region}}'

session = boto3.session.Session(region_name=region_name, profile_name=profile_name)

ec2 = session.client('ec2')
eks = session.client('eks')
efs = session.client('efs')

# def get_default_vpc_id():
#     vpcs = ec2.vpcs.filter(Filters=[{'Name': 'isDefault', 'Values': ['true']}])
#     default_vpc = None
#     for vpc in vpcs:
#         default_vpc = vpc.id
#         break
#     return default_vpc

def get_eks_vpc_id(cluster_name):
    cluster_info = eks.describe_cluster(name=cluster_name)
    vpc_id = cluster_info['cluster']['resourcesVpcConfig']['vpcId']
    return vpc_id

# default_vpc_id = get_default_vpc_id()
eks_vpc_id = get_eks_vpc_id(cluster_name)

# print(default_vpc_id)
# print(eks_vpc_id)

def get_az_subnets(vpc_id):
    subnets = ec2.describe_subnets(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])

    first_subnet_ids = {}

    for subnet in subnets['Subnets']:
        availability_zone = subnet['AvailabilityZone']
        
        if availability_zone not in first_subnet_ids:
            first_subnet_ids[availability_zone] = subnet['SubnetId']
    
    return first_subnet_ids
    

security_group = ec2.create_security_group(GroupName='EFS-SecurityGroup', Description='EFS security group', VpcId=eks_vpc_id)
security_group_id = security_group['GroupId']

ec2.authorize_security_group_ingress(
    GroupId=security_group_id,
    IpProtocol='tcp',
    FromPort=2049,
    ToPort=2049,
    CidrIp='0.0.0.0/0'
)

efs_file_system = efs.create_file_system(
    CreationToken='my-efs-file-system',
    Encrypted=False,
    Tags=[
        {
            'Key': 'cluster_name',
            'Value': cluster_name
        }
    ]
)

efs_file_system_id = efs_file_system['FileSystemId']

while True:
    efs_response = efs.describe_file_systems(FileSystemId=efs_file_system_id)
    if efs_response['FileSystems'][0]['LifeCycleState'] == 'available':
        print('EFS file system is available')
        break
    else:
        print('EFS file system is not yet available, waiting...')
        time.sleep(3) 

subnets = get_az_subnets(eks_vpc_id)
for az, subnet_id in subnets.items():
    efs.create_mount_target(
        FileSystemId=efs_file_system_id,
        SubnetId=subnet_id,
        SecurityGroups=[security_group_id]
    )

print("EFS file system created successfully! The file system ID is: " + efs_file_system_id)

current_path = os.path.abspath(os.path.dirname(__file__))
sc = os.path.join(current_path, "storageclass.yml")

with open(sc, "r") as file:
    content = file.read()

updated_content = re.sub(r'fileSystemId: fs-\w+', f'fileSystemId: {efs_file_system_id}', content)

with open(sc, "w") as file:
    file.write(updated_content)

print("efs ID in storageclass.yml updated successfully!")