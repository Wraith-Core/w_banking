/* w_banking · the bank counter. Lua opens it (status 'openbank' with the account and the page's words), the page
   draws and asks; every money move goes back through a NUI callback and the server decides.
   2.1.0: drawn on the board kit (index.html + bank.css): the services are tabs, the main action is the red band in
   the actions strip, the review is the kit's paper note. The messages and callbacks are unchanged. */
(() => {
'use strict';
const $=s=>document.querySelector(s), bank=$('#bank'), panel=$('#panel'), note=$('#confirm');
let info={}, lang='ar', tab='account', busy=false, generation=0, bankName='';
let words={};
function readWords(data){if(data.strings&&typeof data.strings==='object')words=data.strings;}

const t=k=>words['nui.'+k]||words['ui.'+k]||k;
const money=n=>'$ '+Number(String(n??0).replace(/[^0-9.-]/g,'')||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const text=(s,v)=>$(s).textContent=v;
// a figure or an account inside a sentence: kept left to right in Arabic ("$ 25.00", never "25.00 $")
const iso=v=>'⁦'+v+'⁩';
const TABS=['account','deposit','withdraw','transfer','savings','history'];
const GLYPH_NEXT='<svg class="wf-glyph" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9.1 4.9l7.2 7.05-7.15 7.1"/></svg>';
async function post(action,data={}) {
 const response=await fetch('https://'+(window.GetParentResourceName?.()||'w_banking')+'/'+action,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...data,requestKey:data.requestKey||crypto.randomUUID()})});
 if(!response.ok)throw Error('request'); return response.json();
}
// the status line under the tabs: a plain line, or the kit's error (a red mark before it)
function notice(message,error=false){text('#notice',message);$('#notice').className=error?'wf-error bk-notice':'wf-note-line bk-notice';$('#notice').hidden=false;}
function setBusy(value){busy=value;bank.setAttribute('aria-busy',String(value));bank.querySelectorAll('button,input').forEach(b=>b.disabled=value);}
function description(row){const d=String(row.type||'');const map={'Cash deposit':'cashDeposit','Cash withdrawal':'cashWithdrawal','To savings':'toSavings','From savings':'fromSavings','Bank to savings':'toSavings','Savings to bank':'fromSavings'};if(map[d])return t(map[d]);if(d.startsWith('Transfer to '))return t('transferTo')+' '+d.slice(12);if(d.startsWith('Transfer from '))return t('from')+' '+d.slice(14);return d;}
// a sentence with {name} slots; each value is escaped, figures and accounts kept left to right
const say=(k,v={})=>esc(t(k)).replace(/\{(\w+)\}/g,(_,n)=>v[n]==null?'':v[n]);
const fig=v=>'<b class="wf-num bk-inl bk-ltr">'+esc(v)+'</b>';
const who=v=>'<b class="bk-who bk-ltr">'+esc(v)+'</b>';

/* a statement row as what the player did, in his words (2026-11-12): «حوّلت $ 50.00 إلى 10030» */
function sentence(row){
 const d=String(row.type||''),a=fig(money(Number(row.deposited)||Number(row.withdraw))),plus=Number(row.deposited)>0;
 if(d==='Cash deposit')return say('h_deposit',{a});
 if(d==='Cash withdrawal')return say('h_withdraw',{a});
 if(d==='To savings'||d==='Bank to savings')return say('h_toSavings',{a});
 if(d==='From savings'||d==='Savings to bank')return say('h_fromSavings',{a});
 if(d.startsWith('Transfer to '))return say('h_to',{a,who:who(d.slice(12))});
 if(d.startsWith('Transfer from '))return say('h_from',{a,who:who(d.slice(14))});
 return say(plus?'h_in':'h_out',{a,what:esc(d)});
}
// «اليوم 14:20» / «أمس 19:45» / «8 نوفمبر» from the server's 'YYYY-MM-DD HH:MM:SS'; the raw text if it is not that
function when(raw){
 const m=/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?/.exec(String(raw||''));if(!m)return esc(raw);
 const at=new Date(+m[1],+m[2]-1,+m[3]),now=new Date(),today=new Date(now.getFullYear(),now.getMonth(),now.getDate());
 const days=Math.round((today-at)/864e5),clock=m[4]?' '+iso(m[4]+':'+m[5]):'';
 if(days===0)return esc(t('today')+clock);if(days===1)return esc(t('yesterday')+clock);
 try{return esc(at.toLocaleDateString(lang==='ar'?'ar-SA-u-ca-gregory-nu-latn':'en-GB',{day:'numeric',month:'long'}));}catch{return esc(m[1]+'-'+m[2]+'-'+m[3]);}
}

