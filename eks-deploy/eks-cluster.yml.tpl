apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: {{clustername}}
  region: {{region}}

#vpc:
#  cidr: 10.10.0.0/16

iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: cluster-autoscaler
        namespace: kube-system
        labels: {aws-usage: "cluster-ops"}
      wellKnownPolicies:
        autoScaler: true
addons:
  - name: aws-ebs-csi-driver
    wellKnownPolicies:
      ebsCSIController: true
nodeGroups:
  - name: eks-ng-1
    instanceType: t3.xlarge
    minSize: 2
    maxSize: 4
    desiredCapacity: 2
    privateNetworking: true
    ssh:
      publicKeyPath: ./id_rsa.pub
    tags:
      k8s.io/cluster-autoscaler/enabled: "true"
      k8s.io/cluster-autoscaler/{{clustername}}: "owned"
    iam:
      withAddonPolicies:
        autoScaler: true
        ebs: true
        efs: true
        cloudWatch: true
