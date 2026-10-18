import io
from pathlib import Path
import unittest
import zipfile
from verify_apk import verify_assets, verify_certificate


class VerificationTests(unittest.TestCase):
    def archive(self, name, data):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as target:
            target.writestr(name, data)
        return zipfile.ZipFile(buffer)

    def test_public_branding(self):
        root = Path(__file__).resolve().parents[1]
        name = 'luckyscan50-logo.webp'
        with self.archive('assets/flutter_assets/assets/branding/' + name,
                          (root / 'app/assets/branding' / name).read_bytes()) as archive:
            verify_assets(archive)

    def test_private_and_tampered_assets_rejected(self):
        for name in ('assets/photo.jpg', 'assets/ocr.traineddata',
                     'assets/private_receipts/data.json',
                     'assets/flutter_assets/assets/branding/luckyscan50-logo.webp'):
            with self.subTest(name=name), self.archive(name, b'private') as archive:
                with self.assertRaises(ValueError):
                    verify_assets(archive)

    def test_certificate_identity(self):
        output = 'Signer #1 certificate SHA-256 digest: abcd'
        self.assertEqual(verify_certificate(output, 'ABCD', True), 'abcd')
        with self.assertRaises(ValueError):
            verify_certificate(output, 'ffff', True)
        with self.assertRaises(ValueError):
            verify_certificate(output + '\nSigner #1 certificate DN: CN=Android Debug', require_private=True)
