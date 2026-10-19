const fs=require('fs');
const html=fs.readFileSync('/Users/ruizhihe/Documents/使用pixcall管理/资源库文件夹/使用百度网盘同步/edit_my_archify/test/architecture-anythinks-stack-20261019-224613/anythinks-stack.html','utf8');
function escRe(s){ return String(s).replace(/[.*+?^${}()|[\]\\]/g,'\\$&'); }
function escAttr(s){ return String(s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;'); }
function escText(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
function patchHtmlEdge(html, id, label){
  const re=new RegExp('(<[^>]*?data-edge-id="'+escRe(id)+'"[^>]*?data-edge-label=")[^"]*(")');
  return html.replace(re, '$1'+escAttr(label)+'$2');
}
function patchHtmlBoundary(html, idx, label){
  let out=html;
  const re=new RegExp('(data-composition-frame-id="'+idx+'"[^>]*?data-composition-frame-label=")[^"]*(")');
  out=out.replace(re, '$1'+escAttr(label)+'$2');
  const oldRe=new RegExp('(<text[^>]*?data-boundary-label=""[^>]*>)[^<]*(</text>)');
  return out.replace(oldRe, '$1'+escText(label)+'$2');
}
let r=patchHtmlEdge(html,'client-to-heart','通信协议待定（已编辑）');
console.log('=== 连线 label ===');
const seg=r.slice(r.indexOf('data-edge-id="client-to-heart"')-20, r.indexOf('data-edge-id="client-to-heart"')+120);
console.log(seg.includes('通信协议待定（已编辑）') ? 'PASS 连线label已更新' : 'FAIL');
// 确认只改这一条
console.log('heart-to-sdk 是否未变:', /data-edge-id="heart-to-sdk"[^>]*?data-edge-label="Go in-process · 函数调用"/.test(r));
let rb=patchHtmlBoundary(html,0,'客户端层（已编辑）');
console.log('=== 区域 label ===');
console.log(rb.includes('data-composition-frame-id="0"[^>]*?客户端层（已编辑）'.replace('[^>]*?','')) ? '' : '');
// 用正则再确认
const bm=/data-composition-frame-id="0"[^>]*?data-composition-frame-label="客户端层（已编辑）"/.test(rb);
console.log('rect frame-label:', bm?'PASS':'FAIL');
const bm2=/<text[^>]*?data-boundary-label=""[^>]*>客户端层（已编辑）<\/text>/.test(rb);
console.log('boundary text:', bm2?'PASS':'FAIL');
