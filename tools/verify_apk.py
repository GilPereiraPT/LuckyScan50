#!/usr/bin/env python3
"""Validate the actual ARM64 test artifact; requires Android SDK build-tools."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import zipfile


def verify_assets(archive):
    root = Path(__file__).resolve().parents[1] / 'app/assets/branding'
    allowed = {f'assets/flutter_assets/assets/branding/{name}': root / name
               for name in ('luckyscan50-logo.webp', 'luckyscan50-banner.webp')}
    for name in archive.namelist():
        if name in allowed:
            if archive.read(name) != allowed[name].read_bytes():
                raise ValueError('Modified branding asset: ' + name)
        elif ('private_receipts/' in name or name.endswith('.traineddata') or
              (name.startswith('assets/') and name.lower().endswith(('.jpg', '.jpeg', '.png', '.webp', '.heic')))):
            raise ValueError('Private/test or unsupported OCR asset: ' + name)


def verify_certificate(output, expected=None, require_private=False):
    match = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]+)', output)
    if not match:
        raise ValueError('Missing signing certificate digest')
    digest = match[1].lower()
    if require_private and ('android debug' in output.lower() or digest ==
            '0695a638827b0ffa1725698204080edd8b76d65971cbe30ff2d5219d2d0ee860'):
        raise ValueError('Debug signing certificate is forbidden')
    if expected and digest != expected.lower().replace(':', ''):
        raise ValueError('APK signing certificate differs from configured private key')
    return digest


def verify(apk, build_tools, expected=None, require_private=False):
    apk=apk.resolve()
    if not apk.is_file() or apk.stat().st_size==0:
        raise ValueError('APK missing or empty')
    with zipfile.ZipFile(apk) as archive:
        bad=archive.testzip()
        if bad:
            raise ValueError('ZIP CRC mismatch: '+bad)
        names=archive.namelist()
        if not {'AndroidManifest.xml','classes.dex'}.issubset(names):
            raise ValueError('Missing Android manifest or bytecode')
        verify_assets(archive)
        inventory = [{'path': n, 'bytes': archive.getinfo(n).file_size,
                      'compressedBytes': archive.getinfo(n).compress_size,
                      'sha256': hashlib.sha256(archive.read(n)).hexdigest()}
                     for n in names if n.startswith(('lib/', 'assets/'))]
        libraries=[n for n in names if n.startswith('lib/') and n.endswith('.so')]
        if 'lib/arm64-v8a/libflutter.so' not in libraries:
            raise ValueError('Missing Flutter ARM64 engine')
        if any(n.split('/')[1]!='arm64-v8a' for n in libraries):
            raise ValueError('Unexpected ABI in ARM64 artifact')
        for name in libraries:
            data=archive.read(name)
            if data[:6]!=b'\x7fELF\x02\x01':
                raise ValueError('Expected little-endian ELF64: '+name)
            if struct.unpack_from('<H',data,18)[0] != 183:
                raise ValueError('Native library is not AArch64: '+name)
            offset=struct.unpack_from('<Q',data,32)[0]
            size,count=struct.unpack_from('<HH',data,54)
            loads=0
            for index in range(count):
                header=struct.unpack_from('<IIQQQQQQ',data,offset+index*size)
                if header[0]==1:
                    loads+=1
                    if header[-1]<16384:
                        raise ValueError('ELF LOAD alignment below 16 KB: '+name)
            if not loads:
                raise ValueError('No ELF LOAD segments: '+name)
    outputs={}
    for label,command in [
        ('signature',[str(build_tools/'apksigner'),'verify','--verbose','--print-certs',str(apk)]),
        ('zipAlignment',[str(build_tools/'zipalign'),'-c','-P','16','4',str(apk)]),
        ('package',[str(build_tools/'aapt'),'dump','badging',str(apk)]),
    ]:
        result=subprocess.run(command,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=True)
        outputs[label]=result.stdout
    if "package: name='com.gilpereira.luckyscan50'" not in outputs['package']:
        raise ValueError('Unexpected application ID')
    version=re.search(r"versionName='([^']+)'",outputs['package'])
    certificate=verify_certificate(outputs['signature'], expected, require_private)
    report={'apk':apk.name,'bytes':apk.stat().st_size,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),
            'versionName':version[1] if version else None,'abi':'arm64-v8a',
            'signatureVerified':True,'certificateSha256':certificate,
            'nativeLibraries':len(libraries),'packagedFiles':inventory,'elf16KbAligned':True,'zip16KbAligned':True,
            'realPhotoOcrValidated':False}
    target=apk.with_suffix('.verification.json')
    target.write_text(json.dumps(report,indent=2)+'\n')
    apk.with_suffix('.apk.sha256').write_text(report['sha256']+'  '+apk.name+'\n')
    print(json.dumps(report,indent=2))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk',type=Path)
    parser.add_argument('--build-tools',required=True,type=Path)
    parser.add_argument('--expected-certificate-sha256')
    parser.add_argument('--require-private-signature', action='store_true')
    args=parser.parse_args()
    try:
        verify(args.apk,args.build_tools,args.expected_certificate_sha256,args.require_private_signature)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        detail = str(error)
        if isinstance(error, subprocess.CalledProcessError):
            detail += ': ' + (error.stdout or '')[-1500:]
        # GitHub annotations remain visible when detailed logs require login.
        # These tools process only the generated APK, never signing secrets.
        detail = detail.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        print('::error::APK verification failed: ' + detail, flush=True)
        raise

if __name__=='__main__':
    main()
