import sys, os, json
sys.path.insert(0, os.path.expanduser('~/.azure/cliextensions/azure-devops'))
from azext_devops.dev.common.services import _get_credentials
import requests
ORG = 'https://dev.azure.com/Myridius-Insurity'
PROJ = 'humaid-risk-governance'
cred = _get_credentials(ORG)
s = requests.Session(); cred.signed_session(s)
def upload(path, name):
    r = s.post(f'{ORG}/{PROJ}/_apis/wit/attachments', params={'fileName': name, 'api-version': '7.1'},
               data=open(path, 'rb').read(), headers={'Content-Type': 'application/octet-stream'})
    r.raise_for_status(); return r.json()['url']
def patch(wid, ops):
    r = s.patch(f'{ORG}/{PROJ}/_apis/wit/workitems/{wid}', params={'api-version': '7.1'}, data=json.dumps(ops),
                headers={'Content-Type': 'application/json-patch+json'})
    r.raise_for_status(); return r.json()
def create(fields, relations):
    ops = [{'op': 'add', 'path': f'/fields/{k}', 'value': v} for k, v in fields.items()]
    ops += [{'op': 'add', 'path': '/relations/-', 'value': rel} for rel in relations]
    r = s.post(f'{ORG}/{PROJ}/_apis/wit/workitems/$Bug', params={'api-version': '7.1'}, data=json.dumps(ops),
               headers={'Content-Type': 'application/json-patch+json'})
    r.raise_for_status(); return r.json()
if __name__ == '__main__':
    r = s.get(f'{ORG}/{PROJ}/_apis/wit/workitems/99', params={'api-version': '7.1', 'fields': 'System.Title'})
    print(r.status_code, r.json()['fields'])
