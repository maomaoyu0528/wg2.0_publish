import boto3

profile_name = 'default'

cluster_name = 'eks-test'

region_name='ap-southeast-1'

session = boto3.Session(region_name=region_name, profile_name=profile_name)

ec2 = session.resource('ec2')
eks = session.client('eks')
efs = session.client('efs')

def get_default_vpc_id():
    vpcs = ec2.vpcs.filter(Filters=[{'Name': 'isDefault', 'Values': ['true']}])
    default_vpc = None
    for vpc in vpcs:
        default_vpc = vpc.id
        break
    return default_vpc

def get_eks_vpc_id(cluster_name):
    cluster_info = eks.describe_cluster(name=cluster_name)
    vpc_id = cluster_info['cluster']['resourcesVpcConfig']['vpcId']
    return vpc_id


def get_vpc_peering_id(vpc_id1, vpc_id2):
    vpc_peering_connections = ec2.vpc_peering_connections.filter(
        Filters=[
            {'Name': 'requester-vpc-info.vpc-id', 'Values': [vpc_id1]},
            {'Name': 'accepter-vpc-info.vpc-id', 'Values': [vpc_id2]}
        ]
    )

    peering_id = None
    for peering in vpc_peering_connections:
        peering_id = peering.id
        break  # 找到第一个匹配的就停止搜索

    return peering_id

def delete_route_tables(vpc_id1, vpc_id2, peer_id):
    vpcs = [ec2.Vpc(vpc_id1), ec2.Vpc(vpc_id2)]
    cidrs = [vpc.cidr_block for vpc in vpcs]

    for i, vpc in enumerate(vpcs):
        route_tables = vpc.route_tables.all()
        for route_table in route_tables:
            routes = [route for route in route_table.routes if route.vpc_peering_connection_id == peer_id]

            if len(routes) > 0:
                route = routes[0]
                route.delete()
            # route = route_table.routes.filter(
            #     Filters=[{'Name': 'vpc-peering-connection-id', 'Values': [peer_id]}]
            # )[0]
            # route.delete()

def delete_vpc_peering(peer_id):
    peering = ec2.VpcPeeringConnection(peer_id)
    peering.delete()

def delete_mount_targets(file_system_id):  
    paginator = efs.get_paginator('describe_mount_targets')
    
    for page in paginator.paginate(FileSystemId=file_system_id):
        for mount_target in page['MountTargets']:
            mount_target_id = mount_target['MountTargetId']
            print(f"Deleting mount target: {mount_target_id}")
            efs.delete_mount_target(MountTargetId=mount_target_id)
            print(f"Deleted mount target: {mount_target_id}")

default_vpc_id = get_default_vpc_id()
eks_vpc_id = get_eks_vpc_id(cluster_name)
peering_id = get_vpc_peering_id(eks_vpc_id, default_vpc_id)

delete_route_tables(eks_vpc_id, default_vpc_id, peering_id)

delete_vpc_peering(peering_id)

print("VPC peering connection and related route entries deleted!")
