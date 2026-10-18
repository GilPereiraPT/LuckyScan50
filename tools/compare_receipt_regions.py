#!/usr/bin/env python3
"""Offline Tesseract prototype for explicitly delimited numeric receipt regions.

Manifest rows supply separate number/star crops and optional real ML Kit output.
Ground truth is used only for scoring. Nothing is sent to the application/API.
This desktop experiment cannot establish Android speed, memory or APK impact.
"""
import argparse
import csv
import io
import json
from pathlib import Path
import re
import subprocess
import time


def recognize(path):
    start=time.perf_counter()
    process=subprocess.run(['tesseract',str(path),'stdout','-l','eng','--psm','7',
        '-c','tessedit_char_whitelist=0123456789','tsv'],text=True,
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30,check=True)
    elapsed=(time.perf_counter()-start)*1000
    observations=[]
    values=[]
    for row in csv.DictReader(io.StringIO(process.stdout),delimiter='\t'):
        token=row.get('text','').strip()
        if not token:
            continue
        observations.append({'raw':token,'confidence':float(row['conf']),
            'box':{k:int(row[k]) for k in ('left','top','width','height')}})
        if re.fullmatch(r'\d{1,2}',token):
            values.append(int(token))
        else:
            # Preserve an unsegmented long token; do not split it using truth.
            values.append(None)
    return {'values':values,'observations':observations,'elapsedMs':elapsed}


def score(numbers,stars,truth):
    n=truth['numbers']
    e=truth['stars']
    if (len(n)!=5 or len(e)!=2 or any(type(v)is not int for v in n+e)
            or len(set(n))!=5 or len(set(e))!=2
            or any(not 1<=v<=50 for v in n) or any(not 1<=v<=12 for v in e)):
        raise ValueError('Invalid ground truth; no values may be invented')
    main=sum(i<len(numbers) and numbers[i]==v for i,v in enumerate(n))
    extra=sum(i<len(stars) and stars[i]==v for i,v in enumerate(e))
    return {'correctNumbers':main,'totalNumbers':5,'correctStars':extra,'totalStars':2,
            'completeCorrect':main==5 and extra==2 and len(numbers)==5 and len(stars)==2}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest',type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    manifest=json.loads(args.manifest.read_text())
    rows=manifest.get('rows',[])
    if not rows:
        parser.error('Provide real cropped number/star images; empty benchmarks are invalid')
    report=[]
    for row in rows:
        crops={}
        for kind in ('numbers','stars'):
            path=(args.manifest.parent/row[kind+'Image']).resolve()
            if not path.is_file():
                parser.error('A real region image is missing')
            crops[kind]=recognize(path)
        result={'orientation':row['orientation'],'bet':row['bet'],'tesseract':crops,
            'score':score(crops['numbers']['values'],crops['stars']['values'],row['truth'])}
        if 'mlkit' in row:
            result['mlkitProvided']=row['mlkit']
            result['mlkitScore']=score(row['mlkit']['numbers'],row['mlkit']['stars'],row['truth'])
        report.append(result)
    output={'engine':'tesseract desktop --psm 7 / numeric whitelist','rows':report,
        'rowsMeasured':len(report),'androidValidated':False,'apkImpact':'not measured',
        'latencyWarning':'Desktop latency is not comparable to Android ML Kit latency.',
        'source':'real region files supplied in manifest; no synthetic fallback'}
    args.output.write_text(json.dumps(output,indent=2)+'\n')

if __name__=='__main__':
    main()
