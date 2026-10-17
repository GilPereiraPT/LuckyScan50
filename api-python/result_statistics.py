"""Descriptive statistics over the supplied draws, never predictions."""
from collections import Counter


def frequencies(rows, field):
    # Key confirmation does not require publication of all monetary prize tiers.
    draws=[r for r in rows if r['game']=='euromilhoes' and r['status'] in ('complete','numbers_confirmed')]
    maximum=50 if field=='numbers' else 12
    result=[]
    for number in range(1,maximum+1):
        eligible=[r for r in draws if field=='numbers' or number<=star_limit(r['date'])]
        occurrences=[(i,r) for i,r in enumerate(eligible) if number in r[field]]
        last=occurrences[-1] if occurrences else None
        result.append({'value':number,'count':len(occurrences),'eligibleDraws':len(eligible),
                       'lastDate':last[1]['date'] if last else None,
                       'drawsSinceLast':len(eligible)-1-last[0] if last else None})
    return {'data':result,'drawCount':len(draws),'scope':'stored_confirmed_keys','prediction':False}


def star_limit(day):
    return 9 if day<'2011-05-10' else 11 if day<'2016-09-27' else 12


def summary(rows):
    draws=[r for r in rows if r['game']=='euromilhoes' and r['status'] in ('complete','numbers_confirmed')]
    monthly=Counter(r['date'][:7] for r in draws)
    combinations=Counter(tuple(sorted(r['numbers']))+tuple(sorted(r['stars'])) for r in draws)
    return {'drawCount':len(draws),'firstDate':draws[0]['date'] if draws else None,
            'lastDate':draws[-1]['date'] if draws else None,
            'byMonth':dict(sorted(monthly.items())),
            'oddNumbers':sum(n%2 for r in draws for n in r['numbers']),
            'evenNumbers':sum(n%2==0 for r in draws for n in r['numbers']),
            'byDecade':{str(start):sum(start<=n<=start+9 for r in draws for n in r['numbers']) for start in (1,11,21,31,41)},
            'repeatedCombinations':[{'numbers':list(k[:5]),'stars':list(k[5:]),'count':v} for k,v in sorted(combinations.items()) if v>1],
            'scope':'stored_confirmed_keys','prediction':False}
