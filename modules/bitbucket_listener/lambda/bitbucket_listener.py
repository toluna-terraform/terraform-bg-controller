import json
import logging
import boto3
import requests
import bb_functions as bbf
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
        bbf.bb_check_change_path(USERNAME,PASSWORD,pr_desc,pr_id,repo)
    return event