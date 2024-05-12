const https = require('https');
const AWS = require('aws-sdk');
const ssm = new AWS.SSM({ apiVersion: '2014-11-06', region: 'us-east-1' });

async function getBitBucketPRStatus(username, password, pr_id) {
  const uri = encodeURI(`/2.0/repositories/${process.env.SOURCE_REPOSITORY}/pullrequests/${pr_id}`);
  const auth = "Basic " + Buffer.from(username + ":" + password).toString("base64");
  const options = {
    hostname: 'api.bitbucket.org',
    port: 443,
    path: uri,
    method: 'GET',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': auth
    },
  };
  const body = await new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';

      res.on("data", (chunk) => {
        data += chunk;
      });

      res.on("end", () => {
        resolve(data);
      });
    });

    req.on("error", (error) => {
      reject(error);
    });

    req.end();
  });
  return body;
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

function sendTeamsNotification(APP_NAME, AUTHOR, MERGED_BY, PR_URL, MERGE_COMMIT, TEAMS_WEBHOOK, TRIBE_NAME) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify({
      "@type": "MessageCard",
      "@context": "http://schema.org/extensions",
      "themeColor": "16d700",
      "summary": `${APP_NAME} Deploy to Production Done`,
      "sections": [{
        "activityTitle": `${APP_NAME} Deploy to Production`,
        "activitySubtitle": `${APP_NAME} of Tribe ${TRIBE_NAME}`,
        "activityImage": "",
        "facts": [{
          "name": "URL",
          "value": `[Bitbucket PR](${PR_URL})`
        },
        {
          "name": "Service Name",
          "value": `${APP_NAME}`
        },
        {
          "name": "Commit Id",
          "value": `${MERGE_COMMIT}`
        },
        {
          "name": "Author",
          "Value": `${AUTHOR}`
        },
        {
          "name": "Merged By",
          "value": `${MERGED_BY}`
        }],
        "markdown": true
      }]
    });
    const options = {
      hostname: 'tolunaonline.webhook.office.com',
      path: TEAMS_WEBHOOK,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
    };
    console.log(`Sending Teams Notification: ${data}`);
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

exports.handler = async (event) => {
  console.log(event)
  const username = await getSSMParam('/app/bb_user', true);
  const password = await getSSMParam('/app/bb_app_pass', true);
  const TEAMS_WEBHOOK_LIST = await getSSMParam('/infra/teams_notification_webhook', true);
  const TRIBE_NAME = await getSSMParam('/infra/tribe', true, "(Tribe is undefind, please add tribe name to ssm parameter '/infra/tribe')");
  const pr_id = event.CODEBUILD_WEBHOOK_TRIGGER.replaceAll("pr/", "");
  const bb_pr = await getBitBucketPRStatus(username, password, pr_id);
  const bb_payload = JSON.parse(bb_pr)
  const AUTHOR = bb_payload.author.display_name;
  const MERGED_BY = bb_payload.closed_by.display_name;
  const MERGE_COMMIT = bb_payload.merge_commit.hash;
  const PR_URL = bb_payload.links.html.href;
  const APP_NAME = process.env.APP_NAME.charAt(0).toUpperCase() + process.env.APP_NAME.slice(1);
  const TEAMS_WEBHOOKS = TEAMS_WEBHOOK_LIST.split(',');
  TEAMS_WEBHOOKS.forEach(function(TEAMS_WEBHOOK) {
    sendTeamsNotification(APP_NAME, AUTHOR, MERGED_BY, PR_URL, MERGE_COMMIT, TEAMS_WEBHOOK, TRIBE_NAME);
  });
  
};
