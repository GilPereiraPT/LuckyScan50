"""WordPress transport contract tests; all HTTP is simulated."""
from dataclasses import replace
from email.message import EmailMessage
import io
import json
import smtplib
import unittest
from unittest.mock import Mock, MagicMock, patch
from urllib.error import HTTPError

from email_notifications import Config, EmailError, NoMailRedirect, wordpress_send, deliver
import test_email_notifications as fixtures


def message():
    result = EmailMessage()
    result['To'] = 'reader@example.pt'
    result['Subject'] = 'Confirme os avisos do LuckyScan50'
    result['X-LuckyScan50-Delivery-ID'] = 'd' * 64
    result['List-Unsubscribe'] = '<https://luckyscan50-api.policlinicosdesantoandre.com/v1/email/unsubscribe?id=x&token=y>'
    result.set_content('Confirmar: https://api.example.test/confirm\nCancelar: https://api.example.test/unsubscribe')
    return result


class WordPressTests(unittest.TestCase):
    def setUp(self):
        self.config = Config('/private/mail.sqlite', 'https://api.example.test', 's' * 32,
            'luckyscan50@gmail.com', '', True, provider='wordpress',
            wordpress_url='https://policlinicosdesantoandre.com/wp-json/luckyscan50/v1/mail',
            wordpress_key='k' * 64)

    def transport(self, body=b'{"accepted":true,"duplicate":false}'):
        opener = MagicMock()
        response = opener.open.return_value.__enter__.return_value
        response.status = 200
        response.read.return_value = body
        return opener

    def test_wordpress_requires_no_gmail_password_but_requires_its_own_key(self):
        self.assertTrue(self.config.ready)
        self.assertFalse(replace(self.config, wordpress_key='').ready)
        self.assertFalse(replace(self.config, wordpress_url='http://example.test/luckyscan50/v1/mail').ready)
        self.assertFalse(replace(self.config, provider='unknown').ready)

    def test_posts_minimum_payload_and_secret_only_to_configured_endpoint(self):
        opener = self.transport()
        wordpress_send(self.config, message(), opener)
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, self.config.wordpress_url)
        self.assertEqual(request.get_method(), 'POST')
        self.assertEqual(request.get_header('X-luckyscan50-key'), self.config.wordpress_key)
        payload = json.loads(request.data)
        self.assertEqual(set(payload), {'deliveryId', 'to', 'subject', 'body', 'unsubscribeUrl'})
        self.assertEqual(payload['deliveryId'], 'd' * 64)
        self.assertNotIn(self.config.wordpress_key.encode(), request.data)
        self.assertEqual(opener.open.call_args.kwargs['timeout'], 40)

    def test_duplicate_already_accepted_response_is_success(self):
        wordpress_send(self.config, message(), self.transport(b'{"accepted":true,"duplicate":true}'))

    def test_never_follows_redirects_with_private_key(self):
        self.assertIsNone(NoMailRedirect().redirect_request(None, None, 302, '', {}, 'https://other.test'))

    def test_authentication_failure_stops_sender(self):
        opener = Mock()
        opener.open.side_effect = HTTPError(self.config.wordpress_url, 403, 'denied', {}, io.BytesIO(b''))
        with self.assertRaises(smtplib.SMTPAuthenticationError):
            wordpress_send(self.config, message(), opener)

    def test_quota_is_a_definite_rejection_but_server_errors_are_uncertain(self):
        for code, error in [(429, smtplib.SMTPDataError), (400, smtplib.SMTPDataError),
                            (409, OSError), (500, OSError), (301, OSError)]:
            opener = Mock()
            opener.open.side_effect = HTTPError(self.config.wordpress_url, code, 'error', {}, io.BytesIO(b''))
            with self.assertRaises(error):
                wordpress_send(self.config, message(), opener)

    def test_invalid_success_body_never_claims_delivery(self):
        for body in (b'not json', b'{"accepted":false}', b'[]', b'x' * 8193):
            with self.assertRaises(OSError):
                wordpress_send(self.config, message(), self.transport(body))


class WordPressQueueTests(unittest.TestCase):
    setUp = fixtures.EmailTests.setUp
    subscribe = fixtures.EmailTests.subscribe
    def test_transport_selection_and_stable_id_across_definite_retries(self):
        self.store.config = replace(self.config, provider='wordpress', password='',
            wordpress_url='https://policlinicosdesantoandre.com/wp-json/luckyscan50/v1/mail',
            wordpress_key='k' * 64)
        self.subscribe()
        ids = []
        def temporary(config, msg):
            ids.append(msg['X-LuckyScan50-Delivery-ID'])
            raise smtplib.SMTPDataError(451, b'busy')
        with patch('email_notifications.wordpress_send', side_effect=temporary):
            self.assertEqual(deliver(self.store)['failed'], 1)
        self.now += 1000
        with patch('email_notifications.wordpress_send', side_effect=lambda config, msg: ids.append(msg['X-LuckyScan50-Delivery-ID'])):
            self.assertEqual(deliver(self.store)['sent'], 1)
        self.assertEqual(ids[0], ids[1])


if __name__ == '__main__':
    unittest.main()
