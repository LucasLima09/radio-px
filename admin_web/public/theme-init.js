// Aplicado antes do primeiro paint para evitar flash de tema.
// Servido como arquivo externo (script-src 'self') para respeitar a CSP do backend.
(function () {
  try {
    var saved = localStorage.getItem('radio_px_admin_theme');
    var dark = saved
      ? saved === 'dark'
      : window.matchMedia('(prefers-color-scheme: dark)').matches;
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  } catch (e) {
    document.documentElement.dataset.theme = 'light';
  }
})();
