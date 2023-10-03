const https = require('https');
const AWS = require('aws-sdk');
const ssm = new AWS.SSM({ apiVersion: '2014-11-06', region: 'us-east-1' });
//const webhookURL = `${process.env.SOURCE_REPOSITORY}`;

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
  return body ; 
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

function sendTeamsNotification(AUTHOR, MERGED_BY, PR_URL,MERGE_COMMIT,TEAMS_WEBHOOK) {
     const body = JSON.stringify({  
        "@type": "MessageCard",  
        "@context": "http://schema.org/extensions",  
        "themeColor": "16d700",  
        "summary": "Deploy to Production Done",  
        "sections": [{  
            "activityTitle": "Deploy to Production",  
            "activitySubtitle": `${process.env.APP_NAME} Deployed to Production`,  
            "activityImage": "",  
            "facts": [{  
                "name": "URL",  
                "value": `[Bitbucket Repo](${PR_URL})`
            },  
            {  
                "name": "Service Name",  
                "value": `${process.env.APP_NAME}`  
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
      var req = https.request(options, function (res) {
        var chunks = [];
      
        res.on("data", function (chunk) {
          chunks.push(chunk);
        });
      
        res.on("end", function (chunk) {
          var body = Buffer.concat(chunks);
          console.log(body.toString());
        });
      
        res.on("error", function (error) {
          console.error(error);
        });
      });
      req.write(body);
      req.end();
}

exports.handler = async (event) => {
  const pr_id = event.CODEBUILD_WEBHOOK_TRIGGER.replaceAll("pr/","");
  const username = await getSSMParam('/app/bb_user', true);
  const password = await getSSMParam('/app/bb_app_pass', true);
  const TEAMS_WEBHOOK = await getSSMParam('/infra/teams_notification_webhook', true);
  const bb_pr = await getBitBucketPRStatus(username, password, pr_id);
  const bb_payload = JSON.parse(bb_pr)
  const AUTHOR=bb_payload.author.display_name;
  const MERGED_BY=bb_payload.closed_by.display_name;
  const MERGE_COMMIT=bb_payload.merge_commit.hash;
  const PR_URL=bb_payload.links.html.href;
  sendTeamsNotification(AUTHOR,MERGED_BY,PR_URL,MERGE_COMMIT,TEAMS_WEBHOOK)
};
