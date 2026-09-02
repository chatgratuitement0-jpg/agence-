import { supabaseClient } from './db.js';
import { getCurrentUser } from './auth.js';
import { toast, loading, emptyState } from './ui.js';
import { escapeHtml, qs } from './utils.js';

const db = () => supabaseClient();
const esc = v => escapeHtml(v ?? '');

export async function render() {
  const host = qs('#page');
  host.innerHTML = loading('Loading AI settings…');
  try {
    const user = await getCurrentUser();
    if (!user) throw new Error('Authentication required.');

    const r = await db().from('ai_settings').select('*').eq('user_id', user.id).maybeSingle();
    if (r.error) throw r.error;
    const x = r.data || {};

    host.innerHTML = `<div class="module-head"><div><span class="eyebrow">AI / SETTINGS</span><h2>AI Settings</h2><p>Control how the internal AI engine behaves. No API keys are stored in the browser.</p></div></div>
    <section class="card"><form class="form-grid" id="ai-settings-form">
      <label>AI enabled<select name="enabled"><option value="true" ${x.enabled !== false ? 'selected' : ''}>Yes</option><option value="false" ${x.enabled === false ? 'selected' : ''}>No</option></select></label>
      <label>Model<input name="model" maxlength="120" value="${esc(x.model || '')}" placeholder="Configured server-side"></label>
      <label>Auto reply<select name="auto_reply"><option value="false" ${x.auto_reply !== true ? 'selected' : ''}>No</option><option value="true" ${x.auto_reply === true ? 'selected' : ''}>Yes</option></select></label>
      <label>Qualification engine<select name="qualification_enabled"><option value="true" ${x.qualification_enabled !== false ? 'selected' : ''}>Enabled</option><option value="false" ${x.qualification_enabled === false ? 'selected' : ''}>Disabled</option></select></label>
      <label>Lead scoring<select name="scoring_enabled"><option value="true" ${x.scoring_enabled !== false ? 'selected' : ''}>Enabled</option><option value="false" ${x.scoring_enabled === false ? 'selected' : ''}>Disabled</option></select></label>
      <label class="full">System prompt<textarea name="system_prompt" maxlength="20000" placeholder="Optional global instructions for the future server-side AI provider">${esc(x.system_prompt || '')}</textarea></label>
      <div class="alert alert-warn full">Safety mode: CRM-changing AI actions still require a server-validated decision and human approval. External AI providers are not connected yet.</div>
      <div class="form-actions"><button class="btn btn-primary" type="submit">Save settings</button></div>
    </form></section>`;

    qs('#ai-settings-form').onsubmit = async e => {
      e.preventDefault();
      const button = e.currentTarget.querySelector('button[type="submit"]');
      button.disabled = true;
      try {
        const f = new FormData(e.currentTarget);
        const payload = {
          user_id: user.id,
          enabled: f.get('enabled') === 'true',
          model: String(f.get('model') || '').trim() || null,
          system_prompt: String(f.get('system_prompt') || '').trim() || null,
          auto_reply: f.get('auto_reply') === 'true',
          qualification_enabled: f.get('qualification_enabled') === 'true',
          scoring_enabled: f.get('scoring_enabled') === 'true'
        };
        const saved = await db().from('ai_settings').upsert(payload, { onConflict: 'user_id' }).select().single();
        if (saved.error) throw saved.error;
        toast('AI settings saved', 'success');
      } catch (err) {
        toast(err.message || 'Unable to save AI settings', 'error');
      } finally {
        button.disabled = false;
      }
    };
  } catch (e) {
    host.innerHTML = emptyState('AI settings unavailable', e.message);
  }
}
