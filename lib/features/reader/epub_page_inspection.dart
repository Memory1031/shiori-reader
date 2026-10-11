/// Fixed, optional host-side measurement. It never enables author scripts,
/// fetches a resource, changes styles or installs a JavaScript bridge.
const epubPageInspectionSynchronousScript = r'''(() => {
  const rect = r => ({left:r.left,top:r.top,right:r.right,bottom:r.bottom});
  const path = n => {const parts=[]; for(let e=n;e&&e.nodeType===1&&parts.length<128;e=e.parentElement){
    const name=e.localName; const siblings=e.parentElement?Array.from(e.parentElement.children).filter(c=>c.localName===name):[e];
    parts.unshift(name+'['+(siblings.indexOf(e)+1)+']');}return parts.join('/');};
  const solid = n => {for(let e=n;e;e=e.parentElement){const c=getComputedStyle(e);
    if(Number(c.opacity)!==1||c.backgroundImage!=='none')return null;
    if(c.backgroundColor!=='transparent'&&!/rgba\(.*,[ ]*0\)$/.test(c.backgroundColor)){
      if(c.backgroundColor.startsWith('rgba'))return null; return c.backgroundColor;}}
    return null;};
  const text=[]; const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
  let node;let visited=0;
  while((node=walker.nextNode())&&visited++<10000){
    const parent=node.parentElement;const style=getComputedStyle(parent);
    if(!node.data.trim()||style.display==='none'||style.visibility!=='visible')continue;
    if(text.length>=128)break;
    const range=document.createRange();range.selectNodeContents(node);
    const boxes=Array.from(range.getClientRects()).slice(0,32).map(rect);
    text.push({domPath:path(parent),text:node.data.slice(0,4096),textComplete:node.data.length<=4096,boxes,color:style.color,
      background:solid(parent),fontFamily:style.fontFamily,fontSize:style.fontSize,
      lineHeight:style.lineHeight,clip:style.overflow,opacity:style.opacity});
  }
  const images=Array.from(document.images).slice(0,128).map(n=>({domPath:path(n),
    rect:rect(n.getBoundingClientRect()),complete:n.complete,naturalWidth:n.naturalWidth,
    naturalHeight:n.naturalHeight}));
  const links=Array.from(document.querySelectorAll('a')).slice(0,128).map(n=>({domPath:path(n),
    rect:rect(n.getBoundingClientRect()),address:n.getAttribute('href')}));
  const root=document.scrollingElement||document.documentElement;
  const original=[root.scrollLeft,root.scrollTop];
  root.scrollLeft=1000000;root.scrollTop=1000000;
  const displacement=[root.scrollLeft,root.scrollTop];
  root.scrollLeft=original[0];root.scrollTop=original[1];
  return {clientWidth:root.clientWidth,scrollWidth:root.scrollWidth,clientHeight:root.clientHeight,
    scrollHeight:root.scrollHeight,displacement,text,images,links,
    fontsReady:document.fonts.status==='loaded',truncated:text.length===128||visited>=10000||text.some(t=>!t.textComplete),
    rootOverflowX:getComputedStyle(root).overflowX,rootOverflowY:getComputedStyle(root).overflowY,
    scrollbarsHidden:getComputedStyle(root).scrollbarWidth==='none'};
})()''';

const epubPageInspectionScript =
    '(async () => {await document.fonts.ready; '
    'return $epubPageInspectionSynchronousScript;})()';

final class EpubPageInspection {
  const EpubPageInspection(this.values);
  final Map<String, dynamic> values;
}
