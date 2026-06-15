## 部署文档

### 说明

- eksctl 默认会为每个集群创建独立的VPC，VPC的CIDR为`192.168.0.0/16`

- 如果同一个aws账号内要部署多个eks集群，需要修改VPC默认的CIDR(否则无法于默认VPC通信)，将`eks-cluster.yml.tpl`中vpc配置注释取消

- 集群默认部署2个m5.large规格（2vCPU/8G内存/80G磁盘）的EC2节点，如需要，请自行在eks-cluster.yml修改

- EC2工作节点没有公网IP，如果需要ssh连接工作节点，需要通过一台有公网IP的跳板机进行登录，ssh登录的用户为`ec2-user`，登录证书为`id_rsa`文件。如果跳板机和eks集群不是在同一个VPC，则需要修改类似`eksctl-[集群名称]-nodegroup-eks-ng-1`的安全组，加上允许跳板机所在的IP范围的入站规则

  登录ec2节点命令参考如下：

  注：id_rsa文件的权限不能给太大

  ```
  chmod 400 id_rsa
  ssh -i "/home/ubuntu/eks-deploy/id_rsa" ec2-user@192.168.150.42
  ```

  ​

### 部署前提
1. aws账号安全凭证（即access key id和access key），在IAM中获取生成
2. 在默认VPC中，已部署好RDS，ElastiCache
3. 镜像已推送到ECR

### 部署准备

1. 安装aws cli
    官方文档：https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

    安装参考命令

    安装之前需要安装unzip，参考安装命令

    ```
    sudo apt install unzip
    ```

    ```
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    ```

    执行以下命令

    ```
    aws configure
    需要填写以下几个信息
    access key ID（excel文件中对应的aws帐号的id）
    secret access key（excel文件中对应的aws帐号的key）
    Default region name(ap-southeast-1)
    Default output format(json)
    ```

    1. > 注意：在执行 `aws configure`命令时，最后一个输出格式只能选择`json`，不然kubectl连接集群会无法解析

2. 安装eksctl
    官方文档：https://eksctl.io/introduction/#installation

    注：由于官方eksctl经常更新升级，为了保持稳定性，最好是用已经成功部署过的eksctl版本来执行！！

    上面的备注不对，eksctl必须使用官方版本，否则会不支持集群中k8s的最新版本部署

    步骤：先将eks的tar包拷贝到ubuntu，然后执行如下命令

    ```
    tar xzvf  eksctl_Linux_amd64.tar.gz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
    ```

    安装参考命令

    ```
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
    ```

3. 安装kubectl
    官方文档：https://kubernetes.io/docs/tasks/tools/#kubectl

    安装参考命令

    ```
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    ```

    ```
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    ```

    ```
    kubectl version --client
    ```

    安装参考命令2

    ```
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo apt-get install -y apt-transport-https
    sudo curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

    sudo apt-get update
    sudo apt-get install -y kubectl
    ```

4. 安装helm
    官方文档：https://helm.sh/docs/intro/install/

    安装参考命令

    ```
     curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
     chmod 700 get_helm.sh
     ./get_helm.sh
    ```

5. 安装python3
    Linux系统一般默认有安装python，但如果是python2，请另安装python3；ubuntu22.04，安装命令如下：

    ```
    sudo apt install python-is-python3 python3-pip
    ```

    官方文档：https://www.python.org/downloads/

6. 安装lens（非必须）
    官方文档：https://docs.k8slens.dev/getting-started/install-lens/
  > 注意：lens在Windows下连接eks集群如果报找不到aws命令的话，需将`~/.kube/config`文件中user.exec.command下的aws改成Windows下aws.exe的绝对路径。并且，如果需要管理不同aws账号的不同集群，需要aws的profile配置，`~/.kube/config`文件中也支持配置`AWS_PROFILE`的环境变量，例如：
  ```
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
      - --region
      - ap-southeast-1
      - eks
      - get-token
      - --cluster-name
      - test-ec2
      - --output
      - json
      command: C:\Program Files\Amazon\AWSCLIV2\aws.exe
      env:
      - name: AWS_PROFILE
        value: demo
  ```

