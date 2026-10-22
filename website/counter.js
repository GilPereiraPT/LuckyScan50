'use strict';
(async () => {
  const target = document.getElementById('visit-count');
  if (!target) return;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch('https://luckyscan50-api.policlinicosdesantoandre.com/v1/website/visits', {
      method: 'POST',
      mode: 'cors',
      credentials: 'omit',
      cache: 'no-store',
      referrerPolicy: 'no-referrer',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({event: 'pageview'}),
      signal: controller.signal
    });
    if (!response.ok) throw new Error('Counter unavailable');
    const data = await response.json();
    if (!Number.isSafeInteger(data.total) || data.total < 1) throw new Error('Invalid total');
    target.textContent = new Intl.NumberFormat('pt-PT').format(data.total);
    target.setAttribute('title', 'Total de aberturas da página desde a ativação do contador.');
  } catch (_) {
    target.textContent = 'Indisponível';
    target.setAttribute('title', 'Não foi possível consultar o contador. O restante site continua disponível.');
  } finally {
    clearTimeout(timeout);
  }
})();
