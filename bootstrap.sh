#!/usr/bin/env bash
set -euo pipefail

region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [[ -z "$region" ]]; then
  region="$(aws configure get region || true)"
fi
: "${region:?Abre CloudShell en la región de tu sandbox o exporta AWS_REGION}"

aws_cli() {
  aws --no-cli-pager --region "$region" "$@"
}

account="$(aws_cli sts get-caller-identity --query Account --output text)"
project="reto-java-ecs"
bucket="${project}-tfstate-${account}-${region}"
execution_role="${project}-execution"
deploy_role="${project}-deploy"
deploy_user="${project}-ci"
execution_arn="arn:aws:iam::$account:role/$execution_role"
deploy_arn="arn:aws:iam::$account:role/$deploy_role"
user_arn="arn:aws:iam::$account:user/$deploy_user"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

printf 'Cuenta AWS: %s\nRegión: %s\nBucket: %s\n' "$account" "$region" "$bucket"

cat > "$scratch/ecs-trust.json" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ecs-tasks.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
JSON

if ! aws_cli iam get-role --role-name "$execution_role" >/dev/null 2>&1; then
  aws_cli iam create-role --role-name "$execution_role" \
    --assume-role-policy-document "file://$scratch/ecs-trust.json" >/dev/null
fi
aws_cli iam attach-role-policy --role-name "$execution_role" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

if ! aws_cli iam get-user --user-name "$deploy_user" >/dev/null 2>&1; then
  aws_cli iam create-user --user-name "$deploy_user" >/dev/null
fi
aws_cli iam wait user-exists --user-name "$deploy_user"

cat > "$scratch/deploy-trust.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "$user_arn" },
    "Action": "sts:AssumeRole"
  }]
}
JSON

if ! aws_cli iam get-role --role-name "$deploy_role" >/dev/null 2>&1; then
  aws_cli iam create-role --role-name "$deploy_role" \
    --assume-role-policy-document "file://$scratch/deploy-trust.json" >/dev/null
fi

cat > "$scratch/assume-role.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sts:AssumeRole",
    "Resource": "$deploy_arn"
  }]
}
JSON

aws_cli iam put-user-policy --user-name "$deploy_user" --policy-name AssumeDeployRole \
  --policy-document "file://$scratch/assume-role.json"