### 一键部署
```bash
bash auto.sh [集群名称] [Region名称] [AWS profile名称]
eg：
bash auto.sh eks-game ap-southeast-1
```
前两个参数必填，最后一个参数为可选，默认使用`default` profile
例如：
```bash
bash auto.sh eks-test ap-southeast-1
注：最新版本的执行该命令会报错，需要增加以下一个命令
sed -i 's/\r$//' auto.sh（deploy.sh也需要执行）
sed -i 's/\r$//' deploy.sh
```

### 部署完毕后执行的操作

```
1、在jenkins服务器上挂载
eg：
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 192.168.98.33:/ /home/ubuntu/efs
2、在lens上添加集群信息
eg：
aws configure --profile eks-game 填写的id和key从服务器资料中获取,region填ap-southeast-1，格式填json
填完之后执行下面命令更新配置
aws eks update-kubeconfig --region ap-southeast-1 --name eks-game --profile eks-game
记得修改.kube/config中的aws路径
添加完毕之后lens上会自动生成

--添加ec2节点
eksctl scale nodegroup --cluster=集群名 --nodes=期望节点数 --name=节点组名 --nodes-min=最小节点数 --nodes-max=最大节点数
eg:
eksctl scale nodegroup --cluster=eks-huange --nodes=8 --name=eks-ng-1 --nodes-min=8 --nodes-max=14
--获取公司节点情况
eksctl get nodegroup --cluster eks-huange --region ap-southeast-1 --name eks-ng-1
```



### 手动部署过程

类似地，手动部署要先运行：
```bash
bash manual.sh [集群名称] [Region名称] [AWS profile名称]
```
> 如果一键自动部署过程出错中断，可根据出错位置，在解决出错原因后，手动部署后续步骤
#### 1. 部署eks集群
```bash
eksctl create cluster -f eks-cluster.yml
```
该命令默认aws cli的`default`profile配置，如果要使用不同的profile，可以通过环境变量`AWS_PROFILE`指定，例如，使用profile demo：
```bash
AWS_PROFILE=demo eksctl create cluster -f eks-cluster.yml
```
等待部署完成，时间大约需要十到二十分钟。
部署完成后，显示类似：EKS cluster "{{clustername}}" in "ap-southeast-1" region is ready

此时，kubectl已经可以连接集群：
```bash
$ kubectl get pod -A
NAMESPACE     NAME                                  READY   STATUS    RESTARTS   AGE
kube-system   aws-node-9bw76                        1/1     Running   0          4m1s
kube-system   aws-node-hz2fx                        1/1     Running   0          4m3s
kube-system   coredns-7cc96f45bb-gq84g              1/1     Running   0          15m
kube-system   coredns-7cc96f45bb-gt8w4              1/1     Running   0          15m
kube-system   ebs-csi-controller-7664c869b9-h75br   6/6     Running   0          2m17s
kube-system   ebs-csi-controller-7664c869b9-wtncg   6/6     Running   0          2m17s
kube-system   ebs-csi-node-s98rn                    3/3     Running   0          2m17s
kube-system   ebs-csi-node-wdrhl                    3/3     Running   0          2m17s
kube-system   kube-proxy-b6nnn                      1/1     Running   0          4m1s
kube-system   kube-proxy-p2h54                      1/1     Running   0          4m3s
```
如果kubectl连不上，可以用以下命令更新kubeconfig文件：
```bash
aws eks update-kubeconfig --region [区域名] --name [集群名称]
```
#### 2. 部署系统组件
  - 部署metrics-server
    ```bash
    kubectl apply -f components/metrics-server.yaml

    # 查看状态
    kubectl get deployment metrics-server -n kube-system
    ```
  - 部署kube-prometheus-stack（包含prometheus，grafana，alertmanager，node-exporter）
    ```bash
    # 创建命名空间
    kubectl create namespace prometheus
      
    # 部署kube-prometheus-stack
    helm install monitor components/kube-prometheus-stack-45.10.1.tgz -f components/prom-stack-configs.yml -n prometheus
    ```

  - 部署Fluent Bit
    ```bash
    kubectl apply -f components/fluentbit.yml

    kubectl get pods -n amazon-cloudwatch
    ```

  - 部署EFS CSI Driver
    ```bash
    helm upgrade -i aws-efs-csi-driver components/aws-efs-csi-driver-2.4.1.tgz \
    --namespace kube-system \
    --set image.repository=602401143452.dkr.ecr.ap-southeast-1.amazonaws.com/eks/aws-efs-csi-driver \
    --set controller.serviceAccount.create=false \
    --set controller.serviceAccount.name=efs-csi-controller-sa
    ```

    创建EFS文件系统
    ```bash
    注意：
    在ubuntu24.0版本中执行pip install boto3会报错，执行下面安装命令
    sudo apt install python3-boto3
    python3 components/create_efs.py
    ```
    创建EFS storage class
    ```bash
    kubectl apply -f components/storageclass.yml
    ```

  - 部署cluster-autoscaler
    ```bash
    kubectl apply -f components/cluster-autoscaler-autodiscover.yaml
    ```

  - 打通eks VPC和默认VPC网络
    ```bash
    python3 components/vpc_network.py
    ```

