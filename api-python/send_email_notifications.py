"""cPanel cron runner. Default is dry-run; --send is an explicit activation."""
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path

from email_notifications import Config, EmailError, EmailStore, deadline_map, deliver, maintenance, plan_messages
from passenger_wsgi import load_results


@contextmanager
def cron_lock(path):
    fd = os.open(str(path) + '.cron.lock', os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(fd, 'w') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


def run(send=False):
    config = Config.environment()
    if not config.ready:
        return {'ready': False, 'sent': 0, 'reason': 'email_not_configured'}
    Path(config.database).parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    store = EmailStore(config)
    try:
        with cron_lock(config.database):
            deadlines = deadline_map(os.environ.get('LUCKYSCAN_CLAIM_DEADLINES_FILE'))
            planned = plan_messages(store, load_results(), deadlines, apply=send)
            result = deliver(store) if send else {'sent': 0, 'dryRun': True}
            if send:
                maintenance(store)
            return {'ready': True, 'planned': planned, **result}
    except BlockingIOError:
        return {'ready': True, 'sent': 0, 'reason': 'another_worker_running'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--send', action='store_true', help='Deliver queued mail through configured Gmail SMTP')
    args = parser.parse_args()
    try:
        print(json.dumps(run(send=args.send)))
    except (EmailError, OSError, ValueError, KeyError):
        # Never write email addresses, tokens, credentials or SMTP exception text to cron logs.
        print(json.dumps({'ready': False, 'sent': 0, 'reason': 'configuration_or_data_error'}))
        raise SystemExit(1)
