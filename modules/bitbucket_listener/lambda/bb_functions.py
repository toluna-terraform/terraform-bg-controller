import json
import logging
import boto3
import requests

def bb_check_change_path(USERNAME,PASSWORD,pr_desc,pr_id,repo):
    url = "https://api.bitbucket.org/2.0/repositories/{}/pullrequests/{}/diffstat".format(repo,pr_id)
    headers = {"Content-Type": "application/json"}
    response = requests.get(url, auth=("{}".format(USERNAME['Parameter']['Value']), "{}".format(PASSWORD['Parameter']['Value'])),headers=headers)
    response_body = response.json()
    filechanges = []
    for value in response_body['values']:
        if "old" in value:
            path = value['old']['path']
        else:
            path = value['new']['path']
        filechanges.append(path)
    if any("terraform/app" in s for s in filechanges):
        tf_app_changed = True
    else:
        tf_app_changed = False
    if any("service" in s for s in filechanges):
        tf_service_changed = True
    else:
        tf_service_changed = False
    print(filechanges) 
    print("Infra has changed:::"+str(tf_app_changed))
    print("Service has changed:::"+str(tf_service_changed))