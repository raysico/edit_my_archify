const fs=require('fs');
const dir='/Users/ruizhihe/Documents/使用pixcall管理/资源库文件夹/使用百度网盘同步/edit_my_archify/test/architecture-anythinks-stack-20261019-224613/';
const html=fs.readFileSync(dir+'anythinks-stack.html','utf8');
function escRe(s){ return String(s).replace(/[.*+?^${}()|[\]\\]/g,'\\$&'); }
function escAttr(s){ return String(s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;'); }
function escText(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
function findGroupEnd(html,start){
  let i=html.indexOf('>',start)+1, depth=1;
  while(i<html.length){ const lt=html.indexOf('<',i); if(lt<0)return null; const isClose=html[lt+1]==='/'; const gt=html.indexOf('>',lt); if(gt<0)return null; const tn=(html.slice(lt+(isClose?2:1),gt).match(/^[a-zA-Z0-9]+/)||[''])[0].toLowerCase(); if(tn==='g'){if(isClose)depth--;else depth++; if(depth===0)return gt+1;} i=gt+1; } return null;
}
function patchHtmlNode(html,id,node){
  const re=new RegExp('<g[^>]*?data-node-id="'+escRe(id)+'"[^>]*>','i');
  const m=re.exec(html); if(!m)return html;
  const gStart=m.index; const end=findGroupEnd(html,gStart); if(!end)return html;
  let seg=html.slice(gStart,end);
  seg=seg.replace(/(\sdata-node-label=")[^"]*(")/i,'$1'+escAttr(node.label)+'$2');
  seg=seg.replace(/(<text[^>]*?class="[^"]*t-primary[^"]*"[^>]*>)[^<]*(<\/text>)/i,'$1'+escText(node.label)+'$2');
  if(node.sublabel!==undefined){ seg=seg.replace(/(\sdata-node-sublabel=")[^"]*(")/i,'$1'+escAttr(node.sublabel)+'$2'); seg=seg.replace(/(<text[^>]*?data-detail="context"[^>]*>)[^<]*(<\/text>)/i,'$1'+escText(node.sublabel)+'$2'); }
  if(node.tag!==undefined){ seg=seg.replace(/(\sdata-node-tag=")[^"]*(")/i,'$1'+escAttr(node.tag)+'$2'); seg=seg.replace(/(<text[^>]*?data-detail="fine"[^>]*>)[^<]*(<\/text>)/i,'$1'+escText(node.tag)+'$2'); }
  return html.slice(0,gStart)+seg+html.slice(end);
}
function patchHtmlEdge(html, id, label){
  const m=html.match(new RegExp('<[^>]*?data-edge-id="'+escRe(id)+'"[^>]*>'));
  if(!m) return html;
  const tagStart=m.index, tag=m[0];
  if(tag.indexOf("data-edge-label")<0) return html;
  const newTag=tag.replace(/(data-edge-label=")[^"]*(")/, '$1'+escAttr(label)+'$2');
  return html.slice(0,tagStart)+newTag+html.slice(tagStart+tag.length);
}
function patchHtmlBoundary(html, idx, label){
  let out=html;
  const re=new RegExp('(data-composition-frame-id="'+idx+'"[^>]*?data-composition-frame-label=")[^"]*(")');
  out=out.replace(re,'$1'+escAttr(label)+'$2');
  return out;
}
// 模拟 buildHtml：依次应用三种修改
let out=html;
out=patchHtmlNode(out,'heart',{label:'anythinks-heart X',sublabel:'中间件层X',tag:'节点X'});
out=patchHtmlEdge(out,'client-to-heart','通信协议X');
out=patchHtmlBoundary(out,0,'客户端层X');
const pass=(c,msg)=>{console.log((c?'PASS':'FAIL')+' '+msg); return c;};
let ok=true;
// 节点
ok &= pass(/data-node-label="anythinks-heart X"/.test(out),'节点label属性');
ok &= pass(/>anythinks-heart X</.test(out),'节点t-primary文本');
ok &= pass(/>中间件层X<\/text>/.test(out),'节点sublabel文本');
ok &= pass(/>节点X<\/text>/.test(out),'节点tag文本');
// 连线：定位含该 id 的标签，检查其中 label 被改
const ctTag=out.match(/<[^>]*?data-edge-id="client-to-heart"[^>]*>/);
ok &= pass(ctTag && ctTag[0].indexOf('data-edge-label="通信协议X"')>=0,'连线label');
// 其它连线标签内 label 未变
const hsTag=out.match(/<[^>]*?data-edge-id="heart-to-sdk"[^>]*>/);
ok &= pass(hsTag && hsTag[0].indexOf('data-edge-label="Go in-process · 函数调用"')>=0,'其它连线未变');
// 区域
ok &= pass(/data-composition-frame-id="0"[^>]*?data-composition-frame-label="客户端层X"/.test(out),'区域label');
// 不误伤：其它节点/连线/区域
ok &= pass(/data-node-label="节点模型适配"/.test(out),'其它节点未变');
// 区域
ok &= pass(/data-composition-frame-id="1"[^>]*?data-composition-frame-label="anythinks-heart · 产品中间件层"/.test(out),'其它区域未变');
console.log(ok?'\nALL PASS':'SOME FAIL');
