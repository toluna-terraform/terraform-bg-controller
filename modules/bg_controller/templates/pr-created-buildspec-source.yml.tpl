# code_build spec for pulling source from BitBucket
version: 0.2

phases:
  pre_build:
    commands:
      - yum install -y yum-utils
      - yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
      - yum -y install terraform consul
      - head=$(echo $CODEBUILD_WEBHOOK_HEAD_REF | awk -F/ '{print $NF}')
      - base=$(echo $CODEBUILD_WEBHOOK_BASE_REF | awk -F/ '{print $NF}')
      - git diff --name-only origin/$head origin/$base --raw > /tmp/diff_results.txt
      - PR_NUMBER="$(echo $CODEBUILD_WEBHOOK_TRIGGER | cut -d'/' -f2)"
  build:
    commands:
      - |
        if grep -q terraform/app "/tmp/diff_results.txt" ; then
          TF_CHANGED="true"
        else 
          TF_CHANGED="false"
        fi
        echo "did tf have changes $TF_CHANGED"
        if [[ "${pipeline_type}" == "ci" || "${is_blue_green}" == "true" ]] && [[ "$TF_CHANGED" == "true" ]]; then
          export CONSUL_PROJECT_ID=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/consul_project_id" --with-decryption --query 'Parameter.Value' --output text)
          export CONSUL_HTTP_TOKEN=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/consul_http_token" --with-decryption --query 'Parameter.Value' --output text)
          export CONSUL_HTTP_ADDR=https://consul-cluster-test.consul.$CONSUL_PROJECT_ID.aws.hashicorp.cloud
          export MONGODB_ATLAS_PROJECT_ID=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_project_id" --with-decryption --query 'Parameter.Value' --output text)
          export MONGODB_ATLAS_PUBLIC_KEY=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_public_key" --with-decryption --query 'Parameter.Value' --output text)
          export MONGODB_ATLAS_PRIVATE_KEY=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_private_key" --with-decryption --query 'Parameter.Value' --output text)
          cd terraform/app
          terraform init
          CURRENT_COLOR=$(consul kv get "infra/${app_name}-${env_name}/current_color")
          if [[ $CURRENT_COLOR == "green" ]]; then
            terraform workspace select ${env_name}-blue || terraform workspace new ${env_name}-blue
            terraform init
            terraform plan -detailed-exitcode -out=.tf-plan
            terraform apply -auto-approve .tf-plan
          else 
            terraform workspace select ${env_name}-green || terraform workspace new ${env_name}-green
            terraform init
            terraform plan -detailed-exitcode -out=.tf-plan
            terraform apply -auto-approve .tf-plan
          fi
          consul kv put "infra/${app_name}-${env_name}/infra_changed true
        else
          consul kv put "infra/${app_name}-${env_name}/infra_changed false
        fi
  post_build:
    commands:
      - |
        if grep -q service/ "/tmp/diff_results.txt" ; then
          echo "true" > service_changed.txt
        else 
          echo "false" > service_changed.txt
        fi
      - echo $PR_NUMBER > pr.txt
artifacts:
  files:
    - '**/*'
  s3-prefix: ${env_name}/${pipeline_type}
  discard-paths: no
  name: source_artifacts.zip