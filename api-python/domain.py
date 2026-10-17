"""Shared result validation. Amounts are integer euro cents, never floats."""
from datetime import date, datetime
import re
from urllib.parse import urlsplit

TIERS = ((5,2),(5,1),(5,0),(4,2),(4,1),(3,2),(4,0),(2,2),(3,1),(3,0),(1,2),(2,1),(2,0))
GAMES = ('euromilhoes', 'milhao')


def integer(value, name, maximum=None):
    if type(value) is not int or value < 0 or (maximum is not None and value > maximum):
        raise ValueError('Invalid ' + name)


def validate_result(row):
    if not isinstance(row, dict) or row.get('game') not in GAMES:
        raise ValueError('Invalid game')
    if not re.fullmatch(r'\d{3}/\d{4}', str(row.get('drawId', ''))):
        raise ValueError('Invalid draw')
    try:
        draw_date = date.fromisoformat(row['date'])
        retrieved = datetime.fromisoformat(row['retrievedAt'].replace('Z', '+00:00'))
        if row['date'] != draw_date.isoformat() or retrieved.tzinfo is None:
            raise ValueError('Dates must be ISO dates and timezone-aware timestamps')
        source = urlsplit(row['sourceUrl'])
        if source.scheme != 'https' or not source.hostname or source.username or source.password:
            raise ValueError('Invalid source')
    except (KeyError, TypeError, AttributeError, ValueError) as exc:
        raise ValueError('Invalid dates or source') from exc
    if int(row['drawId'][-4:]) != draw_date.year:
        raise ValueError('Draw year does not match date')
    if row.get('status') not in ('complete', 'numbers_confirmed'):
        raise ValueError('Invalid status')
    if row['game'] == 'milhao':
        if not re.fullmatch(r'[A-Z]{3} ?\d{5}', str(row.get('winningCode', ''))):
            raise ValueError('Invalid Milhao code')
        # Legacy records without this field remain readable, but no prize is inferred.
        if row.get('amountCents') is not None:
            integer(row['amountCents'], 'amountCents')
        return
    for field, count, maximum in (('numbers',5,50), ('stars',2,12)):
        values = row.get(field)
        if (not isinstance(values, list) or len(values) != count
                or any(type(v) is not int or not 1 <= v <= maximum for v in values)
                or len(set(values)) != count):
            raise ValueError('Invalid ' + field)
    tiers = row.get('tiers')
    if not isinstance(tiers, list) or len(tiers) != 13:
        raise ValueError('Expected 13 tiers')
    for index, tier in enumerate(tiers):
        if not isinstance(tier, dict):
            raise ValueError('Invalid tier')
        for name in ('tier', 'main', 'stars'):
            integer(tier.get(name), name)
        if (tier['tier'], tier['main'], tier['stars']) != (index+1, *TIERS[index]):
            raise ValueError('Invalid tier identity')
        for name in ('amountCents', 'winnersPortugal', 'winnersTotal'):
            if name not in tier:
                raise ValueError('Missing ' + name)
            if tier[name] is not None:
                integer(tier[name], name)
        total, portugal = tier['winnersTotal'], tier['winnersPortugal']
        if total is not None and portugal is not None and portugal > total:
            raise ValueError('Portugal winners exceed total')
        if row['status'] == 'complete':
            if total is None or portugal is None:
                raise ValueError('Missing winner counts')
            if total > 0 and (tier['amountCents'] is None or tier['amountCents'] == 0):
                raise ValueError('Missing prize for winners')
            if total == 0 and tier['amountCents'] == 0:
                raise ValueError('Use null for an unawarded prize')


def check_line(draw, numbers, stars):
    validate_result(draw)
    if draw['game'] != 'euromilhoes':
        raise ValueError('Expected Euromilhoes')
    for values, count, maximum in ((numbers,5,50),(stars,2,12)):
        if (not isinstance(values,list) or len(values)!=count
                or any(type(n) is not int or not 1<=n<=maximum for n in values)
                or len(set(values))!=count):
            raise ValueError('Invalid line')
    matches = (len(set(numbers) & set(draw['numbers'])), len(set(stars) & set(draw['stars'])))
    tier = TIERS.index(matches)+1 if matches in TIERS else None
    amount = draw['tiers'][tier-1]['amountCents'] if tier else 0
    return {'mainMatches':matches[0], 'starMatches':matches[1], 'tier':tier,
            'amountCents':amount, 'confirmed':draw['status']=='complete' and amount is not None}
