# code_build spec for pulling source from BitBucket
version: 0.2

phases:
  pre_build:
    commands:
      - yum install -y yum-utils
      - yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
      - yum -y install terraform
      - yum install -y yum-utils consul
      - export CONSUL_PROJECT_ID=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/consul_project_id" --with-decryption --query 'Parameter.Value' --output text)
      - export CONSUL_HTTP_TOKEN=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/consul_http_token" --with-decryption --query 'Parameter.Value' --output text)
      - export CONSUL_HTTP_ADDR=https://consul-cluster-test.consul.$CONSUL_PROJECT_ID.aws.hashicorp.cloud
      - export MONGODB_ATLAS_PROJECT_ID=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_project_id" --with-decryption --query 'Parameter.Value' --output text)
      - export MONGODB_ATLAS_PUBLIC_KEY=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_public_key" --with-decryption --query 'Parameter.Value' --output text)
      - export MONGODB_ATLAS_PRIVATE_KEY=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_private_key" --with-decryption --query 'Parameter.Value' --output text)
        
  build:
    commands:
      - |
        INFRA_CHANGED=$(consul kv get "infra/${app_name}-${env_name}/infra_changed")
        if [ "$INFRA_CHANGED" == "true" ]; then
          CURRENT_COLOR=$(consul kv get "infra/${app_name}-${env_name}/current_color")
          if [ "$CURRENT_COLOR" != "green" ] && [ "$CURRENT_COLOR" != "blue" ]; then
            echo "Creating Green route"
            NEXT_COLOR="green"
            CURRENT_COLOR="white"
            CURRENT_RECORD="DUMMY_Blue"
          else 
            echo "switching colors"
            if [[ $CURRENT_COLOR == "green" ]]; then
              NEXT_COLOR="blue"
              CURRENT_COLOR="green"
            else
              NEXT_COLOR="green"
              CURRENT_COLOR="blue"
            fi
          fi
          consul kv delete "infra/${app_name}-${env_name}/infra_changed"
          consul kv put "infra/${app_name}-${env_name}/current_color" $NEXT_COLOR
          echo "Shifting traffic"
          cd ../shared
          terraform init
          terraform workspace select shared-${env_type}
          terraform init
          terraform plan -target=module.dns -detailed-exitcode -out=.tf-plan
          terraform apply -target=module.dns -auto-approve .tf-plan
          cd terraform/app
          terraform init
          if [[ "$CURRENT_COLOR" == "white" ]]; then
            terraform workspace select ${env_name}
          else
            terraform workspace select ${env_name}-$CURRENT_COLOR
          fi
          echo "Destroying old environment"
          cd ../app
          terraform init
          terraform destroy -auto-approve
          terraform workspace select ${env_name}-$NEXT_COLOR
          if [[ "$CURRENT_COLOR" == "white" ]]; then
            terraform workspace delete ${env_name}
          else
            terraform workspace delete ${env_name}-$CURRENT_COLOR
          fi
        fi
