import json
import sys

rows = [dict(id='demo-plugin',category='plugins',title='Example Screenshot Plugin',date=None,
             date_kind='unknown',status='present',origin='discovered',observed_at='2026-09-23', repository='https://github.com/example/plugin', update_status='Remote changes available', can_update=True),
        dict(id='demo-fix',category='fixes',title='Restore display after docking',date='2026-09-22',
             date_kind='recorded',status='reconstructed',origin='journal',observed_at='2026-09-23')]
action = sys.argv[1]
if action in ('refresh','dashboard'):
    print(json.dumps(dict(records=rows,recovery=dict(ready=True,missing=[]))))
elif action == 'show':
    print(json.dumps(dict(rows[0], details='A synthetic plugin used to demonstrate local machine history.\n\nObserved version: 1.0\nOriginal installation date: unknown\n\nUse Discuss to ask your agent about this item, or Investigate to explore a problem before changing anything.', events=[])))
elif action == 'agent':
    print(json.dumps(dict(message='TEST: '+sys.argv[3])))
else:
    print(json.dumps(dict(error='Test error')),file=sys.stderr)
    sys.exit(1)