/* the statement: one ruled line per transaction, a sentence and when (the kit's rows, no boxes) */
function history(){
 const rows=Array.isArray(info.history)?info.history:[];
 if(!rows.length)return '<p class="wf-empty">'+t('empty')+'</p>';
 return '<div class="bk-hist">'+rows.map(r=>{const plus=Number(r.deposited)>0;return '<div class="bk-hist-line" title="'+esc(description(r)+' · '+r.date)+'"><span class="bk-desc"><span class="bk-desc-name">'+sentence(r)+'</span><span class="bk-desc-acc">'+when(r.date)+' · '+esc(t(r.account==='Savings'?'saved':'balance'))+' · '+say('h_after',{b:fig(money(r.balance))})+'</span></span><span class="wf-num bk-change'+(plus?' is-in':'')+'">'+(plus?'+ ':'− ')+money(Number(r.deposited)||Number(r.withdraw))+'</span></div>';}).join('')+'</div>';
}

/* the readiness line under a money form (2026-11-12, the builders' notebook): what is still missing, with «أصلحه»
   going to that field; once filled, what will happen in one sentence. The same checks as submit() below, which
   stays the one that decides (and the server after it). */
function readiness(){
 const form=$('#transaction'),line=$('#ready');if(!form||!line)return;
 const amount=Number(form.amount.value),cents=Math.round(amount*100),missing=[];
 if(tab==='transfer'&&!form.account.value.trim())missing.push(['account','f_recipient']);
 if(!form.amount.value.trim())missing.push(['amount','f_amount']);
 let html='',bad=false;
 if(missing.length){bad=true;html='<span>'+say('missing',{list:missing.map(m=>esc(t(m[1]))).join(lang==='ar'?'، ':', ')})+'</span><button type="button" class="wf-act bk-fix" data-fix="'+missing[0][0]+'">'+esc(t('fix'))+'</button>';}
 else if(!Number.isFinite(amount)||!Number.isSafeInteger(cents)||cents<1||Math.abs(amount*100-cents)>0.000001||amount>1e9){bad=true;html='<span>'+esc(t('invalid'))+'</span><button type="button" class="wf-act bk-fix" data-fix="amount">'+esc(t('fix'))+'</button>';}
 else{
  const action=tab==='savings'?'savingsDeposit':{deposit:'doDeposit',withdraw:'doWithdraw',transfer:'doTransfer'}[tab];
  const fee=Math.round(amount*Number(info.taxRate||0))/100,have=Math.round(available(action)*100);
  if(tab!=='savings'&&cents+Math.round(fee*100)>have){bad=true;html='<span>'+say('r_over',{v:fig(money(available(action)))})+'</span><button type="button" class="wf-act bk-fix" data-fix="amount">'+esc(t('fix'))+'</button>';}
  else{
   const a=fig(money(amount));
   html='<span>'+(tab==='transfer'?say('r_transfer',{a,who:who(form.account.value.trim())}):say('r_'+tab,{a}))+(fee>0?' '+say('r_fee',{f:fig(money(fee)),t:fig(money(amount+fee))}):'')+'</span>';
  }
 }
 line.innerHTML='<i class="bk-dot'+(bad?' is-bad':'')+'" aria-hidden="true"></i>'+html;
}

/* the actions strip: the open page's main action is the red band (a submit of the page's form), the way to the
   central bank and the key hint after it */
