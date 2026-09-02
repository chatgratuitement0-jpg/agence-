import { authConfigured, signUp, signIn, getCurrentSession } from './auth.js';
import { supabase } from './supabase.js';

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

function renderSignup() {
  const card = document.querySelector('.auth-card');
  if (!card) return;

  card.innerHTML = `<div class="brand centered"><div class="brand-mark">AI</div><div><strong>AI Agency</strong><span>CRM / OS</span></div></div><div class="eyebrow">FIRST ACCOUNT</div><h1>Create your workspace account</h1><p>The first account can access the CRM and its AI Agent.</p><div id="auth-config"></div><form id="signup-form"><label>Full name<input type="text" name="full_name" required autocomplete="name"></label><label>Email<input type="email" name="email" required autocomplete="email"></label><label>Password<input type="password" name="password" required minlength="8" autocomplete="new-password"></label><button class="btn btn-primary" type="submit">Create account</button><button class="btn btn-ghost" id="back-to-login" type="button">Back to sign in</button><div id="login-error" class="form-error"></div></form>`;

  if (!authConfigured()) {
    document.querySelector('#auth-config').innerHTML = '<div class="alert alert-warn">Supabase is not configured. Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY.</div>';
    document.querySelector('#signup-form button[type="submit"]').disabled = true;
    return;
  }

  document.querySelector('#back-to-login').onclick = () => location.reload();
  document.querySelector('#signup-form').onsubmit = async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const data = new FormData(form);
    const button = form.querySelector('button[type="submit"]');
    const error = document.querySelector('#login-error');
    button.disabled = true;
    button.textContent = 'Creating account…';
    error.textContent = '';

    try {
      const result = await signUp(data.get('email'), data.get('password'), data.get('full_name'));
      if (result.error) throw result.error;

      if (result.data?.session) {
        error.className = 'form-error';
        error.textContent = 'Account created. Opening your CRM…';
        await sleep(700);
        location.reload();
        return;
      }

      error.className = 'form-error';
      error.textContent = 'Account created. Check your email to confirm the account, then sign in.';
      button.disabled = false;
      button.textContent = 'Create account';
    } catch (err) {
      error.className = 'form-error';
      error.textContent = err?.message || 'Unable to create account.';
      button.disabled = false;
      button.textContent = 'Create account';
    }
  };
}

function attachSignupEntry() {
  const form = document.querySelector('#login-form');
  if (!form || document.querySelector('#signup-entry')) return;

  const button = document.createElement('button');
  button.type = 'button';
  button.id = 'signup-entry';
  button.className = 'btn btn-ghost';
  button.textContent = 'Create first account';
  button.style.width = '100%';
  button.style.marginTop = '8px';
  button.onclick = renderSignup;
  form.appendChild(button);
}

const observer = new MutationObserver(attachSignupEntry);
observer.observe(document.body, { childList: true, subtree: true });
attachSignupEntry();
