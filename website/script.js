'use strict';
const menuButton = document.querySelector('.menu-toggle');
const navigation = document.querySelector('#navegacao');
if (menuButton && navigation) {
  menuButton.addEventListener('click', () => {
    const expanded = menuButton.getAttribute('aria-expanded') !== 'true';
    menuButton.setAttribute('aria-expanded', String(expanded));
    navigation.classList.toggle('is-open', expanded);
  });
  navigation.querySelectorAll('a').forEach(link => link.addEventListener('click', () => {
    menuButton.setAttribute('aria-expanded', 'false');
    navigation.classList.remove('is-open');
  }));
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && menuButton.getAttribute('aria-expanded') === 'true') {
      menuButton.setAttribute('aria-expanded', 'false');
      navigation.classList.remove('is-open');
      menuButton.focus();
    }
  });
}
const examples = {
  pending: ['Resultado por confirmar', 'Sem um resultado completo, a app mantém a verificação pendente.'],
  none: ['Verificação concluída · sem prémio', 'Neste exemplo, a aposta não corresponde a um escalão premiado.'],
  prize: ['Prémio identificado', 'Neste exemplo, existe um prémio. Registe o recebimento apenas depois de o ter levantado.']
};
document.querySelectorAll('[data-state]').forEach(button => button.addEventListener('click', () => {
  const example = examples[button.dataset.state];
  if (!example) return;
  document.querySelectorAll('[data-state]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
  document.getElementById('demo-status').textContent = example[0];
  document.getElementById('demo-description').textContent = example[1];
}));
