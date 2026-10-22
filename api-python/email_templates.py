"""Editable plain-text email templates, with restricted named placeholders."""
import json
from pathlib import Path
from string import Formatter

DEFAULTS = {'confirm': {'subject': 'Confirme os avisos do LuckyScan50', 'body': 'Foi pedida uma subscrição de avisos do LuckyScan50 para este endereço.\n\nPara confirmar, abra a ligação e escolha Confirmar:\n{confirm_url}\n\nA ligação é válida por 24 horas. Se não fez este pedido, ignore a mensagem.\n'}, 'results': {'subject': 'LuckyScan50 — resultado {label}', 'body': '{label}\nData: {draw_date}\nChave: {winning_key}\n\nFonte: {source_url}\n'}, 'prizes': {'subject': 'LuckyScan50 — prémio por levantar', 'body': 'Um recibo tem {prize_amount} € em prémios identificados ainda não registados como recebidos.\nAbra a app, confirme o recibo e atualize o recebimento se já levantou o prémio.\n{sync_note}'}, 'expiry': {'subject': 'LuckyScan50 — prazo de levantamento próximo', 'body': 'Concurso: {draw}\nData-limite validada: {deadline}\nFaltam {days_remaining} dia(s). Confirme se já levantou o prémio.\nFonte: {source_url}\n{sync_note}'}}
REQUIRED = {
    'confirm': {'confirm_url'},
    'results': {'label', 'draw_date', 'winning_key', 'source_url'},
    'prizes': {'prize_amount', 'sync_note'},
    'expiry': {'draw', 'deadline', 'days_remaining', 'source_url', 'sync_note'},
}


def render(kind, values, filename=''):
    templates = DEFAULTS
    if filename:
        templates = json.loads(Path(filename).read_text(encoding='utf-8'))
        if not isinstance(templates, dict) or set(templates) != set(DEFAULTS):
            raise ValueError('O ficheiro deve conter os quatro modelos de email.')
    template = templates[kind]
    if not isinstance(template, dict) or set(template) != {'subject', 'body'}:
        raise ValueError('Cada modelo deve conter subject e body.')
    fields = set()
    for key in ('subject', 'body'):
        text = template[key]
        if not isinstance(text, str) or not text.strip() or len(text) > (200 if key == 'subject' else 16000):
            raise ValueError('Modelo de email vazio ou demasiado longo.')
        if key == 'subject' and ('\n' in text or '\r' in text or 'LuckyScan50' not in text):
            raise ValueError('O assunto deve incluir LuckyScan50 e ocupar uma linha.')
        for _, field, spec, conversion in Formatter().parse(text):
            if field is not None:
                if field not in values or spec or conversion:
                    raise ValueError('Campo de email desconhecido ou formato não permitido.')
                fields.add(field)
    body_fields = {field for _, field, _, _ in Formatter().parse(template['body']) if field}
    if not REQUIRED[kind].issubset(body_fields):
        raise ValueError('Faltam campos obrigatórios no corpo do email.')
    return template['subject'].format_map(values), template['body'].format_map(values)