function actions(){
 let main='';
 if(tab==='savings'&&!info.savings)main='<button type="button" id="openSavings" class="bk-main">'+t('openSavings')+'</button>';
 else if(tab==='savings')main='<button type="submit" form="transaction" name="operation" value="savingsDeposit" class="bk-main">'+t('toSavings')+'</button><button type="submit" form="transaction" name="operation" value="savingsWithdraw" class="wf-act">'+t('fromSavings')+'</button>';
 else if(tab==='deposit'||tab==='withdraw'||tab==='transfer')main='<button type="submit" form="transaction" class="bk-main">'+t('submit')+'</button>';
 const form=tab==='deposit'||tab==='withdraw'||tab==='transfer'||(tab==='savings'&&info.savings);
 const keys=[form?['Enter',t('k_enter')]:null,['Esc',t('k_esc')]].filter(Boolean);
 $('#actions').innerHTML=main+'<button type="button" id="central" class="wf-act">'+t('central')+'</button><span class="bk-keys">'+keys.map(([k,l])=>'<span><span class="bk-key">'+esc(k)+'</span>'+esc(l)+'</span>').join('')+'</span>';
}

function render(){
 const rtl=lang==='ar';
 document.documentElement.lang=lang;document.documentElement.dir=rtl?'rtl':'ltr';
 bank.dir=rtl?'rtl':'ltr';bank.classList.toggle('is-rtl',rtl);
 text('#brand',t('brand'));
 text('#ownerLabel',t('owner'));text('#owner',info.name||'');text('#numberLabel',t('number'));text('#number',info.accountinfo||'—');
 text('#bankLabel',t('balance'));text('#cashLabel',t('cash'));text('#balanceNote',t('available'));
 text('#balance',money(info.bankbalance));text('#cash',money(info.cash));
 // the page's first sentence (2026-11-12): «رصيدك $ 1,240.00 في بنك فالنتاين · معك $ 85.00 نقدًا»
 $('#sum').innerHTML=say('sum',{balance:fig(money(info.bankbalance)),bank:'<b class="bk-who">'+esc(bankName||t('sumBank'))+'</b>',cash:fig(money(info.cash))})+(info.savings?' '+say('sumSaved',{saved:fig(money(info.savings.amount))}):'');
 $('#refresh').ariaLabel=t('refresh');$('#refresh').title=t('refresh');$('#close').ariaLabel=t('close');$('#close').title=t('close');
 $('#nav').innerHTML=TABS.map(k=>'<button type="button" data-tab="'+k+'" class="wf-tab'+(k===tab?' is-active':'')+'" aria-current="'+(k===tab?'page':'false')+'">'+t(k)+'</button>').join('');
 const w=$('#workspace');w.scrollTop=0;
 const tax=Number(info.taxRate)>0?'<span class="wf-num">'+esc(info.taxRate)+'%</span>':'';
 if(tab==='account')w.innerHTML='<div class="bk-welcome"><h2 class="bk-h2">'+esc(t('welcome')+(info.name||''))+'</h2><p class="wf-note-line">'+t('overviewNote')+'</p></div>'
  +'<div class="bk-figs">'+[['balance',info.bankbalance],['cash',info.cash],['saved',info.savings?info.savings.amount:null]].map(([k,v])=>'<div class="bk-figcell"><span class="wf-label">'+t(k)+'</span><strong class="bk-fig is-mid">'+(v==null?'—':money(v))+'</strong></div>').join('')+'</div>'
  +'<div class="wf-sec">'+t('overview')+'</div><div class="wf-rows bk-quick">'+['deposit','withdraw','transfer','savings'].map(k=>'<button type="button" class="wf-row bk-row" data-tab="'+k+'"><span class="wf-row-main"><span class="wf-row-name">'+t(k)+'</span><span class="wf-row-meta">'+t(k+'Note')+'</span></span><span class="wf-row-state wf-flip">'+GLYPH_NEXT+'</span></button>').join('')+'</div>'
  +'<details class="bk-fold"><summary class="wf-sec bk-fold-head">'+esc(t('advanced'))+'</summary><div class="bk-fold-body">'
  +'<p class="wf-note-line">'+esc(t('adv_number'))+': <b class="wf-num bk-inl bk-ltr">'+esc(info.accountinfo||'—')+'</b></p>'
  +'<p class="wf-note-line">'+(tax?esc(t('transactionTax'))+': '+tax:esc(t('adv_noTax')))+'</p>'
  +'<p class="wf-note-line">'+esc(t('note'))+'</p></div></details>';
 else if(tab==='history')w.innerHTML='<p class="wf-note-line">'+t('historyNote')+'</p>'+history();
 else if(tab==='savings'&&!info.savings)w.innerHTML='<div class="bk-welcome"><h2 class="bk-h2">'+t('noSavings')+'</h2><p class="wf-note-line">'+t('openNote')+'</p></div>';
 else{
  const from=tab==='deposit'?'cash':tab==='savings'?'saved':'balance';
  const avail=tab==='deposit'?info.cash:tab==='savings'?(info.savings?info.savings.amount:0):info.bankbalance;
  w.innerHTML='<form id="transaction" class="bk-form" autocomplete="off"><h2 class="bk-h2">'+t(tab)+'</h2><p class="wf-note-line">'+t(tab+'Note')+'</p><div class="wf-grid">'
   +(tab==='transfer'?'<label class="wf-field is-wide"><span class="wf-label">'+t('recipient')+'</span><input class="wf-input" name="account" required maxlength="64" autocomplete="off" spellcheck="false" placeholder="'+esc(t('recipientHint'))+'"></label>':'')
   +'<label class="wf-field"><span class="wf-label">'+t('amount')+'</span><input class="wf-input is-num" name="amount" aria-label="'+t('amount')+'" required type="number" min="0.01" max="1000000000" step="0.01" placeholder="0" inputmode="decimal"></label>'
   +'<div class="wf-field"><span class="wf-label">'+t(from)+'</span><strong class="bk-fig is-small">'+money(avail)+'</strong></div>'
   +'</div><div class="wf-btns bk-chips">'+[10,50,100,500].map(n=>'<button type="button" class="wf-btn" data-amount="'+n+'"><span class="wf-num">$ '+n+'</span></button>').join('')+'</div>'
   +(tax?'<p class="wf-note-line bk-tax">'+esc(t('transactionTax'))+': '+tax+'</p>':'')+'<p id="ready" class="bk-ready" aria-live="polite"></p></form>';
 }
 actions();
 readiness();
 setBusy(busy);
}