cat > "$scratch/deploy-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadStateBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "arn:aws:s3:::$bucket"
    },
    {
      "Sid": "ReadAndWriteState",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": [
        "arn:aws:s3:::$bucket/registry/terraform.tfstate",
        "arn:aws:s3:::$bucket/service/terraform.tfstate",
        "arn:aws:s3:::$bucket/registry/terraform.tfstate.tflock",
        "arn:aws:s3:::$bucket/service/terraform.tfstate.tflock"
      ]
    },
    {
      "Sid": "RemoveStateLocks",
      "Effect": "Allow",
      "Action": "s3:DeleteObject",
      "Resource": [
        "arn:aws:s3:::$bucket/registry/terraform.tfstate.tflock",
        "arn:aws:s3:::$bucket/service/terraform.tfstate.tflock"
      ]
    },
    {
      "Sid": "RegistryLogin",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*",
      "Condition": { "StringEquals": { "aws:RequestedRegion": "$region" } }
    },
    {
      "Sid": "AppRegistry",
      "Effect": "Allow",
      "Action": [
        "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories",
        "ecr:ListTagsForResource", "ecr:TagResource", "ecr:UntagResource",
        "ecr:PutImageScanningConfiguration", "ecr:PutImageTagMutability",
        "ecr:DescribeImages", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"
      ],
      "Resource": "arn:aws:ecr:$region:$account:repository/$project"
    },
    {
      "Sid": "AppNetwork",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*", "ec2:CreateTags", "ec2:DeleteTags",
        "ec2:CreateVpc", "ec2:ModifyVpcAttribute", "ec2:DeleteVpc",
        "ec2:CreateSubnet", "ec2:ModifySubnetAttribute", "ec2:DeleteSubnet",
        "ec2:CreateInternetGateway", "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway", "ec2:DeleteInternetGateway",
        "ec2:CreateRouteTable", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
        "ec2:ReplaceRouteTableAssociation", "ec2:DeleteRouteTable",
        "ec2:CreateRoute", "ec2:ReplaceRoute", "ec2:DeleteRoute",
        "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
        "ec2:ModifySecurityGroupRules"
      ],
      "Resource": "*",
      "Condition": { "StringEquals": { "aws:RequestedRegion": "$region" } }
    },
    {
      "Sid": "AppLoadBalancer",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:Describe*", "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags",
        "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:ModifyLoadBalancerAttributes", "elasticloadbalancing:SetIpAddressType",
        "elasticloadbalancing:SetSecurityGroups", "elasticloadbalancing:SetSubnets",
        "elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:ModifyTargetGroup", "elasticloadbalancing:ModifyTargetGroupAttributes",
        "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:ModifyListener", "elasticloadbalancing:ModifyListenerAttributes"
      ],
      "Resource": "*",
      "Condition": { "StringEquals": { "aws:RequestedRegion": "$region" } }
    },
    {
      "Sid": "AppEcs",
      "Effect": "Allow",
      "Action": [
        "ecs:CreateCluster", "ecs:DescribeClusters", "ecs:UpdateCluster", "ecs:UpdateClusterSettings",
        "ecs:DeleteCluster", "ecs:PutClusterCapacityProviders",
        "ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition", "ecs:DeregisterTaskDefinition",
        "ecs:CreateService", "ecs:DescribeServices", "ecs:UpdateService", "ecs:DeleteService",
        "ecs:ListServiceDeployments", "ecs:DescribeServiceDeployments", "ecs:StopServiceDeployment",
        "ecs:ListTagsForResource", "ecs:TagResource", "ecs:UntagResource"
      ],
      "Resource": "*",
      "Condition": { "StringEquals": { "aws:RequestedRegion": "$region" } }
    },
    {
      "Sid": "DescribeLogs",
      "Effect": "Allow",
      "Action": "logs:DescribeLogGroups",
      "Resource": "*",
      "Condition": { "StringEquals": { "aws:RequestedRegion": "$region" } }
    },
    {
      "Sid": "AppLogGroup",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup", "logs:DeleteLogGroup",
        "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
        "logs:ListTagsForResource", "logs:TagResource", "logs:UntagResource",
        "logs:ListTagsLogGroup", "logs:TagLogGroup", "logs:UntagLogGroup"
      ],
      "Resource": [
        "arn:aws:logs:$region:$account:log-group:/ecs/$project",
        "arn:aws:logs:$region:$account:log-group:/ecs/$project:*"
      ]
    },
    {
      "Sid": "PassEcsExecutionRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "$execution_arn",
      "Condition": {
        "StringEquals": { "iam:PassedToService": ["ecs-tasks.amazonaws.com", "ecs.amazonaws.com"] }
      }
    },
    {
      "Sid": "CreateServiceLinkedRoles",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": [
        "arn:aws:iam::$account:role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS",
        "arn:aws:iam::$account:role/aws-service-role/elasticloadbalancing.amazonaws.com/AWSServiceRoleForElasticLoadBalancing"
      ],
      "Condition": {
        "StringEquals": {
          "iam:AWSServiceName": ["ecs.amazonaws.com", "elasticloadbalancing.amazonaws.com"]
        }
      }
    }
  ]
}
JSON

aws_cli iam put-role-policy --role-name "$deploy_role" --policy-name RetoJavaEcsDeploy \
  --policy-document "file://$scratch/deploy-policy.json"

if ! aws_cli s3api head-bucket --bucket "$bucket" --expected-bucket-owner "$account" >/dev/null 2>&1; then
  if [[ "$region" == us-east-1 ]]; then
    aws_cli s3api create-bucket --bucket "$bucket" >/dev/null
  else
    aws_cli s3api create-bucket --bucket "$bucket" \
      --create-bucket-configuration "LocationConstraint=$region" >/dev/null
  fi
  aws_cli s3api wait bucket-exists --bucket "$bucket"
fi

aws_cli s3api put-public-access-block --bucket "$bucket" --expected-bucket-owner "$account" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
versioning="$(aws_cli s3api get-bucket-versioning --bucket "$bucket" --expected-bucket-owner "$account" \
  --query Status --output text)"
if [[ "$versioning" != Enabled ]]; then
  aws_cli s3api put-bucket-versioning --bucket "$bucket" --expected-bucket-owner "$account" \
    --versioning-configuration Status=Enabled
  printf '\nAWS recomienda esperar 15 minutos tras habilitar el versionado antes de ejecutar el despliegue.\n'
fi

printf '\nCopia estos valores como variables de GitHub Actions.\n'
printf 'AWS_REGION=%s\nTF_STATE_BUCKET=%s\n' "$region" "$bucket"
printf 'AWS_DEPLOY_ROLE_ARN=%s\nAWS_TASK_EXECUTION_ROLE_ARN=%s\n' "$deploy_arn" "$execution_arn"
printf '\nEn IAM, crea una clave de acceso para %s.\n' "$deploy_user"
