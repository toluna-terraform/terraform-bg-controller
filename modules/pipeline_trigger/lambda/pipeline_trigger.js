const AWS = require('aws-sdk');
const cd = new AWS.CodeDeploy({ apiVersion: '2014-10-06', region: 'us-east-1' });
const region = "us-east-1"

exports.handler = async function (event, context, callback) {
  console.log("EVENT: \n" + JSON.stringify(event, null, 2));
  let bucketName = event.Records[0].s3.bucket.name;
  let path = event.Records[0].s3.object.key;
  let env_name = path.replace('/source_artifacts.zip','');
  console.log(`TRIGGER: \n{\"PIPELINE\":\"codepipline-${process.env.APP_NAME}-${env_name}\"}`);
}