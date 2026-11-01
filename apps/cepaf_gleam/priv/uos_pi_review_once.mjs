// Short Pi SDK transport facade only. Gleam owns scope, budget and dispatch.
// No agent/session, tools, extensions, compaction, registry or retry loop.
import { createHash } from 'node:crypto';
const SDK = '/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js';
const MODEL = 'google/gemini-4-argon';
const ENDPOINTS = 'https://openrouter.ai/api/v1/models/google/gemini-4-argon/endpoints';
const COMPLETION = 'https://openrouter.ai/api/v1/chat/completions';
const providerFetch = globalThis.fetch;
let completionPosts = 0;
let catalogGets = 0;
let explicitUsage;
let reportedModel;
const digest = x => createHash('sha256').update(x).digest('hex');
const check = (x, name) => { if (!x) throw new Error(name); };
const closed = (x, keys) => x && typeof x === 'object' && !Array.isArray(x)
  && Object.keys(x).sort().join('|') === [...keys].sort().join('|');
const integer = n => Number.isSafeInteger(n) && n >= 0;
async function boundedResponse(response, limit) {
  check(response.ok && response.body, 'catalog_unavailable');
  const reader = response.body.getReader(); let bytes = 0; const parts = [];
  try { for (;;) { const next = await reader.read(); if (next.done) break;
    bytes += next.value.length; check(bytes <= limit, 'catalog_bound'); parts.push(next.value); }
  } finally { await reader.cancel().catch(() => {}); }
  return JSON.parse(new TextDecoder('utf-8', { fatal:true }).decode(Buffer.concat(parts)));
}
async function run() {
  check(process.argv.length === 2, 'no_argv_locators');
  const parts=[]; let size=0; let length;
  for await (const part of process.stdin) {
    size+=part.length; check(size<=65540,'input_bound'); parts.push(part);
    const all=Buffer.concat(parts);
    if (length===undefined && all.length>=4) { length=all.readUInt32BE(0); check(length>0&&length<=65536,'frame'); }
    if (length!==undefined && size>=length+4) { check(size===length+4,'trailing'); break; }
  }
  process.stdin.destroy();
  check(length!==undefined && size===length+4,'incomplete');
  const raw=new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(parts).subarray(4)); const body=JSON.parse(raw);
  check(closed(body,['model','messages','max_tokens','temperature','stream','stream_options','reasoning','provider']), 'closed_request');
  check(body.model===MODEL && integer(body.max_tokens) && body.max_tokens>0 && body.max_tokens<=512, 'model_tokens');
  check(Array.isArray(body.messages) && body.messages.length===2
    && body.messages[0].role==='system' && body.messages[1].role==='user'
    && body.messages.every(x=>closed(x,['role','content'])&&typeof x.content==='string'), 'messages');
  const inputBytes=body.messages.reduce((n,x)=>n+Buffer.byteLength(x.content),0);
  check((inputBytes+2048)*4000+body.max_tokens*20000<20000000,'request_price');
  check(body.temperature===0 && body.stream===true
    && JSON.stringify(body.stream_options)==='{"include_usage":true}'
    && JSON.stringify(body.reasoning)==='{"enabled":false}'
    && JSON.stringify(body.provider)==='{"only":["google-ai-studio"],"allow_fallbacks":false,"data_collection":"deny","zdr":true,"require_parameters":true,"max_price":{"prompt":4,"completion":20,"request":0}}','route');
  const key=process.env.OPENROUTER_API_KEY;
  check(typeof key==='string' && key.length>0, 'credential_unavailable');
  const signal=AbortSignal.timeout(30000);
  const { stream }=await import(SDK);
  const fetched=async (url, init) => {
    check(String(url)===COMPLETION && init?.method==='POST' && completionPosts===0, 'one_completion_only');
    check(typeof init.body==='string' && init.body===raw,'exact_body');
    // Public current endpoint eligibility, not a catalog minimum or stale SDK price.
    catalogGets++;
    const catalog=await boundedResponse(await providerFetch(ENDPOINTS,{method:'GET',redirect:'error',signal}),262144);
    check(catalog?.data?.id===MODEL && Array.isArray(catalog.data.endpoints),'catalog_identity');
    const eligible=catalog.data.endpoints.filter(e=>e?.tag==='google-ai-studio');
    check(eligible.length===1 && eligible[0].supports_zdr===true,'provider_or_zdr_unknown');
    const price=eligible[0].pricing;
    const input=Number(price?.prompt), output=Number(price?.completion);
    check(typeof price?.prompt==='string' && typeof price?.completion==='string'
      && Number.isFinite(input) && Number.isFinite(output) && input>=0 && input<=0.000004
      && output>=0 && output<=0.000020 && typeof price.request==='string' && Number(price.request)===0,'price_unknown');
    completionPosts++;
    const response=await providerFetch(url,{...init,redirect:'error',signal});
    check(response.ok && response.body,'completion_unknown');
    // Bound bytes BEFORE Pi accumulates content. Observe actual raw events:
    // initialized SDK zero counters/requested model are not provider evidence.
    let bytes=0, pending=''; const decoder=new TextDecoder('utf-8',{fatal:true});
    const bodyStream=response.body.pipeThrough(new TransformStream({
      transform(chunk,controller) {
        bytes+=chunk.length; check(bytes<=65536,'completion_wire_bound');
        pending+=decoder.decode(chunk,{stream:true});
        for (;;) { const index=pending.indexOf('\n\n'); if(index<0) break;
          const event=pending.slice(0,index); pending=pending.slice(index+2);
          for(const line of event.split('\n')) if(line.startsWith('data:')) {
            const data=line.slice(5).trim(); if(data==='[DONE]') continue;
            const item=JSON.parse(data);
            if(typeof item.model==='string') {
              check(reportedModel===undefined||reportedModel===item.model,'reported_model_changed'); reportedModel=item.model;
            }
            if(item.usage!==undefined && item.usage!==null) {
              check(integer(item.usage.prompt_tokens)&&integer(item.usage.completion_tokens),'usage_unknown');
              explicitUsage={input:item.usage.prompt_tokens,output:item.usage.completion_tokens};
            }
          }
        }
        controller.enqueue(chunk);
      },
    }));
    return new Response(bodyStream,{status:response.status,headers:response.headers});
  };
  const model={id:MODEL,name:'Argon',api:'openai-completions',provider:'openrouter',
    baseUrl:'https://openrouter.ai/api/v1',reasoning:false,input:['text'],
    cost:{input:4,output:20,cacheRead:4,cacheWrite:4},contextWindow:16384,maxTokens:512,
    compat:{maxTokensField:'max_tokens',supportsDeveloperRole:false,supportsStore:false,supportsUsageInStreaming:true}};
  const events=stream(model,{messages:[{role:'system',content:body.messages[0].content},
    {role:'user',content:body.messages[1].content,timestamp:Date.now()}]},
    {apiKey:key,maxTokens:body.max_tokens,maxRetries:0,maxRetryDelayMs:1,timeoutMs:30000,
      signal,fetch:fetched,cacheRetention:'none',env:{},onPayload:()=>body});
  const reply=await events.result();
  check(completionPosts===1 && reply && reply.role==='assistant' && reply.model===MODEL
    && reply.provider==='openrouter' && ['stop','length'].includes(reply.stopReason),'completion_unknown');
  check(reply.content.every(x=>x.type==='text'),'unexpected_tool_or_reasoning');
  const text=reply.content.map(x=>x.text).join(''); check(Buffer.byteLength(text)>0&&Buffer.byteLength(text)<=16384,'output_bound');
  check(explicitUsage && reportedModel===MODEL,'usage_or_reported_model_unknown');
  const input=explicitUsage.input;
  check(input<=inputBytes+2048 && explicitUsage.output<=body.max_tokens,'usage_bound');
  const generation=reply.responseId;
  check(typeof generation==='string' && /^gen-[A-Za-z0-9-]{1,120}$/.test(generation),'generation_unknown');
  return {schema:'uos.pi-single-completion.v1',status:'ADVICE_COST_UNKNOWN',model:MODEL,
    provider:'openrouter',text,generation_id:generation,input_tokens:input,output_tokens:explicitUsage.output,
    reported_model:reportedModel,
    stop_reason:reply.stopReason,completion_posts:completionPosts,catalog_gets:catalogGets,
    tools_executed:0,body_sha256:digest(raw),actual_provider_cost:null};
}
try { process.stdout.write(JSON.stringify(await run())); }
catch { process.stdout.write(JSON.stringify({schema:'uos.pi-single-completion.v1',
  status:completionPosts?'OUTCOME_UNKNOWN':'UNAVAILABLE',model:MODEL,provider:'openrouter',
  completion_posts:completionPosts,catalog_gets:catalogGets,tools_executed:0})); process.exitCode=1; }
