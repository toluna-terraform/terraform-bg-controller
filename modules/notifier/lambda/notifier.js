
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

async function sendTeamsNotification(APP_NAME, ENV_NAME, AUTHOR, MERGED_BY, PR_URL, MERGE_COMMIT, TEAMS_HOOK, TRIBE_NAME, BUILD_STATUS) {
  ENV_NAME = (ENV_NAME.toLowerCase() == "prod") ? "Production" : ENV_NAME;
  let MESSAGE_COLOR = "16d700"
  switch (BUILD_STATUS) {
    case 'STOPPED':
      MESSAGE_COLOR = "fcba03"
      break;
    case 'FAILED':
      MESSAGE_COLOR = "fc0303"
      break;
    default:
      MESSAGE_COLOR = "16d700"
  }
  const data = JSON.stringify({
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": `${MESSAGE_COLOR}`,
    "summary": `${APP_NAME} Deploy to ${ENV_NAME}`,
    "sections": [{
      "activityTitle": `${APP_NAME} Deploy to ${ENV_NAME}  ${BUILD_STATUS}`,
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
        "value": `${AUTHOR}`
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
    path: TEAMS_HOOK.trim(),
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
  };

  console.log(`Sending Teams Notification for ${APP_NAME} to ${ENV_NAME}: ${data}`);

  const req = https.request(options, res => {
    let responseData = '';
    console.log(`Response status for ${APP_NAME}: ${res.statusCode}`);

    res.on('data', d => {
      responseData += d;
    });

    res.on('end', () => {
      console.log(`Response data for ${APP_NAME}: ${responseData}`);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        // Handle successful response here (optional)
      } else {
        console.error(`Request failed with status code ${res.statusCode}: ${responseData}`);
      }
    });
  });

  req.on('error', (error) => {
    console.error('Error sending Teams notification:', error);
  });

  req.write(data);
  req.end();

  // Added await to wait for the request to complete before continuing the loop
  return new Promise((resolve, reject) => {
    req.on('close', () => {
      resolve();
    });
  });
}

exports.handler = async (event) => {
  console.log(JSON.stringify(event));
  const snsMessage = event.Records[0].Sns.Message;
  const jsonMessage = JSON.parse(snsMessage);
  const BUILD_STATUS = jsonMessage.build_status;
  const projectName = jsonMessage.project_name.split("-")
  const ENV_NAME = projectName[projectName.length - 1]
  const HOOK_ID = (ENV_NAME.toLowerCase() == "prod") ? '/infra/teams_notification_webhook' : '/infra/non_prod/teams_notification_webhook'
  const APP_NAME = process.env.APP_NAME.charAt(0).toUpperCase() + process.env.APP_NAME.slice(1);
  const pr_id = await getSSMParam(`/infra/${APP_NAME.toLowerCase()}-${ENV_NAME}/pr_id`, false);
  const username = await getSSMParam('/app/bb_user', true);
  const password = await getSSMParam('/app/bb_app_pass', true);
  const TEAMS_WEBHOOK_LIST = await getSSMParam(HOOK_ID, true);
  const TRIBE_NAME = await getSSMParam('/infra/tribe', true, "(Tribe is undefind, please add tribe name to ssm parameter '/infra/tribe')");
  const bb_pr = await getBitBucketPRStatus(username, password, pr_id);
  const bb_payload = JSON.parse(bb_pr)
  const AUTHOR = bb_payload.author.display_name;
  const MERGED_BY = bb_payload.closed_by.display_name;
  const MERGE_COMMIT = bb_payload.merge_commit.hash;
  const PR_URL = bb_payload.links.html.href;
  const TEAMS_WEBHOOKS = TEAMS_WEBHOOK_LIST.split(',');
  console.log(`${APP_NAME}, ${ENV_NAME}, ${AUTHOR}, ${MERGED_BY}, ${PR_URL}, ${MERGE_COMMIT}, ${TRIBE_NAME}, ${BUILD_STATUS}`)
  const NOTIFICATIONS = TEAMS_WEBHOOKS.map(async (val) => {
    const notification = await sendTeamsNotification(APP_NAME, ENV_NAME, AUTHOR, MERGED_BY, PR_URL, MERGE_COMMIT, val, TRIBE_NAME, BUILD_STATUS)
  })
  await Promise.all(NOTIFICATIONS);
};