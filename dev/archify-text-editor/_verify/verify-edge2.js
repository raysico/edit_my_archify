const fs=require('fs');
const html=fs.readFileSync('/Users/ruizhihe/Documents/使用pixcall管理/资源库文件夹/使用百度网盘同步/edit_my_archify/test/architecture-anythinks-stack-20261019-224613/anythinks-stack.html','utf8');
function escRe(s){ return String(s).replace(/[.*+?^${}()|[\]\\]/g,'\\$&'); }
function escAttr(s){ return String(s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;'); }
function escText(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
function patchHtmlEdge(html, id, label){
  const m=html.match(new RegExp('<[^>]*?data-edge-id="'+escRe(id)+'"[^>]*>'));
  if(!m) return html;
  const tagStart=m.index, tag=m[0];
  if(tag.indexOf("data-edge-label")<0) return html;
  const newTag=tag.replace(/(data-edge-label=")[^"]*(")/, '$1'+escAttr(label)+'$2');
  return html.slice(0,tagStart)+newTag+html.slice(tagStart+tag.length);
}
let r=patchHtmlEdge(html,'client-to-heart','通信协议待定（已编辑）');
const cidx=r.indexOf('data-edge-id="client-to-heart"');
console.log('client-to-heart 标签内含已编辑:', r.slice(cidx-60,cidx+20).includes('通信协议待定（已编辑）'));
console.log('heart-to-sdk 未受影响:', r.slice(r.indexOf('data-edge-id="heart-to-sdk"')-60).includes('Go in-process · 函数调用'));
// 验证无 label 的边不误伤
const kv=patchHtmlEdge(html,'kv-note','KV');
console.log('kv-note 原无label 未被注入:', !kv.includes('data-edge-id="kv-note"'));
// 验证仅改目标，计数 data-edge-label 总变化 =1
console.log('client 出现已编辑次数:', (r.match(/通信协议待定（已编辑）/g)||[]).length);
