const AWS = require('aws-sdk');
const ssm = new AWS.SSM({apiVersion: '2014-11-06', region: 'us-east-1' });
const cd = new AWS.CodeDeploy({ apiVersion: '2014-10-06', region: 'us-east-1' });
const https = require('https');
const {StepFunctions} = require( "aws-sdk");

const region = "us-east-1"
const sf = new StepFunctions({
  region
});


let environment;
let taskToken1;

exports.handler = async function (event, context, callback) {
  console.log('event', event);
  const deploymentId = event.DeploymentId;
  const hookId = event.LifecycleEventHookExecutionId
  var params = {
    deploymentId: deploymentId /* required */
  };

  // if DeploymentType is "AppMesh" (not CodeDeploy or SAM) the environment info is part of event
  // otherwise derive environment info from DeploymentId
  console.log ("DeploymentType = " + event.DeploymentType);
  if (event.DeploymentType == "AppMesh") {
    environment = event.environment;
    console.log("environment = " + environment);
  }
  else 
  {
    let env_name = await cd.getDeployment(params, function(err, data) {
      if (err) 
        { 
          console.log(err, err.stack); // an error occurred
        }
      else {
          console.log(data);
        }// successful response
    }).promise();
  
    // getting envrionment from env_name
    // eg: get chef from ecs-deploy-chef-blue
    if (env_name.deploymentInfo.deploymentConfigName.includes('CodeDeployDefault.ECS')){
      environment = env_name.deploymentInfo.applicationName.replace("ecs-deploy-", "");
      environment = environment.replace("-green", "");
      environment = environment.replace("-blue", "");
    };
  
    if (env_name.deploymentInfo.deploymentConfigName.includes('CodeDeployDefault.Lambda')){
      environment = env_name.deploymentInfo.applicationName.split("-")[1];
    };
    
  }

  var bb_user = {
    Name: '/app/bb_user', 
    WithDecryption: true
  };
  var bb_app_pass = {
    Name: '/app/bb_app_pass', 
    WithDecryption: true
  };

  // latest commit_id of app+env name from SSM parameter
  var commit = {
    Name: `/infra/${process.env.APP_NAME}-${environment}/commit_id`, 
    WithDecryption: true
  };

  const  username = await ssm.getParameter(bb_user).promise();
  const  password = await ssm.getParameter(bb_app_pass).promise();
  const commid_id =  await ssm.getParameter(commit).promise(); 
  const data = JSON.stringify({
    key:`${process.env.APP_NAME} IS READY FOR MERGE`,
    state:"SUCCESSFUL",
    description:"PR IS READY FOR MERGE",
    url:`https://bitbucket.org/tolunaengineering/${process.env.APP_NAME}/commits/${commid_id["Parameter"]["Value"]}`
  });

  console.log(data)
  const uri = encodeURI(`/2.0/repositories/tolunaengineering/${process.env.APP_NAME}/commit/${commid_id["Parameter"]["Value"]}/statuses/build/`); 
  const auth = "Basic " + Buffer.from(username["Parameter"]["Value"] + ":" + password["Parameter"]["Value"]).toString("base64");
  const options = {
    hostname: 'api.bitbucket.org',
    port: 443,
    path: uri,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': data.length,
      'Authorization' : auth
    },
  };

  // http request for the PR merge info
  console.log("PR merge info. options = " + options);
  const resp = https.request(options, res => {
    console.log(`statusCode: ${res.statusCode}`);
    res.on('data', d => {
      process.stdout.write(d);
    });
  });
  console.log("http response = " + JSON.stringify(resp) );

  req.on('error', error => {
    console.error(error);
  });

  resp.write(data);
  resp.end();

  // Update SSM parameters only if DeploymentType is NOT "AppMesh"
  if ( event.DeploymentType != "AppMesh") {
    var deployment_params = {
      Name: `/infra/${process.env.APP_NAME}-${environment}/deployment_id`,
      Value: `${deploymentId}`, 
      Overwrite: true ,
      Type: 'String'
    };
    var hook_params = {
      Name: `/infra/${process.env.APP_NAME}-${environment}/hook_execution_id`,
      Value: `${hookId}`, 
      Overwrite: true ,
      Type: 'String'
    };
    await ssm.putParameter(deployment_params).promise();
    await ssm.putParameter(hook_params).promise();
  }

  // if DeploymentType == AppMesh, call SF with taskToken to update status
  if (event.DeploymentType == "AppMesh") {
    taskToken1 = event.taskToken;
    console.log("taskToken = " + taskToken1);
    let params = {
      taskToken: taskToken1,
      output : JSON.stringify( {"output" : "success hard coded from wait_merge"} )
    };
    await sf.sendTaskSuccess(params).promise();
    console.log("calledbck SF with taskToken = " + taskToken1);
  }

};



