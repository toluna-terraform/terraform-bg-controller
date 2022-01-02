# code_build spec for pulling source from BitBucket
version: 0.2

phases:
  pre_build:
    commands:
      - yum install -y yum-utils
      - yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
      - yum -y install terraform
  build:
    commands:
      - |
        export CONSUL_HTTP_TOKEN=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/consul_http_token" --with-decryption --query 'Parameter.Value' --output text)
        export MONGODB_ATLAS_PROJECT_ID=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_project_id" --with-decryption --query 'Parameter.Value' --output text)
        export MONGODB_ATLAS_PUBLIC_KEY=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_public_key" --with-decryption --query 'Parameter.Value' --output text)
        export MONGODB_ATLAS_PRIVATE_KEY=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_private_key" --with-decryption --query 'Parameter.Value' --output text)
        cd terraform/app
        terraform init
        MY_COLOR="$(cut -d'-' -f2 <<<'${env_name}')"
        MY_ENV="$(cut -d'-' -f1 <<<'${env_name}')"
        if [ "$MY_COLOR" == "green" ]; then
          terraform workspace new $MY_ENV-blue
          terraform init
          terraform plan -detailed-exitcode -out=.tf-plan
          terraform apply -auto-approve .tf-plan
          aws codepipeline start-pipeline-execution --name codepipeline-cd-${app_name}-$MY_ENV-blue --region us-east-1
        else 
          terraform workspace new $MY_ENV-green
          terraform init
          terraform plan -detailed-exitcode -out=.tf-plan
          terraform apply -auto-approve .tf-plan
          aws codepipeline start-pipeline-execution --name codepipeline-cd-${app_name}-$MY_ENV-green --region us-east-1
        fi
        cd ../shared
        terraform init
        terraform workspace select shared-${env_type}
        terraform plan -detailed-exitcode -out=.tf-plan
        terraform apply -auto-approve .tf-plan

        