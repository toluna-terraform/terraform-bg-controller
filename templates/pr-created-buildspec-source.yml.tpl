# code_build spec for pulling source from BitBucket
version: 0.2

phases:
  pre_build:
    commands:
      - yum install -y yum-utils
      - yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
      - yum -y install terraform consul
  build:
    commands:
      - |
        export CONSUL_PROJECT_ID=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/consul_project_id" --with-decryption --query 'Parameter.Value' --output text)
        export CONSUL_HTTP_TOKEN=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/consul_http_token" --with-decryption --query 'Parameter.Value' --output text)
        export CONSUL_HTTP_ADDR=https://consul-cluster-test.consul.$CONSUL_PROJECT_ID.aws.hashicorp.cloud
        export MONGODB_ATLAS_PROJECT_ID=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_project_id" --with-decryption --query 'Parameter.Value' --output text)
        export MONGODB_ATLAS_PUBLIC_KEY=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_public_key" --with-decryption --query 'Parameter.Value' --output text)
        export MONGODB_ATLAS_PRIVATE_KEY=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_private_key" --with-decryption --query 'Parameter.Value' --output text)
        cd terraform/app
        terraform init
        CURRENT_COLOR=$(consul kv get "/infra/${app_name}-${env_name}/current_color")
        if [[ $CURRENT_COLOR == "green" ]]; then
          terraform workspace select ${env_name}-blue || terraform workspace new ${env_name}-blue
          terraform init
          terraform plan -detailed-exitcode -out=.tf-plan
          terraform apply -auto-approve .tf-plan
          aws codepipeline start-pipeline-execution --name codepipeline-cd-${app_name}-${env_name}-blue --region us-east-1
        else 
          terraform workspace select ${env_name}-green || terraform workspace new ${env_name}-green
          terraform init
          terraform plan -detailed-exitcode -out=.tf-plan
          terraform apply -auto-approve .tf-plan
          aws codepipeline start-pipeline-execution --name codepipeline-cd-${app_name}-${env_name}-green --region us-east-1
        fi
        