const AWS = require('aws-sdk');
const ssm = new AWS.SSM({ apiVersion: '2014-11-06', region: 'us-east-1' });
const cd = new AWS.CodeDeploy({ apiVersion: '2014-10-06', region: 'us-east-1' });
const https = require('https');
const {StepFunctions} = require( "aws-sdk");

const region = "us-east-1"
const sf = new StepFunctions({
  region
});


let environment;
let deploymentType;
let deploymentId;
let hookId;
let total_deployments;
let merge_count;
let taskToken1;
let platform;

exports.handler = async function (event, context, callback) {
  console.log('event', event);
  if (event.DeploymentId) {
    deploymentId = event.DeploymentId;
    hookId = event.LifecycleEventHookExecutionId;
    var params = {
      deploymentId: deploymentId /* required */
    };
    let deploy_details = await cd.getDeployment(params, function (err, data) {
      if (err) {
        console.log(err, err.stack); // an error occurred
      }
      else {
        console.log(data);
      }// successful response
    }).promise();
    if (event.DeploymentType == "AppMesh") {
      environment = event.environment;
      platform = "AppMesh"
      console.log("environment = " + environment);
    }
    else {
      platform = deploy_details.deploymentInfo.computePlatform;
    }
    if (platform === "ECS") {
      environment = deploy_details.deploymentInfo.applicationName.replace("ecs-deploy-", "");
      environment = environment.replace("-green", "");
      environment = environment.replace("-blue", "");
      console.log(`::::::::${environment}`);
      await setBitBucketStatus();
      await setSSMParam(`/infra/${process.env.APP_NAME}-${environment}/deployment_id`, `${deploymentId}`, 'String', true);
      await setSSMParam(`/infra/${process.env.APP_NAME}-${environment}/hook_execution_id`, `${hookId}`, 'String', true);
    }
    if (platform === "Lambda") {
      deploymentType = "SAM";
      environment = deploy_details.deploymentInfo.applicationName.split('-')[2];
      let merge_call_count_params = await getSSMParam(`/infra/${process.env.APP_NAME}-${environment}/merge_call_count_params`, true, '0');
      merge_count = parseInt(merge_call_count_params, 10);
      merge_count++;
      await setSSMParam(`/infra/${process.env.APP_NAME}-${environment}/merge_call_count_params`, merge_count, 'String', true);
      merge_call_count_params = merge_count;
      let runningDeployments = await getRunningDeployments();
      total_deployments = await getFilteredDeployments(runningDeployments, deploy_details.deploymentInfo.applicationName);
      let merge_details = await getSSMParam(`/infra/${process.env.APP_NAME}-${environment}/merge_details`, true, '[]');
      if (merge_details == '[]') {
        merge_details = `[{"DeploymentId":\"${deploymentId}\","HookId":\"${hookId}\"}]`;
        await setSSMParam(`/infra/${process.env.APP_NAME}-${environment}/merge_details`, merge_details, 'String', true);
      } else {
        let current_value = merge_details;
        let current_json = JSON.parse(current_value);
        let new_value = JSON.parse(`{"DeploymentId":\"${deploymentId}\","HookId":\"${hookId}\"}`);
        current_json.push(new_value);
        let new_merge_details = JSON.stringify(current_json);
        await setSSMParam(`/infra/${process.env.APP_NAME}-${environment}/merge_details`, new_merge_details, 'String', true);
      }
      console.log(`Total deployments:::${total_deployments}`);
      console.log(`Total merge calls:::${merge_call_count_params}`);
      if (total_deployments <= parseInt(merge_call_count_params, 10)) {
        await setBitBucketStatus();
        await setSSMParam(`/infra/${process.env.APP_NAME}-${environment}/merge_call_count_params`, '0', 'String', true);
      }
    }
    if (platform === "AppMesh") {
      taskToken1 = event.taskToken;
      await setSSMParam(`/infra/${process.env.APP_NAME}-${environment}/hook_execution_id`, hookId, 'String', true);
      await setSSMParam(`/infra/${process.env.APP_NAME}-${environment}/deployment_id`, deploymentId, 'String', true);
      await setBitBucketStatus();
      console.log("taskToken = " + taskToken1);
      let params = {
        taskToken: taskToken1,
        output: JSON.stringify({ "StatusCode": "200" })
      };
      await sf.sendTaskSuccess(params).promise();
      console.log("calledbck SF with taskToken = " + taskToken1);
    }
  }
};

