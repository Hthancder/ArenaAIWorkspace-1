'use strict';
const FaviconTools=(()=>{
 function url(pageUrl,base){try{const page=new URL(pageUrl);if(!['http:','https:'].includes(page.protocol))return '';const image=new URL(base);if(image.protocol!=='chrome-extension:')return '';image.searchParams.set('pageUrl',page.href);image.searchParams.set('size','32');return image.href}catch{return ''}}
 return {url};
})();
if(typeof module!=='undefined')module.exports=FaviconTools;
