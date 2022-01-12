import json
import logging
import boto3
import requests

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def bb_update_description(USERNAME,PASSWORD,pr_desc,pr_id,repo):
    #url = "https://api.bitbucket.org/2.0/repositories/{}/pullrequests/{}".format(repo,pr_id)
    #pr_desc 
    #pr_desc += "# Test title\n\n| **Action** | **PR State** |\n| --- | --- |\n| PR  | Pending |\n|  |  |\n\n"
    #data = {
    #    "description":"{}".format(pr_desc)
    #    
    #}
    #headers = {"Content-Type": "application/json"}
    #response = requests.put(url, auth=("{}".format(USERNAME['Parameter']['Value']), "{}".format(PASSWORD['Parameter']['Value'])),data=json.dumps(data),headers=headers)
    #response_body = response.json()
    #logger.info("Response Code is::::" + str(response.status_code))
    #logger.info("Response Body is::::" + str(response_body))

def lambda_handler(event, context):
    ssm = boto3.client('ssm')
    USERNAME = ssm.get_parameter(
        Name='/app/bb_user',
        WithDecryption=True
    )
    PASSWORD = ssm.get_parameter(
        Name='/app/bb_pass',
        WithDecryption=True
    )
    for record in event['Records']:
        payload = record["body"]
        fullpayload=str(payload)
        jsonpayload = json.loads(fullpayload, strict=False)
        state = jsonpayload['pullrequest']['state']
        src_branch = jsonpayload['pullrequest']['source']['branch']['name']
        dst_branch = jsonpayload['pullrequest']['destination']['branch']['name']
        pr_desc = jsonpayload['pullrequest']['description']
        pr_id = jsonpayload['pullrequest']['id']
        repo = jsonpayload['repository']['full_name']
        bb_update_description(USERNAME,PASSWORD,pr_desc,pr_id,repo)
    return event