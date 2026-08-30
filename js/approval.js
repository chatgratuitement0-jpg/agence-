import { supabase } from './supabase.js';

export async function loadPendingApprovals(container) {
  const { data, error } = await supabase
    .from('sales_agent_tasks')
    .select('id,lead_id,task_type,status,payload,created_at')
    .eq('status','waiting_approval')
    .order('created_at',{ ascending:false });

  if (error) throw error;
  container.innerHTML = '';

  for (const task of data || []) {
    const draft = task.payload?.draft?.message || task.payload?.draft?.text || '';
    const card = document.createElement('article');
    card.className = 'approval-card';
    card.innerHTML = `
      <div class="approval-card__type">${escapeHtml(task.task_type)}</div>
      <div class="approval-card__message">${escapeHtml(draft || 'Action requires your approval.')}</div>
      <div class="approval-card__actions">
        <button data-action="approve" data-id="${task.id}">Approve</button>
        <button data-action="reject" data-id="${task.id}">Reject</button>
      </div>`;
    container.appendChild(card);
  }

  container.onclick = async (event) => {
    const button = event.target.closest('button[data-action]');
    if (!button) return;
    const id = button.dataset.id;
    const action = button.dataset.action;
    const nextStatus = action === 'approve' ? 'completed' : 'cancelled';
    const { error: updateError } = await supabase
      .from('sales_agent_tasks')
      .update({ status: nextStatus, completed_at: new Date().toISOString() })
      .eq('id', id)
      .eq('status', 'waiting_approval');
    if (updateError) throw updateError;
    await loadPendingApprovals(container);
  };
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[ch]));
}
