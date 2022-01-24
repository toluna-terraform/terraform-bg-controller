# code_build spec for pulling source from BitBucket
version: 0.2

env:
  parameter-store:
    USER: "/app/bb_user"  
    PASS: "/app/bb_app_pass"
    CONSUL_PROJECT_ID: "/infra/${app_name}-${env_type}/consul_project_id"
    CONSUL_HTTP_TOKEN: "/infra/${app_name}-${env_type}/consul_http_token"
    MONGODB_ATLAS_PROJECT_ID: "/infra/${app_name}-${env_type}/mongodb_atlas_project_id"
    MONGODB_ATLAS_PROJECT_ID: "/infra/${app_name}-${env_type}/mongodb_atlas_public_key"
    MONGODB_ATLAS_PROJECT_ID: "/infra/${app_name}-${env_type}/mongodb_atlas_private_key"
  
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
      - export CONSUL_HTTP_ADDR=https://consul-cluster-test.consul.$CONSUL_PROJECT_ID.aws.hashicorp.cloud
      - |
        echo "checking if sync is needed"
        git config --global user.email "$USER"
        git config --global user.name "$USER"
        base_url=$(git config --get remote.origin.url)
        bb_url=$(echo $base_url | sed 's/https:\/\//https:\/\/'$USER':'$PASS'@/')
        git remote set-url origin $bb_url.git
        git checkout $head
        git merge origin/$base -m "Auto Sync done by AWS codebuild."| grep "Already up to date." &> /dev/null && SYNC_NEEDED="false" || SYNC_NEEDED="true"
        if [[ $SYNC_NEEDED == "true" ]]; then
          git push --set-upstream origin $head
          echo "Codebuild will now stop and restart from synced branch."
          aws codebuild stop-build --id $CODEBUILD_BUILD_ID
        fi
      - |
        tests_changed=$(grep tests/ "/tmp/diff_results.txt")
        if [[ ! -z $tests_changed ]]; then
          aws s3 cp tests/postman s3://${app_name}-${env_type}-postman-tests/ --recursive
        fi  
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
      - echo $head > head.txt
      - |
        COMMIT_ID=$(git rev-parse --short origin/$head)
        consul kv put "infra/${app_name}-${env_name}/commit_id" $COMMIT_ID

artifacts:
  files:
    - '**/*'
  discard-paths: no
  name: ${env_name}/source_artifacts.zip