async function run(action,data={}){
 if(busy)return;const session=generation;setBusy(true);notice(t('working'));
 try{const r=await post(action,data);if(session!==generation)return;if(r.information)info=r.information;setBusy(false);render();notice(r.message||t('failed'),!r.ok);}
 catch{if(session===generation){setBusy(false);notice(t('failed'),true);}}
}
function available(action){return Number(action==='doDeposit'?info.cash:action==='savingsWithdraw'?info.savings?.amount:info.bankbalance)||0;}

/* the paper note: resolves true on the accept choice, false on cancel / Esc / the page closing */
let answer=null, noteAt=1;
function pick(i){noteAt=i;$('#cancelConfirm').classList.toggle('is-here',i===0);$('#acceptConfirm').classList.toggle('is-here',i===1);}
function ask(title,body,accept){
 text('#confirmKicker',t('brand'));text('#confirmTitle',title);text('#confirmText',body);text('#cancelConfirm',t('cancel'));text('#acceptConfirm',accept);
 pick(1);note.hidden=false;panel.classList.add('is-dim');
 return new Promise(resolve=>{answer=resolve;});
}
function settle(yes){if(!answer)return;const r=answer;answer=null;note.hidden=true;panel.classList.remove('is-dim');r(!!yes);}
$('#cancelConfirm').addEventListener('click',()=>settle(false));
$('#acceptConfirm').addEventListener('click',()=>settle(true));
$('#cancelConfirm').addEventListener('mouseenter',()=>pick(0));
$('#acceptConfirm').addEventListener('mouseenter',()=>pick(1));

