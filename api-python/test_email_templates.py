import json
import tempfile
import unittest
from pathlib import Path
from email_templates import DEFAULTS, render


class EmailTemplateTests(unittest.TestCase):
    def custom(self, templates, kind, values):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'templates.json'
            path.write_text(json.dumps(templates))
            return render(kind, values, str(path))

    def test_confirmation_keeps_real_link(self):
        subject, body = render('confirm', {'confirm_url': 'https://example.test/confirm?id=123'})
        self.assertIn('LuckyScan50', subject)
        self.assertIn('https://example.test/confirm?id=123', body)

    def test_custom_content(self):
        templates = json.loads(json.dumps(DEFAULTS))
        templates['confirm']['body'] = 'Olá! Confirme aqui: {confirm_url}'
        self.assertEqual(self.custom(templates, 'confirm', {'confirm_url': 'LINK'})[1], 'Olá! Confirme aqui: LINK')

    def test_rejects_missing_link_unknown_fields_and_header_injection(self):
        for field, value in [('body', 'Sem ligação'), ('body', '{confirm_url.__class__}'),
                             ('subject', 'LuckyScan50\nBcc: another@example.test')]:
            with self.subTest(value=value):
                templates = json.loads(json.dumps(DEFAULTS))
                templates['confirm'][field] = value
                with self.assertRaises(ValueError):
                    self.custom(templates, 'confirm', {'confirm_url': 'LINK'})

    def test_all_default_event_models(self):
        values = {'label': 'M1lhão 001', 'draw_date': '2026-10-20', 'winning_key': 'ABC123',
                  'source_url': 'https://example.test', 'prize_amount': '10,00',
                  'sync_note': 'Sincronizado hoje.', 'draw': 'milhao:001',
                  'deadline': '2026-10-21', 'days_remaining': 1}
        for kind in ('results', 'prizes', 'expiry'):
            subject, body = render(kind, values)
            self.assertIn('LuckyScan50', subject)
            self.assertNotIn('{', body)
