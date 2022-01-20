# code_build spec for pulling source from BitBucket
version: 0.2

phases:
  pre_build:
    commands:
      - yum install -y yum-utils
      - yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
      - yum -y install terraform consul
      - head=$(echo $CODEBUILD_WEBHOOK_HEAD_REF | sed 's/origin\///' | sed 's/refs\///' | sed 's/heads\///')
      - base=$(echo $CODEBUILD_WEBHOOK_BASE_REF | sed 's/origin\///' | sed 's/refs\///' | sed 's/heads\///')
      - git diff --name-only origin/$head origin/$base --raw > /tmp/diff_results.txt
      - PR_NUMBER="$(echo $CODEBUILD_WEBHOOK_TRIGGER | cut -d'/' -f2)"
      - USER=$(echo $(aws ssm get-parameter --name /app/bb_user --with-decryption) | python3 -c "import sys, json; print(json.load(sys.stdin)['Parameter']['Value'])")
      - PASS=$(echo $(aws ssm get-parameter --name /app/bb_pass --with-decryption) | python3 -c "import sys, json; print(json.load(sys.stdin)['Parameter']['Value'])")
      - export CONSUL_PROJECT_ID=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/consul_project_id" --with-decryption --query 'Parameter.Value' --output text)
      - export CONSUL_HTTP_TOKEN=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/consul_http_token" --with-decryption --query 'Parameter.Value' --output text)
      - export CONSUL_HTTP_ADDR=https://consul-cluster-test.consul.$CONSUL_PROJECT_ID.aws.hashicorp.cloud
      - export MONGODB_ATLAS_PROJECT_ID=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_project_id" --with-decryption --query 'Parameter.Value' --output text)
      - export MONGODB_ATLAS_PUBLIC_KEY=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_public_key" --with-decryption --query 'Parameter.Value' --output text)
      - export MONGODB_ATLAS_PRIVATE_KEY=$(aws ssm get-parameter --name "/infra/${app_name}-${env_type}/mongodb_atlas_private_key" --with-decryption --query 'Parameter.Value' --output text)
          
  build:
    commands:
      - |
        if [[ "${is_managed_env}" == "true" ]]; then
          tf_changed=$(grep terraform/app "/tmp/diff_results.txt")
          if [[ -z $tf_changed ]]; then
            TF_CHANGED="false"
          else 
            TF_CHANGED="true"
          fi
          NEXT_COLOR=$(consul kv get "infra/${app_name}-${env_name}/current_color")
          echo "did tf have changes $TF_CHANGED"
          if [[ "${pipeline_type}" == "ci" ]] || [[ "${is_managed_env}" == "true" && "$TF_CHANGED" == "true" ]]; then
            cd terraform/app
            terraform init
            CURRENT_COLOR=$(consul kv get "infra/${app_name}-${env_name}/current_color")
            if [[ $CURRENT_COLOR == "green" ]]; then
              terraform workspace select ${env_name}-blue || terraform workspace new ${env_name}-blue
              terraform init
              terraform plan -detailed-exitcode -out=.tf-plan
              terraform apply -auto-approve .tf-plan
              NEXT_COLOR="blue"
            else 
              terraform workspace select ${env_name}-green || terraform workspace new ${env_name}-green
              terraform init
              terraform plan -detailed-exitcode -out=.tf-plan
              terraform apply -auto-approve .tf-plan
              NEXT_COLOR="green"
            fi
          fi
        fi
      - consul kv put "infra/${app_name}-${env_name}/infra_changed" $TF_CHANGED
  post_build:
    commands:
      - |
        tests_changed=$(grep tests/ "/tmp/diff_results.txt")
        if [[ ! -z $tests_changed ]]; then
          aws s3 cp tests/postman s3://${app_name}-${env_type}-postman-tests/ --recursive
        fi
      - |
        src_changed=$(grep service/ "/tmp/diff_results.txt")
        if [[ -z $src_changed ]]; then
          echo "false" > src_changed.txt
        else 
          echo "true" > src_changed.txt
        fi
      - echo $PR_NUMBER > pr.txt
      - | 
        if [[ "${pipeline_type}" == "ci" ]]; then
          echo "true" > build.txt
        else
          echo "false" > build.txt
        fi
      - echo $NEXT_COLOR > color.txt
artifacts:
  files:
    - '**/*'
  discard-paths: no
  name: ${env_name}/source_artifacts.zip