const fs=require('fs');
const html=fs.readFileSync('/Users/ruizhihe/Documents/使用pixcall管理/资源库文件夹/使用百度网盘同步/edit_my_archify/test/architecture-anythinks-stack-20261019-224613/anythinks-stack.html','utf8');
function escRe(s){ return String(s).replace(/[.*+?^${}()|[\]\\]/g,'\\$&'); }
function escAttr(s){ return String(s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;'); }
function escText(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
function findGroupEnd(html,start){
  let i=html.indexOf('>',start)+1, depth=1;
  while(i<html.length){ const lt=html.indexOf('<',i); if(lt<0)return null; const isClose=html[lt+1]==='/'; const gt=html.indexOf('>',lt); if(gt<0)return null; const tn=(html.slice(lt+(isClose?2:1),gt).match(/^[a-zA-Z0-9]+/)||[''])[0].toLowerCase(); if(tn==='g'){if(isClose)depth--;else depth++; if(depth===0)return gt+1;} i=gt+1; } return null;
}
function patchHtmlNode(html,id,node){
  const re=new RegExp('<g[^>]*?data-node-id="'+escRe(id)+'"[^>]*>','i');
  const m=re.exec(html); if(!m)return {ok:false,html};
  const gStart=m.index; const end=findGroupEnd(html,gStart); if(!end)return {ok:false,html};
  let seg=html.slice(gStart,end);
  seg=seg.replace(/(\sdata-node-label=")[^"]*(")/i,'$1'+escAttr(node.label)+'$2');
  seg=seg.replace(/(<text[^>]*?class="[^"]*t-primary[^"]*"[^>]*>)[^<]*(<\/text>)/i,'$1'+escText(node.label)+'$2');
  if(node.sublabel!==undefined){ seg=seg.replace(/(\sdata-node-sublabel=")[^"]*(")/i,'$1'+escAttr(node.sublabel)+'$2'); seg=seg.replace(/(<text[^>]*?data-detail="context"[^>]*>)[^<]*(<\/text>)/i,'$1'+escText(node.sublabel)+'$2'); }
  if(node.tag!==undefined){ seg=seg.replace(/(\sdata-node-tag=")[^"]*(")/i,'$1'+escAttr(node.tag)+'$2'); seg=seg.replace(/(<text[^>]*?data-detail="fine"[^>]*>)[^<]*(<\/text>)/i,'$1'+escText(node.tag)+'$2'); }
  return {ok:true, html: html.slice(0,gStart)+seg+html.slice(end)};
}
const r=patchHtmlNode(html,'heart',{label:'anythinks-heart (编辑)',sublabel:'中间件层',tag:'节点模型 · 字段标签'});
console.log('ok:',r.ok);
const idre=/<g[^>]*data-node-id="heart"[^>]*>/;
const m2=idre.exec(r.html); const end2=findGroupEnd(r.html,m2.index);
const seg=r.html.slice(m2.index,end2);
console.log('--- heart segment 关键行 ---');
for(const ln of seg.split('\n')){ if(/data-node-label=|t-primary|data-detail="context"|data-node-sublabel=|data-detail="fine"|data-node-tag=/.test(ln)) console.log(ln.trim().slice(0,120)); }
console.log('--- node-model 是否未受影响 ---');
const idre2=/<g[^>]*data-node-id="node-model"[^>]*>/; const m3=idre2.exec(r.html); const e3=findGroupEnd(r.html,m3.index);
const seg2=r.html.slice(m3.index,e3);
console.log(seg2.split('\n').filter(l=>/t-primary/.test(l)).map(l=>l.trim()).join('\n'));
