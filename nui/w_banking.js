(() => {
'use strict';
const $=s=>document.querySelector(s), bank=$('#bank');
let info={}, lang='ar', tab='account', busy=false, generation=0;
let words={};
function readWords(data){if(data.strings&&typeof data.strings==='object')words=data.strings;}

const t=k=>words['nui.'+k]||words['ui.'+k]||k;
const money=n=>'$ '+Number(String(n??0).replace(/[^0-9.-]/g,'')||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const text=(s,v)=>$(s).textContent=v;
// a figure or an account inside a sentence: kept left to right in Arabic ("$ 25.00", never "25.00 $")
const iso=v=>'⁦'+v+'⁩';
async function post(action,data={}) {
 const response=await fetch('https://'+(window.GetParentResourceName?.()||'w_banking')+'/'+action,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...data,requestKey:data.requestKey||crypto.randomUUID()})});
 if(!response.ok)throw Error('request'); return response.json();
}
function notice(message,error=false){text('#notice',message);$('#notice').className=error?'error':'';$('#notice').hidden=false;}
function setBusy(value){busy=value;bank.setAttribute('aria-busy',String(value));bank.querySelectorAll('button,input').forEach(b=>b.disabled=value);}
function description(row){const d=String(row.type||'');const map={'Cash deposit':'cashDeposit','Cash withdrawal':'cashWithdrawal','To savings':'toSavings','From savings':'fromSavings','Bank to savings':'toSavings','Savings to bank':'fromSavings'};if(map[d])return t(map[d]);if(d.startsWith('Transfer to '))return t('transferTo')+' '+d.slice(12);if(d.startsWith('Transfer from '))return t('from')+' '+d.slice(14);return d;}
function history(){const rows=Array.isArray(info.history)?info.history:[];return rows.length?'<div class="table-wrap"><table><thead><tr>'+['date','description','accountCol','change','after'].map(k=>'<th>'+t(k)+'</th>').join('')+'</tr></thead><tbody>'+rows.map(r=>'<tr><td dir="ltr">'+esc(r.date)+'</td><td class="desc">'+esc(description(r))+'</td><td>'+t(r.account==='Savings'?'savings':'balance')+'</td><td dir="ltr" class="'+(Number(r.deposited)>0?'positive':'negative')+'">'+(Number(r.deposited)>0?'+ ':'− ')+money(Number(r.deposited)||Number(r.withdraw))+'</td><td dir="ltr">'+money(r.balance)+'</td></tr>').join('')+'</tbody></table></div>':'<div class="empty">'+t('empty')+'</div>';}
function render(){
 document.documentElement.lang=lang;document.documentElement.dir=lang==='ar'?'rtl':'ltr';
 text('#ownerLabel',t('owner'));text('#owner',info.name||'');text('#numberLabel',t('number'));text('#number',info.accountinfo||'—');
 text('#title',t(tab));text('#bankLabel',t('balance'));text('#cashLabel',t('cash'));text('#savingsLabel',t('saved'));text('#balanceNote',t('available'));
 text('#balance',money(info.bankbalance));text('#cash',money(info.cash));text('#savings',info.savings?money(info.savings.amount):'—');text('#footer',t('footer'));text('#sideNote',t('note')+(Number(info.taxRate)>0?'\n'+(t('transactionTax')+': ')+info.taxRate+'%':''));
 $('#refresh').ariaLabel=t('refresh');$('#close').ariaLabel=t('close');text('#central',t('central'));
 $('#nav').innerHTML=['account','deposit','withdraw','transfer','savings','history'].map((k,i)=>'<button type="button" data-tab="'+k+'" class="'+(k===tab?'active':'')+'" aria-current="'+(k===tab?'page':'false')+'"><span>0'+(i+1)+'</span>'+t(k)+'</button>').join('');
 const w=$('#workspace');w.scrollTop=0;
 if(tab==='account')w.innerHTML='<div class="welcome"><h2>'+esc(t('welcome')+(info.name||''))+'</h2><p class="muted">'+t('overviewNote')+'</p></div><div class="quick">'+['deposit','withdraw','transfer','savings'].map(k=>'<button data-tab="'+k+'"><b>'+t(k)+'</b><span>'+t(k+'Note')+'</span></button>').join('')+'</div>';
 else if(tab==='history')w.innerHTML='<div class="section-head"><p class="muted">'+t('historyNote')+'</p></div>'+history();
 else if(tab==='savings'&&!info.savings)w.innerHTML='<h2>'+t('noSavings')+'</h2><p class="muted">'+t('openNote')+'</p><button id="openSavings" class="red primary-button">'+t('openSavings')+'</button>';
 else w.innerHTML='<div class="form-layout"><form id="transaction"><h2>'+t(tab)+'</h2><p class="muted">'+t(tab+'Note')+'</p>'+(tab==='transfer'?'<label class="field">'+t('recipient')+'<input name="account" required maxlength="64" autocomplete="off" spellcheck="false" placeholder="'+esc(t('recipientHint'))+'"></label>':'')+'<label class="field">'+t('amount')+'<input name="amount" aria-label="'+t('amount')+'" required type="number" min="0.01" max="1000000000" step="0.01" placeholder="0" inputmode="decimal"></label><div class="chips">'+[10,50,100,500].map(n=>'<button type="button" data-amount="'+n+'">$ '+n+'</button>').join('')+'</div>'+(tab==='savings'?'<div class="actions"><button class="red" name="operation" value="savingsDeposit">'+t('toSavings')+'</button><button name="operation" value="savingsWithdraw">'+t('fromSavings')+'</button></div>':'<button class="red primary-button" type="submit">'+t('submit')+'</button>')+'</form><aside><small>'+t(tab==='deposit'?'cash':'balance')+'</small><h2 dir="ltr" style="margin:calc(12 * var(--ws-px)) 0">'+money(tab==='deposit'?info.cash:info.bankbalance)+'</h2><p class="muted">'+t(tab+'Note')+'</p></aside></div>';
 setBusy(busy);
}
async function run(action,data={}){
 if(busy)return;const session=generation;setBusy(true);notice(t('working'));
 try{const r=await post(action,data);if(session!==generation)return;if(r.information)info=r.information;setBusy(false);render();notice(r.message||t('failed'),!r.ok);}
 catch{if(session===generation){setBusy(false);notice(t('failed'),true);}}
}
function available(action){return Number(action==='doDeposit'?info.cash:action==='savingsWithdraw'?info.savings?.amount:info.bankbalance)||0;}
async function submit(e){
 e.preventDefault();if(busy)return;
 const form=e.target,amount=Number(form.amount.value),action=tab==='savings'?(e.submitter?.value||'savingsDeposit'):{deposit:'doDeposit',withdraw:'doWithdraw',transfer:'doTransfer'}[tab];
 const cents=Math.round(amount*100);if(!Number.isFinite(amount)||!Number.isSafeInteger(cents)||cents<1||Math.abs(amount*100-cents)>0.000001||amount>1e9)return notice(t('invalid'),true);
 if(cents>Math.round(available(action)*100))return notice(t('limit'),true);
 const fee=Math.round(amount*Number(info.taxRate||0))/100;
 if(cents+Math.round(fee*100)>Math.round(available(action)*100))return notice(t('limit'),true);
 const data={amount};if(action==='doTransfer'){
  data.account=form.account.value.trim();if(!data.account)return notice(t('accountError'),true);
  text('#confirmTitle',t('review'));text('#confirmText',iso(money(amount))+'\n'+t('to')+' '+iso(data.account)+(fee>0?'\n'+(t('tax')+': ')+iso(money(fee)):''));text('#cancelConfirm',t('cancel'));text('#acceptConfirm',t('confirm'));
  const dialog=$('#confirm');dialog.returnValue='cancel';dialog.showModal();const accepted=await new Promise(resolve=>dialog.addEventListener('close',()=>resolve(dialog.returnValue==='confirm'),{once:true}));if(!accepted||bank.hidden)return;
 }
 if(action!=='doTransfer'&&fee>0){
  text('#confirmTitle',t('review'));text('#confirmText',iso(money(amount))+'\n'+(t('tax')+': ')+iso(money(fee))+'\n'+(t('total')+': ')+iso(money(amount+fee)));text('#cancelConfirm',t('cancel'));text('#acceptConfirm',t('submit'));const dialog=$('#confirm');dialog.returnValue='cancel';dialog.showModal();const yes=await new Promise(resolve=>dialog.addEventListener('close',()=>resolve(dialog.returnValue==='confirm'),{once:true}));if(!yes||bank.hidden)return;
 }
 run(action,data);
}
bank.addEventListener('submit',e=>{if(e.target.id==='transaction')submit(e);});
bank.addEventListener('click',e=>{
 const b=e.target.closest('button');if(!b||busy)return;
 if(b.dataset.tab){tab=b.dataset.tab;$('#notice').hidden=true;render();}
 if(b.dataset.amount){const input=$('[name=amount]');input.value=b.dataset.amount;input.focus();}
 if(b.id==='openSavings')run('createSavingsAccount');
});
async function close(){if(busy||$('#confirm').open)return;generation++;await post('NUIFocusOff').catch(()=>{});bank.hidden=true;}
$('#central').onclick=()=>post('central');
$('#close').onclick=close;document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!bank.hidden&&!$('#confirm').open){e.preventDefault();close();}});
$('#refresh').onclick=async()=>{if(busy)return;const session=generation;setBusy(true);try{const r=await post('refresh');if(session!==generation)return;if(r.information)info=r.information;else notice(t('failed'),true);}catch{if(session===generation)notice(t('failed'),true);}finally{if(session!==generation)return;setBusy(false);render();}};
window.addEventListener('message',({data:d})=>{
 if(!d||typeof d!=='object')return;
 if(d.status==='openbank'){readWords(d);generation++;info=d.information||{};lang=d.locale==='en'?'en':'ar';if(bank.hidden)tab='account';busy=false;bank.hidden=false;$('#notice').hidden=true;render();}
 else if(d.status==='closebank'){generation++;busy=false;bank.hidden=true;if($('#confirm').open)$('#confirm').close('cancel');}
 else if(d.status==='setLocale'){readWords(d);lang=d.locale==='en'?'en':'ar';render();}
 else if(d.status==='transferError')notice(d.error,true);else if(d.status==='successMessage')notice(d.message);
});
})();
