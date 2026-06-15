import boto3

profile_name = '{{profile}}'

cluster_name = '{{clustername}}'

region_name='{{region}}'

session = boto3.Session(region_name=region_name, profile_name=profile_name)

ec2 = session.resource('ec2')
eks = session.client('eks')

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

default_vpc_id = get_default_vpc_id()
eks_vpc_id = get_eks_vpc_id(cluster_name)

# print(default_vpc_id)
# print(eks_vpc_id)

def create_vpc_peering(vpc_id1, vpc_id2):
    peering = ec2.create_vpc_peering_connection(
        VpcId=vpc_id1,
        PeerVpcId=vpc_id2
    )
    return peering.id

def accept_vpc_peering(peer_id):
    peering = ec2.VpcPeeringConnection(peer_id)
    peering.accept()

def update_route_tables(vpc_id1, vpc_id2, peer_id):
    vpcs = [ec2.Vpc(vpc_id1), ec2.Vpc(vpc_id2)]
    cidrs = [vpc.cidr_block for vpc in vpcs]

    for i, vpc in enumerate(vpcs):
        route_tables = vpc.route_tables.all()
        for route_table in route_tables:
            route_table.create_route(
                DestinationCidrBlock=cidrs[1 - i],
                VpcPeeringConnectionId=peer_id
            )

peering_id = create_vpc_peering(eks_vpc_id, default_vpc_id)
accept_vpc_peering(peering_id)
update_route_tables(eks_vpc_id, default_vpc_id, peering_id)
print('VPC peering connection created!')