#### 3. 部署业务应用
  业务应用的yaml文件存放在apps目录，请根据实际部署情况，修改镜像地址等信息。
    ​```bash
    bash apps/deploy.sh
    ​```

#### 4. 其他说明
  - 自动部署完成后，会返回，`front-image-svc`Service的 External IP，配置DNS CNAME，也可以自行获取：
    ```bash
    kubectl get svc front-image-svc
    ```

  - 自动部署完成后，会返回NAT网关的IP地址，手动获取命令：
    ```bash
    aws --region <区域名> ec2 describe-nat-gateways --filter 'Name=tag:alpha.eksctl.io/cluster-name,Values=<集群名>' --query 'NatGateways[*].NatGatewayAddresses[*].PublicIp' --output text
    例如
    aws --region ap-southeast-1 ec2 describe-nat-gateways --filter 'Name=tag:alpha.eksctl.io/cluster-name,Values=test-ec2' --query 'NatGateways[*].NatGatewayAddresses[*].PublicIp' --output text
    ```

  - 安装完成后，请登录aws，找到刚创建的EFS文件系统（自动部署过程中有输出efs的ID），找到连接的挂载命令，挂载到机器后，将静态文件拷贝到相应pvc目录中

- 节点组的名称为：eks-ng-1，执行手动扩缩容的命令如下

  ```bash
  eksctl scale nodegroup --cluster=<clusterName> --nodes=<desiredCount> --name=<nodegroupName> [ --nodes-min=<minSize> ] [ --nodes-max=<maxSize> ]
  ```

  - Grafana可以通过lens的port-forward在本地打开，admin用户的默认密码是`prom-operator`

  - 登录Grafana后，侧边栏-Dashboard-Import，填入dashboard ID: 16144 导入JVM监控面板。

    ```
    16144 JVM监控面板
    17053 Spring Boot & Endpoint Metrics 2.0
    ```

    也可以在Grafana官网自行寻找合适的dashboard

#### 5. 删除集群说明

- 确认你要删除的集群所使用的的aws profile，eksctl 默认使用default，非默认需通过环境变量AWS_PROFILE指定

- kubectl 所连接的集群是你要删除的集群

- 删除对等连接，连同相关路由项一起删除，修改`components/utils/remove_peering.py`文件中的profile名称，集群名和区域名称，然后执行：
  `python components/utils/remove_peering.py`

- 要先删除pdb，不然eksctl删除会失败

  ```bash
  kubectl delete pdb ebs-csi-controller -n kube-system
  eksctl delete cluster [集群名称]
  eg:
  eksctl delete cluster eks-game
  ```

- 删除名为EFS-SecurityGroup的安全组，EFS文件系统。修改`components/utils/remove_efs.py`文件中的profile名称，集群名和区域名称，然后执行：
  `python components/utils/remove_efs.py`

- 可以登录到AWS查看CloudFormation中是否有正在删除或删除失败的堆栈，如果有，请等待或重新删除堆栈

- 删除EFS后，已经挂载的EFS因连不上服务端，会造成卡死状态，可以用命令强制卸载：

  ```bash
  sudo umount -f /home/ubuntu/efs
  ```

- EBS数据卷，默认不会自动删除，请到EC2页面下自行删除没用的数据卷

- node磁盘清理

  ```
  eksctl upgrade nodegroup --name=eks-ng-1 --cluster=eks-huange
  ```

  ​