import io
from pathlib import Path
import unittest
import struct
import zipfile
from verify_apk import verify_assets, verify_certificate, verify_elf


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
        for name in ('assets/photo.jpg', 'assets/PHOTO.TIFF', 'assets/photo.gif',
                     'assets/ocr.traineddata', 'assets/OCR.TRAINEDDATA',
                     'assets/private_receipts/data.json',
                     'assets/flutter_assets/assets/branding/luckyscan50-logo.webp'):
            with self.subTest(name=name), self.archive(name, b'private') as archive:
                with self.assertRaises(ValueError):
                    verify_assets(archive)

    def test_certificate_identity(self):
        digest = 'ab' * 32
        output = 'Signer #1 certificate SHA-256 digest: ' + digest
        self.assertEqual(verify_certificate(output, digest.upper(), True), digest)
        with self.assertRaises(ValueError):
            verify_certificate(output, 'ffff', True)
        with self.assertRaises(ValueError):
            verify_certificate(output + '\nSigner #1 certificate DN: CN=Android Debug', require_private=True)

    def test_malformed_certificate_digest_rejected(self):
        with self.assertRaises(ValueError):
            verify_certificate('Signer #1 certificate SHA-256 digest: abcd')

    def test_duplicate_zip_entries_rejected(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as target:
            target.writestr('assets/data.json', b'first')
            with self.assertWarns(UserWarning):
                target.writestr('assets/data.json', b'second')
        with zipfile.ZipFile(buffer) as archive, self.assertRaises(ValueError):
            verify_assets(archive)

    def elf(self, alignment=16384, address=0, offset=0, file_size=120, memory_size=120):
        data = bytearray(120)
        data[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<H', data, 18, 183)
        struct.pack_into('<Q', data, 32, 64)
        struct.pack_into('<HH', data, 54, 56, 1)
        struct.pack_into('<IIQQQQQQ', data, 64, 1, 5, offset, address, 0,
                         file_size, memory_size, alignment)
        return data

    def test_valid_16kb_elf(self):
        verify_elf(self.elf(), 'valid.so')

    def test_elf_alignment_and_bounds_rejected(self):
        invalid = [self.elf(alignment=4096), self.elf(alignment=20000),
                   self.elf(address=1), self.elf(file_size=121),
                   self.elf(memory_size=119), b'\x7fELF\x02\x01']
        for data in invalid:
            with self.subTest(data=data[:8]), self.assertRaises(ValueError):
                verify_elf(data, 'invalid.so')
