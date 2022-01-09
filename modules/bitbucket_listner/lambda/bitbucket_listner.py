import json
import logging
import boto3
import requests

logger = logging.getLogger()
logger.setLevel(logging.INFO)

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
    url = "https://api.bitbucket.org/2.0/repositories/{}/{}/pullrequests/{}".format(event['org_id'],event['repo'],event['pr_id'])
    response = requests.get(url, auth=("{}".format(USERNAME['Parameter']['Value']), "{}".format(PASSWORD['Parameter']['Value'])))
    response_body = response.json()
    pr_state = response_body['state']
    logger.info("PR State is: " + str(pr_state))