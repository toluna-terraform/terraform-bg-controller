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
        is_Green=$(aws route53 list-resource-record-sets --hosted-zone-id ${hosted_zone_id} --query "ResourceRecordSets[?Name=='${env_name}.${domain}']" | jq '.[] |select(.SetIdentifier == "green" )')
        is_Blue=$(aws route53 list-resource-record-sets --hosted-zone-id ${hosted_zone_id} --query "ResourceRecordSets[?Name=='${env_name}.${domain}']" | jq '.[] |select(.SetIdentifier == "blue" )')
        if [ -z "$is_Green" ] && [ -z "$is_Blue" ]; then
          echo "Creating Green route"
          is_White=$(aws route53 list-resource-record-sets --hosted-zone-id ${hosted_zone_id} --query "ResourceRecordSets[?Name=='${env_name}.${domain}']" | jq '.[] |select(.SetIdentifier == "white" )')
          NEXT_COLOR="green"
          CURRENT_COLOR="white"
          NEXT_RECORD=$(aws elbv2 describe-load-balancers --names ${app_name}-${env_name}-green --query "LoadBalancers[0].DNSName" --output text )
          CURRENT_RECORD=$(echo $is_White | jq '.ResourceRecords[0].Value')
        else 
          echo "switching colors"
          green_weight=$(echo $is_Green | jq '.Weight')
          if [[ "$green_weight" == 100 ]];then
            NEXT_COLOR="blue"
            CURRENT_COLOR="green"
            NEXT_RECORD=$(aws elbv2 describe-load-balancers --names ${app_name}-${env_name}-blue --query "LoadBalancers[0].DNSName" --output text )
            CURRENT_RECORD=$(echo $is_Green | jq '.ResourceRecords[0].Value')
          else
            NEXT_COLOR="green"
            CURRENT_COLOR="blue"
            NEXT_RECORD=$(aws elbv2 describe-load-balancers --names ${app_name}-${env_name}V-green --query "LoadBalancers[0].DNSName" --output text )
            CURRENT_RECORD=$(echo $is_Blue | jq '.ResourceRecords[0].Value')
          fi
        fi
        aws route53 change-resource-record-sets --hosted-zone-id ${hosted_zone_id} --change-batch '{"Comment": "{'$CURRENT_COLOR': 0, '$NEXT_COLOR': 100 }",
          "Changes": [
            {
              "Action": "UPSERT",
              "ResourceRecordSet": {
              "Name": "${env_name}.${domain}",
                "Type": "CNAME",
                "TTL": 300,
                "Weight": 100,
                "SetIdentifier": "'"$NEXT_COLOR"'",
                "ResourceRecords": [{ "Value": "'"$NEXT_RECORD"'" }]
              }
            },
            {
              "Action": "UPSERT",
              "ResourceRecordSet": {
                "Name": "${env_name}.${domain}",
                "Type": "CNAME",
                "TTL": 300,
                "Weight": 0,
                "SetIdentifier": "'"$CURRENT_COLOR"'",
                "ResourceRecords": [{ "Value": '"$CURRENT_RECORD"' }]
              }
            }
          ]
        }'
        cd terraform/app
        terraform init
        if [[ "$CURRENT_COLOR" == "white" ]]; then
          terraform workspace select ${env_name}
        else
          terraform workspace select ${env_name}-$CURRENT_COLOR
        fi
        terraform init
        terraform destroy -auto-approve
        terraform workspace select ${env_name}-$NEXT_COLOR
        if [[ "$CURRENT_COLOR" == "white" ]]; then
          terraform workspace delete ${env_name}
        else
          terraform workspace delete ${env_name}-$CURRENT_COLOR
        fi
        cd ../shared
        terraform init
        terraform workspace select shared-${env_type}
        terraform init
        terraform plan -detailed-exitcode -out=.tf-plan
        terraform apply -auto-approve .tf-plan
        
      
        
        