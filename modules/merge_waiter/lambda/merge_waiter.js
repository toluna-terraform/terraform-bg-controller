const AWS = require('aws-sdk');
const ssm = new AWS.SSM({ apiVersion: '2014-11-06', region: 'us-east-1' });
const cd = new AWS.CodeDeploy({ apiVersion: '2014-10-06', region: 'us-east-1' });
const dynamodb = new AWS.DynamoDB.DocumentClient();
const https = require('https');
const { StepFunctions } = require("aws-sdk");

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
  const username = await getSSMParam('/app/bb_user', true);
  const password = await getSSMParam('/app/bb_app_pass', true);
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
    platform = deploy_details.deploymentInfo.computePlatform;
    if (platform === "ECS") {
      environment = deploy_details.deploymentInfo.applicationName.replace(`ecs-deploy-`, "");
      environment = environment.replace(`${process.env.APP_NAME}-`, "");
      environment = environment.replace("-green", "");
      environment = environment.replace("-blue", "");
      console.log(`::::::::${environment}`);
      const commit_id = await getSSMParam(`/infra/${process.env.APP_NAME}-${environment}/commit_id`, true);
      await setBitBucketStatus(username, password, commit_id);
      let merge_details = JSON.parse(`{"DeploymentId":\"${deploymentId}\","HookId":\"${hookId}\"}`);
      await setDeployDetails(`${process.env.APP_NAME}-${environment}`, merge_details);
    }
    if (platform === "Lambda") {
      deploymentType = "SAM";
      environment = deploy_details.deploymentInfo.applicationName.replace(`serverlessrepo-${process.env.APP_NAME}-`, '');
      environment = environment.replace(`lambda-deploy-${process.env.APP_NAME}-`, '');
      environment = environment.split('-')[0];
      let runningDeployments = await getRunningDeployments();
      total_deployments = await getFilteredDeployments(runningDeployments, deploy_details.deploymentInfo.applicationName);
      let merge_details = JSON.parse(`{"DeploymentId":\"${deploymentId}\","HookId":\"${hookId}\"}`);
      await setDeployDetails(`${process.env.APP_NAME}-${environment}`, merge_details);
      let deploy_details_status = await getDeployDetails(`${process.env.APP_NAME}-${environment}`);
      if (deploy_details_status?.Item?.Details == null) {
        merge_count = 0;
      } else {
        merge_count = deploy_details_status.Item.Details.length
      }
      let merge_call_count_params = merge_count;
      console.log(`Total deployments:::${total_deployments}`);
      console.log(`Total merge calls:::${merge_call_count_params}`);
      if (total_deployments <= parseInt(merge_call_count_params, 10)) {
        const commit_id = await getSSMParam(`/infra/${process.env.APP_NAME}-${environment}/commit_id`, true);
        await setBitBucketStatus(username, password, commit_id);
      }
    }
  }
};

function setBitBucketStatus(username, password, commit_id) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify({
      key: `${process.env.APP_NAME} IS READY FOR MERGE`,
      state: "SUCCESSFUL",
      description: "PR IS READY FOR MERGE",
      url: `https://bitbucket.org/${process.env.SOURCE_REPOSITORY}/commits/${commit_id}`
    });
    console.log(data);
    const uri = encodeURI(`/2.0/repositories/${process.env.SOURCE_REPOSITORY}/commit/${commit_id}/statuses/build/`);
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
      res.on('end', d => {
        resolve(d);
      });
    });

    req.on('error', error => {
      console.error(error);
      reject(`${error}`)
    });

    req.write(data);
    req.end();
  });
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

async function setDeployDetails(applicationName, details) {
  var db_params = {
    TableName: `MergeWaiter-${process.env.APP_NAME}-${process.env.ENV_TYPE}`,
    Key: { "APPLICATION": `${applicationName}` },
    UpdateExpression: "SET Details = list_append(if_not_exists(Details, :empty_list), :vals)",
    ExpressionAttributeValues: {
      ':vals': [{
        "DeploymentId": `${details.DeploymentId}`,
        "LifecycleEventHookExecutionId": `${details.HookId}`,
      }],
      ":empty_list": []
    }
  };
  try {
    const { Parameter } = await dynamodb.update(db_params).promise();
    return `${details} where set`;
  }
  catch (e) {
    console.error(e);
    return `${details} not set`;
  }
}

async function getDeployDetails(applicationName, defaultValue = null) {
  var db_params = {
    Key: {
      "APPLICATION": `${applicationName}`
    },
    ReturnConsumedCapacity: "TOTAL",
    TableName: `MergeWaiter-${process.env.APP_NAME}-${process.env.ENV_TYPE}`
  };
  try {
    const Parameter = await dynamodb.get(db_params).promise();
    return Parameter //JSON.parse({"Details":`${Parameter?.Item.Details}`,"Count": `${Parameter?.Item.Details.length}`});
  }
  catch (e) {
    console.error(e);
    return null;
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