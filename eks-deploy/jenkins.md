# Jenkins部署并推送AWS ECR

## 1. 安装docker
按照官方文档部署：[Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)
安装后，执行：

`sudo usermod -aG docker $USER`

重新登录！

## 2. 安装jenkins
按照官方文档部署：[Debian Jenkins Packages](https://pkg.jenkins.io/debian-stable/)
Jenkins HOME路径：/var/lib/jenkins
Jenkins 管理命令：
```
sudo systemctl status/restart/stop jenkins
```
部分配置可以在
```
vi /lib/systemd/system/jenkins.service 中修改，如port
```

注：如修改了配置文件之后，需要执行
```
sudo systemctl daemon-reload
```

注：需要在EC2的安全组的入站规则添加对应的jenkins的端口，否则无法通过外网访问。

安装完毕后，重启Jenkins切换成中文版

注：修改jenkins所在ec2的时间（改为北京时区和北京时间）

校正方法如下：

1.运行tzselect，选择Asia（亚洲），选4
2.选择China，选10，然后选定北京时间，选1
3.复制文件到本地时间内
```
sudo cp /usr/share/zoneinfo/Asia/Shanghai  /etc/localtime
```
同时还需要修改ec2的时区（原来的是UTC）
修改命令如下：
```
sudo timedatectl set-timezone Asia/Shanghai
这样设置完了 还是有问题  执行cat /etc/timezone 
sudo vi /etc/timezone  修改成Asia/Shanghai(这样修改后jenkins构建时用的时间才是对的!)
```
修改后，需要重启jenkins服务，重启命令如下：
```
sudo systemctl restart jenkins
```
在初始化jenkins的时候会要求输入初始密码

此时需要先将ubuntu的用户切换成root，才能看到 ,切换命令为

```
su root
```

ubuntu下切换root的方法为，先给root设置密码（这边默认都设置为admin@123）

```
sudo passwd root
```

设置完毕后再su root，切换成root用户，这回就可以进入到jenkins的secrets下看到初始的管理员密码了

安装完毕后，在插件管理中安装

1、Extended Choice Parameter（用来支持复选框参数）

2、docker pipeline插件,stage view插件也必须安装（否则构建的历史记录里面无法看到log）

3、在jenkins的ec2上执行（jenkins需要执行sudo命令需要密码的问题）

```
sudo vim /etc/sudoers.d/90-cloud-init-users
```

在这个文件最后面添加

```
jenkins ALL=(ALL) NOPASSWD: ALL
```

4、拷贝BaseImage文件夹内容

在新的jenkins服务器下执行以下命令：

```
docker build -f Dockerfile -t base:1.0.0 .
目前重构后的新版本使用的是jdk17的，所以BaseImage应该用BaseImageJdk17
```

5、jenkins ec2上还需要安装nfs-common，用来挂载efs

```
sudo apt-get install nfs-common
```
6、jenkins的在挂载好efs后还需要增加一步授权命令（废弃）
```
sudo chown -R jenkins:ubuntu /home/ubuntu/efs/
```
注：增加了这个授权后，要在ec2上执行git pull，需要加sudo

7、同时修改jenkins上的前端更新的job，将efs的pvc目录修改下即可（废弃）

## 3. 安装aws cli

按照官方文档：[Installing or updating the latest version of the AWS CLI - AWS Command Line Interface (amazon.com)](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
登录aws，进入[IAM](https://us-east-1.console.aws.amazon.com/iamv2/home?region=ap-southeast-1#/security_credentials) 生成access token

执行如下命令

`aws configure`命令进行认证 

<font color='red'>注：认证的信息要从AWS的IAM进去，然后在右侧的快速链接进入我的安全凭证，如果没有的话就创建一个root的token。</font>

## 4. 配置

docker 登录 ECR：
```bash
aws ecr get-login-password --region [region] | docker login --username AWS --password-stdin [aws_account_id].dkr.ecr.[region].amazonaws.com

eg:
aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin 912643663034.dkr.ecr.ap-southeast-1.amazonaws.com
```

jenkins中执行docker命令的认证配置：将`~/.docker/config`复制到jenkins主目录`/var/lib/jenkins/.docker`，并更改成jenkins用户组

解决ECR token 12小时过期问题：
```bash
sudo mkdir /var/lib/jenkins/.docker
sudo cp /home/ubuntu/.docker/config.json /var/lib/jenkins/.docker/
sudo chown jenkins:jenkins /var/lib/jenkins/.docker
```
将以下文件保存为`update-ecr-token.sh`

<font color='red'>注：切记要修改update-ecr-token.sh中的仓库地址！！！</font>

```bash
#! /bin/bash

aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin 551987061454.dkr.ecr.ap-southeast-1.amazonaws.com

sudo cp /home/ubuntu/.docker/config.json /var/lib/jenkins/.docker/

sudo chown jenkins:jenkins /var/lib/jenkins/.docker/config.json
```
crontab -e:此命令为修改定时任务
crontab -l:此命令为查看定时任务
添加定时任务，每10小时更新一次token
```
注意：ubuntu24.04版本执行执行这个命令会不生效，要使用crontab -e命令，将以下的命令配置在文件的最底下
0 */10 * * * bash /home/ubuntu/update-ecr-token.sh > /dev/null 2>&1
```
## 解决jenkins执行docker命令报权限错误
将jenkins用户添加到docker用户组：
```
sudo usermod -aG docker jenkins
```

如果，jenkins的job执行有问题，需要手动执行一次 update-ecr-token.sh！！

```
sh update-ecr-token.sh
```

重启jenkins

```
sudo systemctl restart jenkins
```
## 在jenkins上新创建一个job

1、在jenkins上创建job，点击new item，然后类型选的是pipeline

2、在jenkins上要创建一个凭证，配置的是github的帐号密码

