"""All mail tests use fake transports. Never contact Gmail or send live emails."""
from dataclasses import replace
from datetime import datetime, timezone
import io
import json
from pathlib import Path
import smtplib
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import urlsplit

from email_notifications import (
    Config, EmailError, EmailStore, awards, deadline_map, deliver, gmail_send,
    handle_request, plan_messages, validate_watches,
)
from test_app import result


PREFS = {'results': True, 'prizes': True, 'expiry': True, 'leadDays': 7}
TOKEN = 'a' * 64


class EmailTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.now = datetime(2026, 1, 2, 12, tzinfo=timezone.utc).timestamp()
        self.config = Config(str(Path(self.tmp.name) / 'private.sqlite'),
                             'https://api.example.test', 's' * 32,
                             'example@gmail.com', 'p' * 16, True, 200, 20)
        self.store = EmailStore(self.config, lambda: self.now)
        self.identity = self.store.authenticate({'HTTP_AUTHORIZATION': 'Bearer ' + TOKEN})

    def subscribe(self, **kwargs):
        return self.store.subscribe(self.identity, {
            'email': kwargs.get('email', 'reader@example.pt'),
            'consent': True, 'preferences': kwargs.get('preferences', PREFS),
        }, '192.0.2.1')

    def link(self, purpose='confirm'):
        with self.store.connect() as db:
            row = db.execute('SELECT * FROM subscribers WHERE id=?', (self.identity,)).fetchone()
            return self.store.link(row, purpose)

    def confirm(self):
        from urllib.parse import parse_qs
        query = parse_qs(urlsplit(self.link()).query)
        self.store.act_on_link(self.identity, query['token'][0], 'confirm', apply=True)

    def watch(self):
        return {'id': 'receipt-1', 'drawIds': ['001/2026'], 'milhaoDrawIds': [],
                'lines': [{'numbers': [1, 2, 3, 4, 50], 'stars': [1, 2]}],
                'milhaoCodes': [], 'receivedCents': 0}

    def request(self, path, method='GET', body=None, authorization=True):
        url = urlsplit(path)
        payload = json.dumps(body).encode() if body is not None else b''
        env = {'PATH_INFO': url.path, 'QUERY_STRING': url.query, 'REQUEST_METHOD': method,
               'CONTENT_TYPE': 'application/json', 'CONTENT_LENGTH': str(len(payload)),
               'wsgi.input': io.BytesIO(payload), 'REMOTE_ADDR': '192.0.2.1'}
        if authorization:
            env['HTTP_AUTHORIZATION'] = 'Bearer ' + TOKEN
        response = {}
        def start(status, headers):
            response.update(status=int(status.split()[0]), headers=dict(headers))
        with patch('email_notifications.time.time', lambda: self.now), patch('email_notifications.gmail_send'):
            data = handle_request(env, start, self.config)
        return response, b''.join(data)

    def test_subscription_sends_confirmation_immediately_and_only_once(self):
        messages = []
        with patch('email_notifications.gmail_send', side_effect=lambda c, m: messages.append(m)):
            # request() patches the transport too; call the handler directly here.
            def post():
                payload = json.dumps({'email': 'reader@example.pt', 'consent': True,
                                      'preferences': PREFS}).encode()
                env = {'PATH_INFO': '/v1/email/subscription', 'REQUEST_METHOD': 'POST',
                       'CONTENT_TYPE': 'application/json', 'CONTENT_LENGTH': str(len(payload)),
                       'wsgi.input': io.BytesIO(payload), 'REMOTE_ADDR': '192.0.2.1',
                       'HTTP_AUTHORIZATION': 'Bearer ' + TOKEN}
                with patch('email_notifications.time.time', lambda: self.now):
                    return json.loads(b''.join(handle_request(env, lambda *a: None, self.config)))
            first = post()
            second = post()
        self.assertEqual(first['confirmationDelivery'], 'sent')
        self.assertEqual(second['confirmationDelivery'], 'sent')
        self.assertEqual(len(messages), 1)

    def test_immediate_confirmation_does_not_drain_other_subscribers(self):
        self.subscribe()
        other = self.store.authenticate({'HTTP_AUTHORIZATION': 'Bearer ' + 'b' * 64})
        self.store.subscribe(other, {'email': 'other@example.pt', 'consent': True,
                                    'preferences': PREFS}, '192.0.2.2')
        sent = []
        deliver(self.store, lambda c, m: sent.append(m), subscriber_id=self.identity, confirmation_only=True)
        self.assertEqual(len(sent), 1)
        self.assertEqual(sent[0]['To'], 'reader@example.pt')
        with self.store.connect() as db:
            self.assertEqual(db.execute("SELECT state FROM outbox WHERE subscriber=?", (other,)).fetchone()[0], 'queued')

    def test_disabled_by_default_and_no_credentials_exposed(self):
        with patch.dict('os.environ', {}, clear=True):
            self.assertFalse(Config.environment().ready)
        self.assertFalse(replace(self.config, password='').ready)
        self.assertFalse(replace(self.config, base_url='http://api.test').ready)
        response, body = self.request('/v1/email/status')
        self.assertEqual(response['status'], 200)
        self.assertNotIn(self.config.password.encode(), body)
        self.assertEqual(response['headers']['Cache-Control'], 'no-store')

    def test_confirmation_is_required_and_get_does_not_confirm(self):
        self.assertEqual(self.subscribe()['status'], 'pending')
        self.assertEqual(plan_messages(self.store, [result()])['results'], 0)
        with self.assertRaises(EmailError):
            self.store.watches(self.identity, [self.watch()])
        response, _ = self.request(self.link())
        self.assertEqual(response['status'], 200)
        self.assertEqual(self.store.status(self.identity)['status'], 'pending')
        response, _ = self.request(self.link(), 'POST')
        self.assertEqual(response['status'], 200)
        self.assertEqual(self.store.status(self.identity)['status'], 'active')

    def test_links_expire_and_cannot_be_forged(self):
        self.subscribe()
        url = self.link()
        response, _ = self.request(url[:-1] + ('0' if url[-1] != '0' else '1'), 'POST')
        self.assertEqual(response['status'], 400)
        self.now += 86401
        response, _ = self.request(url, 'POST')
        self.assertEqual(response['status'], 400)

    def test_email_change_requires_confirmation_and_invalidates_old_link(self):
        self.subscribe()
        self.confirm()
        self.store.watches(self.identity, [self.watch()])
        old = self.link('unsubscribe')
        self.subscribe(email='another@example.pt')
        self.assertEqual(self.store.status(self.identity)['status'], 'pending')
        response, _ = self.request(old, 'POST')
        self.assertEqual(response['status'], 400)
        with self.store.connect() as db:
            self.assertEqual(db.execute('SELECT watches FROM subscribers').fetchone()[0], '[]')

    def test_resend_cooldown_and_rate_limit(self):
        self.subscribe()
        self.subscribe()
        with self.store.connect() as db:
            self.assertEqual(db.execute('SELECT count(*) FROM outbox').fetchone()[0], 1)
        for _ in range(4):
            self.subscribe()
        with self.assertRaises(EmailError) as context:
            self.subscribe()
        self.assertEqual(context.exception.status, 429)

    def test_no_prizes_or_history_before_opt_in(self):
        self.subscribe()
        self.confirm()
        self.now += 86400 * 2
        # The consent date, not the cron start date, defines the first result.
        old = result()
        old['drawId'], old['date'] = '104/2025', '2025-12-30'
        self.assertEqual(plan_messages(self.store, [old])['results'], 0)

    def test_deduplication_and_official_deadlines_only(self):
        self.subscribe()
        self.confirm()
        self.store.watches(self.identity, [self.watch()])
        self.assertEqual(plan_messages(self.store, [result()], apply=True),
                         {'results': 1, 'prizes': 1, 'expiry': 0})
        self.assertEqual(plan_messages(self.store, [result()], apply=True),
                         {'results': 0, 'prizes': 0, 'expiry': 0})
        deadlines = {'euromilhoes:001/2026': {
            'deadline': '2026-01-07', 'verifiedAt': '2026-01-02',
            'sourceUrl': 'https://www.jogossantacasa.pt/reviewed-test-fixture'}}
        self.assertEqual(plan_messages(self.store, [result()], deadlines, apply=True)['expiry'], 1)
        self.assertEqual(plan_messages(self.store, [result()], deadlines, apply=True)['expiry'], 0)
        paid = self.watch()
        paid['receivedCents'] = 1000
        self.store.watches(self.identity, [paid])
        self.assertEqual(plan_messages(self.store, [result()], deadlines)['prizes'], 0)
        self.assertEqual(plan_messages(self.store, [result()], deadlines)['expiry'], 0)

    def test_dry_run_does_not_queue_messages(self):
        self.subscribe()
        self.confirm()
        with self.store.connect() as db:
            before = db.execute('SELECT count(*) FROM outbox').fetchone()[0]
        self.assertEqual(plan_messages(self.store, [result()])['results'], 1)
        with self.store.connect() as db:
            self.assertEqual(db.execute('SELECT count(*) FROM outbox').fetchone()[0], before)

    def test_known_expired_prize_is_not_reminded(self):
        self.subscribe()
        self.confirm()
        self.store.watches(self.identity, [self.watch()])
        deadlines = {'euromilhoes:001/2026': {
            'deadline': '2026-01-01', 'verifiedAt': '2026-01-01',
            'sourceUrl': 'https://www.jogossantacasa.pt/reviewed-test-fixture'}}
        planned = plan_messages(self.store, [result()], deadlines)
        self.assertEqual(planned['prizes'], 0)
        self.assertEqual(planned['expiry'], 0)

    def test_unsubscribe_cancels_queued_mail_and_erases_personal_data(self):
        self.subscribe()
        self.confirm()
        self.store.watches(self.identity, [self.watch()])
        plan_messages(self.store, [result()], apply=True)
        link = self.link('unsubscribe')
        self.request(link)
        self.assertEqual(self.store.status(self.identity)['status'], 'active')
        self.request(link, 'POST')
        self.assertEqual(self.store.status(self.identity)['email'], '')
        sent = []
        self.assertEqual(deliver(self.store, lambda c, m: sent.append(m))['sent'], 0)
        self.assertFalse(sent)

    def test_gmail_message_and_no_delivery_to_unconfirmed_recipient_except_confirmation(self):
        self.subscribe()
        messages = []
        stats = deliver(self.store, lambda c, m: messages.append(m))
        self.assertEqual(stats['sent'], 1)
        self.assertIn('Confirme', messages[0]['Subject'])
        self.assertIn('Confirmar o meu email', messages[0].get_body(preferencelist=('html',)).get_content())
        self.assertEqual(messages[0]['List-Unsubscribe-Post'], 'List-Unsubscribe=One-Click')
        self.assertIn('Cancelar', messages[0].get_body(preferencelist=('plain',)).get_content())
        self.assertEqual(deliver(self.store, lambda c, m: messages.append(m))['sent'], 0)

    def test_ambiguous_smtp_failure_is_not_automatically_retried(self):
        self.subscribe()
        def ambiguous(config, message):
            raise TimeoutError('possibly submitted')
        self.assertEqual(deliver(self.store, ambiguous)['uncertain'], 1)
        self.assertEqual(deliver(self.store, ambiguous)['uncertain'], 0)

    def test_daily_budget_survives_cancellation_and_counts_retries(self):
        self.subscribe()
        self.store.config = replace(self.config, daily_limit=1)
        def temporary(config, message):
            raise smtplib.SMTPDataError(451, b'try later')
        self.assertEqual(deliver(self.store, temporary)['failed'], 1)
        self.now += 1000
        self.assertEqual(deliver(self.store, temporary)['failed'], 0)
        self.store.revoke(self.identity)
        self.subscribe()
        self.assertEqual(deliver(self.store, temporary)['failed'], 0)

    def test_authentication_body_limits_and_consent(self):
        response, _ = self.request('/v1/email/subscription', authorization=False)
        self.assertEqual(response['status'], 401)
        response, _ = self.request('/v1/email/subscription', 'POST', {'email': 'a@b.pt'})
        self.assertEqual(response['status'], 400)
        for bad in ('a\n@b.pt', 'a@@b.pt', 'a@b', '<script>@b.pt'):
            response, _ = self.request('/v1/email/subscription', 'POST', {
                'email': bad, 'consent': True, 'preferences': PREFS})
            self.assertEqual(response['status'], 400)

    def test_watch_validation_minimizes_uploaded_data(self):
        value = {**self.watch(), 'imagePath': '/private/image.jpg', 'code': 'private'}
        clean = validate_watches([value])[0]
        self.assertNotIn('imagePath', clean)
        self.assertNotIn('code', clean)
        for bad in ([{'id': 'x', 'lines': [{'numbers': [1] * 5, 'stars': [1, 2]}]}], 'bad'):
            with self.assertRaises(EmailError):
                validate_watches(bad)

    def test_deadline_file_rejects_unattributed_dates(self):
        path = Path(self.tmp.name) / 'deadlines.json'
        path.write_text(json.dumps({'euromilhoes:001/2026': {
            'deadline': '2026-01-07', 'verifiedAt': '2026-01-02',
            'sourceUrl': 'https://untrusted.example/path'}}))
        with self.assertRaises(ValueError):
            deadline_map(path)

    def test_milhao_award(self):
        watch = self.watch()
        watch['milhaoDrawIds'] = ['001/2026']
        watch['milhaoCodes'] = ['ABC12345']
        self.assertIn(('milhao:001/2026', 100000000), awards(watch, {'milhao:001/2026': result('milhao')}))

    def test_smtp_uses_gmail_starttls_and_app_password(self):
        with patch('email_notifications.smtplib.SMTP') as smtp:
            message = object()
            gmail_send(self.config, message)
            smtp.assert_called_once_with('smtp.gmail.com', 587, timeout=30)
            connection = smtp.return_value
            connection.starttls.assert_called_once()
            connection.login.assert_called_once_with(self.config.username, self.config.password)
            connection.send_message.assert_called_once_with(message)


if __name__ == '__main__':
    unittest.main()
