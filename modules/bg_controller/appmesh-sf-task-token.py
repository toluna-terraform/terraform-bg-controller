import json
import boto3
import os

appName = os.getenv('APP_NAME')
envName = os.getenv('ENV_NAME')

# ---- receive message from SF
def lambda_handler(event, context):
  ssm_client = boto3.client ("ssm")
 
  # this means CodeBuild called this to return to SF wtih taskToken
  if ( event["CallerId"] != "CodeBuild"):
    taskToken = ssm_client.put_parameter(
			Name = "/infra/{app}-{env_name}/task_token".format( app = appName, env_name = envName),
			Value = event["TaskToken"],
			Type='String',
			Overwrite = True
		)
    # put parameter for DeploymentType
    taskToken = ssm_client.put_parameter(
			Name = "/infra/{app}-{env_name}/deployment_type".format( app = appName, env_name = envName),
			Value = "AppMesh",
			Type='String',
			Overwrite = True
		)
  # this means CodeBuild called this to return to SF wtih taskToken
  else:
    taskTokenMsg = ssm_client.get_parameter(
			Name = "/infra/{app}-{env_name}/task_token".format( app = appName, env_name = envName),
		)
    taskToken = taskTokenMsg["Parameter"]["Value"]
    print ("taskToken = " + taskToken )

    # --- callback SF step
    sfClient = boto3.client( "stepfunctions" )
    sfCallbackResponse = sfClient.send_task_success(
			taskToken = taskToken,
			output  = '{ "StatusCode": "200", "Message" : "merge completed in CodeBuild" }'
	  )
    print ("SF call back response = ", sfCallbackResponse)