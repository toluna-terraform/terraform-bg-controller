# code_build spec for pulling source from BitBucket
version: 0.2

env:
  parameter-store:
    BB_USER: "/app/bb_user"  
    BB_PASS: "/app/bb_app_pass"
    CONSUL_URL: "/infra/consul_url"
    CONSUL_HTTP_TOKEN: "/infra/${app_name}-${env_type}/consul_http_token"
  
phases:
  pre_build:
    commands:
      - yum install -y yum-utils
      - yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
      - yum -y install terraform consul
      - aws s3api delete-object --bucket s3-codepipeline-${app_name}-${env_type} --key ${env_name}/source_artifacts.zip
      - aws s3api delete-object --bucket s3-codepipeline-${app_name}-${env_type} --key ${env_name}-green/source_artifacts.zip
      - aws s3api delete-object --bucket s3-codepipeline-${app_name}-${env_type} --key ${env_name}-blue/source_artifacts.zip
      - head=$(echo $CODEBUILD_WEBHOOK_HEAD_REF | sed 's/origin\///' | sed 's/refs\///' | sed 's/heads\///')
      - base=$(echo $CODEBUILD_WEBHOOK_BASE_REF | sed 's/origin\///' | sed 's/refs\///' | sed 's/heads\///')
      - aws dynamodb delete-item --table-name MergeWaiter-${app_name}-${env_type} --key '{"APPLICATION" :{"S":"${app_name}-${env_name}"}}' || echo "not found"
      - |
        if [[ "${pipeline_type}" != "dev" ]]; then
          export PR_NUMBER="$(echo $CODEBUILD_WEBHOOK_TRIGGER | cut -d'/' -f2)"
        else
          export PR_NUMBER=$CODEBUILD_WEBHOOK_HEAD_REF
        fi
        if [[ "${pipeline_type}" != "dev" ]]; then
          curl -u $BB_USER:$BB_PASS -L "https://api.bitbucket.org/2.0/repositories/tolunaengineering/${app_name}/pullrequests/$PR_NUMBER/diffstat" | jq -r '.values[].old.path, .values[].new.path' > /tmp/diff_results.txt
        fi
      - printf "%s\n%s\nus-east-1\njson" | aws configure --profile ${aws_profile}
      - export CONSUL_HTTP_ADDR=https://$CONSUL_URL
      - export MONGODB_ATLAS_PROJECT_ID=$(aws ssm get-parameters --with-decryption --names /infra/${app_name}-${env_type}/mongodb_atlas_project_id --query 'Parameters[].Value' --output text)
      - export MONGODB_ATLAS_PUBLIC_KEY=$(aws ssm get-parameters --with-decryption --names /infra/${app_name}-${env_type}/mongodb_atlas_public_key --query 'Parameters[].Value' --output text)
      - export MONGODB_ATLAS_PRIVATE_KEY=$(aws ssm get-parameters --with-decryption --names /infra/${app_name}-${env_type}/mongodb_atlas_private_key --query 'Parameters[].Value' --output text)
      - export MONGODB_ATLAS_ORG_ID=$(aws ssm get-parameters --with-decryption --names /infra/${app_name}-${env_type}/mongodb_atlas_org_id --query 'Parameters[].Value' --output text)
      - export CURRENT_COLOR=$(consul kv get "infra/${app_name}-${env_name}/current_color")
      - |
        if [[ $CURRENT_COLOR == "green" ]] || [[ $CURRENT_COLOR == "blue" ]]; then
          export inprogress=($(aws codepipeline list-action-executions --pipeline-name codepipeline-${app_name}-${env_name}-$CURRENT_COLOR --query 'actionExecutionDetails[?status==`InProgress`].status' --output text))
        else
          export inprogress=($(aws codepipeline list-action-executions --pipeline-name codepipeline-${app_name}-${env_name} --query 'actionExecutionDetails[?status==`InProgress`].status' --output text))
        fi
        if [[ "${pipeline_type}" != "dev" ]]; then
        echo "checking for running deployments"
          if [ "$${#inprogress[@]}" -gt 0 ]; then
            COMMENT_URL="https://api.bitbucket.org/2.0/repositories/tolunaengineering/${app_name}/pullrequests/$PR_NUMBER/comments"
            curl --request POST --url $COMMENT_URL--header "Content-Type:application/json" --data "{\"content\":{\"raw\":\"There is already a pull request open for this branch, only one deployment and pr per branch at a time are allowed\"}}" -u $BB_USER:$BB_PASS
            DECLINE_URL="https://api.bitbucket.org/2.0/repositories/tolunaengineering/${app_name}/pullrequests/$PR_NUMBER/decline"
            curl -X POST $DECLINE_URL --data-raw '' -u $BB_USER:$BB_PASS
            aws codebuild stop-build --id $CODEBUILD_BUILD_ID
          fi
        fi
      - |
        if [[ "${pipeline_type}" != "dev" ]]; then
          echo "checking if sync is needed"
          git config --global user.email "$BB_USER"
          git config --global user.name "$BB_USER"
          base_url=$(git config --get remote.origin.url)
          bb_url=$(echo $base_url | sed 's/https:\/\//https:\/\/'$BB_USER':'$BB_PASS'@/')
          git remote set-url origin $bb_url.git
          git checkout $head
          COMMITS_BEHIND=$(git rev-list --left-only --count origin/$base...origin/$head)
          if [[ $COMMITS_BEHIND -gt 0 ]]; then
            echo "The PR is $COMMITS_BEHIND commints behind,Codebuild will now stop and restart from synced branch."
            git merge origin/$base -m "Auto Sync done by AWS codebuild."| grep "Already up to date." &> /dev/null || echo "true"
            git push --set-upstream origin $head
            aws codebuild stop-build --id $CODEBUILD_BUILD_ID
          fi
        fi
      - |
        tests_changed=$(grep -q "tests/" /tmp/diff_results.txt >/dev/null;echo $?)
        if [[ "$tests_changed" -eq 0 ]]; then
          if [ -d "tests/postman" ]; then
            aws s3 cp tests/postman s3://${app_name}-${env_type}-tests/integration_tests --recursive
          fi
          if [ -d "tests/stress_tests" ]; then
            aws s3 cp tests/stress_tests s3://${app_name}-${env_type}-tests/stress-tests --recursive
          fi
        fi
  build:
    on-failure: ABORT
    commands:
      - artifact_prefix="${env_name}"
      - |
        if [[ "${is_managed_env}" == "true" ]]; then
          echo "the following files changed for PR: $${PR_NUMBER}"
          cat /tmp/diff_results.txt
          tf_change_status=$(grep -q "terraform/app" /tmp/diff_results.txt >/dev/null;echo $?)
          if [[ "$tf_change_status" -eq 1 ]]; then
            TF_CHANGED="false"
          else 
            TF_CHANGED="true"
          fi
          consul kv get "infra/${app_name}-${env_name}/current_color" || consul kv put "infra/${app_name}-${env_name}/current_color" blue
          if [[ $(consul kv get "infra/${app_name}-${env_name}/current_color") == "blue" ]]; then
            CURRENT_COLOR="blue"
            NEXT_COLOR="green"
          else
            NEXT_COLOR="blue"
            CURRENT_COLOR="green"
          fi
          artifact_prefix="${env_name}-$CURRENT_COLOR"
          echo "did tf have changes $${TF_CHANGED}"
          if [[ "${is_managed_env}" == "true" ]] && [[ $TF_CHANGED == "true" ]]; then
            cd terraform/app
            terraform init
            COMMENT_URL="https://api.bitbucket.org/2.0/repositories/tolunaengineering/${app_name}/pullrequests/$PR_NUMBER/comments"
            curl --request POST --url $COMMENT_URL --header "Content-Type:application/json" --data "{\"content\":{\"raw\":\"Started infrastructure deployment, creating ${app_name}-$NEXT_COLOR is done.\"}}" -u $BB_USER:$BB_PASS
            terraform workspace select ${env_name}-$NEXT_COLOR || terraform workspace new ${env_name}-$NEXT_COLOR
            terraform init
            terraform apply -auto-approve || exit 1
            cd -
            COMMENT_URL="https://api.bitbucket.org/2.0/repositories/tolunaengineering/${app_name}/pullrequests/$PR_NUMBER/comments"
            curl --request POST --url $COMMENT_URL --header "Content-Type:application/json" --data "{\"content\":{\"raw\":\"Finished the infrastructure deployment, creation of ${app_name}-$${NEXT_COLOR} is done.\"}}" -u $BB_USER:$BB_PASS
          fi
        fi
      - |
        if [[ "${pipeline_type}" != "dev" ]]; then
          consul kv put "infra/${app_name}-${env_name}/infra_changed" $TF_CHANGED
        fi
      
  post_build:
    on-failure: ABORT
    commands:
      - |
        echo "Cleaning up .terraform folders to reduce Artifact size"
        rm -rf terraform/*/.terraform
      - |
        src_changed=$(grep -v -E 'terraform|tests' /tmp/diff_results.txt >/dev/null;echo $?)
        if [[ "$src_changed" -eq 1 ]] && [[ "${pipeline_type}" != "dev" ]]; then
          echo "false" > src_changed.txt
        else 
          echo "true" > src_changed.txt
        fi
      - echo $PR_NUMBER > pr.txt
      - | 
        if [[ "${pipeline_type}" == "ci" ]] || [[ "${pipeline_type}" == "dev" ]]; then
          echo "true" > ci.txt
        else
          echo "false" > ci.txt
        fi
      - echo $NEXT_COLOR > color.txt
      - echo $head > head.txt
      - |
        COMMIT_ID=$${CODEBUILD_RESOLVED_SOURCE_VERSION:0:7}
        consul kv put "infra/${app_name}-${env_name}/commit_id" $COMMIT_ID
        echo $COMMIT_ID > commit_id.txt
        aws ssm put-parameter --name "/infra/${app_name}-${env_name}/commit_id" --type "String" --value $COMMIT_ID --overwrite
artifacts:
  files:
    - '**/*'
  discard-paths: no
  name: $artifact_prefix/source_artifacts.zip
