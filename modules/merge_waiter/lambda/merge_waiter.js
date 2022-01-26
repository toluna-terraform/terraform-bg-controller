const AWS = require('aws-sdk');
const ssm = new AWS.SSM({apiVersion: '2014-11-06', region: 'us-east-1' });
const cd = new AWS.CodeDeploy({ apiVersion: '2014-10-06', region: 'us-east-1' });

exports.handler = async function (event, context, callback) {
  console.log('event', event);
  const deploymentId = event.DeploymentId;
  const hookId = event.LifecycleEventHookExecutionId
  var params = {
    deploymentId: deploymentId /* required */
  };
  let env_name = await cd.getDeployment(params, function(err, data) {
    if (err) 
      { 
        console.log(err, err.stack); // an error occurred
      }
      else {
        console.log(data);
      }// successful response
      }).promise();
  const environment = env_name.deploymentInfo.applicationName.split("-")[2];
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
};



