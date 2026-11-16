const assert=require('node:assert/strict'),fs=require('node:fs');
const P=require('../extension/presets.js');
const pair=(a,b)=>P.ruleOverlaps([a,b]).items;
// 5.7/6.3: the comparison is between rules, so it needs no open tab and no Chrome at all.
assert.equal(P.ruleOverlaps.length,1,'one argument: the preset list, nothing else');
assert.doesNotMatch(fs.readFileSync('extension/presets.js','utf8'),/function ruleOverlaps[\s\S]{0,900}?(chrome\.|api\.tabs)/,'and the body never reaches for a browser');
assert.deepEqual(P.ruleOverlaps([]),{truncated:false,items:[]},'an empty list is an empty answer, not an error');
assert.deepEqual(P.ruleOverlaps(undefined),{truncated:false,items:[]},'and a missing list is the same answer');
{
 const a={id:'a',name:'A',domains:['github.com']},b={id:'b',name:'B',domains:['github.com']};
 const items=pair(a,b);
 assert.equal(items.length,1,'two presets on one domain collide even with no tab open');
 assert.deepEqual([items[0].a,items[0].b,items[0].aName,items[0].bName],['a','b','A','B'],'the pair keeps both identities');
 assert.deepEqual(items[0].reasons,[{host:'github.com',kind:'host',rules:['github.com']}],'said as a host, because a domain rule is the whole host');
}
{
 // 6.1's boundary rules are the point of the comparison, so they are checked here rather than trusted.
 assert.deepEqual(pair({id:'a',domains:['github.com']},{id:'b',domains:['notgithub.com']}),[],'a longer label is not a subdomain');
 assert.deepEqual(pair({id:'a',domains:['github.com']},{id:'b',domains:['api.github.com']}),[],'without the subdomains flag a domain rule owns one host only');
 assert.deepEqual(pair({id:'a',domains:['api.github.com'],subdomains:true},{id:'b',domains:['github.com']}),[],'and a child rule with the flag never reaches up to its parent');
 const items=pair({id:'a',domains:['github.com'],subdomains:true},{id:'b',domains:['api.github.com']});
 assert.deepEqual([items.length,items[0]?.a,items[0]?.reasons],[1,'a',[{host:'api.github.com',kind:'host',rules:['api.github.com']}]],'a parent with subdomains owns the child host, named where they meet');
 assert.deepEqual(pair({id:'b',domains:['api.github.com']},{id:'a',domains:['github.com'],subdomains:true})[0].a,'b','and the pair is the same however the list is ordered');
}
{
 const a={id:'a',paths:['https://github.com/work']},b={id:'b',paths:['https://github.com/workshop']};
 assert.deepEqual(pair(a,b),[],'/work does not swallow /workshop');
 const under={id:'b',paths:['https://github.com/work/shop']};
 assert.deepEqual(pair(a,under)[0].reasons,[{host:'github.com',kind:'path',rules:['https://github.com/work','https://github.com/work/shop']}],'but a deeper root on the same origin does');
 assert.deepEqual(pair({id:'a',paths:['https://github.com/']},{id:'b',paths:['https://gitlab.com/x']}),[],'the root only covers its own origin');
 assert.equal(pair({id:'a',paths:['https://github.com/']},{id:'b',paths:['https://github.com/any/deep']}).length,1,'and covers everything on it');
 assert.deepEqual(pair({id:'a',paths:['https://github.com/work','https://github.com/work/shop']},{id:'b',paths:['https://github.com/work']}),[{a:'a',b:'b',aName:'a',bName:'b',reasons:[{host:'github.com',kind:'path',rules:['https://github.com/work','https://github.com/work']},{host:'github.com',kind:'path',rules:['https://github.com/work/shop','https://github.com/work']}]}],'two matching rule pairs, one pair of presets');
}
{
 const same={id:'b',exactUrls:['https://github.com/team/inbox?tab=1']};
 assert.deepEqual(pair({id:'a',exactUrls:['https://github.com/team/inbox?tab=1']},same)[0].reasons,[{host:'github.com',kind:'exact',rules:['https://github.com/team/inbox?tab=1']}],'an exact URL is compared as a whole string, query included');
 assert.deepEqual(pair({id:'a',exactUrls:['https://github.com/team/inbox?tab=1']},{id:'b',exactUrls:['https://github.com/team/inbox?tab=2']}),[],'and two different queries are two different pages');
 assert.deepEqual(pair({id:'a',paths:['https://github.com/work']},{id:'b',exactUrls:['https://github.com/work/a?x=1']}).length,1,'a path rule still covers an exact URL under it');
}
{
 // A domain rule on one side and a path rule on the other: the wide rule wins the comparison, not the narrow one.
 const items=pair({id:'a',domains:['github.com']},{id:'b',paths:['https://github.com/docs/intro']});
 assert.deepEqual(items[0].reasons,[{host:'github.com',kind:'cover',rules:['github.com','https://github.com/docs/intro']}],'the narrow rule is named so the reason can be read');
 assert.deepEqual(pair({id:'a',domains:['github.com'],subdomains:true},{id:'b',paths:['https://docs.github.com/x']})[0].reasons,[{host:'docs.github.com',kind:'cover',rules:['docs.github.com','https://docs.github.com/x']}],'and that reaches through the subdomain flag');
}
{
 // The honest ceiling: exclusions are never consulted, so the pair is a warning rather than a verdict.
 const items=pair({id:'a',domains:['github.com'],excludeDomains:['github.com']},{id:'b',domains:['github.com']});
 assert.equal(items.length,1,'a preset that excludes the same domain is still reported');
 assert.ok(!/ngoại lệ/.test(JSON.stringify(items)),'and the data carries no promise about what the exception does');
}
{
 const list=[{id:'c',name:'C',domains:['a.dev']},{id:'a',name:'A',domains:['a.dev']},{id:'b',name:'B',domains:['a.dev']},{id:'d',name:'D',domains:['other.dev']}];
 const out=P.ruleOverlaps(list);
 assert.deepEqual([out.truncated,out.items.map(x=>x.aName+'+'+x.bName)],[false,['A+B','C+A','C+B']],'three presets on one host give three pairs, listed by name while each pair keeps the list order inside');
}
{
 const junk=[{id:'a',name:'A',domains:['not a domain!!'],paths:['nonsense'],exactUrls:['also nonsense']},{id:'b',name:'B',domains:['github.com']}];
 assert.deepEqual(P.ruleOverlaps(junk).items,[],'an unreadable rule is dropped, not guessed at');
 assert.deepEqual(P.ruleOverlaps([{},null,{id:'x'}]).items,[],'and a preset with neither id nor name takes part in nothing');
 assert.deepEqual(P.ruleOverlaps([{name:'Chỉ có tên',domains:['x.dev']},{name:'Khác',domains:['x.dev']}]).items.map(x=>[x.a,x.b]),[['Chỉ có tên','Khác']],'a hand-edited list without ids is still compared, under the names it has');
}
{
 const many=Array.from({length:250},(x,i)=>({id:'p'+i,name:'P'+String(i).padStart(3,'0'),domains:['host'+(i%2)+'.dev']}));
 const out=P.ruleOverlaps(many);
 assert.deepEqual([out.truncated,out.items.length,many.length],[true,200,250],'a big list says it was cut instead of pretending to be complete');
 assert.deepEqual([out.items[0].aName,out.items[0].bName],['P000','P002'],'and the pairs kept are the first in that same order');
 assert.ok(out.items.every((x,i)=>!i||x.aName+x.bName>=out.items[i-1].aName+out.items[i-1].bName),'the kept list is sorted, not whatever order the map happened to have');
}
// A rule per preset pair must stay cheap: the comparison indexes by host, so the work grows with the
// rules that exist, not with the square of the list. Checked as a shape, because a stopwatch is not a fact.
assert.doesNotMatch(fs.readFileSync('extension/presets.js','utf8'),/for \(const host of hosts\)[\s\S]{0,400}for \(const other of hosts\)/,'no host-by-host sweep over all hosts');
console.log('Preset rules are compared with each other, on the boundary rules 6.1 demands, without a single open tab: OK');
