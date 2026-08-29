export const escapeHtml=value=>String(value??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
export const qs=(selector,root=document)=>root.querySelector(selector);
export const qsa=(selector,root=document)=>[...root.querySelectorAll(selector)];
export const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
