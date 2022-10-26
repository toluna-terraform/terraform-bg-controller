const AWS = require('aws-sdk');
const ssm = new AWS.SSM({ apiVersion: '2014-11-06', region: 'us-east-1' });
const cd = new AWS.CodeDeploy({ apiVersion: '2014-10-06', region: 'us-east-1' });
const https = require('https');

let environment;
let deploymentType;
let deploymentId;
let hookId;
let total_deployments;
let merge_count;

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
        let platform = deploy_details.deploymentInfo.computePlatform;
        if (platform === "ECS") {
            environment = deploy_details.deploymentInfo.applicationName.replace("ecs-deploy-", "");
            environment = environment.replace("-green", "");
            environment = environment.replace("-blue", "");
            console.log(`::::::::${environment}`);
            setBitBucketStatus();
            setSSMParam(`/infra/${process.env.APP_NAME}-${environment}/deployment_id`, `${deploymentId}`, 'String', true);
            setSSMParam(`/infra/${process.env.APP_NAME}-${environment}/hook_execution_id`, `${hookId}`, 'String', true);
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
            if (total_deployments == parseInt(merge_call_count_params, 10)) {
                setBitBucketStatus();
                await setSSMParam(`/infra/${process.env.APP_NAME}-${environment}/merge_call_count_params`, '0', 'String', true);
            }
        }
    }
};

async function setBitBucketStatus() {
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
    console.log(data);
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
}

async function getRunningDeployments() {
    console.log(`Checking for running deployments`);
    var params = {
        includeOnlyStatuses: [
            'InProgress'
        ]
    };
    try {
        const { Parameter } = await cd.listDeployments(params).promise();
        console.log(`DeploymentList:::::${Parameter?.deplyoments}`);
        return Parameter?.deplyoments ?? null;
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
        const { Parameter } = await cd.batchGetDeployments(params).promise();
        let count_deployments = 0;
        Parameter?.deploymentsInfo.forEach(function (deployment) {
            if (deployment.applicationName == applicationName) {
                count_deployments++;
            }
        });
        total_deployments = count_deployments;
        console.log(`Found matching deployments:::${count_deployments}`)
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
        console.error(e)
        return `${key} not set`;
    }
}

async function getSSMParam(key, withDecryption, defaultValue = null) {
    var params = {
        Name: `${key}`,
        WithDecryption: withDecryption
    };
    console.log(`defaultValue:::::${defaultValue}`)
    try {
        const { Parameter } = await ssm.getParameter(params).promise();
        console.log(`Value:::::${Parameter?.Value}`)
        return Parameter?.Value ?? defaultValue
    } catch (e) {
        console.error(e)
        return defaultValue
    }
}