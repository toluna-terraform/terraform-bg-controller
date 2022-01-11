import json
import logging
import boto3
import requests

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    for record in event['Records']:
        payload = record["body"]
        logger.info("Bitbucket message is:::"+payload)

    # ssm = boto3.client('ssm')
    # USERNAME = ssm.get_parameter(
    #     Name='/app/bb_user',
    #     WithDecryption=True
    # )
    # PASSWORD = ssm.get_parameter(
    #     Name='/app/bb_pass',
    #     WithDecryption=True
    # )
    
    # url = "https://api.bitbucket.org/2.0/repositories/{}/{}/pullrequests/{}".format(body['org_id'],body['repo'],body['pr_id'])
    # response = requests.get(url, auth=("{}".format(USERNAME['Parameter']['Value']), "{}".format(PASSWORD['Parameter']['Value'])))
    # logger.info("Response Code is::::" + str(response.status_code))
    # response_body = response.json()
    # pr_state = response_body['state']
    # logger.info("PR State is::::" + str(pr_state))
    # result = {"statusCode": str(response.status_code)}
    return event