async function setBitBucketStatus() {

  const username = await getSSMParam('/app/bb_user', true);
  const password = await getSSMParam('/app/bb_app_pass', true);
  const commid_id = await getSSMParam(`/infra/${process.env.APP_NAME}-${environment}/commit_id`, true);
  const data = JSON.stringify({
    key: `${process.env.APP_NAME} IS READY FOR MERGE`,
    state: "SUCCESSFUL",
    description: "PR IS READY FOR MERGE",
    url: `https://bitbucket.org/tolunaengineering/${process.env.APP_NAME}/commits/${commid_id}`
  });
  console.log(data);
  const uri = encodeURI(`/2.0/repositories/tolunaengineering/${process.env.APP_NAME}/commit/${commid_id}/statuses/build/`);
  const auth = "Basic " + Buffer.from(username + ":" + password).toString("base64");
  const options = {
    hostname: 'api.bitbucket.org',
    port: 443,
    path: uri,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': data.length,
      'Authorization': auth
    },
  };

  const req = https.request(options, res => {
    console.log(`statusCode: ${res.statusCode}`);
    res.on('data', d => {
      process.stdout.write(d);
    });
  });

  req.on('error', error => {
    console.error(error);
    return `${error}`
  });

  req.write(data);
  req.end();
  return "Done setting Bitbucket Status"
}

async function getRunningDeployments() {
  console.log(`Checking for running deployments`);
  var params = {
    includeOnlyStatuses: [
      'InProgress'
    ]
  };
  try {
    const deplyoments = await cd.listDeployments(params, function (err, data) {
      if (err) console.log(err, err.stack); // an error occurred
      else return data.deployments;     // successful response
    }).promise();
    console.log(`DeploymentList:::::${deplyoments.deployments}`);
    return deplyoments.deployments ?? null;
  } catch (e) {
    console.error(e);
    return null;
  }
}

async function getFilteredDeployments(runningDeployments, applicationName) {
  console.log(`Filtering thru deployments::::${runningDeployments}`);
  var params = {
    deploymentIds: runningDeployments
  };
  try {
    const deploymentsInfo = await cd.batchGetDeployments(params, function (err, data) {
      if (err) console.log(err, err.stack); // an error occurred
      else return data.deploymentsInfo;     // successful response
    }).promise();
    let count_deployments = 0;
    deploymentsInfo.deploymentsInfo.forEach(function (deployment) {
      if (deployment.applicationName == applicationName) {
        count_deployments++;
      }
    });
    console.log(`Found matching deployments:::${count_deployments}`);
    return count_deployments;
  } catch (e) {
    console.error(e);
    return null;
  }
}

async function setSSMParam(key, value, type, overwrite) {
  var params = {
    Name: `${key}`,
    Value: `${value}`,
    Overwrite: overwrite,
    Type: `${type}`
  };
  try {
    const { Parameter } = await ssm.putParameter(params).promise();
    return `${key} was set`;
  }
  catch (e) {
    console.error(e);
    return `${key} not set`;
  }
}

async function getSSMParam(key, withDecryption, defaultValue = null) {
  var params = {
    Name: `${key}`,
    WithDecryption: withDecryption
  };
  try {
    const { Parameter } = await ssm.getParameter(params).promise();
    return Parameter?.Value ?? defaultValue;
  } catch (e) {
    console.error(e);
    return defaultValue;
  }
}