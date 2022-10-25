const AWS = require('aws-sdk');
const ssm = new AWS.SSM({ apiVersion: '2014-11-06', region: 'us-east-1' });
const cd = new AWS.CodeDeploy({ apiVersion: '2014-10-06', region: 'us-east-1' });
const https = require('https');


let environment;
let env_name;
let deploymentType;
let deploymentId;
let hookId;
let total_deployments;
let ready_for_merge_count;

exports.handler = async function (event, context, callback) {
    console.log('event', event);
    if (event.DeploymentId) {
        deploymentId = event.DeploymentId;
        hookId = event.LifecycleEventHookExecutionId
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
        }
        if (platform === "Lambda") {
            deploymentType = "SAM"
            environment = deploy_details.deploymentInfo.applicationName.split('-')[2];
            var params = {
                includeOnlyStatuses: [
                    'InProgress'
                ]
            };
            let listDeployments = await cd.listDeployments(params, function (err, data) {
                if (err) {
                    console.log(err, err.stack);
                }// an error occurred
                else {
                    let deployments_count = Object.keys(data.deployments).length;
                    console.log(`SAM Running Deployment Ids ${deployments_count}, ${data.deployments}`);
                    var params = {
                        deploymentIds: data.deployments
                    };
                    let listFiltesredDeployments = cd.batchGetDeployments(params, function (err, data) {
                        if (err) {
                            console.log(err, err.stack); // an error occurred
                        }
                        else {
                            let count_deployments = 0
                            data.deploymentsInfo.forEach(function (deployment) {
                                if (deployment.applicationName == deploy_details.deploymentInfo.applicationName) {
                                    count_deployments++;


                                }
                            })
                            total_deployments = count_deployments;
                            console.log(`FILTERED::::count=${total_deployments}`);
                            var total_stack_functions_params = {
                                Name: `/infra/${process.env.APP_NAME}-${environment}/total_stack_functions_params`,
                                Value: `${total_deployments}`,
                                Overwrite: true,
                                Type: 'String'
                            };
                            ssm.putParameter(total_stack_functions_params).promise()
                        }
                    }).promise()



                    var merge_call_count_params = {
                        Name: `/infra/${process.env.APP_NAME}-${environment}/merge_call_count_params`,
                        WithDecryption: true
                    };

                    ssm.getParameter(merge_call_count_params, function (err, data) {
                        if (err) {
                            var update_params = {
                                Name: `/infra/${process.env.APP_NAME}-${environment}/merge_call_count_params`,
                                Value: `1`,
                                Overwrite: true,
                                Type: 'String'
                            };
                            ssm.putParameter(update_params).promise()
                        }
                        else {
                            let current_call = parseInt(data.Parameter.Value);
                            current_call++;
                            ready_for_merge_count = current_call;
                            var update_params = {
                                Name: `/infra/${process.env.APP_NAME}-${environment}/merge_call_count_params`,
                                Value: `${current_call}`,
                                Overwrite: true,
                                Type: 'String'
                            };
                            ssm.putParameter(update_params).promise()
                        }
                    });
                    let merge_details = {
                        Name: `/infra/${process.env.APP_NAME}-${environment}/merge_details`,
                        WithDecryption: true
                    };

                    ssm.getParameter(merge_details, function (err, data) {
                        if (err) {
                            var update_params = {
                                Name: `/infra/${process.env.APP_NAME}-${environment}/merge_details`,
                                Value: `[{"DeploymentId":\"${deploymentId}\","HookId":\"${hookId}\"}]`,
                                Overwrite: true,
                                Type: 'String'
                            };
                            ssm.putParameter(update_params).promise()
                        }
                        else {
                            let current_value = data.Parameter.Value
                            let current_json = JSON.parse(current_value);
                            let new_value = JSON.parse(`{"DeploymentId":\"${deploymentId}\","HookId":\"${hookId}\"}`)
                            current_json.push(new_value)
                            var update_params = {
                                Name: `/infra/${process.env.APP_NAME}-${environment}/merge_details`,
                                Value: `${JSON.stringify(current_json)}`,
                                Overwrite: true,
                                Type: 'String'
                            };
                            ssm.putParameter(update_params).promise()
                        }
                    });
                }
            }).promise();

        }
        if (deploymentType == "ECS" || (deploymentType == "SAM" && ready_for_merge_count == total_deployments)) {
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
        }
        if (deploymentType == "ECS") {
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
        } else {
            var merge_call_count_params = {
                Name: `/infra/${process.env.APP_NAME}-${environment}/merge_call_count_params`,
                Value: `0`,
                Overwrite: true,
                Type: 'String'
            };

            await ssm.putParameter(merge_call_count_params).promise();
        }
    }
};



