const AWS = require('aws-sdk');
const ssm = new AWS.SSM({ apiVersion: '2014-11-06', region: 'us-east-1' });
const cd = new AWS.CodeDeploy({ apiVersion: '2014-10-06', region: 'us-east-1' });
const https = require('https');


let environment;
let env_name;
let env_color;
let deploymentType;
let deploymentId;
let hookId;

exports.handler = async function (event, context, callback) {
    console.log('event', event);
    if (event.DeploymentId) {
        deploymentId = event.DeploymentId;
        hookId = event.LifecycleEventHookExecutionId
        var params = {
            deploymentId: deploymentId /* required */
        };
        let ecs_env_name = await cd.getDeployment(params, function (err, data) {
            if (err) {
                console.log(err, err.stack); // an error occurred
            }
            else {
                console.log(data);
            }// successful response
        }).promise();
        let platform = ecs_env_name.deploymentInfo.computePlatform;
        if (platform === "ECS") {
            environment = ecs_env_name.deploymentInfo.applicationName.replace("ecs-deploy-", "");
            environment = environment.replace("-green", "");
            environment = environment.replace("-blue", "");
            console.log(`::::::::${environment}`);
        }
        if (platform === "Lambda") {
            deploymentType = "SAM"
            environment = ecs_env_name.deploymentInfo.applicationName.split('-')[2];
        }
    };
    var bb_user = {
        Name: '/app/bb_user',
        WithDecryption: true
    };
    var bb_app_pass = {
        Name: '/app/bb_app_pass',
        WithDecryption: true
    };
    
    var commit = {
        Name: `/infra/${process.env.APP_NAME}-${environment}/commit_id`,
        WithDecryption: true
    };
    
    const username = await ssm.getParameter(bb_user).promise();
    const password = await ssm.getParameter(bb_app_pass).promise();
    const commid_id = await ssm.getParameter(commit).promise();
    const data = JSON.stringify({
        key: `${process.env.APP_NAME} IS READY FOR MERGE`,
        state: "SUCCESSFUL",
        description: "PR IS READY FOR MERGE",
        url: `https://bitbucket.org/tolunaengineering/${process.env.APP_NAME}/commits/${commid_id["Parameter"]["Value"]}`
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
    });
    
    req.write(data);
    req.end();
    var deployment_params = {
        Name: `/infra/${process.env.APP_NAME}-${environment}/deployment_id`,
        Value: `${deploymentId}`,
        Overwrite: true,
        Type: 'String'
    };
    var hook_params = {
        Name: `/infra/${process.env.APP_NAME}-${environment}/hook_execution_id`,
        Value: `${hookId}`,
        Overwrite: true,
        Type: 'String'
    };
    await ssm.putParameter(deployment_params).promise();
    await ssm.putParameter(hook_params).promise();
};



