'use strict';
// Only a user gesture opens the explicitly named package. Never consume the
// recovery token on page load: mail scanners must not invalidate the link.
const token = new URLSearchParams(window.location.search).get('token_hash');
const button = document.getElementById('open-app');
if (token && /^[a-zA-Z0-9_-]{1,300}$/.test(token)) {
  const query = new URLSearchParams({token_hash: token});
  button.href = `intent://nivramop.com/reset-password?${query}#Intent;scheme=https;package=com.nivra.demo;end`;
  button.hidden = false;
} else {
  document.getElementById('help').textContent = 'Este enlace está incompleto. Solicita un nuevo correo desde «Olvidé mi contraseña» en Nivra.';
}
