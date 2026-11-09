import { createClient } from 'jsr:@supabase/supabase-js@2.57.0';
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,x-client-info,content-type','Access-Control-Allow-Methods':'POST, OPTIONS'}});
const url=Deno.env.get('SUPABASE_URL')!;
const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const deeplKey=Deno.env.get('DEEPL_API_KEY');
const db=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
Deno.serve(async request=>{
 if(request.method==='OPTIONS')return json({},200);
 if(request.method!=='POST')return json({error:'method_not_allowed'},405);
 const token=(request.headers.get('Authorization')??'').replace(/^Bearer\s+/i,'').trim();
 if(!token)return json({error:'missing_token'},401);
 const {data:{user},error:authError}=await db.auth.getUser(token);
 if(authError||!user)return json({error:'unauthorized'},401);
 let messageId:string;
 try{const payload=await request.json();messageId=payload.message_id}catch{return json({error:'invalid_json'},400)}
 if(typeof messageId!=='string'||!/^[0-9a-f-]{36}$/i.test(messageId))return json({error:'invalid_message_id'},400);
 const {data:message,error:messageError}=await db.from('chat_v2_messages').select('id,room_id,sender_id,source_lang,source_text,translated_text,status').eq('id',messageId).maybeSingle();
 if(messageError)return json({error:'database_error'},500);
 if(!message)return json({error:'not_found'},404);
 const {data:room,error:roomError}=await db.from('chat_v2_rooms').select('id,guest_id,active').eq('id',message.room_id).maybeSingle();
 if(roomError||!room||!room.active)return json({error:'room_unavailable'},403);
 const {data:config}=await db.from('chat_v2_config').select('owner_id').eq('singleton',true).maybeSingle();
 if(!config?.owner_id||(user.id!==room.guest_id&&user.id!==config.owner_id))return json({error:'forbidden'},403);
 if(message.status==='translated'&&message.translated_text)return json({status:'translated',text:message.translated_text});
 if(!deeplKey)return json({error:'translation_not_configured'},503);
 const source=message.source_lang==='es'?'ES':'PT';
 const target=message.source_lang==='es'?'PT-BR':'ES';
 try{
 const base=Deno.env.get('DEEPL_API_URL')??(deeplKey.endsWith(':fx')?'https://api-free.deepl.com':'https://api.deepl.com');
 const res=await fetch(base+'/v2/translate',{method:'POST',headers:{Authorization:'DeepL-Auth-Key '+deeplKey,'Content-Type':'application/json'},body:JSON.stringify({text:[message.source_text],source_lang:source,target_lang:target,preserve_formatting:true})});
 if(!res.ok){console.error('DeepL status',res.status);await db.from('chat_v2_messages').update({status:'failed'}).eq('id',message.id);return json({error:'translation_failed'},502)}
 const payload=await res.json();const translated=payload.translations?.[0]?.text;
 if(typeof translated!=='string'||!translated){return json({error:'translation_empty'},502)}
 const {error:updateError}=await db.from('chat_v2_messages').update({translated_text:translated,status:'translated'}).eq('id',message.id);
 if(updateError)return json({error:'database_write_error'},500);
 return json({status:'translated'});
 }catch(e){console.error('Translation failed',e);await db.from('chat_v2_messages').update({status:'failed'}).eq('id',message.id);return json({error:'translation_failed'},502)}
});