async function submit(e){
 e.preventDefault();if(busy||answer)return;
 const form=e.target,amount=Number(form.amount.value),action=tab==='savings'?(e.submitter?.value||'savingsDeposit'):{deposit:'doDeposit',withdraw:'doWithdraw',transfer:'doTransfer'}[tab];
 const cents=Math.round(amount*100);if(!Number.isFinite(amount)||!Number.isSafeInteger(cents)||cents<1||Math.abs(amount*100-cents)>0.000001||amount>1e9)return notice(t('invalid'),true);
 if(cents>Math.round(available(action)*100))return notice(t('limit'),true);
 const fee=Math.round(amount*Number(info.taxRate||0))/100;
 if(cents+Math.round(fee*100)>Math.round(available(action)*100))return notice(t('limit'),true);
 const data={amount};if(action==='doTransfer'){
  data.account=form.account.value.trim();if(!data.account)return notice(t('accountError'),true);
  const accepted=await ask(t('review'),iso(money(amount))+'\n'+t('to')+' '+iso(data.account)+(fee>0?'\n'+(t('tax')+': ')+iso(money(fee)):''),t('confirm'));if(!accepted||bank.hidden)return;
 }
 if(action!=='doTransfer'&&fee>0){
  const yes=await ask(t('review'),iso(money(amount))+'\n'+(t('tax')+': ')+iso(money(fee))+'\n'+(t('total')+': ')+iso(money(amount+fee)),t('submit'));if(!yes||bank.hidden)return;
 }
 run(action,data);
}
bank.addEventListener('submit',e=>{if(e.target.id==='transaction')submit(e);});
bank.addEventListener('input',e=>{if(e.target.closest('#transaction'))readiness();});
bank.addEventListener('click',e=>{
 const b=e.target.closest('button');if(!b||busy||answer)return;
 if(b.dataset.tab){tab=b.dataset.tab;$('#notice').hidden=true;render();}
 if(b.dataset.amount){const input=$('[name=amount]');input.value=b.dataset.amount;input.focus();readiness();}
 if(b.dataset.fix){const input=$('[name='+b.dataset.fix+']');if(input){input.focus();input.select?.();}}
 if(b.id==='openSavings')run('createSavingsAccount');
 if(b.id==='central')post('central');
});
async function close(){if(busy||answer)return;generation++;await post('NUIFocusOff').catch(()=>{});bank.hidden=true;}
$('#close').onclick=close;
document.addEventListener('keydown',e=>{
 if(bank.hidden)return;
 if(answer){
  if(e.key==='Escape'){e.preventDefault();settle(false);}
  else if(e.key==='ArrowLeft'||e.key==='ArrowRight'||e.key==='Tab'){e.preventDefault();pick(1-noteAt);}
  else if(e.key==='Enter'){e.preventDefault();settle(noteAt===1);}
  return;
 }
 if(e.key==='Escape'){e.preventDefault();close();}
});
$('#refresh').onclick=async()=>{if(busy||answer)return;const session=generation;setBusy(true);try{const r=await post('refresh');if(session!==generation)return;if(r.information)info=r.information;else notice(t('failed'),true);}catch{if(session===generation)notice(t('failed'),true);}finally{if(session!==generation)return;setBusy(false);render();}};
window.addEventListener('message',({data:d})=>{
 if(!d||typeof d!=='object')return;
 if(d.status==='openbank'){readWords(d);if('bankName' in d||bank.hidden)bankName=typeof d.bankName==='string'?d.bankName:'';generation++;info=d.information||{};lang=d.locale==='en'?'en':'ar';if(bank.hidden)tab='account';busy=false;bank.hidden=false;$('#notice').hidden=true;render();}
 else if(d.status==='closebank'){generation++;busy=false;bank.hidden=true;settle(false);}
 else if(d.status==='setLocale'){readWords(d);lang=d.locale==='en'?'en':'ar';render();}
 else if(d.status==='transferError')notice(d.error,true);else if(d.status==='successMessage')notice(d.message);
});
})();
