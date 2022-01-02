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
        if [[ "$${MY_COLOR}" == "green" ]]; then
        NEXT_COLOR="blue"
        else
        NEXT_COLOR="green"
        fi
        currentState=$(aws route53 list-resource-record-sets --hosted-zone-id ${hosted_zone_id} --query "ResourceRecordSets[?Name=='${domain}']" | jq '.[] |select(.SetIdentifier == "$MY_COLOR" ) | .Weight|="0"')
        currentState=$(echo $currentState | jq '.[] |select(.SetIdentifier == "$NEXT_COLOR" ) | .Weight|="100"')
        greenRecordSet="$(echo $currentState | jq '. |select(.SetIdentifier == \"green\" )')"
        blueRecordSet="$(echo $currentState | jq '. |select(.SetIdentifier == \"blue\" )')"
        aws route53 change-resource-record-sets --hosted-zone-id ${hosted_zone_id} --change-batch '{"Comment":"{$MY_COLOR 0, $NEXT_COLOR 100}","Changes":[{"Action":"UPSERT","ResourceRecordSet":$greenRecordSet},{"Action":"UPSERT","ResourceRecordSet":$blueRecordSet}]}'
        terraform workspace select ${env_name}
        terraform destroy -auto-approve
        terraform workspace select default
        terraform workspace delete -force ${env_name}

        
        